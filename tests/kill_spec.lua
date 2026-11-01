-- eva-kill: the windows read from sway and Hyprland, the box riding onto the one
-- under the pointer, a press ending it the way Force quit does, a finger's second
-- tap, Escape, and `--active`. A real window ended on a real sway is
-- tools/see/kill.steps'. Hyprland here is a stand-in for its socket.
--
--     morf test --no-dbus tests/kill_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local SURFACE = "layer:eva-kill"

local TREE = morf.json.encode {
  type = "root", nodes = { {
    type = "output", name = "__i3", nodes = {
      { id = 3, type = "workspace", name = "__i3_scratch", pid = morf.json.null, rect = { x = 0, y = 0, width = 1280, height = 800 } },
    },
  }, {
    type = "output", name = "HEADLESS-1", nodes = { {
      type = "workspace", visible = true, floating_nodes = {
        { id = 30, type = "floating_con", name = "Float", app_id = "calc", pid = 3,
          rect = { x = 400, y = 300, width = 200, height = 150 } },
      }, nodes = {
        { id = 10, type = "con", name = "Left", app_id = "foot", pid = 1, focused = false,
          rect = { x = 0, y = 0, width = 640, height = 800 } },
        { id = 20, type = "con", name = "Right", app_id = "eva.clock", pid = 2, focused = true,
          rect = { x = 640, y = 0, width = 640, height = 800 } },
      },
    } },
  } },
}

local function env(extra)
  local full = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" }
  for key, value in pairs(extra or {}) do full[key] = value end
  return full
end

local function sway(extra, args)
  test.clear_stubs()
  test.stub_run("swaymsg", { code = 0, stdout = TREE })
  local e = env(extra)
  e.SWAYSOCK = "/stub"
  test.load("../apps/kill/app.lua", { env = e, args = args, size = { 1280, 800 } })
  test.advance(100)
end

local function state() return test.ipc("state") end

test.it("reads sway's windows, the floating one on top", function()
  sway()
  test.eq(state().windows, 3)
  test.ipc("point", "500", "350")
  test.eq(state().hover, "Float")
  test.ipc("point", "100", "350")
  test.eq(state().hover, "Left")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it("rides a box onto the window, its title on a chip, in " .. style, function()
    sway { EVA_STYLE = style }
    test.ipc("point", "900", "300")
    test.settle(1500)
    local box = test.get("kill-box")
    test.near(box.x, 640, 2)
    test.near(box.width, 640, 2)
    test.eq(test.get("kill-title").text, "Right")
    test.eq(test.get("kill-field").element, "Sdf")
    test.eq(test.get("kill-window").parent, test.get("kill-field").handle)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("moves the box on a spring, not at once", function()
  sway()
  test.ipc("point", "100", "300")
  test.settle(1500)
  test.ipc("point", "900", "300")
  test.advance(32)
  local box = test.get("kill-box")
  test.truthy(box.x > 1 and box.x < 639, "it jumped to " .. box.x)
end)

test.it("a click ends the window through swaymsg, held back when dry", function()
  sway()
  test.click(100, 300, { surface = SURFACE })
  test.advance(16)
  test.eq(state().ended, "Left")
  test.truthy(state().leaving)
  for _, argv in ipairs(test.runs()) do test.falsy(argv[2] and argv[2]:find("kill", 1, true), "ran " .. argv[2]) end
end)

test.it("spells sway's kill by the container's id", function()
  test.clear_stubs()
  test.stub_run("swaymsg", { code = 0, stdout = TREE })
  test.load("../apps/kill/app.lua", { env = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule",
    SWAYSOCK = "/stub" }, size = { 1280, 800 } })
  test.advance(100)
  test.click(900, 300, { surface = SURFACE })
  test.advance(100)
  local runs = test.runs()
  test.eq(runs[#runs], { "swaymsg", "[con_id=20] kill" })
end)

test.it("Escape cancels, and a second launch too", function()
  sway()
  test.click(5, 5, { surface = SURFACE, button = "right" })
  test.key("Escape")
  test.truthy(state().leaving)
  test.eq(state().ended, "")
  sway()
  test.ipc("eva-raise")
  test.truthy(state().leaving)
  test.eq(state().ended, "")
end)

test.it("a press on nothing ends nothing", function()
  test.clear_stubs()
  test.stub_run("swaymsg", { code = 0, stdout = "{}" })
  test.load("../apps/kill/app.lua", { env = env { SWAYSOCK = "/stub" }, size = { 1280, 800 } })
  test.advance(100)
  test.click(100, 100, { surface = SURFACE })
  test.eq(state().ended, "")
  test.falsy(state().leaving)
  test.contains(test.text_of(test.get("kill-hint")), "No windows")
end)

test.it("a finger needs a second tap, the first shows what it would end", function()
  sway()
  test.touch("down", 1, 100, 300, { surface = SURFACE })
  test.touch("up", 1, 100, 300, { surface = SURFACE })
  test.eq(state().ended, "")
  test.truthy(state().armed)
  test.eq(test.get("kill-title").text, "Tap again to end it")
  test.touch("down", 1, 900, 300, { surface = SURFACE })
  test.touch("up", 1, 900, 300, { surface = SURFACE })
  test.eq(state().ended, "", "a tap on another window ended it")
  test.touch("down", 1, 900, 300, { surface = SURFACE })
  test.touch("up", 1, 900, 300, { surface = SURFACE })
  test.eq(state().ended, "Right")
end)

test.it("--active ends the focused window with no overlay", function()
  sway({}, { "--active" })
  test.eq(state().ended, "Right")
  test.falsy(test.find { id = "kill-area" })
end)

local HYPR = [[
  local hypr = require("lib.compositor.hyprland")
  local sent = {}
  hypr.json = function(command, cb)
    if command == "monitors" then cb({ { activeWorkspace = { id = 1 } } }) end
    if command == "clients" then
      cb({ { mapped = true, hidden = false, at = { 100, 50 }, size = { 800, 600 }, workspace = { id = 1 },
        focusHistoryID = 0, title = "Editor", class = "foot", address = "0xabc" } })
    end
    return true
  end
  hypr.dispatch = function(name, arg, cb) sent[#sent + 1] = name .. " " .. tostring(arg) if cb then cb(true, "ok") end return true end
  hypr.eval = function(chunk, cb) sent[#sent + 1] = chunk if cb then cb("ok") end return true end
  package.loaded["lib.compositor.hyprland_config"] = { flavour = function(cb) cb(FLAVOUR) end }
  morf.ipc.sent = function() return sent end
]]

local function hyprland(flavour, args)
  test.clear_stubs()
  test.stub_run("hyprctl", { code = 0, stdout = "200, 200\n" })
  local source = "FLAVOUR = " .. ("%q"):format(flavour) .. HYPR .. morf.fs.read(ROOT .. "apps/kill/app.lua")
  test.load("../apps/kill/app.lua", { source = source, args = args, size = { 1280, 800 },
    env = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", HYPRLAND_INSTANCE_SIGNATURE = "stub" } })
  test.advance(100)
end

test.it("sends Force quit's dispatch on a classic Hyprland, by address", function()
  hyprland("hyprlang")
  test.eq(state().hover, "Editor", "the start position does not pick the window")
  test.ipc("kill")
  test.advance(16)
  test.eq(test.ipc("sent"), { "focuswindow address:0xabc", "killwindow address:0xabc" })
end)

test.it("sends Force quit's dispatch on a Lua Hyprland", function()
  hyprland("lua")
  test.ipc("kill")
  test.advance(16)
  test.contains(test.ipc("sent")[1], 'hl.dsp.window.kill({ window = "address:0xabc" })')
end)

test.it("--active reads the focused window of Hyprland", function()
  hyprland("hyprlang", { "--active" })
  test.eq(test.ipc("sent"), { "focuswindow address:0xabc", "killwindow address:0xabc" })
end)
