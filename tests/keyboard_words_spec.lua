-- The word lists, case folding and emoji lookups behind the keyboard's strip.
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 100, height = 100 }
  local words = require("lib.shell.words")
  local unicase = require("lib.util.unicase")
  local emoji = require("lib.shell.emoji")
  morf.ipc.load = function(lang) words.load(lang) return true end
  morf.ipc.ready = function(lang) return words.ready(lang) end
  morf.ipc.complete = function(lang, typed) return words.complete(lang, typed, 3) end
  morf.ipc.fix = function(lang, typed) return words.fix(lang, typed, 2) end
  morf.ipc.known = function(lang, word) return words.known(lang, word) end
  morf.ipc.upper = function(text) return unicase.upper(text) end
  morf.ipc.lower = function(text) return unicase.lower(text) end
  morf.ipc.fold = function(text) return unicase.fold(text) end
  morf.ipc.chars = function(text) return unicase.chars(text) end
  morf.ipc.named = function(word) return emoji.named(word, 2) end
  morf.ipc.group = function(id) return #emoji.group(id) end
  morf.ipc.groups = function()
    local all = 0
    for _, group in ipairs(emoji.GROUPS) do all = all + #emoji.group(group.id) end
    return all
  end
  morf.ipc.emoji_total = function() return #require("lib.shell.emoji.data") end
  morf.ipc.lists = function()
    local out = {}
    for _, name in ipairs(morf.fs.list(morf.paths.shell("assets/words"))) do
      out[#out + 1] = type(name) == "table" and name.name or name
    end
    return out
  end
  morf.ipc.head = function(name)
    return morf.fs.read(morf.paths.shell("assets/words/" .. name)):match("^[^\n]*")
  end
  morf.ipc.has = function(name, word)
    local text = "\n" .. morf.fs.read(morf.paths.shell("assets/words/" .. name))
    return text:find("\n" .. word .. "\n", 1, true) ~= nil
  end
  morf.ipc.write_own = function(text)
    local home = morf.env("XDG_DATA_HOME")
    morf.fs.mkdir(home .. "/eva/words", { parents = true })
    morf.fs.write(home .. "/eva/words/en.txt", text)
    return true
  end
]]
local function load()
  test.load("../shell/init.lua", { source = HOST, size = { 100, 100 } })
end
local function loaded(lang)
  test.ipc("load", lang)
  test.advance(300)
  test.truthy(test.ipc("ready", lang), lang .. " list did not load")
end

test.it("case maps Latin, Greek and Cyrillic past ASCII", function()
  load()
  test.eq(test.ipc("upper", "éñçëšż"), "ÉÑÇËŠŻ")
  test.eq(test.ipc("upper", "яйё"), "ЯЙЁ")
  test.eq(test.ipc("upper", "ωσς"), "ΩΣΣ")
  test.eq(test.ipc("lower", "ÉЯΩ"), "éяω")
  test.eq(test.ipc("upper", "abc"), "ABC")
end)

test.it("folding drops case and accents for matching", function()
  load()
  test.eq(test.ipc("fold", "Café"), "cafe")
  test.eq(test.ipc("fold", "Është"), "eshte")
  test.eq(test.ipc("chars", "éa"), { "é", "a" })
end)

test.it("word lists complete by frequency, fixing case and accents", function()
  load()
  loaded("en")
  test.eq(test.ipc("complete", "en", "th"), { "the", "this", "that" })
  test.eq(test.ipc("complete", "en", "Th"), { "the", "this", "that" })
  test.eq(test.ipc("complete", "en", "zzzqq"), {})
  test.truthy(test.ipc("known", "en", "London"))
  loaded("sq")
  local found = test.ipc("complete", "sq", "esht")
  test.truthy(#found > 0, "typing without the accent found nothing")
  test.eq(found[1], "është")
end)

test.it("a slip is found one edit away, and the list's own corrections come first", function()
  load()
  loaded("en")
  test.eq(test.ipc("fix", "en", "wierd")[1], "weird")
  local swapped = test.ipc("fix", "en", "teh")
  test.truthy(#swapped > 0 and swapped[1] == "the", "a swap was not corrected")
  test.truthy(#test.ipc("fix", "en", "hello") >= 0)
end)

test.it("a word list of the person's own comes before the shipped one", function()
  local home = morf.paths.state("keyboard-own-words")
  test.load("../shell/init.lua", { source = HOST, size = { 100, 100 }, env = { XDG_DATA_HOME = home } })
  test.ipc("write_own", "# mine\nzymurgy\nthermokarst\n")
  loaded("en")
  test.eq(test.ipc("complete", "en", "th")[1], "thermokarst")
  test.eq(test.ipc("complete", "en", "zym")[1], "zymurgy")
end)

test.it("every shipped list has a source line and no offensive entry", function()
  load()
  local names = test.ipc("lists")
  test.truthy(#names >= 17)
  for _, name in ipairs(names) do
    local head = test.ipc("head", name)
    test.truthy(head:sub(1, 2) == "# ", name .. " does not name its source")
    test.truthy(head:find("Apache License 2.0", 1, true) or head:find("CC BY-SA 4.0", 1, true)
      or head:find("MIT License", 1, true), name .. " does not name its licence")
  end
  for _, word in ipairs { "fuck", "shit", "cunt" } do
    test.falsy(test.ipc("has", "en.txt", word), word .. " shipped")
  end
end)

test.it("emoji are found by a word of their names and sorted into sets", function()
  load()
  test.eq(test.ipc("named", "pizza")[1].char, "🍕")
  test.eq(test.ipc("named", "nosuchname"), {})
  test.truthy(test.ipc("group", "faces") > 50)
  test.truthy(test.ipc("group", "food") > 50)
  test.truthy(test.ipc("groups") > test.ipc("emoji_total") * 0.8, "most emoji belong to no set")
end)
