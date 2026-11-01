-- External screens' brightness: ddcutil's words, the one level the shell has, and
-- that nothing speaks to a monitor unless the system said it may. The hardware
-- is lib/services/host_fake.lua here: real DDC/CI cannot be run in a spec or a VM.
--
--     morf test --no-dbus tests/ddc_spec.lua

local test = morf.test

local DETECT = [[
Display 1
   I2C bus:  /dev/i2c-6
   DRM connector:           card1-DP-1
   EDID synopsis:
      Mfg id:               DEL - Dell Inc.
   Monitor:                 DEL:DELL U2720Q:7H3KD
   VCP version:         2.1

Display 2
   I2C bus:  /dev/i2c-9
   DRM connector:           not found
   Monitor:                 GSM:LG ULTRAWIDE:0x01

Invalid display
   I2C bus:  /dev/i2c-7
   DRM connector:           card1-eDP-1
]]

local function shell(name, env, size)
  local settings = morf.env("XDG_CACHE_HOME") .. "/ddc-" .. name .. ".json"
  morf.fs.remove(settings)
  local values = { EVA_SETTINGS = settings, EVA_DRY_RUN = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") }
  for key, value in pairs(env or {}) do values[key] = value end
  test.load("../shell/init.lua", { source = [[
    require("init")
    local lib = require("lib.services.ddc")
    local ddc = require("ddc_model")
    local osd = require("osd")
    morf.ipc.parse = function(what, text)
      if what == "detect" then return lib.parse_detect(text) end
      local current, max = lib.parse_vcp(text)
      return { current or false, max or false }
    end
    morf.ipc.find = function(name, description)
      local rows = lib.parse_detect(morf.ipc.detect_text)
      local row = lib.find(rows, { name = name, description = description })
      return row and row.bus or ""
    end
    morf.ipc.detect_text = nil
    morf.ipc.args = function() return { lib.read_args("6"), lib.write_args("6", 40.0), lib.raw(50, 200) } end
    morf.ipc.level = function() return ddc.level() or false end
    morf.ipc.shown = function() local value, known = osd.brightness() return { value, known } end
    morf.ipc.set = function(v) osd.set_brightness(tonumber(v)) return true end
    morf.ipc.ran = function()
      local out = {}
      for _, argv in ipairs(require("lib.services.host_fake").ran or {}) do
        if argv[1] == "ddcutil" then out[#out + 1] = table.concat(argv, " ") end
      end
      return out
    end
    morf.ipc.allowed = function() return ddc.allowed() end
    morf.ipc.turn_off = function() require("config").set("displays.ddc", false) return true end
    morf.ipc.found = function(word)
      local out = {}
      for _, entry in ipairs(require("settings_registry").search(word)) do out[#out + 1] = entry.name end
      return out
    end
  ]], size = size or { 1920, 1080 }, env = values })
  test.settle(1000)
end

test.it("reads ddcutil's displays, and leaves out one it cannot talk to", function()
  shell("parse")
  local rows = test.ipc("parse", "detect", DETECT)
  test.eq(#rows, 2)
  test.eq(rows[1].bus, "6")
  test.eq(rows[1].connector, "DP-1")
  test.eq(rows[1].model, "DELL U2720Q")
  test.eq(rows[1].serial, "7H3KD")
  test.eq(rows[2].connector, "")
end)

test.it("reads a level in either form", function()
  shell("vcp")
  test.eq(test.ipc("parse", "vcp", "VCP 10 C 50 100\n"), { 50, 100 })
  test.eq(test.ipc("parse", "vcp", "VCP code 0x10 (Brightness): current value =    75, max value =   200\n"), { 75, 200 })
  test.eq(test.ipc("parse", "vcp", "Display not found\n"), { false, false })
end)

test.it("names a bus and a whole number, scaled to the monitor", function()
  shell("args")
  local out = test.ipc("args")
  test.eq(table.concat(out[1], " "), "ddcutil --bus 6 --brief getvcp 10")
  test.eq(table.concat(out[2], " "), "ddcutil --bus 6 --noverify setvcp 10 40")
  test.eq(out[3], 100)
end)

test.it("without the system's word nothing runs ddcutil, even where it is installed", function()
  test.stub_run("ddcutil", { code = 0, stdout = "" })
  shell("guard")
  test.falsy(test.ipc("allowed"))
  test.eq(test.ipc("level"), false)
  test.eq(test.ipc("shown")[2], false, "no external level, no backlight here")
end)

test.it("the one level follows the monitor this screen is on", function()
  shell("level", { EVA_FAKE_SYSTEM = "1" })
  test.eq(test.ipc("level"), 60)
  test.eq(test.ipc("shown"), { .6, true })
end)

test.it("a change shows at once and goes to the bus", function()
  shell("set", { EVA_FAKE_SYSTEM = "1" })
  test.ipc("set", 0.35) test.settle(100)
  test.eq(test.ipc("level"), 35)
  local said = false
  for _, line in ipairs(test.logs("info")) do
    if line.message:find("setvcp 10 35", 1, true) then said = true end
  end
  test.truthy(said, "the write reached the host seam")
end)

test.it("off in Settings it lets go of the screen", function()
  shell("off", { EVA_FAKE_SYSTEM = "1" })
  test.eq(test.ipc("level"), 60)
  test.ipc("turn_off") test.settle(100)
  test.eq(test.ipc("level"), false)
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the Displays page shows the external screen and its switch", function()
    shell("page-" .. style, { EVA_FAKE_SYSTEM = "1", EVA_STYLE = style })
    test.ipc("utilities", "open") test.settle(600)
    test.ipc("settings", "displays") test.settle(900)
    test.truthy(test.find { id = "displays-ddc-on", visible = true })
    test.truthy(test.find { id = "displays-ddc-screen-1", visible = true })
    test.eq(test.find { id = "displays-ddc-note", visible = true }, nil)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("with the option off the page says which option turns it on", function()
  shell("note", {})
  test.ipc("utilities", "open") test.settle(600)
  test.ipc("settings", "displays") test.settle(900)
  test.truthy(test.find { id = "displays-ddc-note", visible = true })
end)

test.it("Settings search finds it", function()
  shell("search")
  test.contains(table.concat(test.ipc("found", "ddc"), ","), "Brightness of external screens")
end)

test.it("the NixOS rule reaches displays' buses alone, by no group", function()
  local nix = morf.fs.read("nix/nixos/hardware.nix")
  test.contains(nix, 'SUBSYSTEMS=="drm", TAG+="uaccess"')
  test.falsy(nix:find('"i2c"', 1, true), "no user joins the i2c group")
  test.contains(nix, 'EVA_DDC = "1"')
end)
