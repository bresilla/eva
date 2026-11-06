-- What a scratchpad does to text, with no state. A transform is `{ id, name, run }`:
-- `run(text)` answers the new text, or nil and why; `async` hands it `done` as well;
-- `bytes` keeps its answer to the byte on a command line. Encodings, case and JSON
-- are the launcher's codec, sums its calculator's (shell/calc.lua), and colours
-- eva-colorpick's own writing.
local morf = require("morf")
local poll = require("lib.util.poll")
local codec = require("lib.shell.launcher.codec")
local formats = require("apps.colorpick.formats")

local M = {}

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

-- MD5 a slice to a timer tick, for what is piped in at any length.
local function md5(text, done)
  poll.job(function(spend) return codec.md5(text, spend) end, done, { slice = 20000 })
end

-- ------------------------------------------------------------------- tables --

M.GROUPS = {
  { key = "case", name = "Case", icon = "match_case", items = {
    { id = "upper", name = "UPPER", run = codec.upper }, { id = "lower", name = "lower", run = codec.lower },
    { id = "title", name = "Title", run = codec.title }, { id = "sentence", name = "Sentence", run = codec.sentence },
    { id = "camel", name = "camelCase", run = codec.camel }, { id = "pascal", name = "PascalCase", run = codec.pascal },
    { id = "snake", name = "snake_case", run = codec.snake }, { id = "kebab", name = "kebab-case", run = codec.kebab },
    { id = "constant", name = "CONSTANT", run = codec.constant },
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
    { id = "hex", name = "Hex", run = codec.hex_encode },
    { id = "unhex", name = "From hex", bytes = true, run = decoded(codec.hex_decode, "hexadecimal") },
    { id = "html", name = "HTML", run = codec.html_encode },
  } },
  { key = "data", name = "Data", icon = "data_object", items = {
    { id = "json", name = "JSON pretty", run = function(text) return codec.json_pretty(text) end },
    { id = "minify", name = "JSON minify", run = codec.json_minify },
    { id = "sha1", name = "SHA-1", run = function(text) return morf.encoding.sha1(text) end },
    { id = "sha256", name = "SHA-256", run = function(text) return morf.encoding.sha256(text) end },
    { id = "md5", name = "MD5", async = true, run = md5 },
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

return M
