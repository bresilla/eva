-- What a scratchpad does to text, with no state. A transform is `{ id, name, run }`:
-- `run(text)` answers the new text, or nil and why; `async` hands it `done` as well;
-- `bytes` keeps its answer to the byte on a command line. Sums are the launcher's
-- calculator's (shell/calc.lua), and colours are eva-colorpick's own writing.
local morf = require("morf")
local sys = require("common.sys")
local formats = require("colorpick.formats")

local M = {}

local UPPER_RANGES = {
  { 0xE0, 0xF6, -32 }, { 0xF8, 0xFE, -32 }, { 0x3B1, 0x3C1, -32 }, { 0x3C3, 0x3CB, -32 }, { 0x430, 0x44F, -32 },
  { 0x450, 0x45F, -80 },
}

local function upper_code(code)
  if code >= 97 and code <= 122 then return code - 32 end
  for _, range in ipairs(UPPER_RANGES) do
    if code >= range[1] and code <= range[2] then return code + range[3] end
  end
  return code
end

local function lower_code(code)
  if code >= 65 and code <= 90 then return code + 32 end
  for _, range in ipairs(UPPER_RANGES) do
    if code >= range[1] + range[3] and code <= range[2] + range[3] then return code - range[3] end
  end
  return code
end

-- `text` through `map`, a character at a time; bytes that are not UTF-8 keep ASCII rules.
local function map_chars(text, map, plain)
  local ok, out = pcall(function()
    local parts = {}
    for _, code in utf8.codes(text) do parts[#parts + 1] = utf8.char(map(code)) end
    return table.concat(parts)
  end)
  return ok and out or plain(text)
end

function M.upper(text) return map_chars(text, upper_code, string.upper) end
function M.lower(text) return map_chars(text, lower_code, string.lower) end

local function capitalise(word)
  local first = word:match("^[%z\1-\127\194-\244][\128-\191]*")
  if not first then return word end
  return M.upper(first) .. M.lower(word:sub(#first + 1))
end

local function title(text)
  return (text:gsub("[^%s%-_/]+", capitalise))
end

local function sentence(text)
  local low, start = M.lower(text), true
  return (low:gsub("[^%s]+", function(word)
    local out = start and capitalise(word) or word
    start = word:match("[.!?]$") ~= nil
    return out
  end))
end

-- The words of an identifier or a phrase, lower case.
local function words_of(text)
  local spaced = text:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
  local out = {}
  for word in spaced:gmatch("[%w\128-\255]+") do out[#out + 1] = M.lower(word) end
  return out
end

local function joined(mark, shape)
  return function(text)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
      local words = words_of(line)
      if shape then words = shape(words) end
      out[#out + 1] = table.concat(words, mark)
    end
    return (table.concat(out, "\n"):gsub("\n$", ""))
  end
end

local function camel(words)
  for index, word in ipairs(words) do
    if index > 1 then words[index] = capitalise(word) end
  end
  return words
end

local function pascal(words)
  for index, word in ipairs(words) do words[index] = capitalise(word) end
  return words
end

local function constant(words)
  for index, word in ipairs(words) do words[index] = M.upper(word) end
  return words
end

-- ------------------------------------------------------------------- lines --

local function lines_of(text)
  local out, last = {}, text:sub(-1) == "\n"
  for line in ((last and text or text .. "\n")):gmatch("(.-)\r?\n") do out[#out + 1] = line end
  return out, last
end

local function rejoin(lines, last) return table.concat(lines, "\n") .. (last and "\n" or "") end

local function on_lines(edit)
  return function(text)
    local lines, last = lines_of(text)
    return rejoin(edit(lines), last)
  end
end

local function trim(text)
  local lines, last = lines_of(text)
  for index, line in ipairs(lines) do lines[index] = line:gsub("%s+$", "") end
  return (rejoin(lines, last):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function dedupe(lines)
  local seen, out = {}, {}
  for _, line in ipairs(lines) do
    if not seen[line] then
      seen[line] = true
      out[#out + 1] = line
    end
  end
  return out
end

local function flipped(lines)
  local out = {}
  for index = #lines, 1, -1 do out[#out + 1] = lines[index] end
  return out
end

-- ------------------------------------------------------------------- codes --

local function decoded(decode, what)
  return function(text)
    local ok, out = pcall(decode, (text:gsub("%s+$", "")))
    if ok and out then return out end
    return nil, "That is not " .. what
  end
end

local function to_hex(text)
  return (text:gsub(".", function(char) return ("%02x"):format(char:byte()) end))
end

local function from_hex(text)
  local clean = text:gsub("%s+", "")
  if #clean % 2 ~= 0 or clean:find("%X") then return nil, "That is not hexadecimal" end
  return (clean:gsub("%x%x", function(pair) return string.char(tonumber(pair, 16)) end))
end

local function html(text)
  return (text:gsub('[&<>"]', { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

-- -------------------------------------------------------------------- json --

--- `text` with white space outside strings taken out: keys keep their order
--- and numbers their spelling, which a decode and an encode would not.
function M.json_minify(text)
  local ok = pcall(morf.json.decode, text)
  if not ok then return nil, "That is not JSON" end
  local out, inside, at = {}, false, 1
  while at <= #text do
    local char = text:sub(at, at)
    if inside then
      out[#out + 1] = char
      if char == "\\" then
        at = at + 1
        out[#out + 1] = text:sub(at, at)
      elseif char == '"' then
        inside = false
      end
    elseif char == '"' then
      inside = true
      out[#out + 1] = char
    elseif not char:find("%s") then
      out[#out + 1] = char
    end
    at = at + 1
  end
  return table.concat(out)
end

--- `text` laid out with `width` spaces to a level, its keys in their order.
function M.json_pretty(text, width)
  local flat, why = M.json_minify(text)
  if not flat then return nil, why end
  local step = (" "):rep(width or 2)
  local out, depth, inside, at = {}, 0, false, 1
  local function newline() out[#out + 1] = "\n" .. step:rep(depth) end
  while at <= #flat do
    local char = flat:sub(at, at)
    if inside then
      out[#out + 1] = char
      if char == "\\" then
        at = at + 1
        out[#out + 1] = flat:sub(at, at)
      elseif char == '"' then
        inside = false
      end
    elseif char == '"' then
      inside = true
      out[#out + 1] = char
    elseif char == "{" or char == "[" then
      local next_char = flat:sub(at + 1, at + 1)
      out[#out + 1] = char
      if next_char == "}" or next_char == "]" then
        out[#out + 1] = next_char
        at = at + 1
      else
        depth = depth + 1
        newline()
      end
    elseif char == "}" or char == "]" then
      depth = depth - 1
      newline()
      out[#out + 1] = char
    elseif char == "," then
      out[#out + 1] = char
      newline()
    elseif char == ":" then
      out[#out + 1] = ": "
    else
      out[#out + 1] = char
    end
    at = at + 1
  end
  return table.concat(out)
end

-- ------------------------------------------------------------------ numbers --

-- A moment read from a line: seconds, milliseconds, or a date.
local function moment(line)
  local number = tonumber(line)
  if number then return math.abs(number) >= 1e11 and number / 1000 or number end
  local ok, at = pcall(morf.time.parse, line)
  return ok and at or nil
end

local function epoch(text)
  local out = {}
  for _, line in ipairs((lines_of(text))) do
    local word = line:match("^%s*(.-)%s*$")
    if word ~= "" then
      local at = moment(word)
      if not at then return nil, "Not a time: " .. word end
      if tonumber(word) then
        out[#out + 1] = morf.time.format("%Y-%m-%d %H:%M:%S UTC", at, { tz = "UTC" })
      else
        out[#out + 1] = tostring(math.floor(at))
      end
    end
  end
  if #out == 0 then return tostring(math.floor(morf.time.now())) end
  return table.concat(out, "\n")
end

local function bits(number)
  if number == 0 then return "0" end
  local out = {}
  while number > 0 do
    table.insert(out, 1, tostring(number & 1))
    number = number >> 1
  end
  return table.concat(out)
end

local function base(text)
  local word = text:match("^%s*(.-)%s*$"):lower()
  local number = word:match("^0b([01]+)$")
  if number then number = tonumber(number, 2)
  else
    local octal = word:match("^0o([0-7]+)$")
    number = octal and tonumber(octal, 8) or math.tointeger(tonumber(word))
  end
  if not number or number < 0 then return nil, "Say a whole number: 255, 0xff, 0o377 or 0b11111111" end
  return ("%d\n0x%x\n0o%o\n0b%s"):format(number, number, number, bits(number))
end

local function colours(text)
  local word = text:match("^%s*(.-)%s*$")
  local out = {}
  for _, name in ipairs(formats.NAMES) do
    local ok, written = pcall(formats.write, word, name)
    if not ok then return nil, "Not a colour: " .. word end
    out[#out + 1] = written
  end
  return table.concat(out, "\n")
end

-- ----------------------------------------------------------------- counting --

--- Lines, words, characters and bytes of `text`.
function M.counts(text)
  local words, lines = 0, 0
  for _ in text:gmatch("%S+") do words = words + 1 end
  if text ~= "" then
    lines = 1
    for _ in text:gmatch("\n") do lines = lines + 1 end
    if text:sub(-1) == "\n" then lines = lines - 1 end
  end
  return { lines = lines, words = words, characters = utf8.len(text) or #text, bytes = #text }
end

local function plural(count, word) return ("%d %s%s"):format(count, word, count == 1 and "" or "s") end

--- The counts in words.
function M.count_words(text)
  local c = M.counts(text)
  return table.concat({ plural(c.lines, "line"), plural(c.words, "word"), plural(c.characters, "character"),
    plural(c.bytes, "byte") }, " · ")
end

local function md5(text, done)
  sys.run({ "md5sum" }, { stdin = text, read = true, timeout_ms = 5000 }, function(result)
    if not result.ok then done(nil, "md5sum did not answer") return end
    done((result.stdout:match("^(%x+)")))
  end)
end

-- ------------------------------------------------------------------- tables --

M.GROUPS = {
  { key = "case", name = "Case", icon = "match_case", items = {
    { id = "upper", name = "UPPER", run = M.upper }, { id = "lower", name = "lower", run = M.lower },
    { id = "title", name = "Title", run = title }, { id = "sentence", name = "Sentence", run = sentence },
    { id = "camel", name = "camelCase", run = joined("", camel) }, { id = "pascal", name = "PascalCase", run = joined("", pascal) },
    { id = "snake", name = "snake_case", run = joined("_") }, { id = "kebab", name = "kebab-case", run = joined("-") },
    { id = "constant", name = "CONSTANT", run = joined("_", constant) },
  } },
  { key = "lines", name = "Lines", icon = "format_list_bulleted", items = {
    { id = "trim", name = "Trim", run = trim },
    { id = "sort", name = "Sort", run = on_lines(function(lines) table.sort(lines) return lines end) },
    { id = "rsort", name = "Sort down", run = on_lines(function(lines)
      table.sort(lines, function(a, b) return a > b end)
      return lines
    end) },
    { id = "dedupe", name = "Dedupe", run = on_lines(dedupe) },
    { id = "reverse", name = "Reverse", run = on_lines(flipped) },
    { id = "count", name = "Count", run = function(text) return M.count_words(text) end },
  } },
  { key = "codes", name = "Codes", icon = "code", items = {
    { id = "base64", name = "Base64", run = function(text) return morf.encoding.base64_encode(text) end },
    { id = "unbase64", name = "From Base64", bytes = true, run = decoded(morf.encoding.base64_decode, "Base64") },
    { id = "url", name = "URL", run = function(text) return morf.encoding.url_encode(text) end },
    { id = "unurl", name = "From URL", run = decoded(morf.encoding.url_decode, "URL encoded") },
    { id = "hex", name = "Hex", run = to_hex }, { id = "unhex", name = "From hex", bytes = true, run = from_hex },
    { id = "html", name = "HTML", run = html },
  } },
  { key = "data", name = "Data", icon = "data_object", items = {
    { id = "json", name = "JSON pretty", run = function(text) return M.json_pretty(text) end },
    { id = "minify", name = "JSON minify", run = M.json_minify },
    { id = "sha1", name = "SHA-1", run = function(text) return morf.encoding.sha1(text) end },
    { id = "sha256", name = "SHA-256", run = function(text) return morf.encoding.sha256(text) end },
    { id = "md5", name = "MD5", async = true, program = "md5sum", run = md5 },
    { id = "epoch", name = "Epoch", run = epoch }, { id = "colour", name = "Colour", run = colours },
    { id = "base", name = "Bases", run = base },
  } },
}

--- The transform called `id`, or nil.
function M.find(id)
  for _, group in ipairs(M.GROUPS) do
    for _, item in ipairs(group.items) do
      if item.id == id then return item end
    end
  end
end

--- Whether this machine can run `item`.
function M.present(item) return item.program == nil or sys.has(item.program) end

--- Runs `item` on `text`: `done(answer, why)`.
function M.run(item, text, done)
  if item.async then
    item.run(text, done)
    return
  end
  local ok, answer, why = pcall(item.run, text)
  if not ok then done(nil, "That did not work") return end
  done(answer, why)
end

local LOREM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et "
  .. "dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea "
  .. "commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla "
  .. "pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est "
  .. "laborum."

--- `count` paragraphs of placeholder text.
function M.lorem(count)
  local out = {}
  for index = 1, math.max(1, math.min(count or 1, 100)) do out[index] = LOREM end
  return table.concat(out, "\n\n")
end

return M
