-- The frame every tool opens in: the shell's theme, palette and distance field,
-- colours from lule, apps/launch finding the shell's files and keeping one
-- window. The appearance changing under a running window is
-- tools/see/keys-tool.steps'.
--
--     morf test --no-dbus tests/app_frame_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local STATE = morf.env("XDG_STATE_HOME")

local function lule(mode)
  local dir = STATE .. "/frame-lule-" .. mode
  morf.fs.mkdir(dir)
  local text = morf.fs.read(ROOT .. "tests/fixtures/lule-colors.json")
    :gsub("@WALLPAPER@", ROOT .. "tests/fixtures/wallpaper.png"):gsub("@MODE@", mode)
  morf.fs.write(dir .. "/colors.json", text)
  return dir
end

local function appearance(style, name)
  local path = STATE .. "/" .. (name or "frame-appearance.json")
  morf.fs.write(path, morf.json.encode { theme = style, font = "" })
  return path
end

local function tool(style, mode, name)
  test.stub_run("hyprctl", { code = 1 })
  local path = appearance(style, name)
  test.load("../apps/keys/app.lua", {
    env = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = lule(mode), EVA_APPEARANCE = path, EVA_THEME_MODE = mode },
  })
  test.settle(800)
  return path
end

for _, style in ipairs { "material", "tsugumori" } do
  for _, mode in ipairs { "dark", "light" } do
    test.it("opens in " .. style .. ", " .. mode, function()
      tool(style, mode, "frame-" .. style .. "-" .. mode .. ".json")
      local look = test.ipc("eva-app")
      test.eq(look.theme, style)
      test.eq(#test.logs("error"), 0)
      test.truthy(test.find { id = "keys-close" })
    end)
  end
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("draws one field with the shell's seams in " .. style, function()
    test.stub_run("hyprctl", { code = 1 })
    local spy = [[
      local ui = require("morf.ui")
      local make, shape = ui.Sdf, ui.SdfShape
      local field, tabs = {}, {}
      ui.Sdf = function(props)
        if props.id == "keys-frame" then field = { blend = props.blend, profile = props.blend_profile } end
        return make(props)
      end
      ui.SdfShape = function(props)
        if props.track then tabs[#tabs + 1] = { operation = props.operation, group = props.blend_group } end
        return shape(props)
      end
      morf.ipc.field = function() return { field = field, tabs = tabs } end
    ]]
    test.load("../apps/keys/app.lua", {
      source = spy .. morf.fs.read(ROOT .. "apps/keys/app.lua"),
      env = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = lule("dark"), EVA_THEME_MODE = "dark",
        EVA_APPEARANCE = appearance(style, "frame-field-" .. style .. ".json") },
    })
    test.settle(800)
    local seen = test.ipc("field")
    test.eq(seen.field.blend, style == "material" and 25 or 0)
    if style == "material" then test.eq(seen.field.profile, "circular") end
    test.eq(#seen.tabs, 2)
    test.eq(seen.tabs[1].operation, "smooth_union")
    test.eq(seen.tabs[2].operation, "smooth_union")
    test.falsy(seen.tabs[1].group == seen.tabs[2].group)
    test.truthy(test.find { id = "keys-opening" })
  end)

  test.it("keeps the title tab clear of the close tab in " .. style, function()
    tool(style, "dark", "frame-tabs-" .. style .. ".json")
    local left, right = test.get { id = "keys-title-tab" }, test.get { id = "keys-close-tab" }
    test.truthy(left.x + left.width < right.x)
    test.truthy(math.abs(right.x + right.width - test.get({ id = "keys-root" }).width) < 1)
  end)
end

test.it("a second launch has an answer", function()
  tool("material", "dark", "frame-raise.json")
  test.eq(test.ipc("eva-raise"), false)
end)

test.it("takes its colours from lule, dark or light", function()
  tool("material", "dark", "frame-colours-dark.json")
  local dark = test.ipc("eva-app").primary
  test.falsy(dark == "#ffb0ca")
  tool("material", "light", "frame-colours-light.json")
  local light = test.ipc("eva-app").primary
  test.falsy(light == dark)
end)

-- --------------------------------------------------------------- the launcher --

local function launch(env)
  local state = STATE .. "/launch-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  local log = state .. "/calls.log"
  morf.fs.write(log, "")
  if env then env(state) end
  local argv = { "env", "-u", "EVA_SETTINGS", "-u", "EVA_APPEARANCE", "MORF=" .. ROOT .. "tests/fixtures/bin/morf",
    "STUB_LOG=" .. log, "HOME=" .. state, "XDG_STATE_HOME=" .. state }
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/launch"
  argv[#argv + 1] = "keys"
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 5000, "the launcher answered")
  return result, morf.fs.read(log) or "", state
end

local function launcher_host()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
end

test.it("runs a tool as an application", function()
  launcher_host()
  local result, calls = launch()
  test.truthy(result.ok)
  test.contains(calls, "app " .. ROOT .. "apps/keys/app.lua")
end)

test.it("finds the settings the shell named", function()
  launcher_host()
  local _, calls = launch(function(state)
    morf.fs.mkdir(state .. "/eva")
    morf.fs.write(state .. "/eva/settings-path", "/named/by/the/shell.json")
  end)
  test.contains(calls, "EVA_SETTINGS=/named/by/the/shell.json")
end)

test.it("falls back on the newest settings the shell left", function()
  launcher_host()
  local _, calls = launch(function(state)
    morf.fs.mkdir(state .. "/morf/shell-abc")
    morf.fs.write(state .. "/morf/shell-abc/eva.json", "{}")
  end)
  test.contains(calls, "/morf/shell-abc/eva.json")
end)

test.it("finds the appearance the shell keeps", function()
  launcher_host()
  local _, calls = launch(function(state)
    morf.fs.mkdir(state .. "/eva/appearance")
    morf.fs.write(state .. "/eva/appearance/appearance.json", "{}")
  end)
  test.contains(calls, "/eva/appearance/appearance.json")
end)

-- The launcher with a window of the tool already open: `sh -c` holds the
-- tool's path in its arguments, as morf would.
local function second_launch(args)
  launcher_host()
  local state = STATE .. "/guard-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  local log, run = state .. "/calls.log", state .. "/run"
  morf.fs.mkdir(run)
  morf.fs.write(log, "")
  local holder = morf.process.spawn { command = { "sh", "-c", "sleep 30; :", ROOT .. "apps/keys/app.lua" } }
  morf.fs.mkdir(run .. "/eva")
  morf.fs.write(run .. "/eva/keys.window", tostring(holder:pid()))
  local argv = { "env", "-u", "EVA_SETTINGS", "-u", "EVA_APPEARANCE", "MORF=" .. ROOT .. "tests/fixtures/bin/morf",
    "STUB_LOG=" .. log, "HOME=" .. state, "XDG_STATE_HOME=" .. state, "XDG_RUNTIME_DIR=" .. run,
    "WAYLAND_DISPLAY=wayland-9", "sh", ROOT .. "apps/launch", "keys" }
  for _, word in ipairs(args or {}) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 5000, "the launcher answered")
  local calls = morf.fs.read(log) or ""
  holder:kill("KILL")
  return result, calls, holder:pid()
end

test.it("a second launch raises the first and starts nothing", function()
  local result, calls, pid = second_launch()
  test.truthy(result.ok)
  test.contains(calls, "-i wayland-9-app-" .. pid .. " ipc call eva-raise")
  test.falsy(calls:find(" app ", 1, true))
end)

test.it("a job with arguments runs beside the window", function()
  local result, calls = second_launch { "--watch" }
  test.truthy(result.ok)
  test.contains(calls, "app " .. ROOT .. "apps/keys/app.lua -- --watch")
end)

test.it("a window that ended leaves no guard behind", function()
  launcher_host()
  local result, calls = launch(function(state)
    morf.fs.mkdir(state .. "/run")
  end)
  test.truthy(result.ok)
  test.contains(calls, "app " .. ROOT .. "apps/keys/app.lua")
  local again = launch()
  test.truthy(again.ok)
end)

test.it("refuses a tool that is not there", function()
  launcher_host()
  test.ipc("run", "sh", ROOT .. "apps/launch", "nothing")
  local result = test.wait(function() return test.ipc("result") end, 5000, "the launcher answered")
  test.falsy(result.ok)
  test.contains(result.stderr, "no tool nothing")
end)
