-- The workspace rail takes a press and the wheel, in both themes: on a desk
-- down the left edge, and where the left panel carries it; under a finger a
-- tap on the bottom strip, with the swipes from there left alone. The strip
-- beside it opens the left panel above and below the rail, not on it.
local test = morf.test
local SOURCE = [[
  local switches, steps = {}, {}
  local workspace = require("services").workspace
  local go, turn = workspace.go, workspace.step
  workspace.go = function(id) switches[#switches + 1] = id go(id) end
  workspace.step = function(delta) steps[#steps + 1] = delta turn(delta) end
  require("init")
  morf.ipc.rail_state = function()
    return { switches = switches, steps = steps, active = workspace.active(),
      left = require("leftbar").drawer.open:get(), dashboard = require("dashboard").drawer.open:get() }
  end
  morf.ipc.rail_on = function(on) require("config").set("rail.enabled", on == "yes") end
]]
local loads = 0
local function load(style, w, h, touch)
  test.stub_run("task", { code = 0, stdout = "[]" })
  loads = loads + 1
  local env = { EVA_STYLE = style, EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "0",
    LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"),
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/rail-press-" .. loads .. ".json" }
  if touch then env.EVA_INPUT_DEVICES = morf.env("PWD") .. "/tests/fixtures/input-devices-touch" end
  test.load("../shell/init.lua", { size = { w or 1920, h or 1080 }, source = SOURCE, env = env })
  test.settle(1500)
end
local function state() return test.ipc("rail_state") end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " rail switches workspace on a press, on the slot pressed", function()
    load(style)
    test.click("rail-hit-4") test.advance(200)
    test.eq(state().switches, { 4 })
    test.eq(state().active, 4)
    test.click("rail-hit-7") test.advance(200)
    test.eq(state().active, 7)
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " rail turns workspaces with the wheel, a notch at a time", function()
    load(style)
    local hit = test.get("rail-hit-5")
    test.wheel(0, 120, { x = hit.x + 4, y = hit.y + 4 }) test.advance(200)
    test.eq(state().steps, { 1 })
    test.wheel(0, -120, { x = hit.x + 4, y = hit.y + 4 }) test.advance(200)
    test.eq(state().steps, { 1, -1 })
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " rail stays pressable where the left panel carries it", function()
    load(style)
    test.ipc("leftbar", "open", "tasks") test.settle(1500)
    local hit = test.get("rail-hit-3")
    local panel = test.get("drawer-leftbar")
    test.truthy(hit.x >= panel.x + panel.width - 40, "the targets did not ride out")
    test.click("rail-hit-3") test.advance(200)
    test.eq(state().switches, { 3 })
    test.truthy(state().left, "a press on the rail shut the panel it rides on")
  end)

  test.it(style .. " rail leaves the left panel shut while the pointer aims at it", function()
    load(style)
    local hit = test.get("rail-hit-5")
    test.move(hit.x + 4, hit.y + 4) test.advance(1500)
    test.falsy(state().left, "dwelling on the rail opened the panel")
    test.move(14, test.get("rail-hit-1").y - 40) test.advance(1500)
    test.truthy(state().left, "the strip above the rail did not open it")
    test.ipc("close") test.settle(900)
    test.move(14, test.get("rail-hit-9").y + 80) test.advance(1500)
    test.truthy(state().left, "the strip below the rail did not open it")
  end)

  test.it(style .. " left edge is all strip with the rail turned off", function()
    load(style)
    test.ipc("rail_on", "no") test.advance(300)
    test.move(14, 540) test.advance(1500)
    test.truthy(state().left)
  end)

  test.it(style .. " rail takes a tap under a finger, and a swipe still pulls the dashboard", function()
    load(style, 868, 1932, true)
    test.eq(#test.find_all("rail-hit-1"), 0)
    local pill = test.get("rail-pill-6")
    local x, y = pill.x + pill.width / 2, 1930
    test.touch("down", 0, x, y) test.touch("up", 0, x, y) test.advance(300)
    test.eq(state().switches, { 6 })
    test.swipe({ 434, 1930 }, { 434, 1200 }) test.advance(900)
    test.truthy(state().dashboard, "the swipe up no longer reaches the dashboard")
    test.eq(#state().switches, 1, "the swipe counted as a tap")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("the rail's and the bar's wheel hold back in a dry run", function()
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1920, 1080 }, source = SOURCE, env = { EVA_STYLE = "material",
    EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule",
    HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(1500)
  local hit = test.get("rail-hit-5")
  test.wheel(0, 120, { x = hit.x + 4, y = hit.y + 4 }) test.advance(200)
  test.eq(state().steps, {})
end)
