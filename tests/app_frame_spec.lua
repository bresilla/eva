-- The frame every tool opens in: the shell's theme and palette, colours from
-- lule, and apps/launch finding the shell's files. The appearance changing
-- under a running window is tools/see/keys-tool.steps'.
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

test.it("refuses a tool that is not there", function()
  launcher_host()
  test.ipc("run", "sh", ROOT .. "apps/launch", "nothing")
  local result = test.wait(function() return test.ipc("result") end, 5000, "the launcher answered")
  test.falsy(result.ok)
  test.contains(result.stderr, "no tool nothing")
end)
