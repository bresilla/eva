-- What the Settings pages rest on, each against a stand-in: the plans sent to
-- Hyprland in both of its languages, what commands print, what buses answer,
-- and where a secret is and is not allowed to go.
--
--     morf test --no-dbus tests/settings_services_spec.lua
local test = morf.test

local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local function eq(a, b, what)
    if a ~= b then error(("%s: expected %s, got %s"):format(what or "value", tostring(b), tostring(a)), 2) end
  end
  local function truthy(v, what) if not v then error("expected " .. tostring(what or "a true value"), 2) end end
  local function falsy(v, what) if v then error("expected no " .. tostring(what or "value"), 2) end end
  local function has(list, wanted)
    for _, each in ipairs(list) do if each == wanted then return true end end
    return false
  end
  local tests = {}

  function tests.input_plan_lua()
    local lib = require("lib.services.input_config")
    local plan = lib.plan({ chosen = { repeat_rate = 30, tap_to_click = true }, layouts = { { layout = "us", variant = "" },
      { layout = "de", variant = "nodeadkeys" } }, switch = "grp:alt_shift_toggle", devices = {} }, "lua")
    eq(#plan, 1, "one eval")
    local chunk = plan[1].eval
    truthy(chunk:find("input = { repeat_rate = 30 }", 1, true), "repeat rate")
    truthy(chunk:find("tap_to_click = true", 1, true), "the Lua spelling")
    truthy(chunk:find('kb_layout = "us,de"', 1, true), "layouts")
    truthy(chunk:find('kb_variant = ",nodeadkeys"', 1, true), "variants")
    truthy(chunk:find('kb_options = "grp:alt_shift_toggle"', 1, true), "the switch")
  end
  function tests.input_plan_hyprlang()
    local lib = require("lib.services.input_config")
    local plan = lib.plan({ chosen = { tap_to_click = false } }, "hyprlang")
    eq(plan[1].keyword, "input:touchpad:tap-to-click", "the hyprlang spelling")
    eq(plan[1].value, "false")
  end
  function tests.input_refuses()
    local lib = require("lib.services.input_config")
    local plan, why = lib.plan({ layouts = { { layout = 'us"; os.execute("x")', variant = "" } } }, "lua")
    falsy(plan, "a plan from an unsafe layout")
    truthy(why, "why")
    falsy(lib.device_plan("bad name; x", { sensitivity = 1 }, "lua"), "a plan for an unsafe device")
    falsy(lib.path_step("input:kb_file", '/x"); y', "lua"), "a step for an unsafe path")
  end
  function tests.device_plans()
    local lib = require("lib.services.input_config")
    local lua = lib.device_plan("logi-mx", { sensitivity = 0.5, enabled = false }, "lua")
    eq(lua[1].eval, 'hl.device({ name = "logi-mx", enabled = false, sensitivity = 0.5 })')
    local conf = lib.device_plan("logi-mx", { sensitivity = 0.5 }, "hyprlang")
    eq(conf[1].keyword, "device[logi-mx]:sensitivity")
  end
  function tests.layouts_catalogue()
    local lib = require("lib.services.input_config")
    local rows = lib.parse_rules("! layout\n  us   English (US)\n  de   German\n\n! variant\n  nodeadkeys   de: German (no dead keys)\n")
    eq(#rows, 3)
    eq(rows[3].key, "de:nodeadkeys")
    eq(rows[3].layout, "de")
  end
  function tests.readings()
    local lib = require("lib.services.input_config")
    local got = lib.readings { ["input:repeat_rate"] = { int = 30 }, ["input:touchpad:tap-to-click"] = { int = 1 },
      ["input:sensitivity"] = { float = 0.25 } }
    eq(got.repeat_rate, 30) eq(got.tap_to_click, true) eq(got.sensitivity, 0.25)
  end
  -- What `hyprctl -j getoption` printed on Hyprland 0.55.4.
  function tests.readings_of_real_replies()
    local lib = require("lib.services.input_config")
    local got = lib.readings { ["input:touchpad:tap-to-click"] = { option = "input:touchpad:tap-to-click", bool = true, set = false },
      ["input:numlock_by_default"] = { option = "input:numlock_by_default", bool = false, set = false },
      ["input:touchpad:drag_lock"] = { option = "input:touchpad:drag_lock", int = 2, set = true },
      ["input:accel_profile"] = { option = "input:accel_profile", str = ("["):rep(2) .. "EMPTY" .. ("]"):rep(2), set = false } }
    eq(got.tap_to_click, true, "a toggle that is on")
    eq(got.numlock, false, "a toggle that is off")
    eq(got.drag_lock, true, "an option Hyprland keeps as a number")
    eq(got.accel_profile, "", "a string nobody set")
  end
  function tests.a_device_with_a_slash()
    local lib = require("lib.services.input_config")
    local lua = lib.device_plan("tpps/2-ibm-trackpoint", { sensitivity = 0.5 }, "lua")
    eq(lua[1].eval, 'hl.device({ name = "tpps/2-ibm-trackpoint", sensitivity = 0.5 })')
    local plan = lib.plan({ chosen = { repeat_rate = 30 }, devices = { ["tpps/2-ibm-trackpoint"] = { enabled = false } } }, "lua")
    truthy(plan, "the whole plan, past a device with a slash")
    eq(#plan, 2, "the options and the device")
  end

  function tests.sticky_keymap()
    local access = require("lib.services.access")
    local text = [=[
	interpret Alt_L+AnyOf(all) {
		virtualModifier= Alt;
		action= SetMods(modifiers=modMapMods,clearLocks);
	};
	interpret Any+AnyOf(all) {
		action= SetMods(modifiers=modMapMods,clearLocks);
	};
	interpret ISO_Level3_Shift+AnyOfOrNone(all) {
		action= SetMods(modifiers=LevelThree,clearLocks);
	};
]=]
    local out, changed = access.sticky_keymap(text)
    eq(changed, 3)
    falsy(out:find("SetMods", 1, true), "a modifier left unlatched")
    truthy(out:find("LatchMods(modifiers=modMapMods,clearLocks,latchToLock)", 1, true), "a latch")
  end
  function tests.filters()
    local access = require("lib.services.access")
    for _, row in ipairs(access.FILTERS) do
      local source = access.shader(row[1])
      if row[1] == "none" then falsy(source, "a shader for none")
      else truthy(source:find("fragColor", 1, true), row[1]) end
    end
    local step = require("lib.services.input_config").path_step("decoration:screen_shader", "/a/b.frag", "lua")
    eq(step.eval, 'hl.config({ decoration = { screen_shader = "/a/b.frag" } })')
  end
  function tests.mouse_keys()
    local access = require("lib.services.access")
    local on = access.mouse_key_steps(true, "hyprlang")
    eq(on[1].keyword, "binde")
    truthy(on[1].value:find("wlrctl pointer move -12 0", 1, true), "a move")
    eq(access.mouse_key_steps(false, "hyprlang")[1].keyword, "unbind")
    truthy(access.mouse_key_steps(true, "lua")[1].eval:find("hl.bind(", 1, true), "the Lua spelling")
  end

  function tests.printers()
    local p = require("lib.services.printers")
    local rows = p.parse_printers("printer office is idle.  enabled since x\nprinter lab disabled since y -\n\tOut of paper\n")
    eq(#rows, 2) eq(rows[1].state, "idle") eq(rows[1].enabled, true)
    eq(rows[2].enabled, false) eq(rows[2].reason, "Out of paper")
    eq(p.parse_default("system default destination: office\n"), "office")
    eq(p.parse_default("no system default destination\n"), "")
    eq(p.parse_devices("device for office: ipp://x/y\n").office, "ipp://x/y")
    local jobs = p.parse_jobs("office-12  kate  20480  Sat\n")
    eq(jobs[1].id, "office-12") eq(jobs[1].printer, "office")
    eq(p.parse_discovered("ipp://Brother.local/ipp/print\n")[1].name, "Brother")
    eq(p.parse_scanners("device `airscan:x' is a eSCL HP\n")[1].device, "airscan:x")
    eq(p.queue_name("HP LaserJet 4!"), "HP_LaserJet_4")
    local refused
    p.add("x", "not a uri", function(ok, why) refused = why end)
    truthy(refused, "a refusal of a bad address")
  end

  function tests.udisks_parse()
    local lib = require("lib.services.udisks")
    local R = "/org/freedesktop/UDisks2/"
    local _, volumes = lib.parse {
      [R .. "drives/a"] = { ["org.freedesktop.UDisks2.Drive"] = { Vendor = "Kingston", Model = "DT", Size = 32, Removable = true,
        Ejectable = true, CanPowerOff = true } },
      [R .. "block_devices/sda1"] = {
        ["org.freedesktop.UDisks2.Block"] = { Device = "/dev/sda1\0", Drive = R .. "drives/a", Size = 32, IdLabel = "PHOTOS", IdType = "exfat", CryptoBackingDevice = "/" },
        ["org.freedesktop.UDisks2.Filesystem"] = { MountPoints = { "/run/media/PHOTOS\0" } } },
      [R .. "block_devices/sdb1"] = {
        ["org.freedesktop.UDisks2.Block"] = { Device = "/dev/sdb1\0", Drive = R .. "drives/a", Size = 8, IdType = "crypto_LUKS", CryptoBackingDevice = "/" },
        ["org.freedesktop.UDisks2.Encrypted"] = {} },
      [R .. "block_devices/dm0"] = {
        ["org.freedesktop.UDisks2.Block"] = { Device = "/dev/dm-0\0", Size = 8, CryptoBackingDevice = R .. "block_devices/sdb1" },
        ["org.freedesktop.UDisks2.Filesystem"] = { MountPoints = { "/run/media/VAULT\0" } } },
      [R .. "block_devices/hidden"] = {
        ["org.freedesktop.UDisks2.Block"] = { Device = "/dev/sdz\0", HintIgnore = true },
        ["org.freedesktop.UDisks2.Filesystem"] = {} },
    }
    eq(#volumes, 2, "the cleartext side and ignored blocks are not rows")
    local plain, crypt = volumes[1], volumes[2]
    eq(plain.name, "PHOTOS") eq(plain.mount_point, "/run/media/PHOTOS") eq(plain.mounted, true) eq(plain.removable, true)
    eq(crypt.encrypted, true) eq(crypt.unlocked, R .. "block_devices/dm0") eq(crypt.mount_point, "/run/media/VAULT")
    eq(lib.human(1500000), "1.5 MB")
  end

  function tests.permissions()
    local p = require("lib.services.permissions")
    local kind = p.BY_ID.location
    truthy(p.allowed(kind, { "EXACT", "10" }), "an exact location")
    falsy(p.allowed(kind, { "NONE", "10" }), "NONE allowed")
    truthy(p.allowed(p.BY_ID.camera, { "yes" }), "a yes")
    falsy(p.allowed(p.BY_ID.camera, { "ask" }), "an ask taken for a yes")
    eq(p.answer(kind, false, { "EXACT", "10" })[2], "10", "the last-used time kept")
    eq(p.used_at(kind, { "EXACT", "10" }), 10)
    eq(p.app_name("org.mozilla.firefox"), "Firefox")
  end

  function tests.default_apps()
    local d = require("lib.services.default_apps")
    local cache = d.parse_cache("[MIME Cache]\ntext/html=firefox.desktop;chromium.desktop;\n")
    eq(cache["text/html"][2], "chromium.desktop")
    local kind = d.KINDS[1]
    local rows = d.candidates(kind, { ["text/html"] = { "firefox.desktop" }, ["x-scheme-handler/http"] = { "firefox.desktop" } },
      { ["firefox.desktop"] = { name = "Firefox" } })
    eq(#rows, 1, "one row per app") eq(rows[1].name, "Firefox")
    local refused
    d.set(kind, "../../evil", function(ok, why) refused = why end)
    truthy(refused, "a refusal of a bad id")
  end

  function tests.autostart()
    local a = require("lib.services.autostart")
    local keys = a.parse_desktop("[Desktop Entry]\nName=Thing\nHidden=true\n[Other]\nName=No\n")
    eq(keys.Name, "Thing") eq(keys.Hidden, "true")
    local text = a.with_hidden("[Desktop Entry]\nName=Thing\nHidden=false\n", true)
    truthy(text:find("Hidden=true", 1, true), "hidden")
    falsy(text:find("Hidden=false", 1, true), "both")
    truthy(a.with_hidden("[Desktop Entry]\nName=Thing\n", true):find("Hidden=true", 1, true), "added")
    local units = a.parse_unit_files("a.service enabled enabled\nb.service disabled enabled\nc.service static -\nd@.service enabled -\n")
    eq(#units, 2, "only what can be switched")
    eq(a.parse_units("  a.service loaded active running Thing here\n")["a.service"].description, "Thing here")
    local refused
    a.set_service("x; rm -rf", true, function(ok, why) refused = why end)
    truthy(refused, "a refusal of a bad unit")
  end

  function tests.connection_parse()
    local c = require("lib.services.connection")
    local raw = c.parse_terse("IP4.ADDRESS[1]:10.0.0.2/24\nIP4.ADDRESS[2]:10.0.0.3/24\nIP6.ADDRESS[1]:fe80\\:\\:1/64\nconnection.id:Home\n")
    eq(#raw["IP4.ADDRESS"], 2) eq(raw["IP6.ADDRESS"][1], "fe80::1/64") eq(raw["connection.id"], "Home")
    eq(c.parse_dot("-1"), "default", "as nmcli 1.56 prints it with -t")
    eq(c.parse_dot("2"), "yes") eq(c.parse_dot("1"), "opportunistic") eq(c.parse_dot("0"), "no")
    eq(c.parse_dot("-1 (default)"), "default") eq(c.parse_dot("yes"), "yes") eq(c.parse_dot(nil), "default")
  end
  function tests.connection_validate()
    local c = require("lib.services.connection")
    truthy(c.ipv4("192.168.1.1"), "an address") falsy(c.ipv4("300.1.1.1"), "a byte over 255")
    truthy(c.ipv4("10.0.0.2/24", true), "a prefixed address") falsy(c.ipv4("10.0.0.2", true), "no prefix")
    truthy(c.dns_list("1.1.1.1, 2606:4700::1"), "servers") falsy(c.dns_list("not dns"), "words")
    local words = c.modify_words { static = { address = "10.0.0.2/24", gateway = "10.0.0.1" }, dns = "1.1.1.1", metered = "yes" }
    truthy(has(words, "manual"), "manual") truthy(has(words, "10.0.0.2/24"), "address")
    truthy(has(words, "connection.metered"), "metered") truthy(has(words, "yes"), "ignoring the network's dns")
    falsy(c.modify_words { static = { address = "nope" } }, "a bad address")
    eq(c.modify_words { dns = "" }[2], "", "an empty list hands DNS back")
  end
  function tests.wifi_code()
    local c = require("lib.services.connection")
    eq(c.wifi_uri("My;Net", "wpa2", 'p:a"ss', false), 'WIFI:T:WPA;S:My\\;Net;P:p\\:a\\"ss;;')
    eq(c.wifi_uri("Cafe", "open", nil, true), "WIFI:T:nopass;S:Cafe;H:true;;")
    eq(c.wifi_uri("Old", "wep", "pw", false), "WIFI:T:WEP;S:Old;P:pw;;")
  end

  function tests.sound()
    local s = require("lib.services.sound_extras")
    eq(s.codec("a2dp-sink-ldac"), "LDAC") eq(s.codec("a2dp-sink-sbc_xq"), "SBC XQ") eq(s.codec("a2dp-sink"), "SBC")
    eq(s.codec("output:analog-stereo"), nil)
    -- The shape pw-dump gives on a real system: `available` is a word.
    local cards = s.parse_cards(morf.json.encode {
      { id = 7, type = "PipeWire:Interface:Node", info = { props = {} } },
      { id = 43, type = "PipeWire:Interface:Device", info = {
        props = { ["device.name"] = "bluez_card.A", ["device.api"] = "bluez5", ["device.description"] = "Buds" },
        params = { Profile = { { index = 1, name = "a2dp-sink-aac" } }, EnumProfile = {
          { index = 0, name = "off", available = "yes", priority = 0 },
          { index = 1, name = "a2dp-sink-aac", available = "yes", priority = 2 },
          { index = 2, name = "a2dp-sink-ldac", available = "no", priority = 3 },
          { index = 3, name = "headset-head-unit", available = "unknown", priority = 1 } } } } } })
    eq(#cards, 1, "only devices") eq(cards[1].bluetooth, true) eq(cards[1].codec, "AAC") eq(cards[1].id, 43)
    eq(#cards[1].profiles, 2, "what is off or unavailable is not offered")
    eq(cards[1].profiles[1].index, 1)
  end
  function tests.encryption_walks_the_stack()
    local privacy = require("privacy_page_model")
    local root = morf.env("XDG_CACHE_HOME") .. "/sys-block-fixture"
    morf.fs.mkdir(root .. "/dm-2/dm") morf.fs.write(root .. "/dm-2/dm/uuid", "LVM-abc\n")
    morf.fs.mkdir(root .. "/dm-2/slaves/dm-0")
    morf.fs.mkdir(root .. "/dm-0/dm") morf.fs.write(root .. "/dm-0/dm/uuid", "CRYPT-LUKS2-abc\n")
    morf.fs.mkdir(root .. "/dm-5/dm") morf.fs.write(root .. "/dm-5/dm/uuid", "LVM-def\n")
    morf.fs.mkdir(root .. "/dm-5/slaves/nvme0n1p2")
    truthy(privacy.on_crypt("dm-2", root), "LVM on LUKS")
    falsy(privacy.on_crypt("dm-5", root), "LVM on a plain partition")
  end
  function tests.xkbcli_list()
    local lib = require("lib.services.input_config")
    local rows = lib.parse_xkbcli("models:\n- name: 'pc104'\nlayouts:\n- layout: 'al'\n  variant: ''\n  brief: 'sq'\n  description: Albanian\n  iso639: ['sqi']\n- layout: 'al'\n  variant: 'plisi'\n  brief: 'sq'\n  description: Albanian (Plisi)\n")
    eq(#rows, 2) eq(rows[1].key, "al") eq(rows[1].name, "Albanian") eq(rows[2].key, "al:plisi")
    truthy(rows[2].words:find("Albanian", 1, true), "the parent's name to search by")
  end
  function tests.audio_rules()
    local r = require("audio_rules")
    local rows = { { id = 1, name = "speakers" }, { id = 2, name = "buds" } }
    eq(r.wanted(rows, { "buds", "speakers" }, "speakers").id, 2, "a preferred device takes over")
    eq(r.wanted(rows, { "speakers", "buds" }, "speakers"), nil, "the best is already in use")
    eq(r.wanted(rows, { "speakers", "buds" }, "other").id, 1, "an unlisted default gives way")
    eq(r.wanted(rows, {}, "speakers"), nil, "no rules, no change")
  end

  function tests.power()
    local lid = require("lid_watch")
    eq(lid.run_of("poweroff"), "shutdown") eq(lid.run_of("system"), nil) eq(lid.run_of("nothing"), nil)
  end

  function tests.about()
    local a = require("lib.services.about")
    eq(a.parse_os_release('PRETTY_NAME="NixOS 26.05"\n').PRETTY_NAME, "NixOS 26.05")
    local model, count = a.parse_cpu("processor : 0\nmodel name : Chip\nprocessor : 1\n")
    eq(model, "Chip") eq(count, 2)
    eq(a.parse_memory("MemTotal: 2 kB\n"), 2048)
    eq(a.parse_gpus("00:02.0 VGA compatible controller: Intel Iris (rev 01)\n")[1], "Intel Iris")
    eq(a.as_text { { name = "Kernel", value = "6" }, { name = "CPU", value = "x" } }, "Kernel: 6\nCPU: x")
  end
  function tests.timedate()
    local t = require("lib.services.timedate")
    eq(t.parse_locale { "LANG=en_US.UTF-8", "LC_TIME=nl_NL.UTF-8" }.LC_TIME, "nl_NL.UTF-8")
    truthy(t.valid_hostname("eva-book"), "a good name")
    falsy(t.valid_hostname("-bad"), "a leading dash") falsy(t.valid_hostname("has space"), "a space") falsy(t.valid_hostname(""), "nothing")
  end
  function tests.accounts()
    local a = require("lib.services.accounts")
    local path = morf.env("XDG_CACHE_HOME") .. "/group-fixture"
    morf.fs.write(path, "wheel:x:1:kate,root\nusers:x:100:guest\n")
    local admins = a.administrators(path)
    truthy(admins.kate, "kate") falsy(admins.guest, "guest")
  end
  function tests.trash()
    local t = require("lib.services.trash")
    local root = morf.env("XDG_CACHE_HOME") .. "/trash-fixture"
    morf.fs.mkdir(root .. "/files")
    morf.fs.write(root .. "/files/a.txt", "hello")
    eq(t.read(root).count, 1)
    eq(t.read(root .. "/none").count, 0, "no trash yet")
  end
  function tests.registry()
    local r = require("settings_registry")
    local seen = {}
    for _, row in ipairs(r.list()) do
      truthy(row.key and row.name and row.icon and row.keywords, "a whole row")
      falsy(seen[row.key], "a duplicate " .. row.key)
      seen[row.key] = true
      for key in pairs(row) do truthy(key == "key" or key == "name" or key == "icon" or key == "keywords", "a plain row") end
    end
    falsy(seen.home, "All settings among its own results")
    eq(r.search("wifi")[1].key, "network")
    eq(r.search("sticky")[1].key, "accessibility")
    eq(r.search("sticky")[1].name, "Sticky keys")
    eq(#r.search("no such setting xyz"), 0)
    eq(#r.search("   "), 0)
    truthy(#r.search("key repeat") >= 1, "two words")
  end
  function tests.forms_words()
    local f = require("settings_forms")
    local words = { "sh", "-c", "grim -g \"$(slurp)\" \"$0\"", "" }
    local back = f.split(f.join(words))
    eq(#back, 4) eq(back[3], words[3]) eq(back[4], "")
    eq(#f.split("  a   b "), 2)
    eq(#f.split(""), 0)
  end

  morf.ipc.run = function(name) tests[name]() return true end
]]

local names = {}
for name in HOST:gmatch("function tests%.([%w_]+)") do names[#names + 1] = name end
test.it("the service tests are all here", function() test.truthy(#names >= 24, "only " .. #names .. " tests found") end)
for _, name in ipairs(names) do
  test.it("settings: " .. name, function()
    test.load("../shell/init.lua", { size = { 100, 100 }, env = { EVA_DRY_RUN = "1" }, source = HOST })
    test.advance(50)
    test.truthy(test.ipc("run", name))
  end)
end

-- Secrets in the views: nothing that holds one may be a signal.
test.it("no password, PIN or passphrase is kept in a signal", function()
  local strays = {}
  for _, path in ipairs { "themes/layouts/views/connectivity.lua", "themes/layouts/views/settings_devices.lua",
    "themes/layouts/views/quick_pages.lua", "shell/storage_model.lua", "shell/connectivity_model.lua", "shell/connection_model.lua" } do
    local number = 0
    for line in (morf.fs.read(path) .. "\n"):gmatch("(.-)\n") do
      number = number + 1
      local name = line:match('morf%.signal%(%s*"([^"]+)"') or ""
      local lower = name:lower()
      if lower:find("password", 1, true) or lower:find("passphrase", 1, true) or lower:find("%.pin", 1, false)
        or lower:find("secret", 1, true) then
        strays[#strays + 1] = path .. ":" .. number .. " " .. name
      end
    end
  end
  test.eq(strays, {})
end)

test.it("a LUKS passphrase reaches only Unlock, and an enrolled command line never", function()
  test.load("../shell/init.lua", { size = { 100, 100 }, env = { EVA_FAKE_SYSTEM = "1" }, source = [[
    local ui = require("morf.ui")
    ui.Item { width = 10, height = 10 }
    local disks = require("lib.services.udisks").connect()
    morf.ipc.unlock = function()
      local fake = require("lib.services.host_fake")
      local row
      for _, each in ipairs(disks.volumes()) do if each.encrypted then row = each end end
      disks.unlock(row, "correct horse", function() end)
      return { row = row ~= nil, ran = fake.ran }
    end
    morf.ipc.result = function()
      local bus = require("lib.testing.dbus")
      local calls = bus.calls_to("Unlock")
      return { calls = #calls, secret = calls[1] and bus.plain(calls[1].args[1]),
        kept = require("lib.services.host_fake").unlocked_with }
    end
  ]] })
  test.advance(300)
  local first = test.ipc("unlock")
  test.truthy(first.row)
  test.advance(100)
  local after = test.ipc("result")
  test.eq(after.calls, 1)
  test.eq(after.secret, "correct horse")
  for _, argv in ipairs(first.ran) do
    for _, word in ipairs(argv) do test.falsy(tostring(word):find("correct horse", 1, true)) end
  end
end)

-- The layout OSD: the compositor's layout changing reaches the watch once, and
-- nothing fires for a reading that did not move.
test.it("switching layout fires the layout OSD, and only then", function()
  test.load("../shell/init.lua", { size = { 300, 200 }, env = { EVA_DRY_RUN = "1" }, source = [[
    local ui = require("morf.ui")
    ui.Item { width = 10, height = 10 }
    local state = morf.state { keyboard_layout = "English (US)" }
    package.loaded.services = { hyprland = { available = function() return true end, state = state },
      here = function() return false end }
    local fired = {}
    local sources = require("osd_sources")
    sources.watch(function(kind) fired[#fired + 1] = kind end)
    morf.ipc.layout = function(name) state.keyboard_layout = name return true end
    morf.ipc.fired = function() return fired end
    morf.ipc.reading = function() return sources.sources.layout.read().detail end
  ]] })
  test.advance(3000)
  test.eq(test.ipc("fired"), {})
  test.ipc("layout", "German") test.advance(100)
  test.eq(test.ipc("fired"), { "layout" })
  test.eq(test.ipc("reading"), "German")
  test.ipc("layout", "German") test.advance(100)
  test.eq(test.ipc("fired"), { "layout" })
end)
