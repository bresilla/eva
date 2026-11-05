-- Tsugumori's HUD decoration: each finite pass plays once on its event,
-- hides when it ends or its surface goes, and nothing is left moving at rest.
local test = morf.test
local FRAME = 16
local DRAWER = [[
  if morf.env("TEST_REDUCED") == "1" then require("themes.motion_landing").install() end
  local ui = require("morf.ui")
  local drawer = require("drawer")
  local content = ui.Item { width = 320, height = 240 }
  local d = drawer.new { name = morf.env("TEST_NAME") or "sample", edge = "top", width = 320, height = 240,
    content = content }
  ui.Item { width = 1280, height = 720, ui.Sdf { width = 1280, height = 720, d.shape }, d.panel }
  morf.ipc.open = d.set
]]
local function env(extra)
  local out = { EVA_STYLE = "tsugumori", EVA_DRY_RUN = "1",
    EVA_APPEARANCE = morf.env("XDG_CACHE_HOME") .. "/hud-appearance.json",
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/hud-settings.json" }
  for k, v in pairs(extra or {}) do out[k] = v end
  return out
end
local function clean()
  test.eq(#test.logs("warn"), 0)
  test.eq(#test.logs("error"), 0)
end
local function shown(id)
  local node = test.find { id = id }
  return node ~= nil and node.visible and node.opacity > 0
end
local function hidden(id)
  local node = test.find { id = id }
  return node == nil or not node.visible
end
local function at_rest()
  for _ = 1, 20 do
    if test.settle(1000) < 3 * FRAME then return true end
  end
  return false
end

local CARDS = [[
  local ui = require("morf.ui")
  local kit = require("kit")
  local list = {}
  kit.collect(list)
  local card = kit.card { id = "hud-card", width = 200, height = 120 }
  kit.collect(nil)
  ui.Item { width = 400, height = 300, ui.Sdf { anchors = { fill = true }, list[1].shape }, card }
  local marks = require("themes.tsugumori.marks")[card]
  local running = {}
  morf.ipc.enter = function(coming)
    for _, h in ipairs(running) do h:stop() end
    running = require("theme").motion.entries(list, coming, { delay = 0 })
  end
  morf.ipc.marks = function()
    local out = {}
    for i, m in ipairs(marks) do out[i] = { x = m.translate_x, y = m.translate_y } end
    return out
  end
]]

test.describe("tsugumori cards", function()
  test.it("snap their corner brackets in as they enter and rest square", function()
    test.load("../shell/init.lua", { source = CARDS, size = { 400, 300 }, env = env() })
    test.advance(1)
    test.ipc("enter", true)
    test.advance(40)
    local early = test.ipc("marks")
    test.truthy(early[1].x < 0 and early[1].y < 0, "the top-left bracket did not start outside its corner")
    test.truthy(early[4].x > 0 and early[4].y > 0, "the bottom-right bracket did not start outside its corner")
    test.ipc("enter", false) test.advance(10)
    test.ipc("enter", true)
    test.truthy(at_rest())
    for _, m in ipairs(test.ipc("marks")) do test.near(m.x, 0, .01) test.near(m.y, 0, .01) end
    clean()
  end)
end)

local BOOT = { "drawer-sample-boot-trace", "drawer-sample-boot-scan", "drawer-sample-boot-register" }

test.describe("tsugumori drawer boot", function()
  test.it("traces, scans and prints once as a drawer opens, then hides", function()
    test.load("../shell/init.lua", { source = DRAWER, size = { 1280, 720 }, env = env() })
    test.ipc("open", true)
    local seen = {}
    for _ = 1, 60 do
      test.advance(FRAME)
      for _, id in ipairs(BOOT) do if shown(id) then seen[id] = true end end
    end
    for _, id in ipairs(BOOT) do test.truthy(seen[id], id .. " never showed") end
    test.truthy(at_rest(), "the boot pass kept moving")
    for _, id in ipairs(BOOT) do test.truthy(hidden(id), id .. " stayed up at rest") end
    clean()
  end)

  test.it("closing during the pass hides it at once, and reopening plays it again", function()
    test.load("../shell/init.lua", { source = DRAWER, size = { 1280, 720 }, env = env() })
    test.ipc("open", true)
    local up = false
    for _ = 1, 60 do
      test.advance(FRAME)
      if shown("drawer-sample-boot-trace") then up = true break end
    end
    test.truthy(up)
    test.ipc("open", false) test.advance(1)
    for _, id in ipairs(BOOT) do test.truthy(hidden(id), id .. " outlived the close") end
    test.ipc("open", true)
    up = false
    for _ = 1, 60 do
      test.advance(FRAME)
      if shown("drawer-sample-boot-scan") then up = true break end
    end
    test.truthy(up, "reopening did not boot again")
    test.truthy(at_rest())
    clean()
  end)

  test.it("lands at once under Reduce motion", function()
    test.load("../shell/init.lua", { source = DRAWER, size = { 1280, 720 }, env = env { TEST_REDUCED = "1" } })
    test.ipc("open", true)
    test.advance(200)
    for _, id in ipairs(BOOT) do test.truthy(hidden(id), id .. " still moving under Reduce motion") end
    clean()
  end)

  test.it("leaves the on-screen keyboard's drawer as it was", function()
    test.load("../shell/init.lua", { source = DRAWER, size = { 1280, 720 }, env = env { TEST_NAME = "keyboard" } })
    test.ipc("open", true)
    test.advance(1200)
    test.eq(test.find { id = "drawer-keyboard-boot-trace" }, nil)
    test.eq(test.find { id = "drawer-keyboard-dots" }, nil)
    clean()
  end)
end)
