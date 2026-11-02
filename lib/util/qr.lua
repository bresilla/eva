-- QR codes in plain Lua (ISO/IEC 18004): byte mode, the four error levels, versions
-- 1 to 40. Encodes for the launcher, eva-qr, eva-large and the Wi-Fi share
-- page. What it encodes stays in this process, on no command line and in no pipe.
-- The work runs a slice to a timer tick, so a code of any size fits a handler's fuel.
-- Follows Project Nayuki's MIT-licensed QR Code generator; see LICENSE-qr.
--
--   local qr = require("lib.util.qr")
--   qr.encode("https://example.org", "Q", function(code, why) end)
--   code.size, code.dark(x, y), code.path     -- 0-based modules, path data a unit each
--   qr.svg(code)                              -- inline SVG with a quiet zone
--   qr.png(code, { scale = 12, quiet = 2 }, function(bytes, why) end)
--   qr.wifi({ ssid = "Home", security = "WPA" }, secret) -- the text that joins a network

local poll = require("lib.util.poll")

local M = { LEVELS = { "L", "M", "Q", "H" } }

-- Calls of work to a tick: about a third of a handler's fuel.
local SLICE = 12000

local ECC_PER_BLOCK = {
  L = { 7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28,
    28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
  M = { 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26,
    26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28 },
  Q = { 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30,
    28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
  H = { 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28,
    30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30 },
}
local BLOCKS = {
  L = { 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8,
    8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25 },
  M = { 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16,
    17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49 },
  Q = { 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20,
    23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68 },
  H = { 1, 1, 2, 4, 4, 4, 5, 6, 8, 8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25,
    25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81 },
}
local FORMAT = { L = 1, M = 0, Q = 3, H = 2 }
local LAST_VERSION = 40

-- ------------------------------------------------------------ the field --

local EXP, LOG = {}, {}
do
  local x = 1
  for i = 0, 254 do
    EXP[i] = x
    LOG[x] = i
    x = x << 1
    if x > 255 then x = x ~ 0x11D end
  end
  for i = 255, 509 do EXP[i] = EXP[i - 255] end
end

local function multiply(a, b)
  if a == 0 or b == 0 then return 0 end
  return EXP[LOG[a] + LOG[b]]
end

local function divisor(degree)
  local result = {}
  for i = 1, degree do result[i] = 0 end
  result[degree] = 1
  local root = 1
  for _ = 1, degree do
    for j = 1, degree do
      result[j] = multiply(result[j], root)
      if j < degree then result[j] = result[j] ~ result[j + 1] end
    end
    root = multiply(root, 2)
  end
  return result
end

local function remainder(data, div, spend)
  local degree = #div
  local logs, result = {}, {}
  for i = 1, degree do
    logs[i] = div[i] ~= 0 and LOG[div[i]] or false
    result[i] = 0
  end
  for _, byte in ipairs(data) do
    local factor = byte ~ result[1]
    local log_factor = factor ~= 0 and LOG[factor]
    for i = 1, degree - 1 do
      local log_div = logs[i]
      result[i] = (log_factor and log_div) and (result[i + 1] ~ EXP[log_div + log_factor]) or result[i + 1]
    end
    local log_div = logs[degree]
    result[degree] = (log_factor and log_div) and EXP[log_div + log_factor] or 0
    spend(degree)
  end
  return result
end

-- ------------------------------------------------------------- capacity --

local function raw_modules(version)
  local result = (16 * version + 128) * version + 64
  if version >= 2 then
    local aligns = version // 7 + 2
    result = result - ((25 * aligns - 10) * aligns - 55)
    if version >= 7 then result = result - 36 end
  end
  return result
end

local function data_codewords(version, level)
  return raw_modules(version) // 8 - ECC_PER_BLOCK[level][version] * BLOCKS[level][version]
end

local function fits(length, version, level)
  local count_bits = version < 10 and 8 or 16
  return (4 + count_bits + length * 8 + 7) // 8 <= data_codewords(version, level)
end

local function choose(length, level)
  for version = 1, LAST_VERSION do
    if fits(length, version, level) then return version end
  end
end

--- The most bytes a code holds at `level`, or in version `version` of it.
function M.capacity(level, version)
  version = version or LAST_VERSION
  return (data_codewords(version, level) * 8 - 4 - (version < 10 and 8 or 16)) // 8
end

-- -------------------------------------------------------------- the data --

local function codewords(text, version, level, spend)
  local bits, n = {}, 0
  local function push(value, count)
    for i = count - 1, 0, -1 do
      n = n + 1
      bits[n] = (value >> i) & 1
    end
  end
  push(4, 4)
  push(#text, version < 10 and 8 or 16)
  for i = 1, #text do
    push(text:byte(i), 8)
    spend(4)
  end
  local capacity = data_codewords(version, level) * 8
  push(0, math.min(4, capacity - n))
  push(0, (8 - n % 8) % 8)
  local bytes = {}
  for i = 1, n, 8 do
    local value = 0
    for j = 0, 7 do value = (value << 1) | bits[i + j] end
    bytes[#bytes + 1] = value
    spend(3)
  end
  local pad = 0xEC
  while #bytes * 8 < capacity do
    bytes[#bytes + 1] = pad
    pad = pad == 0xEC and 0x11 or 0xEC
  end
  return bytes
end

local function interleaved(data, version, level, spend)
  local blocks_n = BLOCKS[level][version]
  local ecc_len = ECC_PER_BLOCK[level][version]
  local raw = raw_modules(version) // 8
  local short_n = blocks_n - raw % blocks_n
  local short_len = raw // blocks_n
  local div = divisor(ecc_len)
  spend(ecc_len * ecc_len)
  local blocks, at = {}, 1
  for i = 1, blocks_n do
    local length = short_len - ecc_len + (i <= short_n and 0 or 1)
    local block = {}
    for j = 1, length do block[j] = data[at + j - 1] end
    at = at + length
    local ecc = remainder(block, div, spend)
    if i <= short_n then block[#block + 1] = -1 end
    for _, byte in ipairs(ecc) do block[#block + 1] = byte end
    blocks[i] = block
    spend(length)
  end
  local out = {}
  for i = 1, #blocks[1] do
    for j = 1, blocks_n do
      local byte = blocks[j][i]
      if byte >= 0 then out[#out + 1] = byte end
    end
    spend(blocks_n)
  end
  return out
end

-- ------------------------------------------------------------ the matrix --

local function alignment_positions(version)
  if version == 1 then return {} end
  local count = version // 7 + 2
  local step = version == 32 and 26 or math.ceil((version * 4 + 4) / (count * 2 - 2)) * 2
  local positions = { 6 }
  local pos = version * 4 + 10
  while #positions < count do
    table.insert(positions, 2, pos)
    pos = pos - step
  end
  return positions
end

local function matrix(size, spend)
  local cells, fixed = {}, {}
  for y = 0, size - 1 do
    cells[y], fixed[y] = {}, {}
    for x = 0, size - 1 do cells[y][x], fixed[y][x] = false, false end
    spend(size)
  end
  return cells, fixed
end

local function format_bits(level, mask)
  local data = (FORMAT[level] << 3) | mask
  local rem = data
  for _ = 1, 10 do rem = (rem << 1) ~ ((rem >> 9) * 0x537) end
  return ((data << 10) | rem) ~ 0x5412
end

local function draw_format(cells, fixed, size, level, mask)
  local bits = format_bits(level, mask)
  local function set(x, y, bit)
    cells[y][x] = ((bits >> bit) & 1) == 1
    fixed[y][x] = true
  end
  for i = 0, 5 do set(8, i, i) end
  set(8, 7, 6)
  set(8, 8, 7)
  set(7, 8, 8)
  for i = 9, 14 do set(14 - i, 8, i) end
  for i = 0, 7 do set(size - 1 - i, 8, i) end
  for i = 8, 14 do set(8, size - 15 + i, i) end
  cells[size - 8][8] = true
  fixed[size - 8][8] = true
end

local function draw_functions(cells, fixed, size, version, level)
  local function set(x, y, dark)
    if x >= 0 and y >= 0 and x < size and y < size then
      cells[y][x] = dark
      fixed[y][x] = true
    end
  end
  for i = 0, size - 1 do
    set(6, i, i % 2 == 0)
    set(i, 6, i % 2 == 0)
  end
  local function finder(cx, cy)
    for dy = -4, 4 do
      for dx = -4, 4 do
        local dist = math.max(math.abs(dx), math.abs(dy))
        set(cx + dx, cy + dy, dist ~= 2 and dist ~= 4)
      end
    end
  end
  finder(3, 3)
  finder(size - 4, 3)
  finder(3, size - 4)
  local positions = alignment_positions(version)
  local n = #positions
  for i = 1, n do
    for j = 1, n do
      if not ((i == 1 and j == 1) or (i == 1 and j == n) or (i == n and j == 1)) then
        for dy = -2, 2 do
          for dx = -2, 2 do
            set(positions[i] + dx, positions[j] + dy, math.max(math.abs(dx), math.abs(dy)) ~= 1)
          end
        end
      end
    end
  end
  draw_format(cells, fixed, size, level, 0)
  if version >= 7 then
    local rem = version
    for _ = 1, 12 do rem = (rem << 1) ~ ((rem >> 11) * 0x1F25) end
    local bits = (version << 12) | rem
    for i = 0, 17 do
      local dark = ((bits >> i) & 1) == 1
      local a, b = size - 11 + i % 3, i // 3
      set(a, b, dark)
      set(b, a, dark)
    end
  end
end

local function draw_data(cells, fixed, size, data, spend)
  local total = #data * 8
  local i = 0
  local right = size - 1
  while right >= 1 do
    if right == 6 then right = 5 end
    local upward = ((right + 1) & 2) == 0
    for vert = 0, size - 1 do
      local y = upward and (size - 1 - vert) or vert
      for j = 0, 1 do
        local x = right - j
        if not fixed[y][x] and i < total then
          local byte = data[(i >> 3) + 1]
          cells[y][x] = ((byte >> (7 - (i & 7))) & 1) == 1
          i = i + 1
        end
      end
    end
    spend(2 * size)
    right = right - 2
  end
end

local MASKS = {
  [0] = function(x, y) return (x + y) % 2 == 0 end,
  function(_, y) return y % 2 == 0 end,
  function(x) return x % 3 == 0 end,
  function(x, y) return (x + y) % 3 == 0 end,
  function(x, y) return (x // 3 + y // 2) % 2 == 0 end,
  function(x, y) return x * y % 2 + x * y % 3 == 0 end,
  function(x, y) return (x * y % 2 + x * y % 3) % 2 == 0 end,
  function(x, y) return ((x + y) % 2 + x * y % 3) % 2 == 0 end,
}

local function apply_mask(cells, fixed, size, mask, spend)
  local inverts = MASKS[mask]
  for y = 0, size - 1 do
    local row, held = cells[y], fixed[y]
    for x = 0, size - 1 do
      if not held[x] and inverts(x, y) then row[x] = not row[x] end
    end
    spend(2 * size)
  end
end

-- How far a mask is from half the modules dark, with runs of five or more
-- along the rows: the cheap part of the standard's penalty.
local function penalty(cells, size, spend)
  local dark, score = 0, 0
  for y = 0, size - 1 do
    local row = cells[y]
    local run, last = 0, nil
    for x = 0, size - 1 do
      local cell = row[x]
      if cell then dark = dark + 1 end
      if cell == last then
        run = run + 1
        if run == 5 then score = score + 3 elseif run > 5 then score = score + 1 end
      else
        run, last = 1, cell
      end
    end
    spend(size)
  end
  local share = dark * 20 // (size * size)
  return score + math.abs(share - 10) * 10
end

-- The dark modules as path data, one box to a run along a row.
local function outline(cells, size, spend)
  local parts = {}
  for y = 0, size - 1 do
    local row, x = cells[y], 0
    while x < size do
      if row[x] then
        local from = x
        while x < size and row[x] do x = x + 1 end
        parts[#parts + 1] = ("M%d %dh%dv1h-%dz"):format(from, y, x - from, x - from)
      else
        x = x + 1
      end
    end
    spend(size)
  end
  return table.concat(parts)
end

-- The code for `text`, whose smallest version is `version`.
local function build(text, version, level, spend)
  local size = version * 4 + 17
  local data = interleaved(codewords(text, version, level, spend), version, level, spend)
  local cells, fixed = matrix(size, spend)
  draw_functions(cells, fixed, size, version, level)
  spend(2000)
  draw_data(cells, fixed, size, data, spend)
  local chosen, best = 0, math.huge
  for mask = 0, 7 do
    apply_mask(cells, fixed, size, mask, spend)
    draw_format(cells, fixed, size, level, mask)
    local score = penalty(cells, size, spend)
    if score < best then chosen, best = mask, score end
    apply_mask(cells, fixed, size, mask, spend)
  end
  apply_mask(cells, fixed, size, chosen, spend)
  draw_format(cells, fixed, size, level, chosen)
  return {
    size = size, version = version, level = level, path = outline(cells, size, spend),
    dark = function(x, y) return cells[y][x] end,
  }
end

--- Encodes `text` at `level`, M by default, on the ticks after this one:
--- `done(code, why)`, `code` being `{ size, version, level, path, dark(x, y) }`, nil
--- when it will not fit. The handle's `cancel()` drops it.
function M.encode(text, level, done)
  text = tostring(text or "")
  level = level or "M"
  local version = choose(#text, level)
  local refused = text == "" and "nothing to encode" or (not version and "too long for a QR code") or nil
  return poll.job(function(spend)
    if refused then return nil end
    return build(text, version, level, spend)
  end, function(code, why) done(code, refused or why) end, { slice = SLICE })
end

--- An SVG of `code`, dark modules on white with the standard's quiet zone.
function M.svg(code, dark, light)
  local quiet = 4
  local total = code.size + 2 * quiet
  return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" shape-rendering="crispEdges">'
    .. '<rect width="%d" height="%d" fill="%s"/><path fill="%s" transform="translate(%d %d)" d="%s"/></svg>')
    :format(total, total, total, total, light or "#ffffff", dark or "#000000", quiet, quiet, code.path)
end

-- ------------------------------------------------------------------ png --

local CRC = {}
for n = 0, 255 do
  local value = n
  for _ = 1, 8 do value = value & 1 == 1 and 0xEDB88320 ~ (value >> 1) or value >> 1 end
  CRC[n] = value
end

local function chunk(kind, data, spend)
  local value, body = 0xFFFFFFFF, kind .. data
  for i = 1, #body do
    value = CRC[(value ~ body:byte(i)) & 255] ~ (value >> 8)
    if i % 1024 == 0 then spend(2048) end
  end
  return string.pack(">I4", #data) .. body .. string.pack(">I4", value ~ 0xFFFFFFFF)
end

-- `data` as a zlib stream of stored blocks.
local function stored(data, spend)
  local low, high = 1, 0
  for i = 1, #data do
    low = (low + data:byte(i)) % 65521
    high = (high + low) % 65521
    if i % 1024 == 0 then spend(2048) end
  end
  local parts = { "\x78\x01" }
  for at = 1, math.max(#data, 1), 65535 do
    local piece = data:sub(at, at + 65534)
    parts[#parts + 1] = string.pack("<BI2I2", at + 65535 > #data and 1 or 0, #piece, ~#piece & 0xFFFF) .. piece
  end
  parts[#parts + 1] = string.pack(">I4", high << 16 | low)
  return table.concat(parts)
end

-- One row of pixels: a filter byte, then a bit to a pixel, 0 for a dark one.
local function pixel_row(code, y, scale, quiet)
  local side = (code.size + 2 * quiet) * scale
  local bytes, value, bits = { "\0" }, 0, 0
  for pixel = 0, side - 1 do
    local x = pixel // scale - quiet
    local dark = x >= 0 and x < code.size and y >= 0 and y < code.size and code.dark(x, y)
    value, bits = value << 1 | (dark and 0 or 1), bits + 1
    if bits == 8 then
      bytes[#bytes + 1] = string.char(value)
      value, bits = 0, 0
    end
  end
  if bits > 0 then bytes[#bytes + 1] = string.char(value << (8 - bits) | (1 << (8 - bits)) - 1) end
  return table.concat(bytes)
end

--- `code` as the bytes of a black and white PNG, on the ticks after this one:
--- `done(bytes, why)`. `options`: `scale`, pixels to a module (12), and `quiet`, the
--- modules of margin (4).
function M.png(code, options, done)
  options = options or {}
  local scale, quiet = options.scale or 12, options.quiet or 4
  local side = (code.size + 2 * quiet) * scale
  return poll.job(function(spend)
    local rows = {}
    for y = -quiet, code.size + quiet - 1 do
      rows[#rows + 1] = pixel_row(code, y, scale, quiet):rep(scale)
      spend(2 * side)
    end
    return "\137PNG\r\n\26\n" .. chunk("IHDR", string.pack(">I4I4BBBBB", side, side, 1, 0, 0, 0, 0), spend)
      .. chunk("IDAT", stored(table.concat(rows), spend), spend) .. chunk("IEND", "", spend)
  end, done, { slice = SLICE })
end

-- ----------------------------------------------------------------- wi-fi --

M.SECURITY = { "WPA", "WEP", "nopass" }

local function escaped(value) return (tostring(value):gsub('[\\;,:"]', "\\%0")) end

--- The text a phone's camera joins `net` from: `net.ssid`, `net.security` (one of
--- `M.SECURITY`, WPA when not said) and `net.hidden`, with `password`.
function M.wifi(net, password)
  local security = net.security or "WPA"
  local parts = { "WIFI:T:", security, ";S:", escaped(net.ssid), ";" }
  if security ~= "nopass" then parts[#parts + 1] = "P:" .. escaped(password or "") .. ";" end
  if net.hidden then parts[#parts + 1] = "H:true;" end
  parts[#parts + 1] = ";"
  return table.concat(parts)
end

return M
