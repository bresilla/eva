-- The on-screen keyboard past its keys: prediction, typing aids, languages,
-- purpose, the clipboard strip, emoji, posture and what it may keep.
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.width, morf.surface.height = W, H
  morf.surface.keyboard_focus = "none"
  package.loaded.bar = { desk = function() return 10, 10, W - 20, H - 20 end }
  package.loaded["lib.services.keyboards"] = { attached = function() return false end }
  if morf.env("TEST_VOICE") == "1" then require("config").set("keyboard.voice", { "hear" }) end
  local events, ime = {}, nil
  morf.input_method = { subscribe = function(fn) ime = fn end,
    commit = function(value) events[#events + 1] = { text = value } end,
    delete = function(before, after) events[#events + 1] = { delete = before, after = after } end }
  morf.virtual_keyboard = { key = function(code, on) events[#events + 1] = { code = code, on = on } end,
    modifiers = function(mask) events[#events + 1] = { mask = mask } end }
  local config = require("config")
  local hyprland = require("lib.compositor.hyprland")
  hyprland.start { signature = "" }
  local keyboard = require("keyboard")
  local model = require("keyboard_model")
  local C = require("theme").color
  ui.Item { width = W, height = H,
    ui.Rect { anchors = { fill = true }, color = function() return C.surface end },
    ui.Item { x = 10, y = 10, width = W - 20, height = H - 20,
      ui.Sdf { anchors = { fill = true }, fill_color = function() return C.surfaceContainer end, keyboard.drawer.shape },
      keyboard.drawer.panel } }
  morf.ipc.show = keyboard.show
  morf.ipc.close = keyboard.close
  morf.ipc.field = function(text, purpose, hint)
    local value = text ~= "" and text or nil
    if text == "<nothing>" then value = nil end
    if text == "<empty>" then value = "" end
    local hints = hint and hint ~= "" and { hint } or nil
    ime(true, value, value and #value or 0, value and #value or 0, 1, purpose ~= "" and purpose or nil, hints)
  end
  morf.ipc.leave = function() ime(false) end
  morf.ipc.app = function(class)
    hyprland.state.active_window.class = class
    hyprland.state.active_window.address = "0x1"
  end
  morf.ipc.set = function(key, value)
    local kinds = { ["true"] = true, ["false"] = false }
    if kinds[value] ~= nil then value = kinds[value] elseif tonumber(value) then value = tonumber(value) end
    config.set("keyboard." .. key, value)
  end
  morf.ipc.replacements = function() config.set("keyboard.replacements", { { "omw", "on my way" } }) end
  morf.ipc.own_layout = function()
    config.set("keyboard.layouts", { { id = "mine", name = "Mine", short = "MI",
      rows = { "жwertyuiop", "asdfghjkl", "zxcvbnm" } } })
  end
  morf.ipc.languages = function(...) config.set("keyboard.languages", { ... }) end
  morf.ipc.control = keyboard.control
  morf.ipc.decline = function() keyboard.keys.shift:set("off") end
  morf.ipc.clear = function() events = {} end
  morf.ipc.pick = function(i) keyboard.pick(model.candidates:get()[tonumber(i)]) end
  morf.ipc.type = function(text)
    for _, cp in utf8.codes(text) do keyboard.strike { text = utf8.char(cp), mods = {} } end
  end
  morf.ipc.state = function()
    return { open = keyboard.drawer.open:get(), mode = keyboard.keys.mode:get(), shift = keyboard.keys.shift:get(),
      page = keyboard.keys.page:get(), numbers = keyboard.keys.numbers:get(), events = events,
      offers = model.candidates:get(), height = keyboard.keys.height(), inset = require("themes.keyboard").inset:get(),
      purpose = model.purpose(), private = model.is_private(), before = model.before(), language = model.layout().id }
  end
  morf.ipc.write_clips = function(json)
    local store = require("lib.shell.clipboard.store")
    morf.fs.mkdir(store.folder(), { parents = true })
    morf.fs.write(store.index(), json)
    require("keyboard_clips").follow(true)
    return true
  end
  morf.ipc.layouts = function()
    local out = {}
    for _, layout in ipairs(require("keyboard_layouts").all()) do out[#out + 1] = layout.id end
    return out
  end
  morf.ipc.layout_rows = function(id) return require("keyboard_layouts").get(id).rows end
  morf.ipc.unreachable = function(id)
    local layouts = require("keyboard_layouts")
    local layout = layouts.get(id)
    local plan = layouts.plan(layout, { width = 400, gap = 4, unit = 34, key_height = 48 }, true)
    local have, missing = {}, {}
    if not plan or plan.borrowed then return {} end
    for _, row in ipairs(plan.rows) do
      for _, char in ipairs(require("lib.util.unicase").chars(row)) do
        have[char] = true
        for _, alt in ipairs(layouts.alternates(layout, char, {})) do have[alt] = true end
      end
    end
    for _, row in ipairs(layout.rows) do
      for _, char in ipairs(require("lib.util.unicase").chars(row)) do
        if not have[char] then missing[#missing + 1] = char end
      end
    end
    return missing
  end
  morf.ipc.learned = function()
    local path = morf.paths.state("eva-keyboard-words.json")
    return morf.fs.exists(path) and morf.fs.read(path) or ""
  end
  morf.ipc.learned_mode = function() return morf.fs.stat(morf.paths.state("eva-keyboard-words.json")).mode end
  morf.ipc.note = function(word) require("keyboard_learn").note(word) end
  morf.ipc.forget = function() require("keyboard_learn").forget() end
  morf.ipc.haptics = function()
    local haptics = require("haptics")
    return { last = haptics.last:get(), count = haptics.count:get() }
  end
]]
local runs = 0
local function load(style, w, h, env)
  runs = runs + 1
  local vars = { EVA_STYLE = style or "material", EVA_DRY_RUN = "0", EVA_FAKE_HAPTICS = "1",
    TEST_WIDTH = tostring(w or 868), TEST_HEIGHT = tostring(h or 1932),
    EVA_SETTINGS = morf.paths.state("keyboard-depth-" .. runs .. ".json"),
    XDG_RUNTIME_DIR = morf.paths.state("keyboard-depth-run"), HYPRLAND_INSTANCE_SIGNATURE = "depth-" .. runs }
  for name, value in pairs(env or {}) do vars[name] = value end
  test.load("../shell/init.lua", { source = HOST, size = { w or 868, h or 1932 }, env = vars })
end
local function state() return test.ipc("state") end
local function up(style, w, h, env)
  load(style, w, h, env)
  test.ipc("field", "<empty>")
  test.advance(1600)
end
local function key(name, mode, page) return "eva.osk.key." .. (mode or "full") .. "." .. (page or "letters") .. "." .. name end
local function centre(id)
  local k = test.get(id)
  return k.x + k.width / 2, k.y + k.height / 2
end
local function words(offers)
  local out = {}
  for i, offer in ipairs(offers) do out[i] = offer.text end
  return out
end
local function commits(events)
  local out = {}
  for _, event in ipairs(events) do if event.text then out[#out + 1] = event.text end end
  return out
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " the strip completes the word at the cursor and a pick replaces it", function()
    up(style)
    test.ipc("field", "Good morning. Th") test.advance(50)
    test.eq(words(state().offers), { "The", "This", "That" })
    test.eq(test.get("eva.keyboard.offer-1").visible, true)
    test.ipc("clear")
    test.click("eva.keyboard.offer-1")
    test.eq(state().events, { { delete = 2, after = 0 }, { text = "The " } })
    test.eq(state().before, "Good morning. The ")
    test.eq(test.logs("error"), {})
  end)

  test.it(style .. " an unknown word offers its correction", function()
    up(style)
    test.ipc("field", "wierd") test.advance(50)
    test.eq(state().offers[1].kind, "fix")
    test.eq(state().offers[1].text, "weird")
  end)

  test.it(style .. " keys remap to a language, in the strike, the face and on a long press", function()
    up(style)
    test.ipc("control", "language", "sq") test.advance(200)
    test.ipc("field", "Mirë") test.advance(50)
    test.ipc("clear") test.click(key("y", "fulln"))
    test.eq(commits(state().events), { "z" }, "qwertz: the y key must type z")
    -- More letters than QWERTY has keys: the digit row's keys carry the rest.
    test.eq(state().numbers, true)
    local typed = {}
    for name in ("qwertyuiopasdfghjklzxcvbnm1234567890"):gmatch(".") do
      if test.find { id = key(name, "fulln"), visible = true } then
        test.ipc("clear") test.click(key(name, "fulln"))
        for _, text in ipairs(commits(state().events)) do typed[text] = true end
      end
    end
    for char in ("qwertzuiopçasdfghjklëyxcvbnm"):gmatch(utf8.charpattern) do
      test.truthy(typed[char], "no key types " .. char)
    end
    test.eq(test.logs("error"), {})
  end)
end

test.it("between words the strip offers what tends to follow, and a pick types it", function()
  up()
  test.ipc("field", "thank ") test.advance(50)
  test.eq(words(state().offers), { "you" })
  test.ipc("clear") test.ipc("pick", 1)
  test.eq(state().events, { { text = "you " } }, "a next word must cut nothing")
  test.ipc("field", "Done. ") test.advance(50)
  test.eq(words(state().offers), { "I", "The", "We" })
  test.ipc("field", "<nothing>") test.advance(50)
  test.ipc("field", "kumquat ") test.advance(50)
  test.eq(state().offers, {})
end)

test.it("a pick after which punctuation falls pulls it over the automatic space", function()
  up()
  test.ipc("field", "See you th") test.advance(50)
  test.ipc("pick", 1)
  test.ipc("clear") test.ipc("type", ",")
  test.eq(state().events, { { delete = 1, after = 0 }, { text = ", " } })
  test.eq(state().before, "See you the, ")
end)

test.it("two spaces after a word make a full stop, and only there", function()
  up()
  test.ipc("field", "Hello") test.advance(50)
  test.ipc("type", " ") test.ipc("clear") test.ipc("type", " ")
  test.eq(state().events, { { delete = 1, after = 0 }, { text = ". " } })
  test.eq(state().before, "Hello. ")
  test.ipc("field", "Hello ") test.ipc("clear")
  test.ipc("type", " ")
  test.eq(state().events, { { text = " " } }, "a space the keyboard did not type just before stays a space")
  test.ipc("set", "double_space", "false")
  test.ipc("field", "Hello") test.ipc("type", " ") test.ipc("clear") test.ipc("type", " ")
  test.eq(state().events, { { text = " " } })
end)

test.it("a sentence starts with shift taken once, and only where the field says so", function()
  up()
  test.eq(state().shift, "once", "an empty field starts a sentence")
  test.ipc("field", "Hello") test.advance(50)
  test.eq(state().shift, "off")
  test.ipc("field", "Hello. ") test.advance(50)
  test.eq(state().shift, "once")
  test.ipc("field", "Hello") test.advance(50)
  test.eq(state().shift, "off", "moving away gives the capital back")
  test.ipc("field", "<nothing>") test.advance(50)
  test.eq(state().shift, "off", "a field that says nothing gets no capital")
  test.ipc("set", "autocaps", "false")
  test.ipc("field", "<empty>") test.advance(50)
  test.eq(state().shift, "off")
end)

test.it("a capital declined stays declined until the cursor moves", function()
  up()
  test.eq(state().shift, "once")
  test.ipc("decline") test.advance(50)
  test.eq(state().shift, "off", "the capital came straight back")
  test.ipc("field", "Hello. ") test.advance(50)
  test.eq(state().shift, "once")
end)

test.it("holding shift locks capitals", function()
  up() test.ipc("field", "Hello") test.advance(50)
  local x, y = centre(key("shift"))
  test.press(x, y) test.advance(450)
  test.eq(state().shift, "lock", "the hold did not lock")
  test.release(x, y) test.advance(20)
  test.eq(state().shift, "lock", "letting go undid the lock")
  test.ipc("clear") test.click(key("q"))
  test.eq(commits(state().events), { "Q" })
  test.eq(state().shift, "lock")
end)

test.it("a held backspace moves on to whole words", function()
  up() test.ipc("field", "one two three") test.advance(50)
  local x, y = centre(key("backspace"))
  test.ipc("clear")
  test.press(x, y) test.advance(420 + 55 * 14)
  local deletes = 0
  for _, event in ipairs(state().events) do if event.delete then deletes = deletes + 1 end end
  test.truthy(deletes >= 1, "no word went")
  test.release(x, y)
  test.eq(test.logs("error"), {})
end)

test.it("a short backspace still takes one character", function()
  up() test.ipc("field", "one") test.advance(50)
  test.ipc("clear") test.click(key("backspace"))
  test.eq(state().events, { { code = 14, on = true }, { code = 14, on = false } })
end)

test.it("a finger along the space bar moves the cursor and types no space", function()
  up() test.ipc("field", "one two") test.advance(50)
  local x, y = centre(key("space"))
  test.ipc("clear")
  test.press(x, y)
  test.move(x + 26, y) test.move(x + 60, y)
  test.advance(20)
  test.truthy(test.ipc("control", "field_probe", "") == nil)
  test.release(x + 60, y)
  local arrows = 0
  for _, event in ipairs(state().events) do
    test.falsy(event.text, "the space bar typed")
    test.falsy(event.code == 57 and event.on, "the space bar typed a key")
    if event.code == 106 and event.on then arrows = arrows + 1 end
  end
  test.truthy(arrows >= 3, "the cursor moved " .. arrows .. " steps")
end)

test.it("by touch, as a phone sends it, the space bar moves the cursor", function()
  up() test.ipc("field", "one two") test.advance(50)
  local x, y = centre(key("space"))
  test.ipc("clear")
  test.touch("down", 1, x, y) test.advance(20)
  test.touch("move", 1, x + 26, y) test.advance(20)
  test.touch("move", 1, x + 60, y) test.advance(20)
  test.touch("up", 1, x + 60, y) test.advance(20)
  local arrows = 0
  for _, event in ipairs(state().events) do
    test.falsy(event.text, "the space bar typed")
    if event.code == 106 and event.on then arrows = arrows + 1 end
  end
  test.truthy(arrows >= 3, "by touch the cursor moved " .. arrows .. " steps")
end)

test.it("by touch, a long press offers and a slide picks", function()
  up() test.ipc("field", "Hello") test.advance(50)
  local x, y = centre(key("e"))
  test.touch("down", 1, x, y) test.advance(450)
  local strip = test.get("eva.osk.alternates")
  test.truthy(strip.visible, "no alternates by touch")
  local at = strip.x + 4 + (strip.width - 8) / 7 * 2.5
  test.touch("move", 1, at, strip.y + strip.height / 2) test.advance(20)
  test.ipc("clear")
  test.touch("up", 1, at, strip.y + strip.height / 2) test.advance(20)
  test.eq(commits(state().events), { "é" })
end)

test.it("by touch, holding shift locks capitals and holding backspace takes words", function()
  up() test.ipc("field", "one two three") test.advance(50)
  local x, y = centre(key("shift"))
  test.touch("down", 1, x, y) test.advance(450)
  test.touch("up", 1, x, y) test.advance(20)
  test.eq(state().shift, "lock", "a touch hold did not lock")
  x, y = centre(key("backspace"))
  test.ipc("clear")
  test.touch("down", 1, x, y) test.advance(420 + 55 * 14)
  test.touch("up", 1, x, y) test.advance(20)
  local deletes = 0
  for _, event in ipairs(state().events) do if event.delete then deletes = deletes + 1 end end
  test.truthy(deletes >= 1, "a touch hold took no word")
end)

test.it("by touch, the handle pulls the keyboard shut and carries it floating", function()
  up()
  test.ipc("control", "floating", "on") test.advance(800)
  local panel = test.get("drawer-keyboard")
  local handle = test.get("eva.keyboard.handle")
  local x, y = handle.x + handle.width / 2, handle.y + handle.height / 2
  test.touch("down", 1, x, y) test.advance(20)
  test.touch("move", 1, x, y - 200) test.advance(20)
  test.touch("up", 1, x, y - 200) test.advance(100)
  test.truthy(test.get("drawer-keyboard").y < panel.y - 100, "a finger did not carry it")
  test.ipc("control", "floating", "off") test.advance(800)
  handle = test.get("eva.keyboard.handle")
  x, y = handle.x + handle.width / 2, handle.y + handle.height / 2
  test.touch("down", 1, x, y) test.advance(20)
  test.touch("move", 1, x, y + 150) test.advance(20)
  test.touch("move", 1, x, y + 300) test.advance(20)
  test.touch("up", 1, x, y + 300) test.advance(900)
  test.falsy(state().open, "a finger down did not shut it")
end)

test.it("by touch, a chip and an emoji answer a tap", function()
  up() test.ipc("field", "th") test.advance(50)
  local chip = test.get("eva.keyboard.offer-1")
  test.ipc("clear")
  test.touch("down", 1, chip.x + 10, chip.y + 10) test.touch("up", 1, chip.x + 10, chip.y + 10) test.advance(50)
  test.eq(commits(state().events), { "the " })
  test.ipc("control", "pane", "emoji") test.advance(300)
  local grid = test.get("eva.keyboard.emoji-cells")
  test.ipc("clear")
  test.touch("down", 1, grid.x + 10, grid.y + 10) test.touch("up", 1, grid.x + 10, grid.y + 10) test.advance(50)
  test.eq(#commits(state().events), 1, "a tap on the grid typed nothing")
end)

test.it("with the number row on, each language keeps every letter within reach", function()
  up()
  test.ipc("set", "number_row", "true") test.advance(100)
  for _, id in ipairs(test.ipc("layouts")) do
    local missing = test.ipc("unreachable", id)
    test.eq(missing, {}, id .. " loses letters with the number row on")
  end
end)

test.it("a tap on the space bar is still a space", function()
  up() test.ipc("field", "one") test.advance(50)
  test.ipc("clear") test.click(key("space"))
  test.eq(state().events, { { text = " " } })
end)

test.it("the number row setting builds the row and pays for it in height", function()
  up()
  local short = state().height
  test.ipc("set", "number_row", "true") test.advance(100)
  test.eq(state().numbers, true)
  test.truthy(state().height > short)
  test.truthy(test.find { id = key("1", "fulln"), visible = true } ~= nil, "no number row")
  test.ipc("clear") test.click(key("1", "fulln"))
  test.eq(commits(state().events), { "1" })
end)

test.it("the height setting scales the keys, and a gap lifts them", function()
  up()
  local normal = test.get(key("q")).height
  local panel = test.get("drawer-keyboard").height
  test.ipc("set", "height", "1.2") test.advance(100)
  test.truthy(test.get(key("q")).height > normal, "keys did not grow")
  test.ipc("set", "height", "1.0") test.ipc("set", "bottom_gap", "32") test.advance(400)
  test.near(test.get("drawer-keyboard").height, panel + 32, 1)
end)

test.it("every language places each letter once, inside the board, overlapping nothing", function()
  for _, size in ipairs { { 360, 800 }, { 868, 1932 } } do
    load("material", size[1], size[2])
    test.ipc("field", "<empty>") test.advance(1200)
    for _, id in ipairs(test.ipc("layouts")) do
      test.ipc("control", "language", id) test.advance(100)
      local mode = state().numbers and "fulln" or "full"
      local letters, board = {}, test.get("drawer-keyboard")
      for row in table.concat(test.ipc("layout_rows", id), ""):gmatch(utf8.charpattern) do letters[#letters + 1] = row end
      local rects = {}
      local names = { "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "a", "s", "d", "f", "g", "h", "j", "k", "l",
        "z", "x", "c", "v", "b", "n", "m", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }
      for _, name in ipairs(names) do
        local node = test.find { id = key(name, mode), visible = true }
        if node then rects[#rects + 1] = { name = name, x = node.x, y = node.y, w = node.width, h = node.height } end
      end
      test.eq(#rects, math.min(#letters, #rects), id .. " shows more letter keys than it has letters")
      test.truthy(#rects >= 25, id .. " shows only " .. #rects .. " keys")
      for i, a in ipairs(rects) do
        test.truthy(a.x >= board.x - 1 and a.x + a.w <= board.x + board.width + 1, id .. " key " .. a.name .. " leaves the board")
        for j = i + 1, #rects do
          local b = rects[j]
          local apart = a.x + a.w <= b.x + 1 or b.x + b.w <= a.x + 1 or a.y + a.h <= b.y + 1 or b.y + b.h <= a.y + 1
          test.truthy(apart, id .. " keys " .. a.name .. " and " .. b.name .. " overlap")
        end
      end
    end
    test.eq(test.logs("error"), {})
  end
end)

test.it("a language's letters are typed, capitalised and offered on a long press", function()
  up()
  test.ipc("control", "language", "ru") test.advance(200)
  test.ipc("field", "Привет") test.advance(50)
  test.ipc("clear") test.click(key("q", "fulln"))
  test.eq(commits(state().events), { "й" })
  test.click(key("shift", "fulln")) test.ipc("clear")
  test.click(key("q", "fulln"))
  test.eq(commits(state().events), { "Й" })
  -- `е` sits on QWERTY's `t`; a long press offers `ё` first.
  local x, y = centre(key("t", "fulln"))
  test.press(x, y) test.advance(450)
  test.truthy(test.get("eva.osk.alternates").visible)
  test.ipc("clear") test.release(x, y)
  test.eq(commits(state().events), { "ё" })
end)

test.it("a language's press shows its own letter over the key", function()
  up()
  test.ipc("control", "language", "ru") test.advance(200)
  local x, y = centre(key("q", "fulln"))
  test.press(x, y) test.advance(30)
  local bubble = test.get("eva.osk.preview-bubble")
  test.truthy(bubble.visible)
  test.release(x, y)
end)

test.it("a capital accent is offered in capitals, past what Lua can upper-case", function()
  up() test.ipc("field", "Hello") test.advance(50)
  test.click(key("shift"))
  local x, y = centre(key("e"))
  test.press(x, y) test.advance(450)
  local strip = test.get("eva.osk.alternates")
  local at = strip.x + 4 + (strip.width - 8) / 7 * 2.5
  test.move(at, strip.y + strip.height / 2)
  test.ipc("clear") test.release(at, strip.y + strip.height / 2)
  test.eq(commits(state().events), { "É" })
end)

test.it("switching language moves through the list and keeps the board usable", function()
  up()
  test.ipc("languages", "en", "sq", "de") test.advance(50)
  test.eq(state().language, "en")
  test.ipc("control", "language", "next") test.advance(100)
  test.eq(state().language, "sq")
  test.ipc("control", "language", "next") test.ipc("control", "language", "next") test.advance(100)
  test.eq(state().language, "en")
  test.ipc("field", "Hello") test.advance(50)
  test.ipc("clear") test.click(key("q"))
  test.eq(commits(state().events), { "q" })
end)

test.it("the locale picks the language when none is set", function()
  load("material", nil, nil, { LANG = "de_AT.UTF-8", LC_ALL = "", LC_MESSAGES = "" })
  test.ipc("field", "<empty>") test.advance(200)
  test.eq(state().language, "de")
end)

test.it("a window's class picks the board, and a tool can say so itself", function()
  up()
  test.ipc("app", "kitty") test.ipc("leave") test.advance(700)
  test.ipc("field", "<empty>") test.advance(900)
  test.eq(state().purpose, "dev")
  test.eq(state().mode, "dev")
  test.ipc("app", "eva.phone") test.advance(100)
  test.ipc("field", "<empty>") test.advance(100)
  test.eq(state().purpose, "phone")
  test.eq(state().mode, "phone")
  test.ipc("app", "firefox") test.advance(100)
  test.ipc("field", "<empty>") test.advance(100)
  test.eq(state().mode, "full")
  test.ipc("control", "purpose", "number")
  test.ipc("field", "<empty>") test.advance(100)
  test.eq(state().mode, "numbers")
  test.ipc("control", "purpose", "")
  test.ipc("field", "<empty>") test.advance(100)
  test.eq(state().mode, "full")
end)

test.it("a purpose the input method reports wins, ready for an engine that sends it", function()
  up()
  test.ipc("field", "<empty>", "phone") test.advance(100)
  test.eq(state().mode, "phone")
  test.ipc("field", "<empty>", "pin") test.advance(100)
  test.eq(state().mode, "numbers")
  test.truthy(state().private)
  test.ipc("field", "<empty>", "terminal") test.advance(100)
  test.eq(state().mode, "dev")
  test.ipc("field", "<empty>", "email") test.advance(100)
  test.eq(state().mode, "full")
  test.ipc("clear") test.click(key(","))
  test.eq(commits(state().events), { "@" })
  test.ipc("field", "<empty>", "url") test.advance(100)
  test.ipc("clear") test.click(key(","))
  test.eq(commits(state().events), { "/" })
  test.ipc("field", "<empty>", "password") test.advance(100)
  test.truthy(state().private)
end)

test.it("a board picked by hand survives a field's asking", function()
  up()
  test.ipc("show", "numbers") test.advance(100)
  test.ipc("field", "<empty>") test.advance(100)
  test.eq(state().mode, "numbers")
end)

test.it("a password's field gets no help, by what it says or what it shows", function()
  up()
  test.ipc("field", "th", "password") test.advance(50)
  test.eq(state().offers, {})
  test.ipc("field", "th", "", "hidden_text") test.advance(50)
  test.eq(state().offers, {})
  test.ipc("field", "••••") test.advance(50)
  test.truthy(state().private, "a mask did not read as private")
  test.eq(state().offers, {})
  test.ipc("field", "Hello") test.ipc("type", " ") test.ipc("field", "••••") test.ipc("clear") test.ipc("type", " ")
  test.eq(commits(state().events), { " " }, "double space touched a password")
  test.ipc("field", "••••") test.advance(50)
  test.eq(state().shift, "off")
end)

test.it("private typing turns the strip's words off by hand", function()
  up()
  test.ipc("field", "th") test.advance(50)
  test.truthy(#state().offers > 0)
  test.ipc("control", "private", "on") test.advance(50)
  test.eq(state().offers, {})
  test.ipc("control", "private", "off") test.advance(50)
  test.truthy(#state().offers > 0)
end)

test.it("nothing typed reaches the disk by default", function()
  up()
  test.ipc("field", "Zorblat") test.ipc("type", " ") test.advance(3000)
  test.eq(test.ipc("learned"), "")
end)

test.it("learning, once on, keeps words at the owner's eyes only and spares a private field", function()
  up()
  test.ipc("set", "learn", "true")
  test.ipc("field", "Zorblat") test.advance(20)
  test.ipc("type", " ") test.advance(50)
  test.ipc("field", "Zorb") test.advance(50)
  test.eq(words(state().offers)[1], "Zorblat")
  test.advance(3000)
  test.truthy(test.ipc("learned"):find("Zorblat", 1, true))
  test.eq(test.ipc("learned_mode") & 63, 0, "the learned words are readable by others")
  test.ipc("field", "Sekret", "password") test.ipc("type", " ")
  test.ipc("note", "Sekrettwo") test.advance(3000)
  test.falsy(test.ipc("learned"):find("Sekret", 1, true), "a password was learned")
  test.ipc("field", "Masked") test.advance(500)
  test.ipc("control", "private", "on")
  test.ipc("note", "Sekretthree") test.advance(3000)
  test.falsy(test.ipc("learned"):find("Sekretthree", 1, true), "private typing was learned")
end)

test.it("forgetting takes the learned words off the disk", function()
  up()
  test.ipc("set", "learn", "true")
  test.ipc("note", "Zorblat") test.advance(3000)
  test.truthy(test.ipc("learned"):find("Zorblat", 1, true))
  test.ipc("forget") test.advance(100)
  test.eq(test.ipc("learned"), "")
end)

test.it("autocorrect waits to be asked, and a backspace takes it back", function()
  up()
  test.ipc("field", "wierd") test.advance(50)
  test.ipc("clear") test.ipc("type", " ")
  test.eq(state().events, { { text = " " } }, "corrected without being asked")
  test.ipc("set", "autocorrect", "true")
  test.ipc("field", "wierd") test.advance(50)
  test.ipc("clear") test.ipc("type", " ")
  test.eq(state().events, { { delete = 5, after = 0 }, { text = "weird" }, { text = " " } })
  test.eq(state().before, "weird ")
  test.ipc("clear") test.click(key("backspace"))
  test.eq(state().before, "wierd ", "a backspace did not take the correction back")
end)

test.it("a shortcut expands on space and offers itself, and a keyword offers the date", function()
  up()
  test.ipc("replacements")
  test.ipc("field", "omw") test.advance(50)
  test.eq(state().offers[1].kind, "shortcut")
  test.eq(state().offers[1].text, "on my way")
  test.ipc("clear") test.ipc("type", " ")
  test.eq(state().events, { { delete = 3, after = 0 }, { text = "on my way" }, { text = " " } })
  test.advance(500)
  test.ipc("field", "today") test.advance(50)
  test.eq(state().offers[1].kind, "keyword")
  test.truthy(state().offers[1].text:match("^%d%d%d%d%-%d%d%-%d%d$"))
end)

test.it("an emoji's name offers it, and picking one puts it in the word's place", function()
  up()
  test.ipc("field", "I love pizza") test.advance(50)
  local offers = state().offers
  test.eq(offers[#offers].kind, "emoji")
  test.eq(offers[#offers].text, "🍕")
  test.ipc("clear") test.ipc("pick", #offers)
  test.eq(state().events, { { delete = 5, after = 0 }, { text = "🍕" } })
end)

test.it("the clipboard strip reads eva-clipboard's store and pastes", function()
  up()
  test.ipc("write_clips", morf.json.encode {
    { id = "1", kind = "text", text = "first copied" },
    { id = "2", kind = "image", path = "/nowhere.png", mime = "image/png" },
    { id = "3", kind = "text", text = "second copied" } })
  test.ipc("control", "tray", "clips") test.advance(100)
  test.eq(test.get("eva.keyboard.clipboard").visible, true)
  test.ipc("clear")
  test.click("eva.keyboard.clip-2")
  test.eq(commits(state().events), { "second copied" })
  test.eq(test.logs("error"), {})
end)

test.it("a copy just made offers itself where no word is offered", function()
  up()
  test.ipc("field", "") test.advance(50)
  test.ipc("write_clips", morf.json.encode {
    { id = "1", kind = "text", text = "just now", time = morf.time.now_ms() } })
  test.advance(50)
  test.eq(test.get("eva.keyboard.fresh").visible, true)
end)

test.it("the strip is off when the setting says so", function()
  up()
  test.ipc("set", "clipboard", "false")
  test.ipc("write_clips", morf.json.encode { { id = "1", kind = "text", text = "held" } })
  test.ipc("control", "tray", "clips") test.advance(100)
  test.falsy(test.find { id = "eva.keyboard.clip-1", visible = true })
end)

test.it("the emoji pane takes the keys' place and types", function()
  up()
  test.ipc("control", "pane", "emoji") test.advance(300)
  test.eq(test.get("eva.keyboard.emoji-foot").visible, true)
  test.falsy(test.get("eva.keyboard.boards").visible)
  local grid = test.get("eva.keyboard.emoji-cells")
  test.ipc("clear") test.click(grid.x + 10, grid.y + 10)
  test.eq(#commits(state().events), 1, "the grid typed nothing")
  test.click("eva.keyboard.emoji-tab-recent") test.advance(100)
  test.click("eva.keyboard.emoji-letters") test.advance(100)
  test.truthy(test.get("eva.keyboard.boards").visible)
end)

test.it("the emoji search takes the keys for itself", function()
  up()
  test.ipc("control", "pane", "emoji") test.advance(300)
  test.click("eva.keyboard.emoji-search") test.advance(200)
  test.truthy(test.get("eva.keyboard.boards").visible)
  test.ipc("clear")
  test.ipc("type", "pizza")
  test.eq(state().events, {}, "search typed into the field")
  test.advance(50)
  test.eq(test.get("eva.keyboard.search-query").text, "pizza")
  test.click("eva.keyboard.found-1")
  test.eq(commits(state().events), { "🍕" })
end)

test.it("one hand squeezes the keys to a side at their full height, and back", function()
  up()
  local full = test.get(key("q"))
  local whole = test.get("drawer-keyboard")
  test.ipc("control", "hand", "right") test.advance(800)
  local right = test.get(key("q"))
  test.near(right.height, full.height, 1)
  test.truthy(right.width < full.width, "keys did not narrow")
  test.truthy(right.x > full.x + 40, "keys did not move to the right")
  test.eq(test.get("drawer-keyboard").width, whole.width)
  test.truthy(test.get("eva.keyboard.side").visible)
  test.click("eva.keyboard.tool-side-swap") test.advance(800)
  test.truthy(test.get(key("q")).x < right.x, "the other hand did not move it")
  test.click("eva.keyboard.tool-side-full") test.advance(800)
  test.near(test.get(key("q")).width, full.width, 1)
  test.eq(test.logs("error"), {})
end)

test.it("floating gives the screen back, moves by its handle and leaves the edge", function()
  up()
  test.truthy(state().inset > 0)
  test.ipc("control", "floating", "on") test.advance(800)
  test.eq(state().inset, 0, "a floating keyboard still reserves the edge")
  local panel = test.get("drawer-keyboard")
  test.truthy(panel.y + panel.height < 1932 - 100, "still on the edge")
  local handle = test.get("eva.keyboard.handle")
  local x, y = handle.x + handle.width / 2, handle.y + handle.height / 2
  test.press(x, y) test.move(x, y - 200) test.move(x + 30, y - 400) test.release(x + 30, y - 400)
  test.advance(100)
  test.truthy(test.get("drawer-keyboard").y < panel.y - 200, "the handle did not carry it")
  test.ipc("clear") test.click(key("q"))
  test.eq(commits(state().events), { "Q" }, "keys stopped hitting where they are drawn")
  test.ipc("control", "floating", "off") test.advance(800)
  test.truthy(state().inset > 0)
  test.eq(test.logs("error"), {})
end)

test.it("split stands the halves apart on a wide screen, and offers across the gap", function()
  up("material", 1280, 800)
  local before = test.get(key("q"))
  test.ipc("control", "split", "on") test.advance(300)
  local q, p = test.get(key("q")), test.get(key("p"))
  local t, y = test.get(key("t")), test.get(key("y"))
  test.truthy(q.width < before.width, "keys did not narrow")
  test.truthy(y.x - (t.x + t.width) > 200, "the halves stand together")
  test.truthy(p.x + p.width > 1000, "the right half does not reach across")
  test.ipc("clear") test.click(key("p"))
  test.eq(#commits(state().events) + #state().events > 0, true)
  local x, h = centre(key("y"))
  test.press(x, h) test.advance(450)
  local strip = test.get("eva.osk.alternates")
  test.truthy(strip.x > 600, "alternates stayed on the left half")
  test.release(x, h)
end)

test.it("a key buzzes, a long press buzzes, and the setting stills it", function()
  up()
  local before = test.ipc("haptics").count
  test.click(key("q"))
  test.eq(test.ipc("haptics").last, "key")
  test.truthy(test.ipc("haptics").count > before)
  test.advance(100)
  local x, y = centre(key("e"))
  test.press(x, y) test.advance(450)
  test.eq(test.ipc("haptics").last, "long")
  test.release(x, y) test.advance(100)
  test.ipc("set", "haptics", "false")
  local stilled = test.ipc("haptics").count
  test.click(key("w"))
  test.eq(test.ipc("haptics").count, stilled)
end)

test.it("a finger down the handle shuts it, and it stays shut for that application", function()
  up()
  test.ipc("app", "firefox") test.advance(50)
  test.truthy(state().open)
  local handle = test.get("eva.keyboard.handle")
  local x, y = handle.x + handle.width / 2, handle.y + handle.height / 2
  test.press(x, y) test.move(x, y + 100) test.move(x, y + 300) test.release(x, y + 300)
  test.advance(900)
  test.falsy(state().open, "a pull down did not shut it")
  test.ipc("field", "<empty>") test.advance(300)
  test.falsy(state().open, "a pulled keyboard came straight back")
end)

test.it("the tools button and the strip reach every tray", function()
  up()
  test.ipc("field", "th") test.advance(50)
  test.click("eva.keyboard.more") test.advance(50)
  test.eq(test.get("eva.keyboard.tools").visible, true)
  test.click(key("q")) test.advance(50)
  test.eq(test.get("eva.keyboard.words").visible, true, "a key did not bring the offers back")
  test.click("eva.keyboard.more") test.advance(50)
  test.click("eva.keyboard.tool-edit") test.advance(50)
  test.eq(test.get("eva.keyboard.edit").visible, true)
  test.ipc("clear") test.click("eva.keyboard.tool-edit-left")
  test.eq(state().events, { { code = 105, on = true }, { code = 105, on = false } })
  test.click("eva.keyboard.tool-edit-back") test.advance(50)
  test.falsy(test.get("eva.keyboard.edit").visible)
end)

test.it("a pad spreads across a narrow board and types from where it is drawn", function()
  load("material", 412, 915)
  test.ipc("field", "<empty>", "phone") test.advance(1600)
  test.eq(state().mode, "phone")
  local one, three = test.get(key("1", "phone")), test.get(key("3", "phone"))
  local panel = test.get("drawer-keyboard")
  test.truthy(one.width > 100, "dial keys are " .. one.width .. " wide")
  test.truthy(one.x + one.width < three.x, "dial keys overlap")
  test.truthy(three.x + three.width <= panel.x + panel.width, "the pad leaves the board")
  test.truthy(three.x + three.width > panel.x + panel.width - 40, "the pad stops short of the edge")
  test.ipc("clear") test.click(key("3", "phone"))
  test.eq(state().events, { { text = "3" } })
  test.ipc("field", "<empty>", "number") test.advance(300)
  test.eq(state().mode, "numbers")
  test.truthy(test.get(key("1", "numbers")).width > 70)
end)

test.it("a pad stays a column on a wide screen", function()
  up("material", 1280, 800)
  test.ipc("field", "<empty>", "phone") test.advance(300)
  test.truthy(test.get(key("1", "phone")).width < 120)
end)

test.it("the emoji pane has the tools over it, not words", function()
  up()
  test.ipc("field", "th") test.advance(50)
  test.truthy(#state().offers > 0)
  test.ipc("control", "pane", "emoji") test.advance(300)
  test.eq(test.get("eva.keyboard.tools").visible, true, "word offers stayed over the emoji")
  test.ipc("control", "pane", "keys") test.advance(100)
  test.eq(test.get("eva.keyboard.words").visible, true)
end)

test.it("a board is picked by hand from the strip", function()
  up()
  test.ipc("control", "tray", "boards") test.advance(50)
  test.click("eva.keyboard.tool-board-dev") test.advance(100)
  test.eq(state().mode, "dev")
  test.ipc("field", "<empty>") test.advance(100)
  test.eq(state().mode, "dev", "the field took the picked board back")
end)

test.it("a language of the person's own works like a shipped one", function()
  up()
  test.ipc("own_layout") test.advance(50)
  test.ipc("control", "language", "mine") test.advance(200)
  test.eq(state().language, "mine")
  test.ipc("field", "Hello") test.advance(50)
  test.ipc("clear") test.click(key("q"))
  test.eq(commits(state().events), { "ж" })
end)

test.it("a voice command of the person's own types what it hears, and none shows no microphone", function()
  up()
  test.falsy(test.find { id = "eva.keyboard.tool-voice" })
  test.stub_run("hear", { code = 0, stdout = "spoken words\n" })
  load("material", nil, nil, { TEST_VOICE = "1" })
  test.ipc("field", "<empty>") test.advance(1600)
  test.ipc("control", "tray", "tools") test.advance(50)
  test.truthy(test.find { id = "eva.keyboard.tool-voice", visible = true }, "no microphone")
  test.ipc("clear") test.click("eva.keyboard.tool-voice") test.advance(100)
  test.eq(commits(state().events), { "spoken words" })
end)

test.it("a key's height on a phone is at least a finger's target", function()
  load("material", 412, 915)
  test.ipc("field", "<empty>") test.advance(1600)
  test.truthy(test.get(key("q")).height >= 48, "keys are " .. test.get(key("q")).height .. " tall")
end)

test.it("the keyboard fits a compact landscape phone", function()
  load("material", 800, 360)
  test.ipc("field", "<empty>") test.advance(1600)
  local panel = test.get("drawer-keyboard")
  test.truthy(panel.y >= 0, "taller than the screen")
  test.truthy(panel.height < 360 * .72, "it took " .. panel.height .. " of 360")
end)
