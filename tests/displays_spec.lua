-- eva-displays: the outputs of both compositors in one shape, snapping and the
-- layout's rules, profiles matched by what a monitor is and not by its port,
-- the plans sent to Hyprland and sway, and the window driven by the pointer.
-- swaymsg is stubbed and Hyprland is a double: nothing reaches a session.
--
--     morf test --no-dbus tests/displays_spec.lua

local test = morf.test

local HOST = [[
local morf = require("morf")
require("morf.ui").Item { width = 1, height = 1 }
local d = require("lib.shell.displays")
local function panel(name, x, serial, port)
  return { name = port or name, make = "Dell", model = "U2720Q", serial = serial or name, description = "Dell U2720Q " .. (serial or name),
    enabled = true, x = x, y = 0, width = 1920, height = 1080, refresh = 60, scale = 1, transform = 0,
    vrr = false, mirror = "", modes = {} }
end
morf.ipc.sway = function()
  return d.from_sway { { name = "DP-1", make = "Unknown", model = "X", serial = "Unknown", active = true,
    rect = { x = 10, y = 20, width = 960, height = 540 }, scale = 2, transform = "90", adaptive_sync_status = "enabled",
    current_mode = { width = 1920, height = 1080, refresh = 59950 },
    modes = { { width = 1280, height = 720, refresh = 60000 }, { width = 1920, height = 1080, refresh = 59950 },
      { width = 1920, height = 1080, refresh = 59950 } } } }
end
morf.ipc.hypr = function()
  return d.from_hyprland { { id = 0, name = "DP-1", make = "LG", model = "UM", serial = "S1", description = "LG UM S1",
      width = 2560, height = 1440, refreshRate = 143.998, x = 0, y = 0, scale = 1.25, transform = 0, vrr = true, disabled = false,
      mirrorOf = "none", availableModes = { "2560x1440@144.00Hz", "1920x1080@60.00Hz" }, focused = true },
    { id = 1, name = "HDMI-A-1", width = 1920, height = 1080, refreshRate = 60, x = 0, y = 0, scale = 1, transform = 0,
      vrr = false, disabled = false, mirrorOf = "0", availableModes = {} },
    { id = -1, name = "FALLBACK", width = 0, height = 0, disabled = true } }
end
morf.ipc.logical = function()
  local w, h = d.logical { width = 3840, height = 2160, scale = 2, transform = 1 }
  return { w = w, h = h }
end
morf.ipc.snap = function(x, y, reach)
  local nx, ny = d.snap({ x = tonumber(x), y = tonumber(y), w = 100, h = 100 }, { { x = 0, y = 0, w = 200, h = 200 } }, tonumber(reach))
  return { x = nx, y = ny }
end
morf.ipc.overlap = function()
  local a = panel("A", 0)
  local b = panel("B", 1000)
  local first = d.overlap { a, b }
  b.x = 1920
  return { hit = first and first.name, clear = d.overlap { a, b } == nil, joined = d.detached { a, b } == nil }
end
morf.ipc.detached = function()
  local a, b = panel("A", 0), panel("B", 5000)
  return d.detached { a, b } ~= nil
end
morf.ipc.moved_port = function()
  local before = { panel("A", 0, "111", "DP-1"), panel("B", 1920, "222", "DP-2") }
  local profile = d.profile("desk", before)
  profile.outputs[2].scale = 2
  local after = { panel("A", 0, "111", "DP-5"), panel("B", 0, "222", "DP-1") }
  local found = d.match({ profile }, after)
  local wrong = d.match({ profile }, { panel("A", 0, "111", "DP-1"), panel("C", 0, "333", "DP-2") })
  local resolved = d.resolve(profile, after)
  return { found = found and found.name, wrong = wrong == nil, name = resolved[2].name, x = resolved[2].x, scale = resolved[2].scale }
end
morf.ipc.sway_lines = function()
  local o = panel("DP-1", 0)
  o.transform, o.vrr = 1, true
  local fresh = panel("HEADLESS-2", 1920)
  fresh.refresh = 0
  local off = panel("HDMI-A-1", 0)
  off.enabled = false
  return d.sway_lines { o, fresh, off }
end
morf.ipc.hypr_plan = function()
  local config = require("lib.compositor.hyprland_config")
  local sent = {}
  config.use { available = function() return true end,
    request = function(command, cb) sent[#sent + 1] = command cb("ok") end,
    eval = function(chunk, cb) sent[#sent + 1] = chunk cb("ok") end }
  config.set_flavour("lua")
  local o = panel("DP-1", 0, "S9")
  local plan = config.monitors_plan(d.hyprland_rules { o }, "lua")
  local answer
  d.apply({ o }, function(ok) answer = ok end)
  return { chunk = plan[1].eval, text = d.hyprland_text { o }, answer = answer, sent = table.concat(sent, "\n") }
end
morf.ipc.auto = function(x)
  local connected = { panel("A", 0, "111", "DP-1") }
  local kept = d.profile("desk", connected, true)
  kept.outputs[1].x = tonumber(x)
  d.save_profiles { kept }
  morf.ipc.answer = nil
  d.auto_apply(function(name, why) answer_name, answer_why = name, why end)
  return true
end
morf.ipc.auto_result = function() return { name = answer_name, why = answer_why } end
morf.ipc.persist = function()
  local ok, why = d.persist { panel("HEADLESS-1", 0) }
  return { ok = ok, why = why, text = morf.fs.read(d.paths.sway()) }
end
]]

local function pure(env)
  test.load("../shell/init.lua", { source = HOST, env = env or { EVA_SETTINGS = "/nonexistent/eva.json" } })
end

test.it("reads sway's outputs into one shape", function()
  pure()
  local o = test.ipc("sway")[1]
  test.eq(o.make, "")
  test.eq(o.serial, "")
  test.eq(o.refresh, 59.95)
  test.eq(o.transform, 1)
  test.eq(o.vrr, true)
  test.eq(#o.modes, 2)
  test.eq(o.modes[1].width, 1920)
end)

test.it("reads Hyprland's outputs, naming a mirror and dropping its stand-in", function()
  pure()
  local list = test.ipc("hypr")
  test.eq(#list, 2)
  test.eq(list[1].refresh, 144)
  test.eq(list[1].modes[1].refresh, 144)
  test.eq(list[2].mirror, "DP-1")
end)

test.it("sizes an output by its rotation and scale", function()
  pure()
  local size = test.ipc("logical")
  test.eq(size.w, 1080)
  test.eq(size.h, 1920)
end)

test.it("snaps to the nearest edge inside its reach and not beyond", function()
  pure()
  local near = test.ipc("snap", "215", "10", "24")
  test.eq(near.x, 200)
  test.eq(near.y, 0)
  local far = test.ipc("snap", "300", "300", "24")
  test.eq(far.x, 300)
  test.eq(far.y, 300)
end)

test.it("finds outputs that overlap and outputs that touch nothing", function()
  pure()
  local result = test.ipc("overlap")
  test.eq(result.hit, "A")
  test.truthy(result.clear)
  test.truthy(result.joined)
  test.truthy(test.ipc("detached"))
end)

test.it("matches a profile on make, model and serial, whatever the port", function()
  pure()
  local result = test.ipc("moved_port")
  test.eq(result.found, "desk")
  test.truthy(result.wrong)
  test.eq(result.name, "DP-1")
  test.eq(result.x, 1920)
  test.eq(result.scale, 2)
end)

test.it("spells sway's commands, leaving out a refresh it does not know", function()
  pure()
  local lines = test.ipc("sway_lines")
  test.contains(lines[1], 'output "DP-1" enable mode 1920x1080@60Hz pos 0 0 scale 1 transform 90 adaptive_sync on')
  test.contains(lines[2], "mode 1920x1080 pos 1920 0")
  test.contains(lines[3], 'output "HDMI-A-1" disable')
end)

test.it("sends Hyprland hl.monitor rules and persists them by identity", function()
  pure { EVA_SETTINGS = "/nonexistent/eva.json", HYPRLAND_INSTANCE_SIGNATURE = "test" }
  local plan = test.ipc("hypr_plan")
  test.contains(plan.chunk, 'hl.monitor({ output = "DP-1", mode = "1920x1080@60"')
  test.contains(plan.text, 'output = "desc:Dell U2720Q S9"')
  test.truthy(plan.answer)
  test.contains(plan.sent, "hl.monitor")
end)

test.it("writes the file sway reloads", function()
  pure { EVA_SETTINGS = "/nonexistent/eva.json", SWAYSOCK = "/nonexistent/sway.sock" }
  local result = test.ipc("persist")
  test.truthy(result.ok)
  test.contains(result.text, 'output "Dell U2720Q HEADLESS-1" enable')
end)

local CONNECTED = morf.json.encode {
  { name = "DP-1", make = "Dell", model = "U2720Q", serial = "111", active = true,
    rect = { x = 0, y = 0, width = 1920, height = 1080 }, scale = 1, transform = "normal",
    current_mode = { width = 1920, height = 1080, refresh = 60000 }, modes = {} },
}

local function applied()
  local calls = {}
  for _, argv in ipairs(test.runs()) do
    if argv[1] == "swaymsg" and argv[2] ~= "-t" then calls[#calls + 1] = argv[2] end
  end
  return calls
end

test.it("applies the saved profile for what is connected", function()
  test.stub_run("swaymsg", { code = 0, stdout = CONNECTED })
  pure { EVA_SETTINGS = "/nonexistent/eva.json", SWAYSOCK = "/nonexistent/sway.sock" }
  test.ipc("auto", "500")
  test.settle(100)
  test.eq(test.ipc("auto_result").name, "desk")
  test.contains(applied()[1], "pos 500 0")
end)

test.it("leaves an arrangement that already matches alone", function()
  test.stub_run("swaymsg", { code = 0, stdout = CONNECTED })
  pure { EVA_SETTINGS = "/nonexistent/eva.json", SWAYSOCK = "/nonexistent/sway.sock" }
  test.ipc("auto", "0")
  test.settle(100)
  test.eq(test.ipc("auto_result").name, "desk")
  test.eq(#applied(), 0)
end)

-- ----------------------------------------------------------------- the tool --

local OUTPUTS = morf.json.encode {
  { name = "DP-1", make = "Dell", model = "A", serial = "1", active = true, focused = true,
    rect = { x = 0, y = 0, width = 1920, height = 1080 }, scale = 1, transform = "normal",
    current_mode = { width = 1920, height = 1080, refresh = 60000 },
    modes = { { width = 1920, height = 1080, refresh = 60000 } } },
  { name = "DP-2", make = "Dell", model = "B", serial = "2", active = true,
    rect = { x = 1920, y = 0, width = 1920, height = 1080 }, scale = 1, transform = "normal",
    current_mode = { width = 1920, height = 1080, refresh = 60000 },
    modes = { { width = 1920, height = 1080, refresh = 60000 }, { width = 1280, height = 720, refresh = 60000 } } },
}

local function tool()
  test.stub_run("swaymsg", { code = 0, stdout = OUTPUTS })
  test.stub_run("sh", { code = 0 })
  test.load("../apps/displays/app.lua", {
    size = { 1280, 800 },
    env = { SWAYSOCK = "/nonexistent/sway.sock", EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule" },
  })
  test.settle(1000)
end

local function output(state, name)
  for _, o in ipairs(state.outputs) do
    if o.name == name then return o end
  end
end

local function swaymsg_calls()
  local calls = {}
  for _, argv in ipairs(test.runs()) do
    if argv[1] == "swaymsg" and argv[2] ~= "-t" then calls[#calls + 1] = argv[2] end
  end
  return calls
end

local WINDOW = "toplevel:Displays"

test.it("drags a monitor with the pointer, snapping it to the other's edge", function()
  tool()
  local tile = test.get { id = "displays-tile-2" }
  local x, y = tile.x + tile.width / 2, tile.y + tile.height / 2
  test.drag({ x, y }, { x - tile.width, y + tile.height + 4 }, { steps = 6, surface = WINDOW })
  test.settle(200)
  local state = test.ipc("state")
  test.eq(state.selected, "DP-2")
  test.eq(output(state, "DP-2").x, 0)
  test.eq(output(state, "DP-2").y, 1080)
  test.truthy(state.dirty)
end)

test.it("applies, counts down, and reverts by itself", function()
  tool()
  test.ipc("place", "DP-2", "0", "1080")
  test.click { id = "displays-apply" }
  test.settle(200)
  test.eq(test.ipc("state").countdown, 15)
  test.truthy(test.find { id = "displays-keep" }.visible)
  test.contains(swaymsg_calls()[1], "pos 0 1080")
  test.advance(16000)
  test.settle(200)
  local state = test.ipc("state")
  test.eq(state.countdown, 0)
  test.eq(output(state, "DP-2").x, 1920)
  local calls = swaymsg_calls()
  test.contains(calls[#calls], "pos 1920 0")
  test.eq(#test.logs("error"), 0)
end)

test.it("keeps an arrangement in the file a reload reads", function()
  tool()
  test.ipc("place", "DP-2", "0", "1080")
  test.ipc("apply")
  test.settle(200)
  test.click { id = "displays-keep" }
  test.settle(200)
  local state = test.ipc("state")
  test.eq(state.countdown, 0)
  test.falsy(state.dirty)
  test.eq(state.message, "Saved.")
  test.advance(16000)
  test.eq(output(test.ipc("state"), "DP-2").y, 1080)
end)

test.it("refuses an arrangement that cannot work", function()
  tool()
  test.ipc("set", "DP-1", "enabled", "false")
  test.ipc("set", "DP-2", "enabled", "false")
  test.falsy(test.ipc("apply"))
  test.contains(test.ipc("state").message, "at least one")
  test.eq(#swaymsg_calls(), 0)
end)

test.it("saves a profile and offers it", function()
  tool()
  test.truthy(test.ipc("save-profile", "Desk"))
  local state = test.ipc("state")
  test.eq(state.profiles[#state.profiles].name, "Desk")
  test.truthy(state.profiles[#state.profiles].auto)
  test.truthy(test.find { id = "displays-profile-1" })
end)

test.it("hides mirroring where the compositor has none", function()
  tool()
  test.falsy(test.find { id = "displays-mirror" })
end)
