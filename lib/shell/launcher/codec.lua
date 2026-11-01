-- Text turned into other text: encodings, a digest morf has no native for,
-- naming styles, tokens and placeholder words.

local morf = require("morf")

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

--- `text` split into lower-case words, whatever style it was written in.
function M.words(text)
  local spaced = text:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2"):gsub("[_%-%./]+", " ")
  local out = {}
  for word in spaced:gmatch("%S+") do out[#out + 1] = word:lower() end
  return out
end

local function title(word) return word:sub(1, 1):upper() .. word:sub(2) end

--- `text` in every naming style: a list of `{ style, text }`.
function M.cases(text)
  local words = M.words(text)
  local titled, camel = {}, {}
  for i, word in ipairs(words) do
    titled[i] = title(word)
    camel[i] = i == 1 and word or title(word)
  end
  return {
    { "UPPER CASE", text:upper() },
    { "lower case", text:lower() },
    { "Title Case", table.concat(titled, " ") },
    { "Sentence case", title(text:lower()) },
    { "camelCase", table.concat(camel) },
    { "PascalCase", table.concat(titled) },
    { "snake_case", table.concat(words, "_") },
    { "kebab-case", table.concat(words, "-") },
    { "CONSTANT_CASE", table.concat(words, "_"):upper() },
    { "dot.case", table.concat(words, ".") },
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

--- The MD5 digest of `text`, in hexadecimal.
function M.md5(text)
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

local function pretty(value, depth, out)
  local pad = string.rep("  ", depth)
  if type(value) ~= "table" then
    out[#out + 1] = morf.json.encode(value)
    return
  end
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  if #keys == 0 then out[#out + 1] = "{}" return end
  local list = value[1] ~= nil
  if not list then table.sort(keys, function(a, b) return tostring(a) < tostring(b) end) end
  out[#out + 1] = list and "[\n" or "{\n"
  local count = list and #value or #keys
  for i = 1, count do
    out[#out + 1] = pad .. "  "
    if not list then out[#out + 1] = morf.json.encode(tostring(keys[i])) .. ": " end
    pretty(list and value[i] or value[keys[i]], depth + 1, out)
    out[#out + 1] = i < count and ",\n" or "\n"
  end
  out[#out + 1] = pad .. (list and "]" or "}")
end

--- `text` as indented JSON and as one line, or nil when it is not JSON.
function M.json(text)
  local ok, value = pcall(morf.json.decode, text)
  if not ok or value == nil then return nil end
  local out = {}
  pretty(value, 0, out)
  return table.concat(out), morf.json.encode(value)
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
  for i = 1, math.max(1, math.min(20, paragraphs or 1)) do out[i] = LOREM end
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
