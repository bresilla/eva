-- The machine's facts against a machine in a folder: what each section says,
-- Nix hidden on other systems, the words and JSON `eva-info` gets as a job, and
-- Settings' About page drawing them, holding a copy back when dry and fitting a
-- phone. The real machine is tools/see/info.steps'.
--
--     morf test --no-dbus tests/info_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local machine = load(morf.fs.read(ROOT .. "tests/fixtures/fake_machine.lua"))()
local serial = 0

local function put(root, path, text) morf.fs.write(root .. path, text, { parents = true }) end

local function fresh(options)
  serial = serial + 1
  local root = machine.build(morf.env("XDG_STATE_HOME") .. "/info-" .. serial .. "-" .. tostring(morf.time.now_ms()), options)
  put(root, "/sys/class/dmi/id/sys_vendor", "Framework\n")
  put(root, "/sys/class/dmi/id/product_name", "Laptop 13\n")
  put(root, "/sys/class/dmi/id/bios_version", "03.05\n")
  put(root, "/sys/block/nvme0n1/queue/scheduler", "[none] mq-deadline kyber\n")
  put(root, "/sys/kernel/sched_ext/state", "disabled\n")
  put(root, "/sys/bus/usb/devices/1-1/idVendor", "046d\n")
  put(root, "/sys/bus/usb/devices/1-1/idProduct", "c52b\n")
  put(root, "/sys/bus/usb/devices/1-1/product", "USB Receiver\n")
  put(root, "/sys/bus/usb/devices/1-1/manufacturer", "Logitech\n")
  put(root, "/sys/bus/usb/devices/1-1/speed", "12\n")
  put(root, "/sys/bus/usb/devices/1-1/bMaxPower", "98mA\n")
  put(root, "/sys/bus/usb/devices/1-1:1.0/idVendor", "046d\n")
  put(root, "/sys/bus/usb/devices/usb1/idVendor", "1d6b\n")
  put(root, "/share/xdg-desktop-portal/portals/hyprland.portal", "[portal]\n")
  put(root, "/share/xdg-desktop-portal/portals/gtk.portal", "[portal]\n")
  return root
end

local function nixos(root)
  put(root, "/nix/var/nix/profiles/system-41-link/nixos-version", "26.05.20261031.fa13731\n")
  morf.fs.mkdir(root .. "/run")
  morf.fs.symlink("/nix/store/abc-nixos-system-tron-26.05", root .. "/run/current-system.real")
  morf.fs.symlink(root .. "/nix/var/nix/profiles/system-41-link", root .. "/run/current-system")
  morf.fs.symlink("system-41-link", root .. "/nix/var/nix/profiles/system")
end

local function env(root, extra)
  local out = { EVA_INFO_ROOT = root, EVA_DRY_RUN = "1", XDG_DATA_DIRS = "/share", XDG_SESSION_TYPE = "wayland",
    XDG_CURRENT_DESKTOP = "Hyprland", XDG_STATE_HOME = root .. "/state", EVA_SETTINGS = "/nonexistent/eva.json" }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

-- The model alone, as the job has it: the machine in the folder and nothing of
-- the shell's own samplers.
local MODEL = [[
  require("morf.ui").Item { width = 1, height = 1 }
  local model = require("info_model")
  model.gather()
  morf.ipc.state = function()
    return { facts = model.facts:get(), sections = model.sections(model.facts:get()), message = model.message:get() }
  end
  morf.ipc.text = function() return model.text() end
]]

local function facts(root, extra)
  test.stub_run("systemctl", { code = 0, stdout = "broken.service loaded failed failed Broken\n" })
  test.stub_run("nixos-version", { code = 0, stdout = '{"nixosVersion":"26.05","nixpkgsRevision":"fa1373130d5a","configurationRevision":"cafe1234"}' })
  test.load("../shell/init.lua", { env = env(root, extra), source = MODEL })
  test.settle(500)
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

-- The shell on Settings' About page, its facts at hand.
local HOST = [[
  require("init")
  local model = require("info_model")
  morf.ipc.state = function()
    return { facts = model.facts:get(), sections = model.sections(model.facts:get()), message = model.message:get() }
  end
  morf.ipc.text = function() return model.text() end
]]

local function tool(root, extra, size)
  test.stub_run("systemctl", { code = 0, stdout = "broken.service loaded failed failed Broken\n" })
  test.stub_run("nixos-version", { code = 0, stdout = '{"nixosVersion":"26.05","nixpkgsRevision":"fa1373130d5a","configurationRevision":"cafe1234"}' })
  test.stub_run("task", { code = 0, stdout = "[]" })
  local all = env(root, extra)
  all.HOME = morf.env("XDG_CACHE_HOME")
  test.load("../shell/init.lua", { env = all, source = HOST, size = size or { 1600, 1000 } })
  test.settle(500)
  test.ipc("settings", "about")
  test.settle(800)
end

local function section(state, key)
  for _, entry in ipairs(state.sections) do
    if entry.key == key then
      local out = {}
      for _, row in ipairs(entry.rows) do out[row[1]] = row[2] end
      return out
    end
  end
  return nil
end

test.it("names the machine, its system and its hardware", function()
  local root = fresh()
  facts(root)
  local state = test.ipc("state")
  local system = section(state, "system")
  test.eq(system["Host name"], "fakebox")
  test.eq(system["Operating system"], "FakeOS 26.05")
  test.eq(system["Kernel"], "6.18.57")
  test.eq(system["Up"], "1 d 2 h")
  test.eq(system["I/O scheduler"], "none")
  test.eq(system["Sched-ext"], "disabled")
  local hardware = section(state, "hardware")
  test.eq(hardware["Machine"], "Framework Laptop 13")
  test.contains(hardware["Processor"], "Intel Core i7-11800H")
  test.eq(hardware["Threads"], "2")
  test.eq(hardware["Memory"], "15 GiB")
  test.eq(hardware["Swap"], "3.8 GiB")
  test.eq(#test.logs("error"), 0)
end)

test.it("lists the GPU, the disks, USB and the session", function()
  local root = fresh()
  facts(root)
  local state = test.ipc("state")
  test.contains(section(state, "gpus").card0, "8.0 GiB")
  test.contains(section(state, "gpus").card0, "amdgpu")
  test.contains(section(state, "disks").nvme0n1, "Fake NVMe 1TB")
  local usb = section(state, "usb")
  test.contains(usb["USB Receiver"], "046d:c52b")
  test.contains(usb["USB Receiver"], "12 Mb/s, 98mA")
  test.eq(#test.ipc("state").facts.usb, 1)
  local place = section(state, "session")
  test.eq(place["Session"], "wayland")
  test.eq(place["Desktop"], "Hyprland")
  test.eq(place["Portals"], "gtk, hyprland")
  test.eq(place["Failed units"], "broken.service")
end)

test.it("reports its versions", function()
  local root = fresh()
  facts(root)
  local versions = section(test.ipc("state"), "versions")
  test.matches(versions.eva, "^%d+%.%d+%.%d+$")
  test.eq(versions.morf, tostring(morf.version))
end)

test.it("shows the Nix generation on NixOS, and nothing of it elsewhere", function()
  local root = fresh()
  facts(root)
  test.falsy(section(test.ipc("state"), "nix"))

  local nix_root = fresh()
  nixos(nix_root)
  facts(nix_root)
  local nix = section(test.ipc("state"), "nix")
  test.eq(nix["Generation"], "41")
  test.eq(nix["NixOS"], "26.05.20261031.fa13731")
  test.eq(nix["Flake revision"], "cafe1234")
  test.eq(nix["Nixpkgs"], "fa1373130d5a")
  tool(nix_root)
  test.truthy(test.find { id = "about-detail-nix" }, "the page has no card for Nix")
end)

test.it("says everything as words, a section to a block", function()
  local root = fresh()
  facts(root)
  local text = test.ipc("text")
  test.contains(text, "System\n  Host name: fakebox\n")
  test.contains(text, "\nStorage\n")
  test.falsy(text:find("Nix\n", 1, true), "no Nix on this machine")
end)

test.it("holds the copy back when dry", function()
  local root = fresh()
  tool(root)
  test.click(reach("about-copy")) test.settle(100)
  test.truthy(test.find { text_contains = "dry run", visible = true }, "the page did not say it held back")
end)

test.it("draws the facts, a card to each kind", function()
  local root = fresh()
  tool(root)
  test.truthy(test.find { id = "about-detail-system" })
  test.truthy(test.find { id = "about-detail-hardware" })
  test.falsy(test.find { id = "about-detail-versions" }, "the versions are drawn twice")
  test.truthy(test.find { id = "about-copy" })
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " keeps the cards within a phone", function()
    local root = fresh()
    tool(root, { EVA_STYLE = style }, { 380, 800 })
    local card = test.get { id = "about-detail-system" }
    test.truthy(card.x + card.width <= 380, "the card is " .. card.width)
    local copy = test.get { id = "about-copy" }
    test.truthy(copy.x + copy.width <= 380, "the button runs off the side")
    test.eq(#test.logs("error"), 0)
  end)
end

-- ---------------------------------------------------------- the command line --

local function cli(args, extra)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/info-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(extra or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-info"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", result
end

test.it("asks the shell's own code for the facts, with no window", function()
  test.contains(cli { "--json" }, "apps/common/job/app.lua -- info --json")
  test.contains(cli { "--text" }, "apps/common/job/app.lua -- info --text")
end)

test.it("alone it opens About in the Settings window", function()
  test.contains(cli({}, { "STUB_UP=1" }), "ipc call settings about")
end)

test.it("says every fact as a job, as words and for a program", function()
  local root = fresh()
  local out = root .. "/answer"
  test.stub_run("systemctl", { code = 0, stdout = "" })
  test.load("../apps/common/job/app.lua", { args = { "info", "--json" }, env = env(root, { EVA_JOB_OUT = out }) })
  test.settle(500)
  local text = morf.fs.read(out) or ""
  test.eq(text:sub(1, 2), "0\n")
  test.eq(morf.json.decode(text:sub(3)).system.hostname, "fakebox")
  test.load("../apps/common/job/app.lua", { args = { "info", "--text" }, env = env(root, { EVA_JOB_OUT = out }) })
  test.settle(500)
  test.contains(morf.fs.read(out), "System\n  Host name: fakebox\n")
end)

test.it("copies through wl-copy, and not when dry", function()
  local calls = cli { "--copy" }
  test.contains(calls, "apps/common/job/app.lua -- info --text")
  test.contains(calls, "wl-copy")
  local dry, result = cli({ "--copy" }, { "EVA_DRY_RUN=1" })
  test.falsy(dry:find("wl-copy", 1, true), "copied when dry")
  test.contains(result.stderr, "dry run")
end)

test.it("prints its help and refuses what it does not know", function()
  local _, help = cli { "--help" }
  test.contains(help.stdout, "eva-info --copy")
  local _, wrong = cli { "--colour" }
  test.ne(wrong.code, 0)
end)
