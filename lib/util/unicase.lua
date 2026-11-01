-- Case and accents past ASCII, which Lua's own string.upper leaves alone: the
-- Latin, Greek and Cyrillic letters a keyboard types.
--
--   unicase.upper("éя")   --> "ÉЯ"
--   unicase.lower("ÉЯ")   --> "éя"
--   unicase.fold("Café")  --> "cafe"
--   unicase.chars("éa")   --> { "é", "a" }

local M = {}

local to_lower, to_upper = {}, {}
local function pair(up, low)
  to_lower[up] = low
  if not to_upper[low] then to_upper[low] = up end
end
for cp = 0xC0, 0xDE do if cp ~= 0xD7 then pair(cp, cp + 32) end end
pair(0x178, 0xFF)
-- Latin Extended-A: capitals on the even code points, then on the odd.
for cp = 0x100, 0x136, 2 do if cp ~= 0x130 then pair(cp, cp + 1) end end
for cp = 0x139, 0x147, 2 do pair(cp, cp + 1) end
for cp = 0x14A, 0x176, 2 do pair(cp, cp + 1) end
for cp = 0x179, 0x17D, 2 do pair(cp, cp + 1) end
for cp = 0x218, 0x21A, 2 do pair(cp, cp + 1) end
for cp = 0x391, 0x3A9 do if cp ~= 0x3A2 then pair(cp, cp + 32) end end
to_upper[0x3C2] = 0x3A3
for up, low in pairs { [0x386] = 0x3AC, [0x388] = 0x3AD, [0x389] = 0x3AE, [0x38A] = 0x3AF,
  [0x38C] = 0x3CC, [0x38E] = 0x3CD, [0x38F] = 0x3CE } do pair(up, low) end
for cp = 0x400, 0x40F do pair(cp, cp + 80) end
for cp = 0x410, 0x42F do pair(cp, cp + 32) end
pair(0x490, 0x491)

local function map(text, ascii, table_of)
  if not text:find("[\128-\255]") then return ascii(text) end
  local out = {}
  for _, cp in utf8.codes(text, true) do
    if cp < 128 then out[#out + 1] = ascii(string.char(cp))
    else out[#out + 1] = utf8.char(table_of[cp] or cp) end
  end
  return table.concat(out)
end

function M.upper(text) return map(text, string.upper, to_upper) end
function M.lower(text) return map(text, string.lower, to_lower) end

-- Each accented letter's plain one.
local PLAIN = {}
local function plain(letters, base)
  for _, cp in utf8.codes(letters) do PLAIN[cp] = base end
end
plain("àáâãäåāăą", "a") plain("çćĉċč", "c") plain("ďđ", "d") plain("èéêëēĕėęě", "e")
plain("ĝğġģ", "g") plain("ĥħ", "h") plain("ìíîïĩīĭįı", "i") plain("ĵ", "j") plain("ķ", "k")
plain("ĺļľŀł", "l") plain("ñńņňŉ", "n") plain("òóôõöøōŏő", "o") plain("ŕŗř", "r")
plain("śŝşšș", "s") plain("ţťŧț", "t") plain("ùúûüũūŭůűų", "u") plain("ŵ", "w")
plain("ýÿŷ", "y") plain("źżž", "z") plain("ά", "α") plain("έ", "ε") plain("ή", "η")
plain("ίϊΐ", "ι") plain("ό", "ο") plain("ύϋΰ", "υ") plain("ώ", "ω") plain("ς", "σ")
plain("ё", "е")

--- `text` in lower case with its accents gone, for matching what was typed
--- against a word.
function M.fold(text)
  local low = M.lower(text)
  if not low:find("[\128-\255]") then return low end
  local out = {}
  for _, cp in utf8.codes(low, true) do
    out[#out + 1] = PLAIN[cp] or utf8.char(cp)
  end
  return table.concat(out)
end

--- The characters of `text`.
function M.chars(text)
  local out = {}
  for _, cp in utf8.codes(text, true) do out[#out + 1] = utf8.char(cp) end
  return out
end

return M
