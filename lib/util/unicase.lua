-- Case and accents past ASCII, which Lua's own string.upper leaves alone: the
-- Latin (Latin-1 and the Extended blocks), Greek and Cyrillic letters. Each is
-- Unicode's simple mapping, one character for one, so a letter with no single
-- capital stays itself: ß, ŉ.
--
--   unicase.upper("éя")       --> "ÉЯ"
--   unicase.lower("ÉЯ")       --> "éя"
--   unicase.fold("Café")      --> "cafe"
--   unicase.chars("éa")       --> { "é", "a" }
--   unicase.first("ëa")       --> "ë"
--   unicase.capitalise("ëa")  --> "Ëa"
--   unicase.initial("(éa)")   --> "É"

local M = {}

local to_lower, to_upper = {}, {}
local function pair(up, low)
  to_lower[up] = low
  if not to_upper[low] then to_upper[low] = up end
end
-- Capitals on every other code point, each with its small letter next.
local function alternate(from, to)
  for cp = from, to, 2 do pair(cp, cp + 1) end
end
-- Latin-1.
for cp = 0xC0, 0xDE do if cp ~= 0xD7 then pair(cp, cp + 32) end end
pair(0x178, 0xFF)
to_upper[0xB5] = 0x39C
-- Latin Extended-A. İ and ı cross into ASCII, as does the long s.
alternate(0x100, 0x12E)
alternate(0x132, 0x136)
alternate(0x139, 0x147)
alternate(0x14A, 0x176)
alternate(0x179, 0x17D)
to_lower[0x130], to_upper[0x131], to_upper[0x17F] = 0x69, 0x49, 0x53
-- Latin Extended-B.
for _, run in ipairs { { 0x182, 0x184 }, { 0x187, 0x187 }, { 0x18B, 0x18B }, { 0x191, 0x191 }, { 0x198, 0x198 },
  { 0x1A0, 0x1A4 }, { 0x1A7, 0x1A7 }, { 0x1AC, 0x1AC }, { 0x1AF, 0x1AF }, { 0x1B3, 0x1B5 }, { 0x1B8, 0x1B8 },
  { 0x1BC, 0x1BC }, { 0x1CD, 0x1DB }, { 0x1DE, 0x1EE }, { 0x1F4, 0x1F4 }, { 0x1F8, 0x21E }, { 0x222, 0x232 },
  { 0x23B, 0x23B }, { 0x241, 0x241 }, { 0x246, 0x24E } } do alternate(run[1], run[2]) end
for up, low in pairs { [0x181] = 0x253, [0x186] = 0x254, [0x189] = 0x256, [0x18A] = 0x257, [0x18E] = 0x1DD,
  [0x18F] = 0x259, [0x190] = 0x25B, [0x193] = 0x260, [0x194] = 0x263, [0x196] = 0x269, [0x197] = 0x268,
  [0x19C] = 0x26F, [0x19D] = 0x272, [0x19F] = 0x275, [0x1A6] = 0x280, [0x1A9] = 0x283, [0x1AE] = 0x288,
  [0x1B1] = 0x28A, [0x1B2] = 0x28B, [0x1B7] = 0x292, [0x1F6] = 0x195, [0x1F7] = 0x1BF, [0x220] = 0x19E,
  [0x23A] = 0x2C65, [0x23D] = 0x19A, [0x23E] = 0x2C66, [0x243] = 0x180, [0x244] = 0x289, [0x245] = 0x28C,
  [0x2C7E] = 0x23F, [0x2C7F] = 0x240, [0xA7DC] = 0x19B } do
  pair(up, low)
end
-- The digraphs: capital, title case, small.
for _, up in ipairs { 0x1C4, 0x1C7, 0x1CA, 0x1F1 } do
  pair(up, up + 2)
  to_upper[up + 1], to_lower[up + 1] = up, up + 2
end
-- Latin Extended Additional.
alternate(0x1E00, 0x1E94)
alternate(0x1EA0, 0x1EFE)
to_lower[0x1E9E], to_upper[0x1E9B] = 0xDF, 0x1E60
-- Greek, with the old letters and the symbols that read as letters.
for cp = 0x391, 0x3AB do if cp ~= 0x3A2 then pair(cp, cp + 32) end end
to_upper[0x3C2] = 0x3A3
for up, low in pairs { [0x386] = 0x3AC, [0x388] = 0x3AD, [0x389] = 0x3AE, [0x38A] = 0x3AF,
  [0x38C] = 0x3CC, [0x38E] = 0x3CD, [0x38F] = 0x3CE, [0x37F] = 0x3F3, [0x3CF] = 0x3D7, [0x3F9] = 0x3F2,
  [0x3FD] = 0x37B, [0x3FE] = 0x37C, [0x3FF] = 0x37D } do pair(up, low) end
alternate(0x370, 0x372)
alternate(0x376, 0x376)
alternate(0x3D8, 0x3EE)
alternate(0x3F7, 0x3F7)
alternate(0x3FA, 0x3FA)
for low, up in pairs { [0x3D0] = 0x392, [0x3D1] = 0x398, [0x3D5] = 0x3A6, [0x3D6] = 0x3A0, [0x3F0] = 0x39A,
  [0x3F1] = 0x3A1, [0x3F5] = 0x395 } do to_upper[low] = up end
to_lower[0x3F4] = 0x3B8
-- Cyrillic.
for cp = 0x400, 0x40F do pair(cp, cp + 80) end
for cp = 0x410, 0x42F do pair(cp, cp + 32) end
alternate(0x460, 0x480)
alternate(0x48A, 0x4BE)
pair(0x4C0, 0x4CF)
alternate(0x4C1, 0x4CD)
alternate(0x4D0, 0x52E)

local function map(text, ascii, table_of)
  if not text:find("[\128-\255]") or not utf8.len(text) then return ascii(text) end
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

--- The first `count` characters of `text` (1), whole ones.
function M.first(text, count)
  count = count or 1
  if not utf8.len(text) then return text:sub(1, count) end
  local stop = utf8.offset(text, count + 1)
  return stop and text:sub(1, stop - 1) or text
end

--- `text` with its first letter a capital and the rest as it is.
function M.capitalise(text)
  local lead = M.first(text)
  return M.upper(lead) .. text:sub(#lead + 1)
end

--- The first letter or digit of `text` as a capital: what stands for a name on
--- an avatar. `fallback` ("?") where it has none.
function M.initial(text, fallback)
  if utf8.len(text) then
    for _, char in ipairs(M.chars(text)) do
      if #char > 1 or char:find("%w") then return M.upper(char) end
    end
  end
  return fallback or "?"
end

return M
