-- Updates: a flake.lock read and aged, where it is looked for, the package
-- managers' answers, a rebuild's log dry and through a stand-in pkexec, on
-- Settings' Updates page, and `eva-update --check`. No spec runs a rebuild:
-- every path here is the canned log or a stand-in.
--
--     morf test --no-dbus tests/update_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local PKEXEC = ROOT .. "tests/fixtures/bin-see/pkexec"
-- Monday 2 November 2026, 10:00 UTC.
local NOW = 1793613600
local DAY = 86400
local serial = 0

local function folder(name)
  serial = serial + 1
  local path = morf.env("XDG_STATE_HOME") .. "/update-" .. name .. "-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(path)
  return path
end

local function lock(path)
  local text = morf.json.encode {
    root = "root", version = 7,
    nodes = {
      root = { inputs = { nixpkgs = "nixpkgs_2", home = "home-manager", local_tree = "tree", follows = { "nixpkgs" } } },
      nixpkgs_2 = { locked = { lastModified = NOW - 200 * DAY, owner = "NixOS", repo = "nixpkgs", rev = "abcdef1234567", type = "github" } },
      ["home-manager"] = { locked = { lastModified = NOW - 40 * DAY, owner = "nix-community", repo = "home-manager", rev = "1234567abcdef", type = "github" } },
      tree = { locked = { lastModified = NOW - DAY / 2, type = "git", url = "https://example.test/tree.git", rev = "feedbeef12345" } },
      inner = { locked = { lastModified = 1, owner = "x", repo = "y", rev = "000", type = "github" } },
    },
  }
  morf.fs.write(path .. "/flake.lock", text, { parents = true })
  return path .. "/flake.lock"
end

local function env(extra)
  local out = { EVA_DRY_RUN = "1", EVA_NOW = tostring(NOW), EVA_SETTINGS = "/nonexistent/eva.json" }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

local function quiet_managers()
  test.stub_run("checkupdates", { code = 127, error_kind = "not_found" })
  test.stub_run("apt", { code = 127, error_kind = "not_found" })
  test.stub_run("dnf", { code = 127, error_kind = "not_found" })
  test.stub_run("flatpak", { code = 127, error_kind = "not_found" })
end

local function nixos(path)
  morf.fs.mkdir(path .. "/run")
  morf.fs.write(path .. "/run/current-system", "")
  return path
end

-- The shell on Settings' Updates page, its model at hand.
local HOST = [[
  require("init")
  local model = require("system_updates")
  morf.ipc.state = function()
    local log = {}
    for index = 1, math.min(model.rows:len(), 60) do log[index] = model.rows:get(index).text end
    return { nixos = model.nixos:get(), flake = model.flake:get(), inputs = model.inputs:get(), managers = model.managers:get(),
      state = model.state:get(), message = model.message:get(), lines = model.lines:get(), log = log, argv = model.argv(),
      pending = model.pending() }
  end
  morf.ipc.rebuild = function() return model.rebuild() end
  morf.ipc.cancel = function() return model.cancel() end
]]

local function tool(extra, source, size)
  test.stub_run("task", { code = 0, stdout = "[]" })
  local all = env(extra)
  all.HOME = morf.env("XDG_CACHE_HOME")
  test.load("../shell/init.lua", { env = all, source = (source or "") .. HOST, size = size or { 1600, 1000 } })
  test.settle(300)
  test.ipc("settings", "updates")
  test.settle(800)
end

test.it("reads a flake's own inputs, the oldest first", function()
  local root = nixos(folder("inputs"))
  quiet_managers()
  tool { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = lock(root) }
  local state = test.ipc("state")
  test.eq(#state.inputs, 3)
  test.eq(state.inputs[1].name, "nixpkgs")
  test.eq(state.inputs[1].source, "github:NixOS/nixpkgs")
  test.eq(state.inputs[1].rev, "abcdef1")
  test.eq(state.inputs[2].name, "home")
  test.eq(state.inputs[3].source, "https://example.test/tree.git")
  test.eq(state.pending, 2)
  test.eq(#test.logs("error"), 0)
end)

test.it("says how old each input is, in words", function()
  local root = nixos(folder("age"))
  quiet_managers()
  tool { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = lock(root) }
  test.eq(test.get({ id = "update-input-age-1" }).text, "6 months")
  test.eq(test.get({ id = "update-input-age-2" }).text, "40 days")
  test.eq(test.get({ id = "update-input-age-3" }).text, "Today")
  test.contains(test.get({ id = "update-input-row-1-subtitle" }).text, "github:NixOS/nixpkgs abcdef1")
end)

test.it("takes the lock from the variable, the system, then the setting", function()
  local root = nixos(folder("where"))
  local named = folder("named")
  lock(named)
  quiet_managers()
  tool { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = named }
  test.eq(test.ipc("state").flake, named .. "/flake.lock")

  lock(root .. "/etc/nixos")
  tool { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = false }
  test.eq(test.ipc("state").flake, root .. "/etc/nixos/flake.lock")

  local set = nixos(folder("set"))
  local kept = folder("kept")
  lock(kept)
  local source = ([[
    local config = require("config")
    local real = config.get
    config.get = function(key)
      if key == "update.flake" then return %q end
      return real(key)
    end
  ]]):format(kept)
  tool({ EVA_UPDATE_ROOT = set, EVA_UPDATE_FLAKE = false }, source)
  test.eq(test.ipc("state").flake, kept .. "/flake.lock")
end)

test.it("says so when there is no lock, and offers no rebuild", function()
  local root = nixos(folder("none"))
  quiet_managers()
  tool { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = false }
  test.truthy(test.find({ id = "update-no-flake" }).visible)
  test.falsy(test.ipc("rebuild"))
  test.eq(test.ipc("state").state, "idle")
end)

test.it("refuses a file that is no lock", function()
  local root = nixos(folder("broken"))
  morf.fs.write(root .. "/flake.lock", "{ not json")
  quiet_managers()
  tool { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = root }
  test.eq(#test.ipc("state").inputs, 0)
  test.contains(test.ipc("state").message, "no flake.lock")
end)

test.it("counts what each package manager has waiting", function()
  local root = folder("others")
  test.stub_run("checkupdates", { code = 0, stdout = "linux 6.1 -> 6.2\nfirefox 1 -> 2\n" })
  test.stub_run("apt", { code = 0, stdout = "Listing...\nvim/stable 9.0 amd64 [upgradable from: 8.2]\n" })
  test.stub_run("dnf", { code = 100, stdout = "kernel.x86_64 6.2 updates\nvim.x86_64 9.0 updates\nbash.x86_64 5.2 updates\n" })
  test.stub_run("flatpak", { code = 0, stdout = "org.gnome.Calculator\n" })
  tool { EVA_UPDATE_ROOT = root }
  local state = test.ipc("state")
  test.falsy(state.nixos)
  test.eq(state.pending, 7)
  local by = {}
  for _, manager in ipairs(state.managers) do by[manager.name] = manager end
  test.eq(by.pacman.count, 2)
  test.eq(by.pacman.packages[2], "firefox")
  test.eq(by.apt.count, 1)
  test.eq(by.apt.packages[1], "vim")
  test.eq(by.dnf.count, 3)
  test.eq(by.flatpak.count, 1)
  test.falsy(test.find({ id = "update-rebuild" }).visible)
end)

test.it("leaves out the managers this machine lacks", function()
  local root = folder("lacks")
  quiet_managers()
  test.stub_run("flatpak", { code = 0, stdout = "" })
  tool { EVA_UPDATE_ROOT = root }
  local state = test.ipc("state")
  test.eq(#state.managers, 1)
  test.eq(state.managers[1].name, "flatpak")
  test.eq(state.pending, 0)
  test.eq(test.get({ id = "update-note" }).text, "Nothing waits")
end)

test.it("plays a canned log when dry, and builds nothing", function()
  local root = nixos(folder("dry"))
  quiet_managers()
  tool { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = lock(root) }
  test.truthy(test.ipc("rebuild"))
  test.eq(test.ipc("state").state, "running")
  test.truthy(test.find { id = "update-log-section", visible = true }, "the log did not show on the page")
  test.falsy(test.ipc("rebuild"), "a second one is refused")
  test.advance(1000)
  test.settle(100)
  test.contains(test.ipc("state").log[1], "dry run")
  test.advance(8000)
  test.settle(200)
  local state = test.ipc("state")
  test.eq(state.state, "done")
  test.truthy(state.lines > 10)
  test.contains(state.log[#state.log], "Done.")
  test.eq(test.ipc("state").argv[2], "nixos-rebuild")
  for _, run in ipairs(test.runs()) do
    test.ne(run[1], "pkexec", "a dry rebuild ran pkexec")
  end
end)

test.it("stops a canned rebuild part of the way", function()
  local root = nixos(folder("stop"))
  quiet_managers()
  tool { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = lock(root) }
  test.ipc("rebuild")
  test.advance(1000)
  test.truthy(test.ipc("cancel"))
  test.settle(300)
  local state = test.ipc("state")
  test.eq(state.state, "failed")
  test.contains(state.message, "stopped")
  test.falsy(test.ipc("cancel"))
end)

test.it("spawns the rebuild and follows its log when it is not dry", function()
  local root = nixos(folder("real"))
  quiet_managers()
  tool { EVA_DRY_RUN = "0", EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = lock(root), EVA_PKEXEC = PKEXEC }
  test.truthy(test.ipc("rebuild"))
  test.wait(function()
    test.advance(100)
    return test.ipc("state").state ~= "running"
  end, 5000, "the stand-in ended")
  test.settle(300)
  local state = test.ipc("state")
  test.eq(state.state, "done")
  test.contains(table.concat(state.log, "\n"), "would run: nixos-rebuild switch --flake " .. root)
  test.contains(table.concat(state.log, "\n"), "a line on stderr")
end)

test.it("keeps its log bounded", function()
  local root = nixos(folder("bound"))
  quiet_managers()
  local source = [[
    local morf = require("morf")
    local model = require("system_updates")
    model.LIMIT = 40
    morf.ipc.flood = function(count)
      for index = 1, tonumber(count) do model.feed("line " .. index) end
      return true
    end
  ]]
  tool({ EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = lock(root) }, source)
  test.ipc("flood", 500)
  test.advance(300)
  test.settle(100)
  test.eq(test.ipc("state").lines, 40)
  test.eq(test.ipc("state").log[40], "line 500")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " fits a phone", function()
    local root = nixos(folder("phone"))
    quiet_managers()
    tool({ EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = lock(root), EVA_STYLE = style }, nil, { 380, 800 })
    local button = test.get { id = "update-rebuild" }
    test.truthy(button.x + button.width <= 380, "the button runs off the side")
    test.truthy(button.y + button.height <= 800, "the button runs off the foot")
    test.ipc("rebuild")
    test.advance(2000)
    test.settle(200)
    test.eq(#test.logs("error"), 0)
  end)
end

-- ---------------------------------------------------------- the command line --

local function cli(args, up)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/update-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  if up then argv[#argv + 1] = "STUB_UP=1" end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-update"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", result
end

test.it("asks the shell's own code for the count, with no window", function()
  test.contains(cli { "--check" }, "apps/common/job/app.lua -- update --check")
end)

test.it("alone it opens Updates in the Settings window", function()
  test.contains(cli({}, true), "ipc call settings updates")
end)

test.it("counts with no window, as a job", function()
  local root = nixos(folder("count"))
  local out = root .. "/count"
  quiet_managers()
  test.load("../apps/common/job/app.lua", { env = env { EVA_UPDATE_ROOT = root, EVA_UPDATE_FLAKE = lock(root), EVA_JOB_OUT = out },
    args = { "update", "--check" } })
  test.settle(300)
  test.eq(morf.fs.read(out), "0\n2\n")
end)

test.it("prints its help and refuses what it does not know", function()
  local _, help = cli { "--help" }
  test.contains(help.stdout, "eva-update --check")
  local _, wrong = cli { "--colour" }
  test.ne(wrong.code, 0)
end)
