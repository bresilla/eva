-- eva-startup: the autostart spec's rule on real files under a scratch XDG
-- folder, the launcher's list of apps, the timers from a stub of systemctl, and
-- the command line.
--
--     morf test --no-dbus tests/startup_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local serial = 0
local function fresh()
  serial = serial + 1
  local root = morf.env("XDG_STATE_HOME") .. "/startup-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(root .. "/config/autostart", { parents = true })
  morf.fs.mkdir(root .. "/system/autostart", { parents = true })
  morf.fs.mkdir(root .. "/data/applications", { parents = true })
  morf.fs.write(root .. "/system/autostart/applet.desktop",
    "[Desktop Entry]\nType=Application\nName=Applet\nComment=In the tray\nExec=applet\n")
  morf.fs.write(root .. "/config/autostart/mine.desktop", "[Desktop Entry]\nType=Application\nName=Mine\nExec=mine --go\n")
  morf.fs.write(root .. "/data/applications/editor.desktop",
    "[Desktop Entry]\nType=Application\nName=Editor\nComment=Writes\nExec=editor %F\nIcon=accessories-text-editor\n")
  return root
end

local function environment(root, more)
  local full = { XDG_CONFIG_HOME = root .. "/config", XDG_CONFIG_DIRS = root .. "/system", XDG_DATA_HOME = root .. "/data",
    XDG_DATA_DIRS = root .. "/nothing", XDG_STATE_HOME = root .. "/state", EVA_SETTINGS = "/nonexistent/eva.json",
    LULE_A = "/nonexistent/lule", EVA_FAKE_STARTUP = "1" }
  for key, value in pairs(more or {}) do full[key] = value end
  return full
end

local function window(style, root, more)
  root = root or fresh()
  local appearance = root .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style or "material", font = "" })
  test.load("../apps/startup/app.lua", { env = environment(root, { EVA_APPEARANCE = appearance }), size = nil })
  test.settle(400)
  return root
end

local function row(id)
  for _, entry in ipairs(test.ipc("state").rows) do
    if entry.id == id .. ".desktop" then return entry end
  end
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("lists the user's and the system's entries, in " .. style, function()
    window(style)
    test.truthy(row("applet").enabled)
    test.eq(row("applet").origin, "system")
    test.eq(row("mine").origin, "user")
    test.eq(test.get("startup-name-1").text, "Applet")
    test.contains(test.get("startup-note-1").text, "· system")
    test.eq(#test.logs("error"), 0)
  end)

  test.it("the switch writes the override, in " .. style, function()
    local root = window(style)
    test.click("startup-switch-1")
    test.settle(200)
    test.falsy(row("applet").enabled)
    test.contains(morf.fs.read(root .. "/config/autostart/applet.desktop"), "Hidden=true")
  end)
end

test.it("disabling a system entry never writes the system's file", function()
  local root = window()
  local before = morf.fs.read(root .. "/system/autostart/applet.desktop")
  test.truthy(test.ipc("disable", "applet"))
  test.eq(morf.fs.read(root .. "/system/autostart/applet.desktop"), before)
  local override = morf.fs.read(root .. "/config/autostart/applet.desktop")
  test.contains(override, "Hidden=true")
  test.contains(override, "Exec=applet")
  test.eq(row("applet").origin, "user")
  test.eq(row("applet").over, root .. "/system/autostart/applet.desktop")
end)

test.it("enabling it again takes the override away", function()
  local root = window()
  test.ipc("disable", "applet")
  test.truthy(test.ipc("enable", "applet"))
  test.falsy(morf.fs.exists(root .. "/config/autostart/applet.desktop"))
  test.truthy(row("applet").enabled)
  test.eq(row("applet").origin, "system")
end)

test.it("keeps what a person changed in an override", function()
  local root = fresh()
  morf.fs.write(root .. "/config/autostart/applet.desktop",
    "[Desktop Entry]\nType=Application\nName=Applet\nExec=applet --quiet\nHidden=true\n")
  window(nil, root)
  test.falsy(row("applet").enabled)
  test.ipc("enable", "applet")
  local text = morf.fs.read(root .. "/config/autostart/applet.desktop")
  test.contains(text, "Exec=applet --quiet")
  test.eq(text:find("Hidden", 1, true), nil)
  test.truthy(row("applet").enabled)
end)

test.it("reads a bare override by the system's name", function()
  local root = fresh()
  morf.fs.write(root .. "/config/autostart/applet.desktop", "[Desktop Entry]\nHidden=true\n")
  window(nil, root)
  test.eq(row("applet").name, "Applet")
  test.falsy(row("applet").enabled)
end)

test.it("takes GNOME's switch as off too", function()
  local root = fresh()
  morf.fs.write(root .. "/config/autostart/old.desktop",
    "[Desktop Entry]\nType=Application\nName=Old\nExec=old\nX-GNOME-Autostart-enabled=false\n")
  window(nil, root)
  test.falsy(row("old").enabled)
  test.ipc("enable", "old")
  test.truthy(row("old").enabled)
  test.eq(morf.fs.read(root .. "/config/autostart/old.desktop"):find("GNOME", 1, true), nil)
end)

test.it("removes a person's own entry, and offers no such thing for a system's", function()
  local root = window()
  test.falsy(test.find { id = "startup-delete-1", visible = true })
  test.click("startup-delete-2")
  test.settle(200)
  test.falsy(morf.fs.exists(root .. "/config/autostart/mine.desktop"))
  test.eq(#test.ipc("state").rows, 1)
end)

test.it("adds an app from the launcher's own list", function()
  local root = fresh()
  test.load("../apps/startup/app.lua", { env = environment(root, { TEST_APPS = root .. "/data/applications" }), source = [[
    local morf = require("morf")
    morf.apps = { entries = function()
      return {
        applications = function()
          return { { id = "editor.desktop", name = "Editor", comment = "Writes", source = morf.env("TEST_APPS") } }
        end,
        refresh = function() return false end,
      }
    end }
    require("app")
  ]] })
  test.settle(400)
  test.ipc("tab", "add")
  test.settle(400)
  test.eq(test.ipc("search", "edit"), 1)
  test.settle(100)
  test.click("startup-pick-1")
  test.settle(200)
  test.contains(morf.fs.read(root .. "/config/autostart/editor.desktop"), "Exec=editor %F")
  test.truthy(row("editor").enabled)
  test.contains(test.ipc("state").message, "starts with the session")
end)

test.it("adds a command of a person's own", function()
  local root = window()
  test.truthy(test.ipc("command", "My Backup!", "rsync -a ~/notes /mnt"))
  local text = morf.fs.read(root .. "/config/autostart/eva-my-backup.desktop")
  test.contains(text, "Exec=rsync -a ~/notes /mnt")
  test.contains(text, "Name=My Backup!")
  test.falsy(test.ipc("command", "", "nothing"))
  test.contains(test.ipc("state").message, "name and a command")
end)

test.it("touches no file under a dry run", function()
  local root = fresh()
  local appearance = root .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = "material", font = "" })
  test.load("../apps/startup/app.lua", { env = environment(root, { EVA_APPEARANCE = appearance, EVA_DRY_RUN = "1" }) })
  test.settle(300)
  test.ipc("disable", "applet")
  test.falsy(morf.fs.exists(root .. "/config/autostart/applet.desktop"))
end)

-- --------------------------------------------------------------------- timers --

local TIMERS = morf.json.encode {
  { unit = "backup.timer", activates = "backup.service", next = 1793620800000000, last = 1793530000000000 },
  { unit = "eva-alarm-abc.timer", activates = "eva-alarm-abc.service", next = 1793617200000000, last = 0 },
  { unit = "never.timer", activates = "never.service" },
}

test.it("lists the timers soonest first, and shows eva's alarms as such", function()
  local root = fresh()
  morf.fs.write(root .. "/state/eva/clock/alarms.json", morf.json.encode {
    { id = "abc", kind = "alarm", label = "gym", on = true, hour = 7, minute = 30, at = 1793617200 },
  }, { parents = true })
  test.clear_stubs()
  test.stub_run("systemctl", { code = 0, stdout = TIMERS })
  test.load("../apps/startup/app.lua", { env = environment(root, { EVA_FAKE_STARTUP = false }) })
  test.settle(400)
  local rows = test.ipc("state").timers
  test.eq(rows[1].name, "eva-alarm-abc")
  test.contains(rows[1].alarm, "gym")
  test.eq(rows[2].name, "backup")
  test.eq(rows[3].name, "never")
  test.ipc("tab", "scheduled")
  test.settle(300)
  test.contains(test.get("startup-timer-1").text, "gym")
  test.contains(test.get("startup-timer-note-1").text, "Clock · Next")
  test.contains(test.get("startup-timer-note-3").text, "Next never")
  test.clear_stubs()
end)

test.it("says so where there is no user session of systemd", function()
  test.clear_stubs()
  test.stub_run("systemctl", { code = 1 })
  test.load("../apps/startup/app.lua", { env = environment(fresh(), { EVA_FAKE_STARTUP = false }) })
  test.settle(300)
  test.eq(test.ipc("state").scheduled, "none")
  test.clear_stubs()
end)

-- ------------------------------------------------------------- desktop files --

test.it("changes one key and leaves the rest of the file", function()
  test.load("../shell/init.lua", { source = [[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local desktop = require("lib.util.desktop")
    morf.ipc.set = function(text, key, value) return desktop.set(text, key, value ~= "" and value or nil) end
    morf.ipc.parse = function(text) return desktop.parse(text) end
    morf.ipc.exec = function(...) return desktop.exec({ ... }) end
  ]] })
  local text = "# note\n[Desktop Entry]\nName=A\nName[de]=B\n\n[Desktop Action x]\nName=C\nHidden=true\n"
  test.eq(test.ipc("set", text, "Hidden", "true"),
    "# note\n[Desktop Entry]\nName=A\nName[de]=B\nHidden=true\n\n[Desktop Action x]\nName=C\nHidden=true\n")
  test.eq(test.ipc("set", text, "Name", "Z"),
    "# note\n[Desktop Entry]\nName=Z\nName[de]=B\n\n[Desktop Action x]\nName=C\nHidden=true\n")
  test.eq(test.ipc("set", text, "Name", ""), "# note\n[Desktop Entry]\nName[de]=B\n\n[Desktop Action x]\nName=C\nHidden=true\n")
  test.eq(test.ipc("parse", text).Hidden, nil)
  test.eq(test.ipc("parse", text).Name, "A")
  test.eq(test.ipc("parse", "[Desktop Entry]\nName=a\\nb\\\\c\n").Name, "a\nb\\c")
  test.eq(test.ipc("exec", "chromium", "--app=https://a.test/x?y=1&z=50%"), 'chromium "--app=https://a.test/x?y=1&z=50%%"')
  test.eq(test.ipc("exec", "say", 'a "b" $c'), 'say "a \\"b\\" \\$c"')
end)

-- --------------------------------------------------------------------- jobs --

local function job(root, args, more)
  local out = root .. "/answer"
  morf.fs.remove(out)
  local env = environment(root, more)
  env.EVA_JOB_OUT = out
  test.clear_stubs()
  test.load("../apps/startup/app.lua", { args = args, env = env })
  test.settle(200)
  return morf.fs.read(out) or ""
end

test.it("list, disable and enable by file or by name", function()
  local root = fresh()
  test.contains(job(root, { "list" }), "on  applet")
  test.contains(job(root, { "disable", "Applet" }), "off applet")
  test.contains(morf.fs.read(root .. "/config/autostart/applet.desktop"), "Hidden=true")
  test.contains(job(root, { "enable", "applet" }), "on  applet")
end)

test.it("says what it cannot find or may not do", function()
  local root = fresh()
  test.contains(job(root, { "enable", "nothing" }), "1\nnothing called nothing")
  test.contains(job(root, { "remove", "applet" }), "1\nApplet belongs to the system")
  test.contains(job(root, { "sideways" }), "1\nunknown command")
end)

test.it("timers answers from the stand-in", function()
  test.contains(job(fresh(), { "timers" }), "eva-alarm-a1b2c3")
end)

local function cli(args)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/startup-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "sh", ROOT .. "apps/startup/cli" }
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.clear_stubs()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", test.ipc("result")
end

test.it("the command line asks the tool's own job", function()
  test.contains(cli { "disable", "x" }, "app " .. ROOT .. "apps/startup/app.lua -- disable x")
end)
