-- eva-large: where the words come from, how they fit the screen, the QR, and how
-- it ends. The clipboard and qrencode for real are tools/see/large.steps'.
--
--     morf test --no-dbus tests/large_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local SURFACE = "layer:eva-large"

local function env(extra)
  local full = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1",
    PATH = "/nonexistent" }
  for key, value in pairs(extra or {}) do full[key] = value end
  return full
end

local function tool(args, extra, size)
  test.clear_stubs()
  test.stub_run("wl-paste", { code = 0, stdout = "from the clipboard" })
  test.load("../apps/large/app.lua", { args = args, env = env(extra), size = size or { 1280, 800 } })
  test.settle(1500)
end

local function state() return test.ipc("state") end

test.it("takes the words from the arguments", function()
  tool { "hello", "large", "world" }
  test.eq(state().text, "hello large world")
  test.eq(state().from, "arguments")
  test.eq(#test.runs(), 0, "it read the clipboard anyway")
end)

test.it("takes what the cli read from stdin, and leaves no file", function()
  local file = morf.env("XDG_STATE_HOME") .. "/large-stdin.txt"
  morf.fs.write(file, "piped words\n")
  tool(nil, { EVA_LARGE_FILE = file })
  test.eq(state().text, "piped words")
  test.eq(state().from, "stdin")
  test.falsy(morf.fs.exists(file), "the words stayed on disk")
end)

test.it("falls to the clipboard", function()
  tool()
  test.eq(state().text, "from the clipboard")
  test.eq(state().from, "clipboard")
  test.eq(test.runs()[1], { "wl-paste", "--no-newline", "--type", "text" })
end)

test.it("says so when there is nothing", function()
  test.clear_stubs()
  test.stub_run("wl-paste", { code = 1, stdout = "" })
  test.load("../apps/large/app.lua", { env = env(), size = { 1280, 800 } })
  test.settle(1500)
  test.eq(state().text, "")
  test.eq(test.get("large-text").text, "Nothing to show")
end)

local function fits(card)
  local text, box = test.get("large-text"), test.get(card or "large-card")
  test.truthy(text.y >= box.y, "the words run above the card")
  test.truthy(text.y + text.height <= box.y + box.height + 1, "the words run under the card")
  return text
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("fills the screen with a word in " .. style, function()
    tool({ "Hi" }, { EVA_STYLE = style })
    local text = fits()
    test.truthy(text.height > 300, "only " .. text.height .. " tall")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("gets smaller as the words get longer, and always fits", function()
  local sizes = {}
  for index, words in ipairs { "Hi", "the quick brown fox", ("many words of text "):rep(20) } do
    tool { words }
    fits()
    sizes[index] = test.get("large-text").height
  end
  test.truthy(#sizes == 3)
end)

test.it("holds a long word to the width", function()
  tool { "supercalifragilisticexpialidocious" }
  local text, card = test.get("large-text"), test.get("large-card")
  test.truthy(text.width <= card.width, "the word runs off the card")
end)

test.it("fits a phone upright", function()
  tool({ "A rather longer line of words" }, nil, { 412, 915 })
  fits()
  test.truthy(test.get("large-card").x >= 0)
end)

test.it("writes the QR from stdin, never the command line", function()
  test.clear_stubs()
  test.stub_run("qrencode", { code = 0 })
  test.load("../apps/large/app.lua", { source = [[
    package.loaded["common.sys"] = nil
    local sys = require("common.sys")
    sys.has = function() return true end
  ]] .. morf.fs.read(ROOT .. "apps/large/app.lua"), args = { "s3cret" }, env = env(), size = { 1280, 800 } })
  test.settle(1500)
  local run = test.runs()[1]
  test.eq(run[1], "qrencode")
  test.falsy(table.concat(run, " "):find("s3cret", 1, true), "the words are on a command line")
  test.truthy(state().qr ~= "")
  local card, words = test.get("large-qr-card"), test.get("large-card")
  test.truthy(card.visible)
  test.truthy(card.x >= words.x + words.width, "the QR is not beside the words")
end)

test.it("leaves the QR out when it has none", function()
  tool { "no qrencode here" }
  test.eq(state().qr, "")
  test.falsy(test.get("large-qr-card").visible)
end)

test.it("ends on a press, on Escape, and on a second launch", function()
  tool { "words" }
  test.click(100, 100, { surface = SURFACE })
  test.truthy(state().leaving, "press")
  tool { "words" }
  test.click(100, 100, { surface = SURFACE, button = "right" })
  test.truthy(state().leaving, "right press")
  tool { "words" }
  test.ipc("eva-raise")
  test.truthy(state().leaving, "second launch")
end)
