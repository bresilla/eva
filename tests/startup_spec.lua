-- Startup: Settings' Startup apps page on real files under a scratch XDG folder,
-- a command of one's own and the timers from a stub of systemctl; the desktop
-- files' rule; and `eva-startup`, a job on the page's own code.
--
--     morf test --no-dbus tests/startup_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local JOB = "../apps/common/job/app.lua"

local serial = 0
local function fresh()
  serial = serial + 1
  local root = morf.env("XDG_STATE_HOME") .. "/startup-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(root .. "/config/autostart", { parents = true })
  morf.fs.mkdir(root .. "/system/autostart", { parents = true })
  morf.fs.mkdir(root .. "/state/eva/clock", { parents = true })
  morf.fs.write(root .. "/system/autostart/applet.desktop",
    "[Desktop Entry]\nType=Application\nName=Applet\nComment=In the tray\nExec=applet\n")
  morf.fs.write(root .. "/config/autostart/mine.desktop", "[Desktop Entry]\nType=Application\nName=Mine\nExec=mine --go\n")
  morf.fs.write(root .. "/state/eva/clock/alarms.json",
    '[{"id":"a1b2c3","kind":"alarm","label":"gym","on":true,"hour":7,"minute":30,"days":[1,3,5],"at":1793613600}]')
  return root
end

local function environment(root, more)
  local full = { XDG_CONFIG_HOME = root .. "/config", XDG_CONFIG_DIRS = root .. "/system",
    XDG_STATE_HOME = root .. "/state", EVA_SETTINGS = root .. "/eva.json", LULE_A = "/nonexistent/lule" }
  for key, value in pairs(more or {}) do full[key] = value end
  return full
end

-- What systemctl says of the user's timers, one of them an alarm of eva's.
local function timers()
  local now = math.floor(morf.time.now())
  test.stub_run("systemctl", { code = 0, stdout = morf.json.encode {
    { unit = "mail-sync.timer", activates = "mail-sync.service", next = (now + 240) * 1000000, last = (now - 600) * 1000000 },
    { unit = "eva-alarm-a1b2c3.timer", activates = "eva-alarm-a1b2c3.service", next = (now + 1800) * 1000000, last = 0 },
  } })
end

local function page(style, root)
  root = root or fresh()
  test.clear_stubs()
  timers()
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1600, 1000 }, env = environment(root, { EVA_STYLE = style,
    HOME = morf.env("XDG_CACHE_HOME"), EVA_WALLPAPER = "" }) })
  test.settle(1000)
  test.ipc("settings", "startup") test.settle(1500)
  return root
end

-- The Settings window's page wheeled until `id` stands in it.
local function reach(id)
  for _ = 1, 40 do
    local node, pane = test.find { id = id, visible = true }, test.get("settings-detail")
    if node and node.y > pane.y and node.y + node.height < pane.y + pane.height then return id end
    test.wheel(0, 120, { x = pane.x + pane.width / 2, y = pane.y + pane.height / 2 }) test.advance(200)
  end
  return id
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("lists the user's and the system's entries, and the timers, in " .. style, function()
    page(style)
    test.truthy(test.find { text = "Applet", visible = true })
    test.truthy(test.find { text = "Mine", visible = true })
    test.truthy(test.find { text_contains = "gym", visible = true } or test.find { id = "startup-timer-row-1" },
      "no alarm among the timers")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("starts a command of a person's own with the session", function()
  local root = page("material")
  test.click(reach("startup-command-name")) test.type("Night backup") test.advance(50)
  test.click(reach("startup-command")) test.type("rsync -a ~/notes /mnt/backup") test.advance(50)
  test.click(reach("startup-command-add")) test.settle(300)
  local text = morf.fs.read(root .. "/config/autostart/eva-night-backup.desktop") or ""
  test.contains(text, "Name=Night backup")
  test.contains(text, "Exec=rsync -a ~/notes /mnt/backup")
end)

test.it("shows its scheduled jobs soonest first, eva's alarms by what they are", function()
  page("material")
  test.truthy(test.find { text = "mail-sync" }, "the first timer is not listed")
  test.contains(test.get("startup-timer-row-1-title").text, "mail-sync")
end)

test.it("says so where there is no user session of systemd", function()
  local root = fresh()
  test.clear_stubs()
  test.stub_run("systemctl", { code = 1, stderr = "Failed to connect to bus" })
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1600, 1000 }, env = environment(root, { HOME = morf.env("XDG_CACHE_HOME") }) })
  test.settle(1000)
  test.ipc("settings", "startup") test.settle(1500)
  test.truthy(test.find { id = "startup-timers-none" }.visible)
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

local function job(root, args)
  local out = root .. "/answer"
  morf.fs.remove(out)
  local env = environment(root)
  env.EVA_JOB_OUT = out
  local words = { "startup" }
  for _, word in ipairs(args) do words[#words + 1] = word end
  test.clear_stubs()
  timers()
  test.load(JOB, { args = words, env = env })
  test.settle(200)
  return morf.fs.read(out) or ""
end

test.it("list, disable and enable by file or by name", function()
  local root = fresh()
  test.contains(job(root, { "list" }), "on  applet")
  test.contains(job(root, { "disable", "Applet" }), "off applet")
  test.contains(morf.fs.read(root .. "/config/autostart/applet.desktop"), "Hidden=true")
  test.falsy(morf.fs.read(root .. "/system/autostart/applet.desktop"):find("Hidden", 1, true), "the system's file was written")
  test.contains(job(root, { "enable", "applet" }), "on  applet")
end)

test.it("says what it cannot find or may not do", function()
  local root = fresh()
  test.contains(job(root, { "enable", "nothing" }), "1\nnothing called nothing")
  test.contains(job(root, { "remove", "applet" }), "1\nApplet belongs to the system")
  test.contains(job(root, { "sideways" }), "1\nunknown command")
end)

test.it("removes a person's own entry", function()
  local root = fresh()
  test.contains(job(root, { "remove", "mine" }), "0\nremoved")
  test.falsy(morf.fs.exists(root .. "/config/autostart/mine.desktop"))
end)

test.it("timers lists the scheduled jobs, eva's alarms by what they are", function()
  local text = job(fresh(), { "timers" })
  test.contains(text, "mail-sync")
  test.contains(text, "eva-alarm-a1b2c3 (")
end)

local function cli(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/startup-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-startup"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.clear_stubs()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", test.ipc("result")
end

test.it("the command line runs the page's own code as a job", function()
  test.contains(cli { "disable", "x" }, "app " .. ROOT .. "apps/common/job/app.lua -- startup disable x")
end)

test.it("alone it opens Startup apps in the Settings window", function()
  test.contains(cli({}, { "STUB_UP=1" }), "ipc call settings startup")
end)

test.it("its help is its header", function()
  local _, result = cli { "--help" }
  test.contains(result.stdout, "eva-startup timers")
end)
