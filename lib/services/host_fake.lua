-- A whole machine for EVA_FAKE_SYSTEM: the far end of every bus and command
-- the Settings pages reach, so the real service code runs with nothing real
-- behind it. `EVA_FAKE_SYSTEM=1` is an ordinary distribution; `=nixos` is a
-- NixOS with its configuration holding the time zone, locale, host name and
-- firewall. EVA_FAKE_CAN="suspend=no,hibernate=na" answers logind's questions.
local morf = require("morf")
local bus = require("lib.testing.dbus")

local M = { dbus = bus.dbus, ran = {} }

local mode = morf.env("EVA_FAKE_SYSTEM")
local NIXOS = mode == "nixos"

function M.nixos() return NIXOS end
function M.declared() return NIXOS end
function M.managed() return false end

local PROGRAMS = { ["pw-dump"] = true, ["pw-play"] = true, xkbcli = true, wlrctl = true, supergfxctl = true,
  scanimage = not NIXOS, lpstat = not NIXOS, ["firewall-cmd"] = not NIXOS, gsettings = true, lspci = true, ["xdg-open"] = true,
  gio = true, ["eva-battery"] = true, ping = true, getent = true, ddcutil = true }

-- Which backup tools this machine has: EVA_FAKE_BACKUPS="snapper,restic". Their
-- commands are answered below; the real ones never run.
for tool in (morf.env("EVA_FAKE_BACKUPS") or ""):gmatch("[^,]+") do PROGRAMS[tool] = true end

-- What the network does: `ok`, or how it breaks (`portal`, `no-address`,
-- `self-assigned`, `no-gateway`, `no-dns`, `no-internet`, `quiet-router`).
M.net = morf.env("EVA_FAKE_NET") or ""
if M.net == "" then M.net = "ok" end

function M.installed(program) return PROGRAMS[program] == true end
function M.tool(name)
  if name == "displays" or name == "update" or name == "info" then return { "eva-" .. name } end
  return nil
end

-- ---------------------------------------------------------------- commands --

local firewall_on, printers_on = true, { office = true }
local autostart_rows = {
  { key = "nm-applet.desktop", id = "nm-applet.desktop", name = "Network applet", enabled = true, system = true },
  { key = "syncthing.desktop", id = "syncthing.desktop", name = "Syncthing", enabled = true, own = true },
  { key = "geoclue-demo.desktop", id = "geoclue-demo.desktop", name = "Location agent", enabled = false, own = true, system = true },
}

local function device(id, name, api, title, active, profiles)
  return { id = id, type = "PipeWire:Interface:Device", info = {
    props = { ["device.name"] = name, ["device.api"] = api, ["device.description"] = title },
    params = { Profile = { { index = active, name = profiles[active + 1].name } }, EnumProfile = profiles } } }
end

local DEVICES = morf.json.encode {
  device(42, "alsa_card.pci-0000_00_1f.3", "alsa", "Built-in Audio", 1, {
    { index = 0, name = "off", description = "Off", available = "yes", priority = 0 },
    { index = 1, name = "output:analog-stereo+input:analog-stereo", description = "Analog Stereo Duplex", available = "yes", priority = 6565 },
    { index = 2, name = "output:hdmi-stereo", description = "Digital Stereo (HDMI)", available = "yes", priority = 5900 },
    { index = 3, name = "output:hdmi-stereo-extra1", description = "Digital Stereo (HDMI 2)", available = "no", priority = 5700 } }),
  device(43, "bluez_card.AA_BB_CC_DD_EE_01", "bluez5", "Pixel Buds Pro", 1, {
    { index = 0, name = "off", description = "Off", available = "yes", priority = 0 },
    { index = 1, name = "a2dp-sink-ldac", description = "High Fidelity Playback (LDAC)", available = "yes", priority = 130 },
    { index = 2, name = "a2dp-sink-aac", description = "High Fidelity Playback (AAC)", available = "yes", priority = 120 },
    { index = 3, name = "a2dp-sink-sbc_xq", description = "High Fidelity Playback (SBC XQ)", available = "yes", priority = 110 },
    { index = 4, name = "headset-head-unit-msbc", description = "Headset Head Unit (mSBC)", available = "yes", priority = 50 } }),
}

local OUTPUT = {
  ["lpstat -p"] = "printer office is idle.  enabled since Sat 01 Nov 2026\nprinter lab disabled since Fri 31 Oct 2026 -\n\tOut of paper\n",
  ["lpstat -d"] = "system default destination: office\n",
  ["lpstat -v"] = "device for office: ipp://office.local/ipp/print\ndevice for lab: ipp://lab.local/ipp/print\n",
  ["lpstat -o"] = "office-12  kate  20480  Sat 01 Nov 2026 09:12:00\n",
  ["scanimage -L"] = "device `airscan:e0:HP LaserJet' is a eSCL HP LaserJet ip=192.168.1.40\n",
  ["driverless"] = "ipp://HP%20LaserJet._ipp._tcp.local/\nipp://Brother.local/ipp/print\n",
  ["lpinfo -v"] = "network ipp://Brother.local/ipp/print\n",
  ["localectl list-locales"] = "C.UTF-8\nde_DE.UTF-8\nen_GB.UTF-8\nen_US.UTF-8\nfr_FR.UTF-8\nnl_NL.UTF-8\nsq_AL.UTF-8\n",
  ["lspci"] = "00:02.0 VGA compatible controller: Intel Corporation Iris Xe Graphics (rev 01)\n",
  ["eva-battery status"] = "charge 57%\nlimit true\nbetween 40 and 80\n",
  ["supergfxctl -g"] = "Hybrid\n",
  ["supergfxctl -s"] = "[Integrated, Hybrid, AsusMuxDgpu]\n",
}

local function joined(argv, count) return table.concat(argv, " ", 1, math.min(count, #argv)) end

M.snapshots = {
  snapper = { root = { { number = 0, type = "single", date = "", description = "current" },
    { number = 41, type = "pre", date = "2026-10-30 09:12:00", description = "nixos-rebuild" },
    { number = 42, type = "post", date = "2026-10-30 09:14:30", description = "nixos-rebuild" },
    { number = 43, type = "single", date = "2026-11-01 08:00:00", description = "timeline" } } },
  btrbk = "format=\"snapshots\" source_url='/home' source_host='' source_port='' source_subvolume='/home' "
    .. "snapshot_subvolume='/mnt/pool/_snap/home.20261030T0900' snapshot_name='home' status='' source_rsh=''\n"
    .. "format=\"snapshots\" source_url='/home' source_host='' source_port='' source_subvolume='/home' "
    .. "snapshot_subvolume='/mnt/pool/_snap/home.20261101T0900' snapshot_name='home' status='' source_rsh=''\n",
  restic = { { short_id = "1a2b3c4d", time = "2026-10-29T22:00:03.1Z", paths = { "/home/kate" }, hostname = "evabook" },
    { short_id = "5e6f7a8b", time = "2026-10-31T22:00:01.9Z", paths = { "/home/kate" }, hostname = "evabook" } },
}

local function backup_answer(argv)
  local line = table.concat(argv, " ")
  if line:find("snapper --jsonout list-configs", 1, true) then
    return { ok = true, stdout = morf.json.encode { configs = { { config = "root", subvolume = "/home" } } } }
  end
  if line:find("snapper --jsonout", 1, true) then return { ok = true, stdout = morf.json.encode(M.snapshots.snapper) } end
  if line:find("btrbk list", 1, true) then
    if argv[1] ~= "pkexec" then return { ok = false, code = 1, stderr = "ERROR: btrbk must be run as root" } end
    return { ok = true, stdout = M.snapshots.btrbk }
  end
  if line:find("restic snapshots", 1, true) then return { ok = true, stdout = morf.json.encode(M.snapshots.restic) } end
  if line:find("snapper -c root create", 1, true) then
    table.insert(M.snapshots.snapper.root, { number = 44, type = "single", date = "2026-11-01 12:00:00", description = "Made in Settings" })
    return { ok = true, stdout = "" }
  end
  return nil
end

local function answer(argv, options)
  local line = table.concat(argv, " ")
  local backup = backup_answer(argv)
  if backup then return backup end
  for _, take in ipairs { #argv, 3, 2, 1 } do
    local text = OUTPUT[joined(argv, take)]
    if text then return { ok = true, stdout = text } end
  end
  if argv[1] == "xdg-mime" and argv[2] == "query" then
    local mime = argv[4] or ""
    local apps = M.mime_cache()[mime]
    return { ok = true, stdout = (apps and apps[1] or "") .. "\n" }
  end
  if argv[1] == "firewall-cmd" then return { ok = firewall_on, code = firewall_on and 0 or 252, stdout = firewall_on and "running\n" or "not running\n" } end
  if argv[1] == "systemctl" and argv[2] == "is-active" then return { ok = true, stdout = "active\n" } end
  if line:find("list-unit-files", 1, true) then
    return { ok = true, stdout = "eva-clipboard.service enabled enabled\nsyncthing.service enabled enabled\nredshift.service disabled enabled\n" }
  end
  if line:find("list-units", 1, true) then
    return { ok = true, stdout = "eva-clipboard.service loaded active running eva clipboard history\nsyncthing.service loaded active running Syncthing\nredshift.service loaded inactive dead Redshift\n" }
  end
  if argv[1] == "pw-dump" then return { ok = true, stdout = DEVICES } end
  if argv[1] == "nmcli" and argv[2] == "-t" and argv[5] == "device" then
    if M.net == "no-address" then return { ok = true, stdout = "IP4.GATEWAY:--\n" } end
    if M.net == "self-assigned" then return { ok = true, stdout = "IP4.ADDRESS[1]:169.254.12.3/16\nIP4.GATEWAY:--\n" } end
    return { ok = true, stdout = "IP4.ADDRESS[1]:192.168.1.23/24\nIP4.GATEWAY:192.168.1.1\nIP4.DNS[1]:192.168.1.1\nIP4.DNS[2]:9.9.9.9\n" }
  end
  if argv[1] == "ping" then
    local quiet = M.net == "no-gateway" or M.net == "quiet-router"
    return { ok = not quiet, code = quiet and 1 or 0, stdout = quiet and "" or "2 packets transmitted, 2 received\n" }
  end
  if argv[1] == "getent" then
    local broken = M.net == "no-dns" or M.net == "no-gateway"
    return { ok = not broken, code = broken and 2 or 0, stdout = broken and "" or "203.0.113.7 STREAM stand-in\n" }
  end
  if argv[1] == "nmcli" and argv[2] == "-t" then
    return { ok = true, stdout = table.concat({ "connection.id:Home", "connection.uuid:u-home", "connection.type:802-11-wireless",
      "connection.metered:unknown", "connection.autoconnect:yes", "connection.dns-over-tls:-1", "ipv4.method:auto", "ipv4.addresses:",
      "ipv4.gateway:--", "ipv4.dns:", "ipv4.ignore-auto-dns:no", "ipv6.method:auto", "802-11-wireless.hidden:no",
      "802-11-wireless.cloned-mac-address:", "IP4.ADDRESS[1]:192.168.1.23/24", "IP4.GATEWAY:192.168.1.1", "IP4.DNS[1]:192.168.1.1",
      "IP4.DNS[2]:9.9.9.9", "IP6.ADDRESS[1]:fe80\\:\\:1/64", "GENERAL.DEVICES:wlan0" }, "\n") .. "\n" }
  end
  if argv[1] == "xkbcli" then
    return { ok = true, stdout = "interpret Any+AnyOf(all) {\n action= SetMods(modifiers=modMapMods,clearLocks);\n};\n" }
  end
  return nil
end

--- A command's result. Changes land in the fixture, so a page reads them back.
-- One external monitor on the screen the shell is on, at 60 of 100.
M.ddc_level = 60

local function ddcutil(argv)
  if argv[2] == "detect" then
    local screen = (morf.screens or {})[1] or {}
    return { ok = true, stdout = ("Display 1\n   I2C bus:  /dev/i2c-6\n   DRM connector:           card0-%s\n"
      .. "   Monitor:                 DEL:DELL U2720Q:7H3KD\n\nInvalid display\n   I2C bus:  /dev/i2c-7\n"):format(screen.name or "DP-1") }
  end
  if argv[#argv - 1] == "getvcp" or argv[#argv] == "10" and argv[5] == "getvcp" then
    return { ok = true, stdout = ("VCP 10 C %d 100\n"):format(M.ddc_level) }
  end
  if argv[#argv - 2] == "setvcp" then
    M.ddc_level = tonumber(argv[#argv])
    return { ok = true, stdout = "" }
  end
  return { ok = false, code = 1, stderr = "unknown" }
end

function M.run(argv, options)
  M.ran[#M.ran + 1] = argv
  M.stdin = options and options.stdin or M.stdin
  if argv[1] == "ddcutil" then return ddcutil(argv) end
  if argv[1] == "pkexec" and argv[3] == "systemctl" then firewall_on = argv[4] == "enable" return { ok = true, stdout = "" } end
  if argv[1] == "lpadmin" or argv[1] == "cancel" or argv[1] == "cupsenable" or argv[1] == "cupsdisable" then
    printers_on[argv[#argv]] = true
    return { ok = true, stdout = "" }
  end
  return answer(argv, options) or { ok = true, stdout = "" }
end

--- A server's answer, by what the network is doing. Each request is kept in
--- `M.asked`; no request leaves the process.
M.asked = {}
function M.http(spec)
  M.asked[#M.asked + 1] = spec.url
  if M.net == "no-internet" or M.net == "no-dns" or M.net == "no-gateway" then
    return { ok = false, status = 0, url = spec.url, error = "no route to host" }
  end
  if M.net == "portal" then
    return { ok = true, status = 200, url = "http://login.cafe.test/welcome", body = "<html>Sign in to Cafe</html>" }
  end
  if spec.url:find("generate_204", 1, true) then return { ok = true, status = 204, url = spec.url, body = "" } end
  if spec.url:find("success.txt", 1, true) then return { ok = true, status = 200, url = spec.url, body = "success\n" } end
  if spec.url:find("check_network_status", 1, true) then
    return { ok = true, status = 200, url = spec.url, body = "NetworkManager is online\n" }
  end
  local size = tonumber(spec.url:match("bytes=(%d+)")) or #(spec.body or "")
  return { ok = true, status = 200, url = spec.url, body = string.rep("0", math.min(size, 1024)), bytes = size,
    took_ms = size == 0 and 18 or size // 12500 }
end

--- The network turning, as NetworkManager announces it.
function M.set_net(scene)
  M.net = scene
  local path, name = "/org/freedesktop/NetworkManager", "org.freedesktop.NetworkManager"
  local connectivity = scene == "portal" and 2 or 4
  bus.props("system", name, path, name).Connectivity = connectivity
  bus.emit("system", name, path, "org.freedesktop.DBus.Properties", "PropertiesChanged", { name, { Connectivity = connectivity }, {} })
end

-- ------------------------------------------------------------------- files --

function M.mime_cache()
  return { ["x-scheme-handler/http"] = { "firefox.desktop", "chromium.desktop" }, ["text/html"] = { "firefox.desktop" },
    ["x-scheme-handler/mailto"] = { "thunderbird.desktop" }, ["text/calendar"] = { "thunderbird.desktop" },
    ["inode/directory"] = { "nautilus.desktop", "thunar.desktop" }, ["text/plain"] = { "helix.desktop", "gedit.desktop" },
    ["application/pdf"] = { "zathura.desktop", "firefox.desktop" }, ["image/png"] = { "imv.desktop" },
    ["audio/mpeg"] = { "mpv.desktop" }, ["video/mp4"] = { "mpv.desktop", "vlc.desktop" } }
end

function M.apps()
  local out = {}
  for id, name in pairs { ["firefox.desktop"] = "Firefox", ["chromium.desktop"] = "Chromium", ["thunderbird.desktop"] = "Thunderbird",
    ["nautilus.desktop"] = "Files", ["thunar.desktop"] = "Thunar", ["helix.desktop"] = "Helix", ["gedit.desktop"] = "Text Editor",
    ["zathura.desktop"] = "Zathura", ["imv.desktop"] = "imv", ["mpv.desktop"] = "mpv", ["vlc.desktop"] = "VLC" } do
    out[id] = { id = id, name = name, exec = (id:gsub("%.desktop$", "")) }
  end
  return out
end

function M.autostart() return autostart_rows end
function M.accounts()
  return { { name = "kate", label = "Kate Nowak", initial = "K", home = "/home/kate" },
    { name = "guest", label = "Guest", initial = "G", home = "/home/guest" } }
end
function M.administrators() return { kate = true } end
function M.outputs()
  return { { name = "eDP-1", description = "BOE 0x0BCA", width = 2560, height = 1600, refresh = 60, scale = 1.5, enabled = true },
    { name = "DP-2", description = "Dell U2720Q", width = 3840, height = 2160, refresh = 60, scale = 1.5, enabled = true } }
end
function M.security() return { secure_boot = true, encrypted = true } end
function M.sound_themes() return { { key = "freedesktop", name = "Freedesktop", path = "/nonexistent" }, { key = "ocean", name = "Ocean", path = "/nonexistent" } } end
function M.cursor_themes() return { { key = "Adwaita", name = "Adwaita" }, { key = "Bibata-Modern-Ice", name = "Bibata Modern Ice" } } end
function M.about()
  return { ["/etc/os-release"] = 'PRETTY_NAME="Fixture Linux 26.11"\nNAME="Fixture"\n',
    ["/proc/cpuinfo"] = "processor : 0\nmodel name : Intel Core Ultra 7 155H\nprocessor : 1\n",
    ["/proc/meminfo"] = "MemTotal:       32480000 kB\n", ["/sys/class/dmi/id/sys_vendor"] = "Framework",
    ["/sys/class/dmi/id/product_name"] = "Laptop 13", ["/proc/sys/kernel/hostname"] = "evabook",
    ["/proc/sys/kernel/osrelease"] = "6.18.57" }
end

-- --------------------------------------------------------------- hyprland --

--- A double of lib.compositor.hyprland with one mouse, one keyboard and a
--- touchpad, answering as a Lua-configured Hyprland does.
function M.hyprland()
  local double = { sent = {}, state = { keyboard_layout = "English (US)" }, listeners = {} }
  M.last_hyprland = double
  function double.fire(name)
    for _, handler in ipairs(double.listeners[name] or {}) do handler() end
  end
  function double.available() return true end
  function double.eval(_, callback) if callback then callback("ok") end end
  function double.request(command, callback)
    double.sent[#double.sent + 1] = command
    if callback then callback("ok") end
  end
  function double.options(_, callback)
    callback({ ["input:repeat_rate"] = { int = 25 }, ["input:repeat_delay"] = { int = 600 },
      ["input:sensitivity"] = { float = 0 }, ["input:touchpad:tap-to-click"] = { bool = true },
      ["input:touchpad:natural_scroll"] = { bool = true } })
  end
  function double.devices(callback)
    callback { mice = { { name = "logitech-mx-master-3" }, { name = "pixa3854-touchpad" } },
      keyboards = { { name = "at-translated-set-2-keyboard", active_keymap = "English (US)", main = true } }, tablets = {}, touch = {} }
  end
  function double.on(name, handler)
    double.listeners[name] = double.listeners[name] or {}
    table.insert(double.listeners[name], handler)
    return { off = function() end }
  end
  function double.reload(_, callback)
    double.sent[#double.sent + 1] = "/reload"
    if callback then callback("ok") end
  end
  double.bound = {}
  function double.binds(callback) callback(double.bound) end
  return double
end

-- ------------------------------------------------------------------ audio --

local function list(rows)
  return { len = function() return #rows end, get = function(_, index) return rows[index] end }
end

local SINKS = { { id = 40, name = "alsa_output.pci-0000_00_1f.3.analog-stereo", description = "Built-in speakers", kind = "sink",
    volume = .62, volumes = { .62, .62 }, channels = 2, muted = false, default = true },
  { id = 41, name = "bluez_output.AA_BB_CC_DD_EE_01", description = "Pixel Buds Pro", kind = "sink", volume = .4,
    volumes = { .4, .4 }, channels = 2, muted = false, default = false } }
local SOURCES = { { id = 50, name = "alsa_input.pci-0000_00_1f.3.analog-stereo", description = "Built-in microphone", kind = "source",
  volume = .7, volumes = { .7, .7 }, channels = 2, muted = false, default = true } }

--- Stands in for morf.audio, a meter included.
local function fake_audio()
  local audio = { sinks = list(SINKS), sources = list(SOURCES), streams = list {} }
  function audio.available() return true end
  function audio.default_sink() return SINKS[1] end
  function audio.default_source() return SOURCES[1] end
  function audio.device(id)
    for _, row in ipairs(SINKS) do if row.id == id then return row end end
    for _, row in ipairs(SOURCES) do if row.id == id then return row end end
  end
  function audio.stream() return nil end
  function audio.monitor(spec)
    local tick = 0
    local timer = morf.time.timer(100, function()
      tick = tick + 1
      spec.on_level(.35 + .25 * math.sin(tick / 3), .3)
    end, true)
    return { stop = function() timer:cancel() end }
  end
  for _, name in ipairs { "set_volume", "set_mute", "set_default", "move_stream", "set_channel_volumes" } do
    audio[name] = function() return true end
  end
  return audio
end

morf.audio = fake_audio()

-- A laptop's battery, for the Power page.
require("lib.services.sysinfo").battery = function()
  return { ac = true, time_to_full = 3000, batteries = { { name = "BAT0", capacity = 57, status = "Charging", power = 28.5,
    health = 91, charge_limit = 80, charge_start = 40, charge_mode = "Standard", cycles = 212, temperature = 31.5 } } }
end

-- ------------------------------------------------------------------- buses --

local S = "system"
local function can(name, default)
  local wanted = morf.env("EVA_FAKE_CAN") or ""
  return wanted:match(name .. "=(%a+)") or default
end

bus.object(S, "org.freedesktop.login1", "/org/freedesktop/login1", "org.freedesktop.login1.Manager",
  { HandleLidSwitch = "suspend", HandleLidSwitchExternalPower = "ignore", HandlePowerKey = "poweroff", LidClosed = false,
    Docked = false, IdleHint = false, PreparingForSleep = false, PreparingForShutdown = false },
  { CanSuspend = function() return can("suspend", "yes") end, CanHibernate = function() return can("hibernate", "yes") end,
    CanReboot = function() return can("reboot", "yes") end, CanPowerOff = function() return can("shutdown", "yes") end,
    CanHybridSleep = function() return "na" end, CanSuspendThenHibernate = function() return "na" end,
    ListInhibitors = function() return { {} } end, Inhibit = function() return { bus.fd("inhibit") } end })

local time = bus.object(S, "org.freedesktop.timedate1", "/org/freedesktop/timedate1", "org.freedesktop.timedate1",
  { Timezone = "Europe/Amsterdam", NTP = true, CanNTP = true, NTPSynchronized = true, LocalRTC = false, TimeUSec = 0 },
  { ListTimezones = function()
      return { { "Africa/Nairobi", "America/New_York", "Asia/Tokyo", "Europe/Amsterdam", "Europe/Berlin", "Europe/Tirana",
        "Pacific/Auckland", "UTC" } }
    end,
    SetTimezone = function(args) time.Timezone = bus.plain(args[1]) end,
    SetNTP = function(args) time.NTP = bus.plain(args[1]) end,
    SetTime = function() end })

local locale = bus.object(S, "org.freedesktop.locale1", "/org/freedesktop/locale1", "org.freedesktop.locale1",
  { Locale = { "LANG=en_US.UTF-8", "LC_TIME=nl_NL.UTF-8" } },
  { SetLocale = function(args) locale.Locale = bus.plain(args[1]) end })

local hostname = bus.object(S, "org.freedesktop.hostname1", "/org/freedesktop/hostname1", "org.freedesktop.hostname1",
  { StaticHostname = "evabook", Hostname = "evabook" },
  { SetStaticHostname = function(args) hostname.StaticHostname = bus.plain(args[1]) end })

local UD, ROOT = "org.freedesktop.UDisks2", "/org/freedesktop/UDisks2"
local function block(device, drive, size, label, fs, hint)
  return { Device = device .. "\0", PreferredDevice = device .. "\0", Drive = drive, Size = size, IdLabel = label, IdType = fs,
    HintSystem = hint, HintIgnore = false, CryptoBackingDevice = "/" }
end
local mount = { MountPoints = {} }
local function drive_object(path, vendor, model, size, removable)
  bus.object(S, UD, path, UD .. ".Drive", { Vendor = vendor, Model = model, Size = size, Removable = removable,
    MediaRemovable = removable, Ejectable = removable, CanPowerOff = removable, ConnectionBus = removable and "usb" or "nvme" },
    { PowerOff = function() end, Eject = function() end })
end
drive_object(ROOT .. "/drives/usb", "Kingston", "DataTraveler", 32e9, true)
drive_object(ROOT .. "/drives/nvme", "Samsung", "990 PRO", 1e12, false)
drive_object(ROOT .. "/drives/crypt", "SanDisk", "Extreme", 64e9, true)
bus.object(S, UD, ROOT .. "/block_devices/sda1", UD .. ".Block", block("/dev/sda1", ROOT .. "/drives/usb", 32e9, "PHOTOS", "exfat", false))
bus.object(S, UD, ROOT .. "/block_devices/sda1", UD .. ".Filesystem", mount, {
  Mount = function() mount.MountPoints = { "/run/media/kate/PHOTOS\0" } return "/run/media/kate/PHOTOS" end,
  Unmount = function() mount.MountPoints = {} end })
bus.object(S, UD, ROOT .. "/block_devices/nvme0n1p2", UD .. ".Block", block("/dev/nvme0n1p2", ROOT .. "/drives/nvme", 1e12, "", "ext4", true))
bus.object(S, UD, ROOT .. "/block_devices/nvme0n1p2", UD .. ".Filesystem", { MountPoints = { "/\0" } }, {})
bus.object(S, UD, ROOT .. "/block_devices/sdb1", UD .. ".Block", block("/dev/sdb1", ROOT .. "/drives/crypt", 64e9, "", "crypto_LUKS", false))
bus.object(S, UD, ROOT .. "/block_devices/sdb1", UD .. ".Encrypted", {}, {
  Unlock = function(args)
    M.unlocked_with = bus.plain(args[1])
    return ROOT .. "/block_devices/dm_2d0"
  end, Lock = function() end })
bus.object(S, UD, ROOT .. "/block_devices/dm_2d0", UD .. ".Filesystem", { MountPoints = {} }, { Mount = function() return "/run/media/kate/VAULT" end })

--- A drive arriving, as UDisks2 announces one.
function M.plug()
  local path = ROOT .. "/block_devices/sdc1"
  drive_object(ROOT .. "/drives/new", "SanDisk", "Ultra", 16e9, true)
  bus.object(S, UD, path, UD .. ".Block", block("/dev/sdc1", ROOT .. "/drives/new", 16e9, "CAMERA", "vfat", false))
  bus.object(S, UD, path, UD .. ".Filesystem", { MountPoints = {} }, {})
  bus.emit(S, UD, ROOT, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", { path, {} })
end

--- The lid moving, as logind announces it.
function M.lid(closed)
  local path, name = "/org/freedesktop/login1", "org.freedesktop.login1"
  bus.props(S, name, path, name .. ".Manager").LidClosed = closed == true
  bus.emit(S, name, path, "org.freedesktop.DBus.Properties", "PropertiesChanged", { name .. ".Manager", { LidClosed = closed == true }, {} })
end

local NM, NM_ROOT = "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager"
local AP = NM_ROOT .. "/AccessPoint/1"
bus.object(S, NM, NM_ROOT, NM, { Version = "1.50", State = 70, Connectivity = M.net == "portal" and 2 or 4, NetworkingEnabled = true, WirelessEnabled = true,
  WirelessHardwareEnabled = true, ActiveConnections = { NM_ROOT .. "/ActiveConnection/1" }, PrimaryConnection = NM_ROOT .. "/ActiveConnection/1",
  PrimaryConnectionType = "802-11-wireless", AllDevices = { NM_ROOT .. "/Devices/1", NM_ROOT .. "/Devices/2" } }, {})
bus.object(S, NM, NM_ROOT .. "/ActiveConnection/1", NM .. ".Connection.Active", { Id = "Home", Uuid = "u-home", Type = "802-11-wireless",
  State = 2, Default = true, Devices = { NM_ROOT .. "/Devices/1" }, Connection = NM_ROOT .. "/Settings/1" }, {})
bus.object(S, NM, NM_ROOT .. "/Devices/1", NM .. ".Device", { Interface = "wlan0", DeviceType = 2, State = 100, Managed = true,
  ActiveConnection = NM_ROOT .. "/ActiveConnection/1", Driver = "iwlwifi" }, {})
bus.object(S, NM, NM_ROOT .. "/Devices/1", NM .. ".Device.Wireless", { HwAddress = "AA:BB:CC:00:00:01", ActiveAccessPoint = AP,
  AccessPoints = { AP, NM_ROOT .. "/AccessPoint/2" }, LastScan = 1 }, {})
bus.object(S, NM, NM_ROOT .. "/Devices/2", NM .. ".Device", { Interface = "eth0", DeviceType = 1, State = 30, Managed = true, Driver = "r8169" }, {})
bus.object(S, NM, NM_ROOT .. "/Devices/2", NM .. ".Device.Wired", { HwAddress = "AA:BB:CC:00:00:02", Carrier = false, Speed = 0 }, {})
bus.object(S, NM, AP, NM .. ".AccessPoint", { Ssid = "Home", Strength = 84, Frequency = 5180, Flags = 1, WpaFlags = 0, RsnFlags = 0x100,
  HwAddress = "11:22:33:44:55:66", MaxBitrate = 866000 }, {})
bus.object(S, NM, NM_ROOT .. "/AccessPoint/2", NM .. ".AccessPoint", { Ssid = "Cafe", Strength = 41, Frequency = 2437, Flags = 0,
  WpaFlags = 0, RsnFlags = 0, HwAddress = "11:22:33:44:55:77", MaxBitrate = 54000 }, {})
bus.object(S, NM, NM_ROOT .. "/Settings", NM .. ".Settings", {}, { ListConnections = function() return { { NM_ROOT .. "/Settings/1" } } end })
bus.object(S, NM, NM_ROOT .. "/Settings/1", NM .. ".Settings.Connection", {}, {
  GetSettings = function()
    return { { connection = { id = "Home", uuid = "u-home", type = "802-11-wireless", autoconnect = true, timestamp = 10 },
      ["802-11-wireless"] = { ssid = "Home" }, ipv4 = { method = "auto" }, ipv6 = { method = "auto" } } }
  end,
  GetSecrets = function() return { { ["802-11-wireless-security"] = { psk = "fixture passphrase" } } } end })

local BZ = "org.bluez"
bus.object(S, BZ, "/org/bluez/hci0", BZ .. ".Adapter1", { Address = "AA:AA:AA:AA:AA:AA", Alias = "evabook", Name = "evabook", Powered = true,
  Discovering = false, Discoverable = false, Pairable = true }, { RemoveDevice = function() end, StartDiscovery = function() end, StopDiscovery = function() end })
bus.object(S, BZ, "/org/bluez/hci0/dev_01", BZ .. ".Device1", { Address = "AA:BB:CC:DD:EE:01", Alias = "Pixel Buds Pro", Name = "Pixel Buds Pro",
  Icon = "audio-headset", Paired = true, Bonded = true, Trusted = true, Connected = true, Adapter = "/org/bluez/hci0" },
  { Disconnect = function() end, Connect = function() end })
bus.object(S, BZ, "/org/bluez/hci0/dev_01", BZ .. ".Battery1", { Percentage = 78 }, {})
bus.object(S, BZ, "/org/bluez/hci0/dev_02", BZ .. ".Device1", { Address = "AA:BB:CC:DD:EE:02", Alias = "MX Master 3", Name = "MX Master 3",
  Icon = "input-mouse", Paired = true, Bonded = true, Trusted = false, Connected = false, Adapter = "/org/bluez/hci0" }, { Connect = function() end })

local STORE, STORE_PATH = "org.freedesktop.impl.portal.PermissionStore", "/org/freedesktop/impl/portal/PermissionStore"
local answers = {
  ["location/location"] = { ["org.mozilla.firefox"] = { "EXACT", "1793520000" }, ["org.gnome.Maps"] = { "NONE", "0" } },
  ["devices/camera"] = { ["us.zoom.Zoom"] = { "yes" }, ["com.discordapp.Discord"] = { "no" } },
  ["devices/microphone"] = { ["us.zoom.Zoom"] = { "yes" } },
  ["screenshot/screenshot"] = { ["com.obsproject.Studio"] = { "yes" } },
  ["notifications/notification"] = { ["org.signal.Signal"] = { "yes" } },
  ["background/background"] = { ["org.signal.Signal"] = { "yes" } },
}
bus.object("session", STORE, STORE_PATH, STORE, {}, {
  Lookup = function(args)
    local entry = answers[bus.plain(args[1]) .. "/" .. bus.plain(args[2])]
    if not entry then error("org.freedesktop.portal.Error.NotFound: no entry", 0) end
    return { entry, "" }
  end,
  SetPermission = function(args)
    local name = bus.plain(args[1]) .. "/" .. bus.plain(args[3])
    answers[name] = answers[name] or {}
    answers[name][bus.plain(args[4])] = bus.plain(args[5])
  end,
  DeletePermission = function(args) (answers[bus.plain(args[1]) .. "/" .. bus.plain(args[2])] or {})[bus.plain(args[3])] = nil end })

return M
