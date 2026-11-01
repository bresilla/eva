-- Text turned into other text: encodings, an MD5 digest,
-- case and naming styles, JSON, tokens and placeholder words. The launcher's modes
-- and eva-text both call these.

local morf = require("morf")
local unicase = require("lib.util.unicase")

local M = {}

--- `text` as hexadecimal.
function M.hex_encode(text)
  return (text:gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

--- The bytes of a hexadecimal string, or nil.
function M.hex_decode(text)
  local digits = text:gsub("%s", ""):gsub("^0[xX]", "")
  if #digits % 2 ~= 0 or digits:find("%X") then return nil end
  return (digits:gsub("%x%x", function(pair) return string.char(tonumber(pair, 16)) end))
end

local ENTITIES = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&#39;" }
local NAMED = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " " }

function M.html_encode(text) return (text:gsub("[&<>\"']", ENTITIES)) end

function M.html_decode(text)
  return (text:gsub("&(#?[%w]+);", function(name)
    local hex = name:match("^#[xX](%x+)$")
    if hex then return utf8.char(tonumber(hex, 16)) end
    local number = name:match("^#(%d+)$")
    if number then return utf8.char(tonumber(number)) end
    return NAMED[name]
  end))
end

function M.rot13(text)
  return (text:gsub("%a", function(c)
    local base = c:match("%l") and 97 or 65
    return string.char((c:byte() - base + 13) % 26 + base)
  end))
end

-- ----------------------------------------------------------------- case --

M.upper, M.lower = unicase.upper, unicase.lower

local function capitalise(word) return unicase.capitalise(M.lower(word)) end

--- Each word of `text` capitalised, its separators kept.
function M.title(text)
  return (text:gsub("[^%s%-_/]+", capitalise))
end

--- `text` in lower case with each sentence's first word capitalised.
function M.sentence(text)
  local low, start = M.lower(text), true
  return (low:gsub("[^%s]+", function(word)
    local out = start and capitalise(word) or word
    start = word:match("[.!?]$") ~= nil
    return out
  end))
end

--- `text` split into lower-case words, whatever style it was written in.
function M.words(text)
  local spaced = text:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"):gsub("(%d)(%a)", "%1 %2")
  local out = {}
  for word in spaced:gmatch("[%w\128-\255]+") do out[#out + 1] = M.lower(word) end
  return out
end

-- A style: each line's words through `shape`, joined by `mark`.
local function joined(mark, shape)
  return function(text)
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do
      local words = M.words(line)
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

M.camel, M.pascal, M.constant = joined("", camel), joined("", pascal), joined("_", constant)
M.snake, M.kebab, M.dot = joined("_"), joined("-"), joined(".")

--- `text` in every naming style: a list of `{ style, text }`.
function M.cases(text)
  return {
    { "UPPER CASE", M.upper(text) },
    { "lower case", M.lower(text) },
    { "Title Case", table.concat(pascal(M.words(text)), " ") },
    { "Sentence case", M.sentence(text) },
    { "camelCase", M.camel(text) },
    { "PascalCase", M.pascal(text) },
    { "snake_case", M.snake(text) },
    { "kebab-case", M.kebab(text) },
    { "CONSTANT_CASE", M.constant(text) },
    { "dot.case", M.dot(text) },
  }
end

-- ------------------------------------------------------------------ md5 --

local S = { 7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21 }
local K = {}
for i = 0, 63 do K[i] = math.floor(math.abs(math.sin(i + 1)) * 4294967296) end

local function rotate(x, c)
  x = x & 0xFFFFFFFF
  return ((x << c) | (x >> (32 - c))) & 0xFFFFFFFF
end

--- The MD5 digest of `text`, in hexadecimal. `spend` is a `lib.util.poll` job's,
--- for text longer than a handler's fuel; 14 kB fit without.
function M.md5(text, spend)
  local length = #text
  local message = text .. "\128" .. string.rep("\0", (55 - length) % 64) .. string.pack("<I8", length * 8)
  local a0, b0, c0, d0 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
  for chunk = 1, #message, 64 do
    local words = { string.unpack("<I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", message, chunk) }
    local a, b, c, d = a0, b0, c0, d0
    for i = 0, 63 do
      local f, g
      if i < 16 then f, g = (b & c) | (~b & d), i
      elseif i < 32 then f, g = (d & b) | (~d & c), (5 * i + 1) % 16
      elseif i < 48 then f, g = b ~ c ~ d, (3 * i + 5) % 16
      else f, g = c ~ (b | (~d & 0xFFFFFFFF)), (7 * i) % 16 end
      f = (f + a + K[i] + words[g + 1]) & 0xFFFFFFFF
      a, d, c = d, c, b
      b = (b + rotate(f, S[(i // 16) * 4 + i % 4 + 1])) & 0xFFFFFFFF
    end
    a0, b0, c0, d0 = (a0 + a) & 0xFFFFFFFF, (b0 + b) & 0xFFFFFFFF, (c0 + c) & 0xFFFFFFFF, (d0 + d) & 0xFFFFFFFF
    if spend then spend(200) end
  end
  return (string.pack("<I4I4I4I4", a0, b0, c0, d0):gsub(".", function(c) return ("%02x"):format(c:byte()) end))
end

-- ------------------------------------------------------------------ jwt --

local function base64url(text)
  local plain = text:gsub("-", "+"):gsub("_", "/")
  plain = plain .. string.rep("=", (4 - #plain % 4) % 4)
  return morf.encoding.base64_decode(plain)
end

--- The header and payload of a JSON Web Token, as JSON text, or nil. The
--- signature is not checked.
function M.jwt(token)
  local head, body = token:match("^%s*([%w_-]+)%.([%w_-]+)%.?[%w_-]*%s*$")
  if not head then return nil end
  local ok_head, header = pcall(base64url, head)
  local ok_body, payload = pcall(base64url, body)
  if not (ok_head and ok_body and header and payload) then return nil end
  if not (pcall(morf.json.decode, header) and pcall(morf.json.decode, payload)) then return nil end
  return header, payload
end

-- ----------------------------------------------------------------- json --

-- Where the string opening at `from` closes.
local function string_end(text, from)
  local at = from + 1
  while true do
    local mark = text:find('["\\]', at)
    if not mark then return #text end
    if text:sub(mark, mark) == '"' then return mark end
    at = mark + 2
  end
end

--- `text` with white space outside strings taken out, keys in their order and
--- numbers as written.
function M.json_minify(text)
  local ok = pcall(morf.json.decode, text)
  if not ok then return nil, "That is not JSON" end
  local out, at = {}, 1
  while at <= #text do
    local quote = text:find('"', at, true) or #text + 1
    out[#out + 1] = (text:sub(at, quote - 1):gsub("%s+", ""))
    if quote > #text then break end
    local close = string_end(text, quote)
    out[#out + 1] = text:sub(quote, close)
    at = close + 1
  end
  return table.concat(out)
end

-- `flat`, JSON with no white space, laid out with `width` spaces to a level.
local function laid_out(flat, width)
  local lines = setmetatable({}, { __index = function(known, depth)
    known[depth] = "\n" .. (" "):rep(width * depth)
    return known[depth]
  end })
  local out, n, depth, at = {}, 0, 0, 1
  while at <= #flat do
    local mark, _, char = flat:find('([%[%]{},:"])', at)
    if not mark then
      out[n + 1] = flat:sub(at)
      break
    end
    if mark > at then
      n = n + 1
      out[n] = flat:sub(at, mark - 1)
    end
    at = mark + 1
    if char == '"' then
      at = string_end(flat, mark) + 1
      n = n + 1
      out[n] = flat:sub(mark, at - 1)
    elseif char == "," then
      out[n + 1], out[n + 2] = char, lines[depth]
      n = n + 2
    elseif char == ":" then
      n = n + 1
      out[n] = ": "
    elseif char == "}" or char == "]" then
      depth = depth - 1
      out[n + 1], out[n + 2] = lines[depth], char
      n = n + 2
    else
      local next_char = flat:sub(at, at)
      if next_char == "}" or next_char == "]" then
        out[n + 1], out[n + 2] = char, next_char
        at = at + 1
      else
        depth = depth + 1
        out[n + 1], out[n + 2] = char, lines[depth]
      end
      n = n + 2
    end
  end
  return table.concat(out)
end

--- `text` laid out with `width` spaces to a level, its keys in their order.
function M.json_pretty(text, width)
  local flat, why = M.json_minify(text)
  if not flat then return nil, why end
  return laid_out(flat, width or 2)
end

--- `text` as indented JSON and as one line, or nil when it is not JSON.
function M.json(text)
  local line = M.json_minify(text)
  if not line then return nil end
  return laid_out(line, 2), line
end

-- ---------------------------------------------------------------- lorem --

local LOREM = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore "
  .. "et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex "
  .. "ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat "
  .. "nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim "
  .. "id est laborum."

--- `paragraphs` paragraphs of placeholder text.
function M.lorem(paragraphs)
  local out = {}
  for i = 1, math.max(1, math.min(100, paragraphs or 1)) do out[i] = LOREM end
  return table.concat(out, "\n\n")
end

--- The code points of `text`, as U+ names: a list of `{ char, name }`.
function M.code_points(text)
  local out = {}
  if not utf8.len(text) then return out end
  for _, code in utf8.codes(text) do
    out[#out + 1] = { utf8.char(code), ("U+%04X"):format(code) }
  end
  return out
end

return M
