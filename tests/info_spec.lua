-- eva-info against a machine in a folder: what each section says, Nix hidden on
-- other systems, the words and JSON a command line gets, the copy held back
-- when dry, and the window on a phone. The real machine is tools/see/info.steps'.
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

local function tool(root, extra)
  test.stub_run("systemctl", { code = 0, stdout = "broken.service loaded failed failed Broken\n" })
  test.stub_run("nixos-version", { code = 0, stdout = '{"nixosVersion":"26.05","nixpkgsRevision":"fa1373130d5a","configurationRevision":"cafe1234"}' })
  test.load("../apps/info/app.lua", { env = env(root, extra) })
  test.settle(500)
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
  tool(root)
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
  tool(root)
  local state = test.ipc("state")
  test.contains(section(state, "gpus").card0, "8.0 GiB")
  test.contains(section(state, "gpus").card0, "amdgpu")
  test.contains(section(state, "disks").nvme0n1, "Fake NVMe 1TB")
  local usb = section(state, "usb")
  test.contains(usb["USB Receiver"], "046d:c52b")
  test.contains(usb["USB Receiver"], "12 Mb/s")
  test.eq(#test.ipc("state").facts.usb, 1)
  local place = section(state, "session")
  test.eq(place["Session"], "wayland")
  test.eq(place["Desktop"], "Hyprland")
  test.eq(place["Portals"], "gtk, hyprland")
  test.eq(place["Failed units"], "broken.service")
end)

test.it("reports its versions", function()
  local root = fresh()
  tool(root)
  local versions = section(test.ipc("state"), "versions")
  test.matches(versions.eva, "^%d+%.%d+%.%d+$")
  test.eq(versions.morf, tostring(morf.version))
end)

test.it("shows the Nix generation on NixOS, and nothing of it elsewhere", function()
  local root = fresh()
  tool(root)
  test.falsy(section(test.ipc("state"), "nix"))
  test.falsy(test.find { id = "info-nix" })

  local nix_root = fresh()
  nixos(nix_root)
  tool(nix_root)
  local nix = section(test.ipc("state"), "nix")
  test.eq(nix["Generation"], "41")
  test.eq(nix["NixOS"], "26.05.20261031.fa13731")
  test.eq(nix["Flake revision"], "cafe1234")
  test.eq(nix["Nixpkgs"], "fa1373130d5a")
  test.truthy(test.find { id = "info-nix" })
end)

test.it("says everything as words, a section to a block", function()
  local root = fresh()
  tool(root)
  local text = test.ipc("text")
  test.contains(text, "System\n  Host name: fakebox\n")
  test.contains(text, "\nStorage\n")
  test.falsy(text:find("Nix\n", 1, true), "no Nix on this machine")
end)

test.it("holds the copy back when dry", function()
  local root = fresh()
  tool(root)
  test.truthy(test.ipc("copy"))
  test.contains(test.ipc("state").message, "dry run")
  test.settle(100)
  test.contains(test.get({ id = "info-note" }).text, "dry run")
end)

test.it("draws the facts", function()
  local root = fresh()
  tool(root)
  test.eq(test.get({ id = "info-host" }).text, "fakebox")
  test.truthy(test.find { id = "info-system" })
  test.truthy(test.find { id = "info-hardware" })
  test.truthy(test.find { id = "info-copy" })
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " takes one column on a phone", function()
    local root = fresh()
    tool(root, { EVA_STYLE = style })
    test.resize_window("toplevel:About this machine", 380, 800)
    test.settle(400)
    local card = test.get { id = "info-system" }
    test.truthy(card.width <= 380, "the card is " .. card.width)
    local copy = test.get { id = "info-copy" }
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
  argv[#argv + 1] = ROOT .. "apps/info/cli"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or "", result
end

test.it("asks its own code for the facts, with no window", function()
  test.contains(cli { "--json" }, "info/app.lua -- --json")
  test.contains(cli { "--text" }, "info/app.lua -- --text")
end)

test.it("copies through wl-copy, and not when dry", function()
  local calls = cli { "--copy" }
  test.contains(calls, "info/app.lua -- --text")
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
