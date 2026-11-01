-- Snapping: the arithmetic on its own, then the real shell on the window
-- stand-in, whose list shows where each command really put a window.
local test = morf.test

test.it("cells, zones and layouts are worked out exactly", function()
  test.load("../shell/init.lua", { source = [[
    local m = require("snap_model")
    morf.ipc.calc = function()
      local area = m.area { x = 0, y = 0, width = 2000, height = 1000, scale = 1, reserved = { 10, 20, 10, 20 } }
      return { area = area, left = m.box("left", area, 8), right = m.box("right", area, 8),
        scaled = m.area { x = 0, y = 0, width = 3840, height = 2160, scale = 2, reserved = { 0, 0, 0, 0 } },
        at = { m.zone(30, 500, area, 48, 160), m.zone(1950, 500, area, 48, 160), m.zone(1000, 30, area, 48, 160),
          m.zone(20, 30, area, 48, 160), m.zone(1980, 970, area, 48, 160), m.zone(1000, 500, area, 48, 160) or "none" },
        assign = m.assign("halves", 3) }
    end
    return require("morf.ui").Item { width = 10, height = 10 }
  ]] })
  local r = test.ipc("calc")
  test.eq(r.area, { x = 10, y = 20, width = 1980, height = 960 })
  test.eq(r.left, { x = 18, y = 28, width = 978, height = 944 })
  test.eq(r.right, { x = 1004, y = 28, width = 978, height = 944 })
  test.eq(r.scaled.width, 1920)
  test.eq(r.at, { "left", "right", "full", "top_left", "bottom_right", "none" })
  test.eq(r.assign, { "left", "right", "right" })
end)

local SCENE = [[{"focus":1,"clients":[
  {"class":"kitty","title":"one","workspace":1},
  {"class":"firefox","title":"web","workspace":1},
  {"class":"code","title":"edit","workspace":1}]}]]

local function load()
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1920, 1080 }, env = { EVA_FAKE_WINDOWS = SCENE, EVA_DRY_RUN = "1" } })
  test.advance(200)
end

local function window(title)
  for _, w in ipairs(test.ipc("windows")) do if w.title == title then return w end end
end

local function last_wire()
  local wire = test.ipc("windows", "wire")
  return wire[#wire] or ""
end

test.it("a snap floats the window and puts it exactly in the cell", function()
  load()
  test.eq(test.ipc("snap", "left"), true)
  test.advance(16)
  local w = window("one")
  test.truthy(w.floating, "the window did not float")
  test.eq({ w.x, w.y, w.width, w.height }, { 24.0, 24.0, 932.0, 1032.0 })
  test.contains(last_wire(), 'hl.dsp.window.resize({ window = "address:' .. w.address .. '", x = 932, y = 1032 })')
  test.contains(last_wire(), "hl.dsp.window.move({ window")
end)

test.it("after a snap the other windows are offered for the room left, and fill it", function()
  load()
  test.ipc("snap", "left") test.advance(100)
  test.truthy(test.get("snap-assist").visible, "no offer")
  test.truthy(test.get("snap-offer-1").visible)
  test.truthy(test.get("snap-offer-2").visible)
  test.click("snap-offer-area-1") test.advance(100)
  test.falsy(test.find({ id = "snap-assist", visible = true }), "the offer stayed after filling the room")
  local w = window("web")
  test.truthy(w.floating)
  test.eq(w.x, 964.0)
end)

test.it("escape leaves the room empty", function()
  load()
  test.ipc("snap", "left") test.advance(100)
  test.key("Escape") test.advance(100)
  test.falsy(test.find({ id = "snap-assist", visible = true }))
  test.falsy(window("web").floating)
end)

test.it("a drag shows the landing, and the window lands there", function()
  load()
  test.eq(test.ipc("snap", "drag"), true)
  test.ipc("stand_in_cursor", "1900", "500")
  test.advance(100)
  test.settle(2000)
  local box = test.get("snap-landing")
  test.near(box.x, 964, 2, "the landing is not on the right half")
  test.near(box.width, 932, 2)
  test.ipc("stand_in_cursor", "1000", "500")
  test.advance(100)
  test.eq(test.ipc("snap", "drop"), false, "landed away from the edges")
  test.ipc("snap", "drag")
  test.ipc("stand_in_cursor", "1900", "500")
  test.advance(100)
  test.eq(test.ipc("snap", "drop"), true)
  test.advance(16)
  test.eq(window("one").x, 964.0)
end)

test.it("while a window is dragged the edges and corners leave it alone", function()
  load()
  test.ipc("corner", "top_left", "overview", "")
  test.advance(100)
  test.ipc("snap", "drag")
  test.ipc("stand_in_cursor", "1900", "500")
  test.move(1918, 500) test.advance(1000)
  test.eq(test.ipc("drawers"), "", "dragging to an edge opened a panel")
  test.move(3, 3) test.advance(500)
  test.falsy(test.ipc("overview", "state"), "dragging to a corner ran its action")
  test.move(900, 500)
  test.ipc("snap", "drop")
  -- The compositor gives the pointer back only now, on the edge.
  test.move(1918, 500) test.advance(1000)
  test.eq(test.ipc("drawers"), "", "the pointer resting where the window was dropped opened a panel")
  test.advance(2000)
  test.eq(test.ipc("drawers"), "", "the panel opened once the landing had settled")
  test.key("Escape")
  test.ipc("close") test.advance(100)
  test.move(900, 500) test.advance(100)
  test.move(1918, 500) test.advance(1000)
  test.contains(test.ipc("drawers"), "sidebar", "left and come back, the edge should open its panel")
  test.ipc("corner", "top_left", "none", "")
  test.advance(400)
end)

test.it("when the compositor names no window, the last focused one stands for it", function()
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1920, 1080 }, source = [[
    local root = require("init")
    morf.ipc.blur = function() require("services").hyprland.state.active_window.address = "" end
    return root
  ]], env = { EVA_FAKE_WINDOWS = SCENE, EVA_DRY_RUN = "1" } })
  test.advance(200)
  test.ipc("blur")
  test.eq(test.ipc("snap", "left"), true, "no window for the shell to act on")
  test.advance(16)
  test.truthy(window("one").floating)
  test.ipc("workspace", "2") test.advance(100)
  test.ipc("blur")
  test.eq(test.ipc("keep_above"), false, "an empty workspace has no window to stand in")
end)

test.it("the picker places a window in a cell, or the whole workspace in a layout", function()
  load()
  test.ipc("snap", "picker") test.advance(300)
  test.truthy(test.get("snap-picker").visible)
  test.click("snap-layout-halves-cell-2") test.advance(100)
  test.eq(window("one").x, 964.0)
  test.key("Escape") test.advance(100)
  test.eq(test.ipc("snap", "layout", "thirds"), 3)
  test.advance(16)
  test.eq(window("one").width, 617.0)
  test.truthy(window("edit").x > window("web").x)
  test.eq(#test.logs("warn"), 0)
end)

test.it("kill mode lights the window under the pointer and a press force-quits it", function()
  load()
  test.ipc("kill_mode") test.advance(200)
  test.truthy(test.get("kill-area").visible)
  test.move(1400, 300) test.advance(300)
  test.near(test.get("kill-target").x, 964, 40)
  test.click(1400, 300) test.advance(100)
  test.falsy(test.find({ id = "kill-area", visible = true }), "it stayed on")
  test.falsy(window("web"), "the window is still there")
  test.truthy(last_wire():find("hl.dsp.window.kill", 1, true), last_wire())
end)

test.it("escape leaves kill mode and nothing dies", function()
  load()
  test.ipc("kill_mode") test.advance(100)
  test.key("Escape") test.advance(100)
  test.falsy(test.find({ id = "kill-area", visible = true }))
  test.eq(#test.ipc("windows"), 3)
end)

test.it("the window menu keeps a window above and steps its opacity", function()
  load()
  test.ipc("window_menu", "open") test.advance(600)
  test.click("window-menu-top-10") test.advance(100)
  test.truthy(window("one").floating, "keep above did not float it")
  test.contains(last_wire(), 'hl.dsp.window.alter_zorder({ mode = "top"')
  test.click("window-menu-top-11") test.advance(100)
  test.eq(window("one").opacity, .85)
  test.contains(last_wire(), 'hl.dsp.window.set_prop({ prop = "opacity"')
  test.eq(test.logs("warn"), {})
end)

test.it("the window menu opens kill mode and the picker", function()
  load()
  test.ipc("window_menu", "open") test.advance(600)
  test.click("window-menu-bottom-3") test.advance(200)
  test.truthy(test.get("kill-area").visible)
  test.key("Escape") test.advance(200)
  test.ipc("window_menu", "open") test.advance(600)
  test.click("window-menu-top-12") test.advance(200)
  test.truthy(test.get("snap-picker").visible)
end)
