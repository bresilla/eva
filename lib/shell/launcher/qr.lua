-- QR codes in plain Lua (ISO/IEC 18004): byte mode, error correction M, up to
-- `MAX_BYTES`, as much as one handler can build and a screen can show a camera.
--
--   local qr = require("lib.shell.launcher.qr")
--   local code = qr.encode("https://example.org")   -- nil, why when too long
--   code.size, code.dark(x, y)                       -- 0-based modules
--   qr.svg(code)                                     -- an inline SVG, quiet zone included

local M = { MAX_BYTES = 400 }

local ECC_PER_BLOCK = { M = { 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24 } }
local BLOCKS = { M = { 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10 } }
local FORMAT = { M = 0 }

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

local function remainder(data, div)
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

local function choose(length)
  for version = 1, #BLOCKS.M do
    if fits(length, version, "M") then return version, "M" end
  end
end

-- -------------------------------------------------------------- the data --

local function codewords(text, version, level)
  local bits, n = {}, 0
  local function push(value, count)
    for i = count - 1, 0, -1 do
      n = n + 1
      bits[n] = (value >> i) & 1
    end
  end
  push(4, 4)
  push(#text, version < 10 and 8 or 16)
  for i = 1, #text do push(text:byte(i), 8) end
  local capacity = data_codewords(version, level) * 8
  push(0, math.min(4, capacity - n))
  push(0, (8 - n % 8) % 8)
  local bytes = {}
  for i = 1, n, 8 do
    local value = 0
    for j = 0, 7 do value = (value << 1) | bits[i + j] end
    bytes[#bytes + 1] = value
  end
  local pad = 0xEC
  while #bytes * 8 < capacity do
    bytes[#bytes + 1] = pad
    pad = pad == 0xEC and 0x11 or 0xEC
  end
  return bytes
end

local function interleaved(data, version, level)
  local blocks_n = BLOCKS[level][version]
  local ecc_len = ECC_PER_BLOCK[level][version]
  local raw = raw_modules(version) // 8
  local short_n = blocks_n - raw % blocks_n
  local short_len = raw // blocks_n
  local div = divisor(ecc_len)
  local blocks, at = {}, 1
  for i = 1, blocks_n do
    local length = short_len - ecc_len + (i <= short_n and 0 or 1)
    local block = {}
    for j = 1, length do block[j] = data[at + j - 1] end
    at = at + length
    local ecc = remainder(block, div)
    if i <= short_n then block[#block + 1] = -1 end
    for _, byte in ipairs(ecc) do block[#block + 1] = byte end
    blocks[i] = block
  end
  local out = {}
  for i = 1, #blocks[1] do
    for j = 1, blocks_n do
      local byte = blocks[j][i]
      if byte >= 0 then out[#out + 1] = byte end
    end
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

local function matrix(size)
  local cells, fixed = {}, {}
  for y = 0, size - 1 do
    cells[y], fixed[y] = {}, {}
    for x = 0, size - 1 do cells[y][x], fixed[y][x] = false, false end
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

local function draw_data(cells, fixed, size, data)
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

local function apply_mask(cells, fixed, size, mask)
  local inverts = MASKS[mask]
  for y = 0, size - 1 do
    local row, held = cells[y], fixed[y]
    for x = 0, size - 1 do
      if not held[x] and inverts(x, y) then row[x] = not row[x] end
    end
  end
end

-- How far a mask is from half the modules dark, with runs of five or more
-- along the rows: the cheap part of the standard's penalty.
local function penalty(cells, size)
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
  end
  local share = dark * 20 // (size * size)
  return score + math.abs(share - 10) * 10
end

-- Past this size a mask is taken without trying them all.
local TRIED_UP_TO = 33

--- Encodes `text`. Returns `{ size, version, level, dark(x, y) }`, or nil and
--- why when it will not fit.
function M.encode(text)
  text = tostring(text or "")
  if text == "" then return nil, "nothing to encode" end
  if #text > M.MAX_BYTES then return nil, "too long for a QR code" end
  local version, level = choose(#text)
  if not version then return nil, "too long for a QR code" end
  local size = version * 4 + 17
  local data = interleaved(codewords(text, version, level), version, level)
  local cells, fixed = matrix(size)
  draw_functions(cells, fixed, size, version, level)
  draw_data(cells, fixed, size, data)
  local chosen, best = 2, math.huge
  if size <= TRIED_UP_TO then
    for mask = 0, 7 do
      apply_mask(cells, fixed, size, mask)
      draw_format(cells, fixed, size, level, mask)
      local score = penalty(cells, size)
      if score < best then chosen, best = mask, score end
      apply_mask(cells, fixed, size, mask)
    end
  end
  apply_mask(cells, fixed, size, chosen)
  draw_format(cells, fixed, size, level, chosen)
  return {
    size = size, version = version, level = level,
    dark = function(x, y) return cells[y][x] end,
  }
end

--- An SVG of `code`, dark modules on white with the standard's quiet zone.
function M.svg(code, dark, light)
  local quiet = 4
  local total = code.size + 2 * quiet
  local parts = {}
  for y = 0, code.size - 1 do
    local x = 0
    while x < code.size do
      if code.dark(x, y) then
        local from = x
        while x < code.size and code.dark(x, y) do x = x + 1 end
        parts[#parts + 1] = ("M%d %dh%dv1h-%dz"):format(from + quiet, y + quiet, x - from, x - from)
      else
        x = x + 1
      end
    end
  end
  return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" shape-rendering="crispEdges">'
    .. '<rect width="%d" height="%d" fill="%s"/><path fill="%s" d="%s"/></svg>')
    :format(total, total, total, total, light or "#ffffff", dark or "#000000", table.concat(parts))
end

return M
