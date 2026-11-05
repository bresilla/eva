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

local PRESS = [[
  local ui = require("morf.ui")
  local nodes, path = {}, ui.Path
  ui.Path = function(props)
    local node = path(props)
    if props.id then nodes[props.id] = node end
    return node
  end
  morf.ipc.shift = function(id) return nodes[id] and nodes[id].translate_x end
  local kit = require("kit")
  ui.Item { width = 400, height = 300,
    ui.Item { x = 100, y = 100, kit.pill { id = "hud-press", label = "Engage", width = 150 } } }
]]

test.describe("tsugumori feedback", function()
  test.it("closes its reticle onto a hovered control and scans a press", function()
    test.load("../shell/init.lua", { source = PRESS, size = { 400, 300 }, env = env() })
    test.advance(50)
    test.move("hud-press") test.advance(30)
    test.truthy(test.ipc("shift", "hud-press-mark-1") < -3, "the reticle did not start further out")
    test.advance(400)
    test.near(test.ipc("shift", "hud-press-mark-1"), -3, .01)
    local box = test.get("hud-press")
    test.press(box.x + 20, box.y + 10) test.advance(50)
    test.truthy(test.get("hud-press-scan").opacity > 0, "a press drew no scan line")
    test.release(box.x + 20, box.y + 10)
    test.leave()
    test.truthy(at_rest())
    test.near(test.get("hud-press-scan").opacity, 0, .001)
    test.near(test.get("hud-press-mark-1").opacity, 0, .001)
    clean()
  end)
end)

local METER = [[
  local ui = require("morf.ui")
  local kit = require("kit")
  local level = morf.signal("hud.level", 0)
  local nodes, path = {}, ui.Path
  ui.Path = function(props) local node = path(props) nodes[#nodes + 1] = node return node end
  ui.Item { width = 400, height = 100,
    kit.meter { id = "hud-meter", width = 160, height = 8, count = 10, value = function() return level:get() end } }
  ui.Path = path
  morf.ipc.level = function(v) level:set(v) end
  morf.ipc.lit = function() return nodes[#nodes].trim_end end
]]

test.describe("tsugumori meters", function()
  test.it("light their cells one whole cell at a time and settle on the level", function()
    test.load("../shell/init.lua", { source = METER, size = { 400, 100 }, env = env() })
    test.advance(20)
    test.near(test.ipc("lit"), 0, .001)
    test.ipc("level", 1)
    local partial = false
    for _ = 1, 12 do
      test.advance(FRAME)
      local lit = test.ipc("lit")
      local cells = lit * 10
      test.truthy(math.abs(cells - math.floor(cells + .5)) < .02, "a cell lit only part way: " .. lit)
      if lit > .05 and lit < .95 then partial = true end
    end
    test.truthy(partial, "the cells all lit at once")
    test.truthy(at_rest())
    test.near(test.ipc("lit"), 1, .001)
    clean()
  end)
end)

local function shell()
  for _, program in ipairs { "systemctl", "loginctl" } do test.stub_run(program, { code = 0 }) end
  test.load("../shell/init.lua", { size = { 1280, 800 }, env = env { EVA_WALLPAPER = "", EVA_FAKE_OSD = "1" } })
  test.settle(1500)
end
local function ever(id, frames)
  for _ = 1, frames or 40 do
    test.advance(FRAME)
    if shown(id) then return true end
  end
  return false
end

test.describe("tsugumori chrome in the shell", function()
  test.it("traces a workspace change along the rail and leaves nothing up", function()
    shell()
    test.truthy(test.find { id = "tsugumori-frame-corners" }, "the frame has no corner reticles")
    test.ipc("workspace", 4)
    test.truthy(ever("rail-trace"), "the switch drew no trace")
    test.truthy(at_rest())
    test.truthy(hidden("rail-trace"))
    test.truthy(hidden("rail-card-boot-scan"))
    clean()
  end)

  test.it("locks onto the volume readout and the session's focus, and lets go on hiding", function()
    shell()
    test.ipc("osd", "volume")
    test.truthy(ever("levels-bud-lock-boot-scan"), "the readout came up unmarked")
    test.truthy(at_rest())
    test.ipc("session", "open")
    test.truthy(ever("session-lock-lock-boot-bracket-1", 60), "the focused row was not locked onto")
    test.ipc("close") test.advance(120)
    test.truthy(hidden("session-lock-lock-boot-bracket-1"), "the lock outlived the menu")
    test.truthy(at_rest())
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

  test.it("closing during the pass fades it out quickly, and reopening plays it again", function()
    test.load("../shell/init.lua", { source = DRAWER, size = { 1280, 720 }, env = env() })
    test.ipc("open", true)
    local up = false
    for _ = 1, 60 do
      test.advance(FRAME)
      if shown("drawer-sample-boot-trace") then up = true break end
    end
    test.truthy(up)
    test.ipc("open", false) test.advance(120)
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
