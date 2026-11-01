-- Words that turn into the next ones: the text itself is always the truth, the
-- outline melts in from the old words, and at rest no morph is left behind.
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  local nodes = {}
  local make = ui.Text
  ui.Text = function(props)
    local node = make(props)
    if props.id then nodes[props.id] = node end
    return node
  end
  local kit = require("kit")
  local words = morf.signal("morph.words", "12:04")
  morf.surface.width, morf.surface.height = 400, 120
  ui.Item { width = 400, height = 120,
    kit.text { id = "words", x = 10, y = 10, morph = true, text = function() return words:get() end },
    kit.text { id = "plain", x = 10, y = 50, text = function() return words:get() end },
  }
  morf.ipc.say = function(value) words:set(value) end
  morf.ipc.morph = function(id)
    local node = nodes[id]
    return { to = node.morph_to, progress = node.morph_progress, text = node.text }
  end
]]

local function load(style)
  test.load("../shell/init.lua", { source = HOST, size = { 400, 120 }, env = {
    EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_WALLPAPER = "",
    EVA_APPEARANCE = morf.env("XDG_CACHE_HOME") .. "/morph-appearance.json",
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/morph-settings.json",
  } })
  test.advance(100)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " text morph", function()
    test.it("leaves nothing behind at rest", function()
      load(style)
      local rest = test.ipc("morph", "words")
      test.eq(rest.to, "")
      test.near(rest.progress, 0, 0.0001)
      test.eq(rest.text, "12:04")
    end)

    test.it("stands at the new words at once and melts in from the old", function()
      load(style)
      test.ipc("say", "12:05")
      local started = test.ipc("morph", "words")
      test.eq(started.text, "12:05", "the text must be the truth as soon as it changes")
      test.eq(started.to, "12:04", "the old words are not what it melts from")
      test.near(started.progress, 1, 0.05)
      test.advance(48)
      local moving = test.ipc("morph", "words")
      test.truthy(moving.progress > 0 and moving.progress < 1, "the morph did not run")
      test.settle(1000)
      local landed = test.ipc("morph", "words")
      test.eq(landed.text, "12:05")
      test.eq(landed.to, "", "a finished morph was left in place")
      test.near(landed.progress, 0, 0.0001)
      test.eq(#test.logs("error"), 0)
    end)

    test.it("takes a new value in flight without falling behind", function()
      load(style)
      test.ipc("say", "12:05")
      test.advance(32)
      test.ipc("say", "12:06")
      local turned = test.ipc("morph", "words")
      test.eq(turned.text, "12:06")
      test.eq(turned.to, "12:05")
      test.settle(1000)
      test.eq(test.ipc("morph", "words").text, "12:06")
      test.eq(test.ipc("morph", "words").to, "")
      test.eq(test.get("plain").text, "12:06")
    end)
  end)
end
