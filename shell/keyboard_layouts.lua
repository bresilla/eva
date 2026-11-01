-- The keyboard's languages: each one's rows of letters, what its keys offer on
-- a long press, and the word list it predicts from.
--
--   rows    the three rows of letters, as strings
--   alts    a letter's offers on a long press, before the shared accents
--   words   the list in shell/assets/words, when there is one
--   whole   never cut down to the 26 keys of a QWERTY board
--   upper   letters whose capital is not the usual one
--
-- `plan` fits a language onto the keys lib.shell.osk builds, which are fixed:
-- 26 letters, and ten digits above them. A language with more letters takes
-- the digit keys over, and every key is placed again from its rows.
local config = require("config")
local unicase = require("lib.util.unicase")

local M = {}

local QWERTY = { "qwertyuiop", "asdfghjkl", "zxcvbnm" }
local QWERTZ = { "qwertzuiop", "asdfghjkl", "yxcvbnm" }
local DIGITS = "1234567890"

-- What each letter offers in any language that names none of its own first.
M.ACCENTS = {
  a = { "á", "à", "â", "ä", "ã", "å", "æ", "ā" }, c = { "ç", "ć", "č" }, d = { "ð", "ď" },
  e = { "è", "é", "ê", "ë", "ē", "€" }, g = { "ğ" }, i = { "ì", "í", "î", "ï", "ī" }, l = { "ł" },
  n = { "ñ", "ń" }, o = { "ò", "ó", "ô", "ö", "õ", "ø", "œ" }, s = { "ß", "ś", "š" }, t = { "þ" },
  u = { "ù", "ú", "û", "ü", "ū" }, y = { "ý", "ÿ" }, z = { "ž", "ź", "ż" },
}

M.LIST = {
  { id = "en", name = "English", short = "EN", rows = QWERTY, words = "en" },
  { id = "sq", name = "Shqip", short = "SQ", words = "sq",
    rows = { "qwertzuiopç", "asdfghjklë", "yxcvbnm" }, alts = { e = { "ë" }, c = { "ç" } } },
  { id = "de", name = "Deutsch", short = "DE", words = "de",
    rows = { "qwertzuiopü", "asdfghjklöä", "yxcvbnm" },
    alts = { s = { "ß" }, a = { "ä" }, o = { "ö" }, u = { "ü" } } },
  { id = "nl", name = "Nederlands", short = "NL", rows = QWERTY, words = "nl",
    alts = { e = { "é", "ë", "è" }, i = { "ï", "í" }, o = { "ö", "ó" }, u = { "ü", "ú" }, a = { "á", "ä" } } },
  { id = "fr", name = "Français", short = "FR", words = "fr",
    rows = { "azertyuiop", "qsdfghjklm", "wxcvbn" },
    alts = { e = { "é", "è", "ê", "ë" }, a = { "à", "â", "æ" }, c = { "ç" }, u = { "ù", "û", "ü" },
      i = { "î", "ï" }, o = { "ô", "œ" }, y = { "ÿ" } } },
  { id = "es", name = "Español", short = "ES", words = "es",
    rows = { "qwertyuiop", "asdfghjklñ", "zxcvbnm" },
    alts = { a = { "á" }, e = { "é" }, i = { "í" }, o = { "ó" }, u = { "ú", "ü" }, n = { "ñ" } } },
  { id = "it", name = "Italiano", short = "IT", rows = QWERTY, words = "it",
    alts = { a = { "à" }, e = { "è", "é" }, i = { "ì" }, o = { "ò" }, u = { "ù" } } },
  { id = "pt", name = "Português", short = "PT", words = "pt",
    rows = { "qwertyuiop", "asdfghjklç", "zxcvbnm" },
    alts = { a = { "ã", "á", "â", "à" }, e = { "é", "ê" }, i = { "í" }, o = { "õ", "ó", "ô" }, u = { "ú" }, c = { "ç" } } },
  { id = "sv", name = "Svenska", short = "SV", words = "sv",
    rows = { "qwertyuiopå", "asdfghjklöä", "zxcvbnm" }, alts = { a = { "å", "ä" }, o = { "ö" }, e = { "é" } } },
  { id = "fi", name = "Suomi", short = "FI", words = "fi",
    rows = { "qwertyuiopå", "asdfghjklöä", "zxcvbnm" }, alts = { a = { "ä", "å" }, o = { "ö" } } },
  { id = "nb", name = "Norsk", short = "NB", words = "nb",
    rows = { "qwertyuiopå", "asdfghjkløæ", "zxcvbnm" }, alts = { a = { "å", "æ" }, o = { "ø" }, e = { "é" } } },
  { id = "da", name = "Dansk", short = "DA", words = "da",
    rows = { "qwertyuiopå", "asdfghjklæø", "zxcvbnm" }, alts = { a = { "å", "æ" }, o = { "ø" }, e = { "é" } } },
  { id = "pl", name = "Polski", short = "PL", rows = QWERTY, words = "pl",
    alts = { a = { "ą" }, c = { "ć" }, e = { "ę" }, l = { "ł" }, n = { "ń" }, o = { "ó" }, s = { "ś" }, z = { "ż", "ź" } } },
  { id = "cs", name = "Čeština", short = "CS", rows = QWERTZ, words = "cs",
    alts = { a = { "á" }, c = { "č" }, d = { "ď" }, e = { "ě", "é" }, i = { "í" }, n = { "ň" }, o = { "ó" },
      r = { "ř" }, s = { "š" }, t = { "ť" }, u = { "ů", "ú" }, y = { "ý" }, z = { "ž" } } },
  { id = "tr", name = "Türkçe", short = "TR", words = "tr",
    rows = { "qwertyuıopğü", "asdfghjklşi", "zxcvbnmöç" }, upper = { i = "İ", ["ı"] = "I" },
    alts = { ["ı"] = { "i" }, g = { "ğ" }, s = { "ş" }, u = { "ü" }, o = { "ö" }, c = { "ç" } } },
  { id = "ru", name = "Русский", short = "RU", words = "ru", whole = true,
    rows = { "йцукенгшщзх", "фывапролджэ", "ячсмитьбю" }, alts = { ["е"] = { "ё" }, ["ь"] = { "ъ" } } },
  { id = "uk", name = "Українська", short = "UK", whole = true,
    rows = { "йцукенгшщзхї", "фівапролджє", "ячсмитьбю" }, alts = { ["г"] = { "ґ" }, ["і"] = { "ї" } } },
  { id = "el", name = "Ελληνικά", short = "EL", words = "el",
    rows = { "ςερτυθιοπ", "ασδφγηξκλ", "ζχψωβνμ" },
    alts = { ["α"] = { "ά" }, ["ε"] = { "έ" }, ["η"] = { "ή" }, ["ι"] = { "ί", "ϊ", "ΐ" }, ["ο"] = { "ό" },
      ["υ"] = { "ύ", "ϋ", "ΰ" }, ["ω"] = { "ώ" } } },
  { id = "dvorak", name = "Dvorak", short = "DV", words = "en",
    rows = { "pyfgcrl", "aoeuidhtns", "qjkxbmwvz" } },
  { id = "colemak", name = "Colemak", short = "CO", words = "en",
    rows = { "qwfpgjluy", "arstdhneio", "zxcvbkm" } },
}

--- The languages, the person's own from the settings after the shipped ones.
function M.all()
  local out = {}
  for _, layout in ipairs(M.LIST) do out[#out + 1] = layout end
  for _, layout in ipairs(config.get("keyboard.layouts")) do out[#out + 1] = layout end
  return out
end

--- The language called `id`.
function M.get(id)
  for _, layout in ipairs(M.all()) do if layout.id == id then return layout end end
end

--- The language a locale such as "de_AT.UTF-8" names, if there is one.
function M.from_locale(locale)
  local code = (locale or ""):match("^(%a%a%a?)")
  if code == "no" or code == "nn" then code = "nb" end
  return code and M.get(code:lower()) or nil
end

local function same(a, b)
  for i = 1, 3 do if a[i] ~= b[i] then return false end end
  return true
end

--- `text` as `layout` capitalises it.
function M.upper(layout, text)
  local own = layout and layout.upper and layout.upper[text]
  return own or unicase.upper(text)
end

--- What `char` offers on a long press in `layout`.
function M.alternates(layout, char, base)
  local out, seen = {}, {}
  local function take(list)
    for _, value in ipairs(list or {}) do
      if not seen[value] and value ~= char then
        seen[value] = true
        out[#out + 1] = value
      end
    end
  end
  take(layout.alts and layout.alts[char])
  take(base)
  take(M.ACCENTS[char])
  return out
end

local function row_count(rows)
  local n = 0
  for _, row in ipairs(rows) do n = n + utf8.len(row) end
  return n
end

-- The rows cut down to QWERTY's shape; what falls off stays on a long press.
local function cut(rows)
  local out = {}
  for i, row in ipairs(rows) do
    local chars, keep = unicase.chars(row), {}
    for n = 1, math.min(#chars, utf8.len(QWERTY[i])) do keep[n] = chars[n] end
    out[i] = table.concat(keep)
  end
  return out
end

-- One row of `count` keys between two keys `side` units wide, as osk lays a
-- row out: the slots, then the x and width of each side key.
local function lay_row(board, count, side)
  local W, GAP, UNIT = board.width, board.gap, board.unit
  local units = math.max(10, count + 2 * side)
  local u = math.min(UNIT, (W - 2 * GAP - (units - 1) * GAP) / units)
  local full = units * u + (units - 1) * GAP
  local x = math.floor((W - full) / 2)
  local lead = (units - count - 2 * side) / 2 * (u + GAP)
  local slots = {}
  local function take(span)
    local w = math.floor(span * u + (span - 1) * GAP)
    local at = x
    x = x + w + GAP
    return at, w
  end
  x = x + math.floor(lead)
  local first_x, first_w
  if side > 0 then first_x, first_w = take(side) end
  for i = 1, count do
    local at, w = take(1)
    slots[i] = { x = at, w = w }
  end
  local last_x, last_w
  if side > 0 then last_x, last_w = take(side) end
  return slots, first_x, first_w, last_x, last_w
end

--- Fits `layout` onto a board `{ width, gap, unit, key_height }`, with the
--- number row wanted or not; `no_digits` for a mode that has no digit keys.
--- Nil for the board as osk lays it out. Otherwise: `numbers` (the digit row's
--- keys must be built), `lift` (rows of height the board gives back),
--- `borrowed` (the digit keys carry letters) and `keys`, each base key's
--- `{ char, x, row, w, hidden }`.
function M.plan(layout, board, number_row, no_digits)
  if not layout or (same(layout.rows, QWERTY) and not layout.alts) then return nil end
  local rows = layout.rows
  local total = row_count(rows)
  local borrowed = total > 26 and not no_digits and (layout.whole or not number_row)
  if total > 26 and not borrowed then rows = cut(rows) end
  local first = (number_row and not borrowed) and 1 or 0
  local plan = { numbers = number_row or borrowed, borrowed = borrowed, keys = {}, rows = rows,
    lift = borrowed and 1 or 0, bottom = first + 3 }
  local pool = {}
  for _, row in ipairs(QWERTY) do for char in row:gmatch(".") do pool[#pool + 1] = char end end
  if borrowed then for char in DIGITS:gmatch(".") do pool[#pool + 1] = char end end
  local next_key = 1
  for r, row in ipairs(rows) do
    local chars = unicase.chars(row)
    local side = 0
    if r == 3 then side = math.max(1, (10 - #chars) / 2) end
    local slots, sx, sw, bx, bw = lay_row(board, #chars, side)
    for i, char in ipairs(chars) do
      local base = pool[next_key]
      next_key = next_key + 1
      plan.keys[base] = { char = char, x = slots[i].x, w = slots[i].w, row = first + r - 1 }
    end
    if r == 3 then
      plan.keys.shift = { x = sx, w = sw, row = first + 2 }
      plan.keys.backspace = { x = bx, w = bw, row = first + 2 }
    end
  end
  for n = next_key, #pool do plan.keys[pool[n]] = { hidden = true } end
  return plan
end

return M
