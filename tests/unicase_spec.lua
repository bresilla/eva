-- Capitals past ASCII: one uppercase for everything the shell shows, covering
-- Latin-1, the Latin Extended blocks, Greek and Cyrillic, and Tsugumori's
-- captions going through it.
--
--     morf test --no-dbus tests/unicase_spec.lua
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local unicase = require("lib.util.unicase")
  morf.ipc.upper = function(text) return unicase.upper(text) end
  morf.ipc.lower = function(text) return unicase.lower(text) end
  morf.ipc.first = function(text, count) return unicase.first(text, tonumber(count)) end
  morf.ipc.capitalise = function(text) return unicase.capitalise(text) end
  morf.ipc.initial = function(text) return unicase.initial(text) end
  morf.ipc.broken = function() return unicase.upper("ab\255c") == "AB\255C" end
]]

local function load()
  test.load("../shell/init.lua", { size = { 100, 100 }, source = HOST, env = { EVA_DRY_RUN = "1" } })
  test.advance(50)
end

local CASES = {
  { "Albanian", "një çelës për këtë", "NJË ÇELËS PËR KËTË" },
  { "Latin-1", "àáâãäåæçèéêëìíîïðñòóôõöøùúûüýþÿ", "ÀÁÂÃÄÅÆÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝÞŸ" },
  { "Latin-1's micro sign", "µ", "Μ" },
  { "Latin Extended-A", "āćčďęğħıĳķłńőœřśšşťůűźżž", "ĀĆČĎĘĞĦIĲĶŁŃŐŒŘŚŠŞŤŮŰŹŻŽ" },
  { "the long s", "ſ", "S" },
  { "Latin Extended-B", "ƀƃƌơưəɛǎǐǒǔǧǵșțȟ", "ɃƂƋƠƯƏƐǍǏǑǓǦǴȘȚȞ" },
  { "digraphs", "ǆǉǌǳ", "ǄǇǊǱ" },
  { "the title-case digraphs", "ǅǈǋǲ", "ǄǇǊǱ" },
  { "Latin Extended Additional", "ạảấầẩẫậếệộựỳỹḃḋṡẅ", "ẠẢẤẦẨẪẬẾỆỘỰỲỸḂḊṠẄ" },
  { "Greek", "αβγδεζηθικλμνξοπρστυφχψω", "ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩ" },
  { "Greek accents and final sigma", "άέήίόύώϊϋς", "ΆΈΉΊΌΎΏΪΫΣ" },
  { "Cyrillic", "абвгдежзийклмнопрстуфхцчшщъыьэюя", "АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ" },
  { "Cyrillic past Russian", "ёђѓєѕіїјљњћќўџґғҗқңүұҳӏӑӗәөԑ", "ЁЂЃЄЅІЇЈЉЊЋЌЎЏҐҒҖҚҢҮҰҲӀӐӖӘӨԐ" },
  { "the name that showed the bug", "Rosé Pine", "ROSÉ PINE" },
  { "ASCII", "plain 123 !?", "PLAIN 123 !?" },
}

for _, case in ipairs(CASES) do
  test.it("upper: " .. case[1], function()
    load()
    test.eq(test.ipc("upper", case[2]), case[3])
  end)
end

test.it("a capital has its small letter back", function()
  load()
  test.eq(test.ipc("lower", "ËÇÉŸ ΣΑΣ ЖЯ ƏȘ ẠỰ"), "ëçéÿ σασ жя əș ạự")
  test.eq(test.ipc("lower", "İI"), "ii")
  test.eq(test.ipc("lower", "ẞ"), "ß")
end)

test.it("one letter stays one letter", function()
  load()
  test.eq(test.ipc("upper", "straße"), "STRAßE")
  test.eq(test.ipc("upper", "ŉ"), "ŉ")
  test.eq(test.ipc("upper", "€ 中 😀"), "€ 中 😀")
end)

test.it("bytes that are not UTF-8 pass as ASCII does", function()
  load()
  test.truthy(test.ipc("broken"))
end)

test.it("the first character is a whole one", function()
  load()
  test.eq(test.ipc("first", "Ëllo"), "Ë")
  test.eq(test.ipc("first", "çë", 2), "çë")
  test.eq(test.ipc("first", "", 2), "")
  test.eq(test.ipc("first", "ab", 5), "ab")
end)

test.it("capitalise lifts the first letter and leaves the rest", function()
  load()
  test.eq(test.ipc("capitalise", "ëmail iPhone"), "Ëmail iPhone")
  test.eq(test.ipc("capitalise", "balanced"), "Balanced")
  test.eq(test.ipc("capitalise", ""), "")
end)

test.it("an initial skips to the first letter or digit, and takes it whole", function()
  load()
  test.eq(test.ipc("initial", "Éric"), "É")
  test.eq(test.ipc("initial", "ëndërr"), "Ë")
  test.eq(test.ipc("initial", "(work) mail"), "W")
  test.eq(test.ipc("initial", "9lives"), "9")
  test.eq(test.ipc("initial", "!!"), "?")
  test.eq(test.ipc("initial", ""), "?")
end)

test.it("nothing a theme shows uppercases by bytes", function()
  for _, pattern in ipairs { "themes/tsugumori/**/*.lua", "themes/material/**/*.lua", "themes/layouts/**/*.lua", "themes/*.lua" } do
    for _, name in ipairs(morf.fs.glob(pattern)) do
      local source = morf.fs.read(name)
      test.falsy(source:find(":upper()", 1, true), name .. " uppercases by bytes")
      test.falsy(source:find("string.upper", 1, true), name .. " uppercases by bytes")
    end
  end
end)
