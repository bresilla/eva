-- eva-colorpick: the formats, a colour read from a picture, the recent colours,
-- the pointer on the frozen screen, and its page in Tools.
--
--     morf test --no-dbus tests/colorpick_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local PICTURE = ROOT .. "tests/fixtures/wallpaper.png"

local HOST = [[
local morf = require("morf")
require("morf.ui").Item { width = 1, height = 1 }
local formats = require("apps.colorpick.formats")
morf.ipc.write = function(hex, name) return formats.write(hex, name) end
]]

local ENV = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" }

test.it("writes a colour every way", function()
  test.load("../apps/colorpick/app.lua", { source = HOST, env = ENV })
  test.eq(test.ipc("write", "#3366cc", "hex"), "#3366cc")
  test.eq(test.ipc("write", "#3366cc", "rgb"), "rgb(51, 102, 204)")
  test.eq(test.ipc("write", "#3366cc", "hsl"), "hsl(220, 60%, 50%)")
  test.contains(test.ipc("write", "#3366cc", "oklch"), "oklch(")
  test.eq(test.ipc("write", "#808080", "hsl"), "hsl(0, 0%, 50%)")
end)

-- Its page alone, as the Tools window shows it.
local function tool()
  test.stub_run("grim", { code = 0 })
  local env = { EVA_TEST_TOOL = "colorpick", EVA_TEST_PAGE = "488x380" }
  for key, value in pairs(ENV) do env[key] = value end
  test.load("../shell/init.lua", { env = env, source = morf.fs.read(ROOT .. "tests/fixtures/tool_page.lua") })
  test.settle(300)
end

test.it("shows the formats, and nothing recent before the first pick", function()
  tool()
  test.truthy(test.find { id = "colorpick-format-oklch" })
  test.falsy(test.find({ id = "colorpick-recent-1" }).visible)
  test.eq(#test.logs("error"), 0)
end)

test.it("reads the colour under the pointer and keeps it", function()
  test.load("../apps/colorpick/app.lua", { env = ENV, source = morf.fs.read(ROOT .. "apps/colorpick/app.lua") .. ([[
    require("apps.colorpick.model").picture:set { path = %q, width = 64, height = 64 }
  ]]):format(PICTURE) })
  test.settle(300)
  test.ipc("point", "10", "10")
  test.settle(100)
  test.eq(#test.logs("error"), 0)
  test.truthy(test.find { id = "colorpick-hint" })
  test.truthy(test.find({ id = "colorpick-lens" }).visible)
  local hover = test.ipc("state").hover
  test.eq(#hover, 7)
  test.eq(test.ipc("pick"), hover)
  local state = test.ipc("state")
  test.falsy(state.frozen)
  test.eq(state.picked, hover)
  test.eq(state.recent[1], hover)
  test.contains(state.message, hover)
end)

test.it("reads the colour on a screen too large to read a pixel of at once", function()
  local big = morf.env("XDG_STATE_HOME") .. "/colorpick-big.png"
  test.load { source = ([[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local done = false
    morf.image.process { output = %q, ops = {}, on_done = function() done = true end,
      source = '<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="2160"><rect width="3840" height="2160" fill="#336699"/></svg>' }
    morf.ipc.done = function() return done end
  ]]):format(big) }
  test.wait(function() test.advance(16) return test.ipc("done") end, 8000, "the picture was made")
  test.load("../apps/colorpick/app.lua", { env = ENV, source = morf.fs.read(ROOT .. "apps/colorpick/app.lua") .. ([[
    require("apps.colorpick.model").picture:set { path = %q, width = 3840, height = 2160 }
  ]]):format(big) })
  test.settle(200)
  test.ipc("point", "100", "100")
  local hover = test.wait(function()
    test.advance(16)
    local seen = test.ipc("state").hover
    return seen ~= "" and seen or nil
  end, 5000, "the colour came back")
  test.eq(hover, "#336699")
end)

test.it("keeps one of each recent colour, the newest first", function()
  test.load("../apps/colorpick/app.lua", { env = ENV, source = morf.fs.read(ROOT .. "apps/colorpick/app.lua") .. ([[
    local model = require("apps.colorpick.model")
    morf.ipc.again = function(x)
      model.picture:set { path = %q, width = 64, height = 64 }
      model.point(tonumber(x), 1, 1)
      return model.pick()
    end
  ]]):format(PICTURE) })
  test.settle(300)
  local first = test.ipc("again", "1")
  test.ipc("again", "60")
  test.ipc("again", "1")
  local recent = test.ipc("state").recent
  test.eq(recent[1], first)
  local seen = 0
  for _, hex in ipairs(recent) do if hex == first then seen = seen + 1 end end
  test.eq(seen, 1)
end)

test.it("holds back sending to the theme under EVA_DRY_RUN", function()
  tool()
  test.ipc("lule", "#123456")
  test.contains(test.ipc("state").message, "#123456")
end)
