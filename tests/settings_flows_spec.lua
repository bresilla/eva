-- The Settings pages used: a press in the shell, through the model and the real
-- service code, to the stand-in's end of the bus or command, and back.
--
--     morf test --no-dbus tests/settings_flows_spec.lua
local test = morf.test

local function load(style, env)
  local settings = morf.env("XDG_CACHE_HOME") .. "/settings-flows-" .. style .. ".json"
  morf.fs.remove(settings)
  local vars = { EVA_STYLE = style, EVA_DRY_RUN = "", EVA_FAKE_SYSTEM = "1", EVA_SETTINGS = settings, EVA_WALLPAPER = "",
    EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") }
  for key, value in pairs(env or {}) do vars[key] = value end
  test.load("../shell/init.lua", { size = { 1920, 1080 }, env = vars })
  test.settle(1500)
  test.ipc("utilities", "open")
  test.settle(800)
end

-- Inline: the models with no shell around them.
local hosted = 0
local function host(source, env)
  hosted = hosted + 1
  local fresh = morf.env("XDG_CACHE_HOME") .. "/settings-flows-host-" .. hosted .. ".json"
  morf.fs.remove(fresh)
  local vars = { EVA_FAKE_SYSTEM = "1", EVA_DRY_RUN = "", EVA_SETTINGS = fresh }
  for key, value in pairs(env or {}) do vars[key] = value end
  test.load("../shell/init.lua", { size = { 300, 200 }, env = vars, source = [[
    local ui = require("morf.ui")
    ui.Item { width = 10, height = 10 }
  ]] .. source })
  test.advance(200)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": unlocking a drive sends the passphrase once, and clears the prompt", function()
    load(style)
    test.ipc("settings", "storage") test.settle(900)
    test.click("storage-drive-unlock-2") test.settle(300)
    test.truthy(test.find { id = "storage-unlock-prompt", visible = true })
    test.type("correct horse") test.settle(200)
    test.key("Return") test.settle(500)
    test.falsy(test.find { id = "storage-unlock-prompt", visible = true }, "the prompt stayed")
    test.eq(test.get("storage-passphrase").text, "", "the field kept the passphrase")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": the microphone test shows a live level and stops with the page", function()
    load(style)
    test.ipc("settings", "microphone") test.settle(900)
    test.click("sound-test-button") test.settle(600)
    test.truthy(test.find { id = "sound-test-level", visible = true }, "no level shown")
    test.truthy(test.find { text = "A good level", visible = true }, "no verdict on the level")
    test.ipc("settings", "sound") test.settle(900)
    test.ipc("settings", "microphone") test.settle(900)
    test.falsy(test.find { id = "sound-test-level", visible = true }, "the test outlived its page")
  end)

  test.it(style .. ": a plugged drive brings its popup, and the setting stops it", function()
    load(style)
    test.clear_logs()
    test.ipc("fake-plug") test.advance(500)
    test.truthy(test.find { id = "drive-popup", visible = true }, "no popup: " .. tostring((test.logs("warn")[1] or {}).message))
    test.truthy(test.find { text = "CAMERA", visible = true }, "the popup does not name the drive")
    test.click("drive-popup-close") test.settle(200)
    test.falsy(test.find { id = "drive-popup", visible = true })
  end)
end

test.it("sharing Wi-Fi reads the secret over the bus and encodes it with no program", function()
  host([[
    local fake = require("lib.services.host_fake")
    local model = require("connection_model")
    local drew, failed
    morf.ipc.share = function()
      model.share({ ssid = "Home", security = "wpa2" }, function(code) drew = code.size end, function(why) failed = why end)
      return true
    end
    morf.ipc.state = function() return { drew = drew, failed = failed, stdin = fake.stdin, ran = fake.ran } end
  ]])
  test.ipc("share") test.advance(200)
  local state = test.ipc("state")
  test.eq(state.failed, nil)
  test.eq(state.drew, 29)
  test.falsy((state.stdin or ""):find("fixture passphrase", 1, true), "the secret went to a program")
  for _, argv in ipairs(state.ran) do
    for _, word in ipairs(argv) do test.falsy(tostring(word):find("fixture passphrase", 1, true), "the secret on a command line") end
  end
end)

test.it("a choice reaches Hyprland, and again after every reload", function()
  host([[
    local input = require("input_model")
    local fake = require("lib.services.host_fake")
    local conf = require("lib.compositor.hyprland_config")
    input.available()
    conf.set_flavour("lua")
    input.start()
    morf.ipc.choose = function() input.choose("repeat_rate", 40) return true end
    morf.ipc.reload = function() fake.last_hyprland.sent = {} fake.last_hyprland.fire("configreloaded") return true end
    morf.ipc.sent = function() return fake.last_hyprland.sent end
  ]])
  test.ipc("choose") test.advance(100)
  test.truthy(table.concat(test.ipc("sent"), "\n"):find("repeat_rate = 40", 1, true), "the choice was not sent")
  test.ipc("reload") test.advance(100)
  test.truthy(table.concat(test.ipc("sent"), "\n"):find("repeat_rate = 40", 1, true), "it was not sent again after a reload")
end)

test.it("nothing is sent to Hyprland until something is chosen", function()
  host([[
    local input = require("input_model")
    local fake = require("lib.services.host_fake")
    input.available()
    input.start()
    morf.ipc.sent = function() return fake.last_hyprland.sent end
  ]])
  test.advance(100)
  test.eq(test.ipc("sent"), {})
end)

test.it("closing the lid runs what Settings chose, and leaves System to logind", function()
  host([[
    local config = require("config")
    package.loaded.session = { run = function(id) morf.ipc.ran = nil morf.ipc.last = function() return id end end }
    morf.ipc.last = function() return "" end
    local fake = require("lib.services.host_fake")
    require("lid_watch").start()
    morf.ipc.choose = function(value) config.set("power.lid_ac", value) config.set("power.lid_battery", value) return true end
    morf.ipc.lid = function(closed) fake.lid(closed == "yes") return true end
  ]])
  test.ipc("lid", "yes") test.advance(100)
  test.eq(test.ipc("last"), "", "System belongs to logind")
  test.ipc("lid", "no") test.advance(100)
  test.ipc("choose", "lock") test.advance(100)
  test.ipc("lid", "yes") test.advance(100)
  test.eq(test.ipc("last"), "lock")
end)

test.it("the shell takes from logind only what is chosen, so the rest keeps working", function()
  host([[
    local config = require("config")
    local lid = require("lid_watch")
    morf.ipc.taken = function(lid_ac, lid_battery, button, battery)
      config.set("power.lid_ac", lid_ac) config.set("power.lid_battery", lid_battery) config.set("power.button", button)
      return lid.taken(battery == "yes")
    end
  ]])
  test.eq(test.ipc("taken", "system", "system", "system", "no"), "", "nothing chosen, nothing held")
  test.eq(test.ipc("taken", "lock", "system", "system", "no"), "handle-lid-switch", "the power button stays logind's")
  test.eq(test.ipc("taken", "lock", "system", "system", "yes"), "", "on battery the lid stays logind's")
  test.eq(test.ipc("taken", "system", "system", "lock", "no"), "handle-power-key", "the lid stays logind's")
  test.eq(test.ipc("taken", "suspend", "suspend", "lock", "yes"), "handle-lid-switch:handle-power-key")
end)

test.it("changing layouts rebuilds the sticky keymap", function()
  host([[
    local config = require("config")
    local fake = require("lib.services.host_fake")
    local input = require("input_model")
    input.available()
    require("lib.compositor.hyprland_config").set_flavour("lua")
    config.set("accessibility.sticky_keys", true)
    morf.ipc.rebuild = function()
      fake.ran = {}
      require("access_model").rebuild()
      return true
    end
    morf.ipc.ran = function()
      local out = {}
      for _, argv in ipairs(fake.ran) do out[#out + 1] = table.concat(argv, " ") end
      return out
    end
  ]])
  test.ipc("rebuild") test.advance(100)
  test.truthy(table.concat(test.ipc("ran"), "\n"):find("xkbcli compile-keymap", 1, true), "the keymap was not rebuilt")
end)

test.it("a disk under the limit warns once until it recovers", function()
  host([[
    local storage = require("storage_model")
    local free = 5
    storage.usage = function() return { free = free, total = 100, used = 100 - free, share = (100 - free) / 100 } end
    local pushed = 0
    package.loaded.notifs = { push = function() pushed = pushed + 1 end }
    local watch = require("drive_watch")
    morf.ipc.check = function(left) free = tonumber(left) watch.check { "/" } return pushed end
  ]])
  test.eq(test.ipc("check", "5"), 1)
  test.eq(test.ipc("check", "4"), 1, "warned twice")
  test.eq(test.ipc("check", "50"), 1)
  test.eq(test.ipc("check", "5"), 2, "did not warn again after recovering")
end)

test.it("large text and high contrast are in force from the theme up", function()
  local settings = morf.env("XDG_CACHE_HOME") .. "/settings-access.json"
  morf.fs.write(settings, '{ "appearance": { "text_scale": 1.5, "high_contrast": true } }')
  host([[
    morf.ipc.reading = function()
      local theme = require("theme")
      return { size = theme.size.normal, variant = theme.color.onSurfaceVariant:hex(), text = theme.color.onSurface:hex(),
        surface = theme.color.surface:hex() }
    end
  ]], { EVA_SETTINGS = settings, EVA_THEME_MODE = "dark" })
  local got = test.ipc("reading")
  test.eq(got.size, 24)
  test.eq(got.variant, got.text, "secondary text is not at full strength")
  test.eq(got.surface:sub(1, 7):lower(), "#000000")
end)

test.it("a NixOS configuration's values say so, and offer nothing that would fail", function()
  load("material", { EVA_FAKE_SYSTEM = "nixos" })
  test.ipc("settings", "datetime") test.settle(900)
  test.truthy(test.find { id = "datetime-declared", visible = true }, "the time zone is not marked as declared")
  test.falsy(test.find { id = "datetime-zone", visible = true }, "a picker that cannot work")
  test.ipc("settings", "region") test.settle(900)
  test.truthy(test.find { id = "region-declared", visible = true })
  test.ipc("settings", "firewall") test.settle(900)
  test.truthy(test.find { id = "firewall-declared", visible = true })
  test.ipc("settings", "about") test.settle(900)
  test.truthy(test.find { id = "about-declared", visible = true })
  test.ipc("settings", "users") test.settle(900)
  test.truthy(test.find { id = "users-declared", visible = true })
  test.ipc("settings", "printers") test.settle(900)
  test.truthy(test.find { id = "printers-declared", visible = true })
end)
