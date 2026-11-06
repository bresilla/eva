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
local function ever(id, frames)
  for _ = 1, frames or 40 do
    test.advance(FRAME)
    if shown(id) then return true end
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
  local marks = require("themes.tsugumori.marks").cards[card].marks
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
    ui.Item { x = 100, y = 100, kit.pill { id = "hud-press", label = "Engage", width = 150 } },
    kit.action { id = "eva.osk.key.full.letters.q", x = 20, y = 220, width = 40, height = 40, cursor = "pointer",
      on_pressed = function() end } }
]]

test.describe("tsugumori feedback", function()
  test.it("closes its reticle onto a hovered control and scans a press", function()
    test.load("../shell/init.lua", { source = PRESS, size = { 400, 300 }, env = env() })
    test.advance(50)
    test.move("hud-press") test.advance(30)
    test.truthy(test.ipc("shift", "hud-press-mark-1") < -3, "the reticle did not start further out")
    test.advance(400)
    test.near(test.ipc("shift", "hud-press-mark-1"), -2, .01)
    for i = 2, 4 do test.truthy(test.find { id = "hud-press-mark-" .. i }, "no bracket " .. i) end
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

  test.it("leaves an on-screen keyboard key's feedback as it was", function()
    test.load("../shell/init.lua", { source = PRESS, size = { 400, 300 }, env = env() })
    test.advance(50)
    local key = "eva.osk.key.full.letters.q"
    test.truthy(test.find { id = key }, "no key")
    test.move(40, 240) test.advance(30)
    -- A layout's area draws its feedback under the shared control name.
    test.truthy(test.find { id = "tsugumori-control-wash" }, "the key drew no feedback")
    local shift = test.ipc("shift", "tsugumori-control-mark-1")
    test.truthy(shift <= 0 and shift >= -3, "the key's marks closed in from further out")
    test.click(40, 240) test.advance(50)
    test.eq(test.find { id = "tsugumori-control-scan" }, nil)
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

local POPUP = [[
  local ui = require("morf.ui")
  local kit = require("kit")
  local root = ui.Item { width = 520, height = 400 }
  local opener = kit.widgets.push { id = "opener", x = 20, y = 20, width = 100, height = 30, label = "Menu" }
  ui.reparent(opener, root)
  local menu = kit.widgets.menu { id = "menu", width = 200, items = { { label = "One" }, { label = "Two" } } }
  morf.ipc.open = function() menu.open(opener) end
  morf.ipc.close = function() menu.close("closed") end
  morf.ipc.lock = function() return require("theme").motion.lock_on ~= nil end
]]

test.describe("tsugumori popups", function()
  test.it("boot as a menu opens and let go as it closes", function()
    test.load("../shell/init.lua", { source = POPUP, size = { 520, 400 }, env = env() })
    test.advance(200)
    test.ipc("open")
    test.truthy(ever("popup-menu-boot-trace"), "the menu opened without booting")
    test.ipc("close") test.advance(120)
    test.truthy(hidden("popup-menu-boot-trace"))
    test.truthy(at_rest())
    clean()
  end)

  test.it("material keeps the lock-on hook and draws nothing with it", function()
    test.load("../shell/init.lua", { source = POPUP, size = { 520, 400 }, env = env { EVA_STYLE = "material" } })
    test.advance(200)
    test.truthy(test.ipc("lock"), "material has no lock_on")
    test.ipc("open")
    test.advance(600)
    test.eq(test.find { id = "popup-menu-boot-trace" }, nil)
    clean()
  end)
end)

local function shell()
  for _, program in ipairs { "systemctl", "loginctl" } do test.stub_run(program, { code = 0 }) end
  test.load("../shell/init.lua", { size = { 1280, 800 }, env = env { EVA_WALLPAPER = "", EVA_FAKE_OSD = "1" } })
  test.settle(1500)
end

test.describe("tsugumori chrome in the shell", function()
  test.it("traces a workspace change along the rail and leaves nothing up", function()
    shell()
    test.eq(test.find { id = "tsugumori-frame-corners" }, nil, "the frame still has corner reticles")
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

local CONTENT = [[
  if morf.env("TEST_REDUCED") == "1" then require("themes.motion_landing").install() end
  local ui = require("morf.ui")
  local kit = require("kit")
  local drawer = require("drawer")
  local P = require("themes.layouts.page")
  local level = morf.signal("boot.level", .8)
  local clicks = 0
  local tile = P.tile { id = "boot-tile", title = "Telemetry", width = 260, height = 150,
    kit.meter { id = "boot-meter", width = 200, height = 6, count = 20, value = function() return level:get() end },
    kit.action { id = "boot-press", y = 40, width = 120, height = 36, cursor = "pointer",
      on_clicked = function() clicks = clicks + 1 end } }
  local content = ui.Item { width = 320, height = 240, ui.Item { x = 30, y = 40, tile } }
  local d = drawer.new { name = "sample", edge = "top", width = 320, height = 240, content = content }
  ui.Item { width = 1280, height = 720, ui.Sdf { width = 1280, height = 720, d.shape }, d.panel }
  morf.ipc.open = d.set
  local registry = require("themes.tsugumori.marks")
  local card
  for _, entry in pairs(registry.cards) do if entry.outline then card = entry end end
  local caption
  for node in pairs(registry.captions) do caption = registry.captions[node] end
  morf.ipc.state = function()
    local m = card.marks[4]
    return { trim = card.outline.trim_end, start = card.outline.trim_start, outline = card.outline.opacity,
      x = m.translate_x, y = m.translate_y, mark = m.opacity, plate = caption.plate.opacity,
      rule = caption.rule.scale_x }
  end
  morf.ipc.clicks = function() return clicks end
]]
local function content_env(extra) return env(extra) end
local function covered()
  local curtain = test.find { id = "drawer-sample-curtain" }
  if not curtain or not curtain.visible then return 0 end
  return (curtain.width or 0) / 320
end
local function resting(s)
  return math.abs(s.trim - 1) < .001 and math.abs(s.start) < .001 and math.abs(s.x) < .01 and math.abs(s.y) < .01
    and math.abs(s.mark - 1) < .001 and math.abs(s.plate - 1) < .001 and math.abs(s.rule - 1) < .001
end

test.describe("tsugumori content boot", function()
  test.it("draws the cards in over the content once the cover has gone, and again on reopening", function()
    test.load("../shell/init.lua", { source = CONTENT, size = { 1280, 720 }, env = content_env() })
    test.advance(50)
    for round = 1, 2 do
      test.ipc("open", true)
      local drawing, scanning, flew, lit = nil, nil, false, false
      for _ = 1, 80 do
        test.advance(FRAME)
        local s = test.ipc("state")
        if not drawing and s.trim > .55 and s.trim < .99 then drawing = covered() end
        if not scanning and shown("drawer-sample-boot-scan") then scanning = covered() end
        if math.abs(s.x) > 20 and s.mark > .5 then flew = true end
        if s.plate > 0 and s.plate < 1 or s.rule > 0 and s.rule < 1 then lit = true end
      end
      test.truthy(drawing, "round " .. round .. ": the outline never drew in")
      test.truthy(drawing < .05, "round " .. round .. ": the outline drew under the cover")
      test.truthy(scanning and scanning < .05, "round " .. round .. ": the scan ran under the cover")
      test.truthy(flew, "round " .. round .. ": the brackets did not fly in from further out")
      test.truthy(lit, "round " .. round .. ": the caption did not light")
      test.truthy(at_rest(), "round " .. round .. ": the pass kept moving")
      test.truthy(resting(test.ipc("state")), "round " .. round .. ": the chrome did not come to rest")
      test.truthy(hidden("drawer-sample-boot-scan"))
      test.ipc("open", false)
      test.truthy(at_rest())
    end
    clean()
  end)

  test.it("lets presses through while it plays", function()
    test.load("../shell/init.lua", { source = CONTENT, size = { 1280, 720 }, env = content_env() })
    test.advance(50)
    test.ipc("open", true)
    test.truthy(ever("drawer-sample-boot-scan", 60), "no scan")
    test.click("boot-press")
    test.eq(test.ipc("clicks"), 1)
    clean()
  end)

  test.it("stops and rests the chrome when the drawer shuts mid-pass", function()
    test.load("../shell/init.lua", { source = CONTENT, size = { 1280, 720 }, env = content_env() })
    test.advance(50)
    test.ipc("open", true)
    local mid = false
    for _ = 1, 60 do
      test.advance(FRAME)
      local s = test.ipc("state")
      if s.trim > .55 and s.trim < .95 then mid = true break end
    end
    test.truthy(mid, "never caught the pass mid-way")
    test.ipc("open", false)
    test.advance(FRAME)
    local s = test.ipc("state")
    test.truthy(resting(s), ("the chrome was left mid-pass: trim %.2f..%.2f mark %.2f,%.2f/%.2f plate %.2f rule %.2f")
      :format(s.start, s.trim, s.x, s.y, s.mark, s.plate, s.rule))
    test.advance(120)
    test.truthy(hidden("drawer-sample-boot-scan"), "the scan outlived the close")
    test.truthy(at_rest())
    test.truthy(resting(test.ipc("state")), "the chrome moved again after the close")
    clean()
  end)

  test.it("lands at once under Reduce motion", function()
    test.load("../shell/init.lua", { source = CONTENT, size = { 1280, 720 }, env = content_env { TEST_REDUCED = "1" } })
    test.advance(50)
    test.ipc("open", true)
    for _ = 1, 12 do
      test.advance(FRAME)
      local s = test.ipc("state")
      test.truthy(s.trim > .99 or s.trim < .51, "the outline travelled under Reduce motion")
    end
    test.advance(100)
    test.truthy(resting(test.ipc("state")), "the chrome did not land")
    test.truthy(hidden("drawer-sample-boot-scan"))
    clean()
  end)

  test.it("leaves nothing moving at rest, before or after a pass", function()
    test.load("../shell/init.lua", { source = CONTENT, size = { 1280, 720 }, env = content_env() })
    test.truthy(at_rest(), "moving before any pass")
    test.ipc("open", true)
    test.truthy(at_rest(), "moving after the pass")
    test.frames()
    test.advance(2000)
    test.eq(test.frames().frames, 0, "frames drawn at rest")
    test.truthy(resting(test.ipc("state")))
    clean()
  end)
end)

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
