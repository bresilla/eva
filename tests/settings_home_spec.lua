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

local function open() return test.ipc("settings", "state").open end
-- Whether the way round marks row `id` as the category on show.
local function marked(id)
  local row = test.accessible({ id = id })[1]
  return row ~= nil and row.checked == true
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the panel's All settings opens the window beside its way round", function()
    load(style)
    test.click("utilities-all-settings") test.settle(900)
    test.truthy(open(), "All settings opened no window")
    test.falsy(test.find { id = "drawer-sidebar", visible = true }, "the panel stayed under the window")
    test.truthy(test.find { id = "settings-index", visible = true }, "no index of every page beside the way round")
    test.truthy(test.find { id = "settings-nav-system", visible = true }, "no System category")
    test.falsy(test.find { id = "settings-nav-page-bluetooth" }, "the way round lists pages, not categories")
    test.click("settings-nav-device") test.settle(900)
    test.truthy(test.find { id = "settings-category-page-device", visible = true }, "a category of many opens their list")
    test.click("settings-open-bluetooth") test.settle(900)
    test.truthy(test.find { id = "bluetooth-scroll", visible = true })
    test.truthy(test.find { id = "settings-back", visible = true }, "a page under a category has no way back to its list")
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "settings-category-page-device", visible = true }, "Back from a page under a category does not reach its list")
    test.truthy(marked("settings-nav-device"), "the way round does not mark Bluetooth's category")
    -- A category of one page opens it.
    test.click("settings-nav-sound") test.settle(900)
    test.eq(test.ipc("settings", "state").page, "sound", "a category of one page did not open it")
    -- A page one level into another goes back to it.
    test.ipc("settings", "bar/tray") test.settle(900)
    test.truthy(marked("settings-nav-shell"), "the way round does not mark Desktop")
    test.truthy(test.find { text = "Which tray icons show", visible = true },
      "a nested page does not say what it holds")
    test.click("settings-back") test.settle(900)
    test.eq(test.ipc("settings", "state").page, "bar", "Back from a nested page goes to its parent")
    test.key("Escape") test.settle(900)
    test.falsy(open(), "Escape left the window open")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": on a phone Back walks the pages, one at a time, to All settings", function()
    load(style, { 412, 915 })
    test.click("utilities-all-settings") test.settle(900)
    test.truthy(test.find { id = "settings-home", visible = true })
    test.falsy(test.find { id = "settings-navigation", visible = true }, "a phone has no way round beside the page")
    test.click("settings-category-device") test.settle(900)
    test.click("settings-open-bluetooth") test.settle(900)
    test.truthy(test.find { id = "bluetooth-scroll", visible = true })
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "settings-category-page-device", visible = true }, "Back from a page goes to its category")
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "settings-home", visible = true }, "Back from a category goes home")
    test.falsy(test.find { id = "settings-back", visible = true }, "home has a way back")
    -- A category of one page opens it, and Back goes home from it.
    test.click("settings-category-sound") test.settle(900)
    test.eq(test.ipc("settings", "state").page, "sound", "a category of one page did not open it")
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "settings-home", visible = true }, "Back from a category's one page goes home")
    -- A page a tile opens goes back up its category.
    test.ipc("settings", "bluetooth") test.settle(900)
    test.click("settings-back") test.settle(900)
    test.truthy(test.find { id = "settings-category-page-device", visible = true }, "A deep link goes back to its category")
    test.click("settings-close") test.settle(900)
    test.falsy(open(), "the close control left it open")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": Back returns to the place in a list, and a list opened anew starts at its top", function()
    load(style, { 412, 600 })
    test.ipc("settings", "home") test.settle(900)
    test.click("settings-category-device") test.settle(900)
    local top = test.get("settings-open-input").y
    test.wheel(0, 200, { x = 200, y = 300 }) test.settle(2000)
    local scrolled = test.get("settings-open-input").y
    test.truthy(scrolled < top - 40, "the list did not scroll")
    test.click("settings-open-input") test.settle(900)
    test.click("settings-back") test.settle(900)
    test.near(test.get("settings-open-input").y, scrolled, 2, "Back lost the place")
    test.click("settings-back") test.settle(1200)
    test.click("settings-category-device") test.settle(900)
    test.near(test.get("settings-open-input").y, top, 2, "a list opened anew kept its old place")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": search finds a page and a setting, Enter opens it, and a shut window forgets it", function()
    load(style)
    test.ipc("settings", "home") test.settle(900)
    test.type("repeat") test.settle(300)
    test.truthy(test.find { text = "Key repeat", visible = true }, "a setting is found by its name")
    test.falsy(test.find { id = "settings-nav-connections", visible = true })
    test.ipc("settings", "close") test.settle(900)
    test.ipc("settings", "home") test.settle(900)
    test.truthy(test.find { id = "settings-nav-connections", visible = true }, "the search was forgotten")
    test.type("firewall") test.settle(300)
    test.key("Return") test.settle(900)
    test.truthy(test.find { id = "firewall-scroll", visible = true }, "Enter opens the first result")
    test.truthy(marked("settings-nav-privacy"), "the way round does not mark its category")
  end)

  test.it(style .. ": on a phone the window holds the same home, the whole screen", function()
    load(style, { 412, 915 })
    test.ipc("settings", "home") test.settle(900)
    test.truthy(test.find { id = "settings-home", visible = true })
    test.truthy(test.find { id = "settings-search", visible = true })
    local box, window = test.get("settings-home"), test.get("settings-window")
    test.truthy(box.x >= 0 and box.x + box.width <= 412, "the home leaves the phone's width")
    test.eq({ window.x, window.y, window.width, window.height }, { 0, 0, 412, 915 }, "the window does not fill the phone")
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
      "shell/appearance_model.lua", "shell/island.lua", "shell/standby_model.lua",
      "shell/focus_model.lua", "shell/focus_page.lua", "shell/notification_settings.lua",
      "shell/notification_rules.lua", "shell/bar_store.lua", "shell/bar_page.lua", "shell/bar_custom.lua", "shell/panels_board.lua",
      "lib/shell/launcher/pins.lua", "shell/launcher_modes/web.lua",
      "shell/assistant_model.lua", "shell/calendar_sources.lua", "shell/notes_model.lua", "shell/net_help_model.lua",
      "shell/charge_limit_model.lua",
      "shell/haptics.lua", "shell/mobile_model.lua", "themes/layouts/views/connectivity.lua", "shell/keyboard.lua",
      "shell/quick_tiles.lua", "shell/idle_model.lua", "shell/idle_page.lua", "shell/lock_page.lua",
      "themes/layouts/views/idle_page.lua", "themes/layouts/views/lock_page.lua",
      "shell/windows_page.lua", "themes/layouts/views/windows_page.lua",
      "shell/screen_time_model.lua", "themes/layouts/views/screen_time_page.lua",
      "shell/touch_page.lua", "shell/touch_bindings.lua",
      "shell/keys_model.lua", "shell/about_model.lua",
      "shell/layouts_model.lua",
      "themes/layouts/views/assistant_settings.lua", "themes/layouts/views/calendar_settings.lua",
      "themes/layouts/views/bar_page.lua", "themes/layouts/views/utilities.lua",
      "themes/layouts/views/notification_settings.lua" } do
      local ok, text = pcall(morf.fs.read, name)
      if ok then pages[#pages + 1] = text end
    end
    local sources = table.concat(pages, "\n")
    local reached = require("settings_forms").keys()
    -- Kept by the shell itself: what it remembers, not what a person sets;
    -- then what only the settings file sets.
    local kept = { "airplane.on", "airplane.was", "ringer.mode", "capture.tools", "bar.modules", "bar.small",
      "bar.outputs", "appearance.density", "appearance.font_file", "theme.variant" }
    local groups = { "osd.kinds", "lule", "quick", "input", "accessibility", "sound", "power", "storage", "proxy", "nightlight",
      "edgebar", "dashboard", "sidebar", "leftbar", "bottom", "capture.tools", "appearance", "rotation", "polkit", "osd",
      "notifications", "wallpaper", "desktop", "island", "bar", "focus", "standby", "panels", "assistant", "calendar",
      "keyboard", "filters", "phone", "idle", "lock", "windows", "gestures" }
    -- Each list by the first part of its keys: a key looks only at its own.
    local function by_head(list)
      local out = {}
      for _, each in ipairs(list) do
        local head = each:match("^[^%.]+")
        out[head] = out[head] or {}
        out[head][#out[head] + 1] = each
      end
      return out
    end
    local kept_by_head, groups_by_head = by_head(kept), by_head(groups)
    local function covered(key)
      if reached[key] then return true end
      local head = key:match("^[^%.]+")
      for _, each in ipairs(kept_by_head[head] or {}) do
        if key == each or key:sub(1, #each + 1) == each .. "." then return true end
      end
      for _, each in ipairs(groups_by_head[head] or {}) do
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

test.it("Settings holds what eva-info and eva-update showed", function()
  test.load("../shell/init.lua", { size = { 300, 200 }, env = { EVA_DRY_RUN = "1" }, source = HOST .. [[
    morf.ipc.tools = function()
      local about = require("about_model")
      return { info = about.about().info ~= nil, update = about.updates().check ~= nil }
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

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": a window too narrow for two panes shows one page at a time", function()
    load(style, { 800, 600 })
    test.ipc("settings", "home") test.settle(900)
    local window = test.get("settings-window")
    test.truthy(window.width < 800, "the window filled a desk")
    test.falsy(test.find { id = "settings-navigation", visible = true }, "two panes in a narrow window")
    test.truthy(test.find { id = "settings-home", visible = true }, "no home of categories")
    test.click("settings-category-sound") test.settle(900)
    test.truthy(test.find { id = "settings-back", visible = true }, "no way back with one page at a time")
    test.eq(#test.logs("error"), 0)
  end)
end
