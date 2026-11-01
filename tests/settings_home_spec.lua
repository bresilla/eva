-- All settings: the way in from the panel, the categories, search, Back, and
-- that nothing a person might set is out of reach.
--
--     morf test --no-dbus tests/settings_home_spec.lua
local test = morf.test

local function load(style, size)
  local settings = morf.env("XDG_CACHE_HOME") .. "/settings-home-" .. style .. ".json"
  morf.fs.remove(settings)
  test.load("../shell/init.lua", { size = size or { 1920, 1080 }, env = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_FAKE_SYSTEM = "1",
    EVA_SETTINGS = settings, EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(1500)
  test.ipc("utilities", "open")
  test.settle(900)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the panel leads to All settings, and Back returns where it came from", function()
    load(style)
    test.click("utilities-all-settings") test.settle(900)
    test.truthy(test.find { id = "settings-home", visible = true })
    test.truthy(test.find { id = "settings-category-title-system", visible = true } or test.find { id = "settings-category-system", visible = true })
    test.click("settings-open-bluetooth") test.settle(900)
    test.truthy(test.find { id = "bluetooth-scroll", visible = true })
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "settings-home", visible = true }, "Back from a page opened at home goes home")
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "utilities-all-settings", visible = true }, "Back from home goes to the panel")
    -- A page a tile opens still goes back to the panel.
    test.ipc("settings", "bluetooth") test.settle(900)
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "utilities-all-settings", visible = true }, "A deep link goes back to the panel")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": search finds a page and a setting, Enter opens it, and a shut panel forgets it", function()
    load(style)
    test.ipc("settings", "home") test.settle(900)
    test.type("repeat") test.settle(300)
    test.truthy(test.find { text = "Key repeat", visible = true }, "a setting is found by its name")
    test.falsy(test.find { id = "settings-category-connections", visible = true })
    -- Escape shuts the panel, as it does from any field in one.
    test.key("Escape") test.settle(900)
    test.ipc("utilities", "open") test.settle(900)
    test.ipc("settings", "home") test.settle(900)
    test.truthy(test.find { id = "settings-category-connections", visible = true }, "the search was forgotten")
    test.type("firewall") test.settle(300)
    test.key("Return") test.settle(900)
    test.truthy(test.find { id = "firewall-scroll", visible = true }, "Enter opens the first result")
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "settings-home", visible = true })
  end)

  test.it(style .. ": on a phone the sheet holds the same home", function()
    load(style, { 412, 915 })
    test.ipc("settings", "home") test.settle(900)
    test.truthy(test.find { id = "settings-home", visible = true })
    test.truthy(test.find { id = "settings-search", visible = true })
    local box = test.get("settings-home")
    test.truthy(box.x >= 0 and box.x + box.width <= 412, "the home leaves the phone's width")
  end)
end

local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local function leaves(tree, prefix, out)
    for key, value in pairs(tree) do
      local path = prefix == "" and key or (prefix .. "." .. key)
      if type(value) == "table" and next(value) ~= nil and value[1] == nil then leaves(value, path, out)
      else out[#out + 1] = path end
    end
    return out
  end
  morf.ipc.unreached = function()
    -- What the pages that are not forms write to, by key.
    local pages = {}
    for _, name in ipairs { "shell/bar_settings_model.lua", "shell/settings_model.lua", "shell/input_model.lua", "shell/access_model.lua",
      "shell/lid_watch.lua",
      "shell/sound_extras_model.lua", "shell/power_extras_model.lua", "shell/storage_model.lua", "shell/privacy_page_model.lua",
      "shell/connection_model.lua", "shell/osd_model.lua", "shell/quick_hardware.lua", "shell/datetime_model.lua",
      "themes/color_mode.lua", "shell/lule_page.lua", "shell/lule_model.lua", "shell/lule_studio.lua",
      "shell/equalizer_model.lua", "shell/tiles_model.lua", "shell/bar.lua", "shell/capture.lua", "shell/capture_editor.lua",
      "shell/appearance_model.lua", "shell/wallpaper_model.lua", "shell/desktop_model.lua", "shell/island.lua", "shell/standby_model.lua",
      "shell/profiles_model.lua", "shell/focus_model.lua", "shell/focus_page.lua", "shell/notification_settings.lua",
      "shell/notification_rules.lua", "shell/bar_store.lua", "shell/bar_page.lua", "shell/bar_custom.lua", "shell/panels_board.lua",
      "lib/shell/launcher/pins.lua", "shell/launcher_modes/web.lua",
      "shell/assistant_model.lua", "shell/calendar_sources.lua", "shell/notes_model.lua", "shell/net_help_model.lua",
      "shell/charge_limit_model.lua",
      "shell/haptics.lua", "shell/mobile_model.lua", "themes/layouts/views/connectivity.lua", "shell/keyboard.lua",
      "shell/quick_tiles.lua", "shell/idle_model.lua", "shell/idle_page.lua", "shell/lock_page.lua",
      "themes/layouts/views/idle_page.lua", "themes/layouts/views/lock_page.lua",
      "shell/windows_page.lua", "themes/layouts/views/windows_page.lua",
      "themes/layouts/views/assistant_settings.lua", "themes/layouts/views/calendar_settings.lua",
      "themes/layouts/views/look_page.lua", "themes/layouts/views/wallpaper_page.lua", "themes/layouts/views/desktop_page.lua",
      "themes/layouts/views/bar_page.lua", "themes/layouts/views/utilities.lua",
      "themes/layouts/views/notification_settings.lua" } do
      local ok, text = pcall(morf.fs.read, name)
      if ok then pages[#pages + 1] = text end
    end
    local sources = table.concat(pages, "\n")
    local reached = require("settings_forms").keys()
    -- Kept by the shell itself: what it remembers, not what a person sets.
    -- `bar.workspaces.shown` is read by nothing.
    local kept = { "airplane.on", "airplane.was", "ringer.mode", "capture.tools", "bar.workspaces.shown", "bar.modules", "bar.small",
      "bar.outputs", "wallpaper.fits" }
    local groups = { "osd.kinds", "lule", "quick", "input", "accessibility", "sound", "power", "storage", "proxy", "nightlight",
      "edgebar", "dashboard", "sidebar", "leftbar", "bottom", "capture.tools", "appearance", "rotation", "polkit", "osd",
      "notifications", "wallpaper", "desktop", "island", "bar", "focus", "standby", "panels", "assistant", "calendar",
      "keyboard", "filters", "phone", "idle", "lock", "dock", "windows" }
    local function covered(key)
      if reached[key] then return true end
      for _, each in ipairs(kept) do if key == each or key:sub(1, #each + 1) == each .. "." then return true end end
      for _, each in ipairs(groups) do
        if key:sub(1, #each + 1) == each .. "." and sources:find(key:sub(#each + 2):match("[^%.]+"), 1, true) then return true end
      end
      return sources:find(key, 1, true) ~= nil
    end
    local out = {}
    for _, key in ipairs(leaves(require("config").defaults or {}, "", {})) do
      if not covered(key) then out[#out + 1] = key end
    end
    table.sort(out)
    return out
  end
  morf.ipc.keys_named = function()
    local forms, known, out = require("settings_forms"), require("config"), {}
    for key in pairs(forms.keys()) do
      if known.get(key) == nil then out[#out + 1] = key end
    end
    table.sort(out)
    return out
  end
]]

-- What logind says this machine cannot do is not offered, in either place the
-- session's actions are.
for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": session buttons follow CanSuspend and CanHibernate", function()
    local env = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_FAKE_SYSTEM = "1", EVA_FAKE_CAN = "suspend=no,hibernate=na",
      EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") }
    test.load("../shell/init.lua", { size = { 1920, 1080 }, env = env })
    test.settle(1500)
    test.ipc("utilities", "open") test.settle(900)
    test.falsy(test.find { id = "utilities-session-suspend", visible = true }, "Suspend offered where logind says no")
    test.truthy(test.find { id = "utilities-session-reboot", visible = true }, "Restart gone")
    test.ipc("close") test.settle(500)
    test.ipc("session", "open") test.settle(900)
    test.falsy(test.find { text = "Hibernate", visible = true } or test.find { text = "HIBERNATE", visible = true }, "Hibernate offered")
    env.EVA_FAKE_CAN = "suspend=challenge"
    test.load("../shell/init.lua", { size = { 1920, 1080 }, env = env })
    test.settle(1500)
    test.ipc("utilities", "open") test.settle(900)
    test.truthy(test.find { id = "utilities-session-suspend", visible = true }, "challenge means polkit asks, so it stays")
  end)
end

test.it("Settings reaches eva-info and eva-update, now that they exist", function()
  test.load("../shell/init.lua", { size = { 300, 200 }, env = { EVA_DRY_RUN = "1" }, source = HOST .. [[
    morf.ipc.tools = function()
      local about = require("about_model")
      return { info = about.about().can_info(), update = about.updates().available() }
    end
  ]] })
  test.advance(100)
  test.eq(test.ipc("tools"), { info = true, update = true })
end)

test.it("a times field keeps each time of day once, in order, and nothing else", function()
  test.load("../shell/init.lua", { size = { 300, 200 }, env = { EVA_DRY_RUN = "1" }, source = HOST .. [[
    morf.ipc.times = function(line)
      local forms = require("settings_forms")
      return forms.times(forms.split(line))
    end
  ]] })
  test.advance(100)
  test.eq(test.ipc("times", "18:00 08:00"), { "08:00", "18:00" })
  test.eq(test.ipc("times", "8:05,18:30"), { "08:05", "18:30" })
  test.eq(test.ipc("times", "23:59 00:00 00:00"), { "00:00", "23:59" })
  test.eq(test.ipc("times", "24:00 12:60 123:45 12:345 noon"), {})
end)

test.it("a records field keeps its tables through one line of words", function()
  test.load("../shell/init.lua", { size = { 300, 200 }, env = { EVA_DRY_RUN = "1" }, source = HOST .. [[
    morf.ipc.records = function()
      local forms = require("settings_forms")
      local fields = { "name", "url" }
      local line = forms.join_records({ { name = "Two words", url = "https://a/{query}" }, { name = "b", url = "https://b" } }, fields)
      return { line = line, back = forms.split_records(line .. " short", fields) }
    end
  ]] })
  test.advance(100)
  local said = test.ipc("records")
  test.eq(said.line, '"Two words" https://a/{query} b https://b')
  test.eq(said.back, { { name = "Two words", url = "https://a/{query}" }, { name = "b", url = "https://b" } })
end)

test.it("every key the forms name is a real key", function()
  test.load("../shell/init.lua", { size = { 300, 200 }, env = { EVA_DRY_RUN = "1" }, source = HOST })
  test.advance(100)
  test.eq(test.ipc("keys_named"), {})
end)

test.it("every setting a person might want is reachable from a page", function()
  test.load("../shell/init.lua", { size = { 300, 200 }, env = { EVA_DRY_RUN = "1" }, source = HOST })
  test.advance(100)
  test.eq(table.concat(test.ipc("unreached"), " "), "")
end)
