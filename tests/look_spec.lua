-- The look of everything: the colour mode and what turns it, schemes by name,
-- what the rest of the desktop is told, glass, density, corners, the font file,
-- and the song's colours.
--
--     morf test --no-dbus tests/look_spec.lua
local test = morf.test
local ROOT = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/wallpapers")

local SOURCE = [[
  local fonts = require("themes.fonts")
  local set_font, font_calls = fonts.set, {}
  fonts.set = function(choice, done)
    font_calls[#font_calls + 1] = choice.file
    return set_font(choice, done)
  end
  morf.ipc.l_font_calls = function() return font_calls end
  require("init")
  local config = require("config")
  local theme = require("theme")
  local model = require("appearance_model")
  local mode = require("themes.color_mode")
  local look = require("lib.services.desktop_look")
  local schemes = require("themes.schemes")
  morf.ipc.l_set = function(key, value) return config.set(key, value) end
  morf.ipc.l_get = function(key) return config.get(key) end
  morf.ipc.l_mode = function() return model.mode() end
  morf.ipc.l_chosen = function() return mode.chosen() end
  morf.ipc.l_choose = function(value) mode.set(value) end
  morf.ipc.l_schedule = function(a, b) return mode.set_schedule(a, b) end
  morf.ipc.l_snooze = function(value, seconds) mode.snooze(value, seconds) end
  morf.ipc.l_pref = function(key, value)
    local kept = require("themes").preferences
    if value ~= nil then kept.set(key, value) end
    return kept.get(key)
  end
  morf.ipc.l_color = function(role) return theme.color[role]:hex():sub(1, 7) end
  morf.ipc.l_lule = function(role) return theme.lule[role]:hex():sub(1, 7) end
  morf.ipc.l_alpha = function(role) return require("themes.glass").fill(theme.color[role]).a end
  morf.ipc.l_space = function(key) return theme.space[key] end
  morf.ipc.l_tokens = function() return { rounding = theme.ROUNDING, seam = theme.SEAM, pad = theme.PAD, gap = theme.GAP, corners = theme.corners } end
  morf.ipc.l_round = function(r) return require("kit").round(r) end
  morf.ipc.l_plan = function(want)
    local plan = look.plan(want)
    return plan
  end
  morf.ipc.l_ini = function(text, section, key, value) return look.ini_set(text, section, key, value) end
  local failures
  morf.ipc.l_failed = function() return failures end
  morf.ipc.l_apply = function(want)
    return look.apply(look.plan(want), function(failed) failures = failed end)
  end
  morf.ipc.l_themes = function() return look.themes() end
  morf.ipc.l_sequences = function(palette) return look.sequences(palette) end
  morf.ipc.l_terminals = function(palette) return look.terminals(palette) end
  morf.ipc.l_qt = function() return look.qt_palette(model.qt_colors()) end
  morf.ipc.l_local = function(utc, zone) return model.local_time(utc, zone) end
  morf.ipc.l_sun = function() model.find_sun() end
  morf.ipc.l_font = function(path)
    local taken
    fonts.set({ file = path }, function(ok) taken = ok end)
    return taken
  end
  morf.ipc.l_scheme = function(id, value) local f = schemes.flavour(id, value) return f and f.ground end
  morf.ipc.l_schemes = function() local out = {} for i, s in ipairs(schemes.LIST) do out[i] = s.id end return out end
  morf.ipc.l_accent = function(text) return require("song_theme").accent_of(text) end
  morf.ipc.l_song = function() return theme.song:get() end
  morf.ipc.l_play = function(art, playing)
    require("services").player = function() return { art_url = art, playing = playing } end
    config.set("theme.follow_song", false)
    config.set("theme.follow_song", true)
  end
]]

local serial = 0
local function load(spec)
  spec = spec or {}
  serial = serial + 1
  local cache = morf.env("XDG_CACHE_HOME")
  local home = cache .. "/look-home-" .. serial
  morf.fs.mkdir(home, { parents = true })
  local env = { EVA_DRY_RUN = spec.live and "0" or "1", EVA_STYLE = spec.style or "material", EVA_WALLPAPER = "",
    EVA_SETTINGS = cache .. "/look-settings-" .. serial .. ".json",
    EVA_APPEARANCE = cache .. "/look-appearance-" .. serial .. ".json",
    LULE_A = "/nonexistent/lule", HOME = home, XDG_CONFIG_HOME = home .. "/config", EVA_FAKE_CLOCK = spec.clock or "",
    EVA_THEME_MODE = spec.forced or "", EVA_ICON_DIRS = spec.icons or "", EVA_FAKE_PTS = spec.pts }
  morf.fs.write(env.EVA_SETTINGS, morf.json.encode(spec.settings or {}))
  if spec.appearance then morf.fs.write(env.EVA_APPEARANCE, morf.json.encode(spec.appearance)) end
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = SOURCE, size = spec.size or { 1600, 1000 }, env = env })
  test.settle(1200)
  return home, env
end

test.describe("the colour mode", function()
  test.it("turns by the clock, across midnight too", function()
    load { clock = "12:00", appearance = { mode = "schedule" } }
    test.eq(test.ipc("l_chosen"), "schedule")
    test.eq(test.ipc("l_mode"), "light")
    load { clock = "23:30", appearance = { mode = "schedule" } }
    test.eq(test.ipc("l_mode"), "dark")
    load { clock = "02:00", appearance = { mode = "schedule", light_from = "22:00", dark_from = "06:00" } }
    test.eq(test.ipc("l_mode"), "light", "a schedule across midnight broke")
  end)

  test.it("turns by the sun's times once they are known, and stands by the tool until then", function()
    load { clock = "12:00", appearance = { mode = "sun" } }
    test.eq(test.ipc("l_mode"), "dark", "no sunrise yet: the tool's mode stands")
    test.ipc("l_pref", "sunrise", "07:40")
    test.ipc("l_pref", "sunset", "17:10")
    test.advance(16)
    test.eq(test.ipc("l_mode"), "light")
    load { clock = "18:00", appearance = { mode = "sun", sunrise = "07:40", sunset = "17:10" } }
    test.eq(test.ipc("l_mode"), "dark")
  end)

  test.it("finds the sun through eva-nightlight and keeps it in local time", function()
    test.stub_run("eva-nightlight", { code = 0, stdout = "sunrise 06:30\nsunset 16:45\n" })
    load { appearance = { mode = "dark" } }
    test.ipc("l_sun")
    test.wait(function() test.advance(16) return test.ipc("l_pref", "sunrise") ~= "" end, 3000, "the sun was never found")
    test.eq(test.ipc("l_local", "06:30", "+0100"), "07:30")
    test.eq(test.ipc("l_local", "23:30", "+0100"), "00:30")
    test.eq(test.ipc("l_local", "00:30", "-0200"), "22:30")
  end)

  test.it("holds a snooze, then resumes", function()
    load { clock = "12:00", appearance = { mode = "schedule" } }
    test.eq(test.ipc("l_mode"), "light")
    test.ipc("l_snooze", "dark", 3600)
    test.advance(16)
    test.eq(test.ipc("l_mode"), "dark")
    test.ipc("l_snooze", "dark", -1)
    test.advance(16)
    test.eq(test.ipc("l_mode"), "light", "the choice did not resume")
  end)

  test.it("refuses a schedule it cannot read, and lets a preview override", function()
    load { forced = "light", appearance = { mode = "dark" } }
    test.eq(test.ipc("l_mode"), "light")
    test.falsy(test.ipc("l_schedule", "late", "19:00"))
    test.truthy(test.ipc("l_schedule", "06:30", "21:00"))
  end)

  test.it("offers every mode on the Theme page and says what it is doing", function()
    for _, style in ipairs { "material", "tsugumori" } do
      load { style = style, clock = "12:00", appearance = { mode = "schedule" } }
      test.ipc("settings", "theme") test.settle(2500)
      test.truthy(test.find { id = "settings-theme-light-from", visible = true }, "no schedule fields")
      test.truthy(test.find { id = "settings-theme-snooze", visible = true }, "no snooze")
      test.click("settings-theme-mode-system") test.settle(300)
      test.eq(test.ipc("l_chosen"), "system")
      test.falsy(test.find { id = "settings-theme-light-from", visible = true }, "the schedule stayed")
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
    end
  end)
end)

test.describe("schemes by name", function()
  test.it("offers the ones people expect", function()
    load {}
    test.eq(test.ipc("l_schemes"), { "catppuccin", "gruvbox", "nord", "tokyonight", "dracula", "rosepine" })
  end)

  for _, id in ipairs { "catppuccin", "gruvbox", "nord", "tokyonight", "dracula", "rosepine" } do
    test.it(id .. " lays its own colours over the shell and the terminals", function()
      load { settings = { theme = { source = id } } }
      test.settle(600)
      local ground = test.ipc("l_scheme", id, "dark")
      test.eq(test.ipc("l_color", "surface"), ground)
      test.eq(test.ipc("l_lule", "background"), ground)
    end)
  end

  test.it("turns with the mode, and a scheme with one flavour keeps it", function()
    load { forced = "light", settings = { theme = { source = "catppuccin" } } }
    test.settle(600)
    test.eq(test.ipc("l_color", "surface"), "#eff1f5")
    test.eq(test.ipc("l_scheme", "dracula", "light"), "#282a36")
  end)

  test.it("is on the Look page, and takes hold at once", function()
    load {}
    test.ipc("settings", "theme/look") test.settle(2500)
    test.click("look-source-nord") test.settle(600)
    test.eq(test.ipc("l_get", "theme.source"), "nord")
    test.eq(test.ipc("l_color", "surface"), "#2e3440")
    test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
  end)
end)

test.describe("the rest of the desktop", function()
  test.it("plans gsettings, GTK and Qt from what is chosen", function()
    load {}
    local plan = test.ipc("l_plan", { mode = "dark", cursor_theme = "Bibata", cursor_size = 32, icon_theme = "Papirus" })
    local said = {}
    for _, argv in ipairs(plan.commands) do said[#said + 1] = table.concat(argv, " ") end
    local text = table.concat(said, "\n")
    test.truthy(text:find("gsettings set org.gnome.desktop.interface color-scheme prefer-dark", 1, true))
    test.truthy(text:find("gsettings set org.gnome.desktop.interface cursor-theme Bibata", 1, true))
    test.truthy(text:find("gsettings set org.gnome.desktop.interface cursor-size 32", 1, true))
    test.truthy(text:find("gsettings set org.gnome.desktop.interface icon-theme Papirus", 1, true))
    test.truthy(text:find("hyprctl setcursor Bibata 32", 1, true))
  end)

  test.it("leaves the desktop's own scheme alone while following it", function()
    load {}
    local plan = test.ipc("l_plan", { mode = "dark", system = true })
    for _, argv in ipairs(plan.commands) do
      test.falsy(table.concat(argv, " "):find("color-scheme", 1, true), "it would fight the desktop")
    end
  end)

  test.it("keeps every other line of a settings file", function()
    load {}
    local before = "[Settings]\ngtk-theme-name=Adwaita\ngtk-font-name=Sans 11\n\n[Other]\nkey=value\n"
    local after = test.ipc("l_ini", before, "Settings", "gtk-theme-name", "Nord")
    test.truthy(after:find("gtk-theme-name=Nord", 1, true))
    test.falsy(after:find("Adwaita", 1, true))
    test.truthy(after:find("gtk-font-name=Sans 11", 1, true))
    test.truthy(after:find("key=value", 1, true))
    local added = test.ipc("l_ini", before, "Settings", "gtk-icon-theme-name", "Papirus")
    test.truthy(added:find("gtk-icon-theme-name=Papirus\n\n[Other]", 1, true) or added:find("gtk-icon-theme-name=Papirus", 1, true))
    test.truthy(added:find("[Settings]\n", 1, true))
    test.eq(test.ipc("l_ini", "", "Appearance", "icon_theme", "A"), "[Appearance]\nicon_theme=A\n")
  end)

  test.it("writes the files and runs the commands, and says when a tool is missing", function()
    test.stub_run("gsettings", { code = 0 })
    test.stub_run("hyprctl", { code = 1, stderr = "no compositor" })
    local home = load { live = true, settings = { appearance = { sync = false } } }
    local want = { mode = "light", cursor_theme = "Bibata", cursor_size = 24, icon_theme = "Papirus" }
    -- Nothing below may run unless the whole plan stays inside the scratch home.
    local plan = test.ipc("l_plan", want)
    for _, list in ipairs { plan.writes, plan.edits } do
      for _, change in ipairs(list) do
        test.eq(change.path:sub(1, #home), home, "a plan reached outside the scratch home: " .. change.path)
      end
    end
    test.truthy(test.ipc("l_apply", want))
    test.wait(function() test.advance(16) return test.ipc("l_failed") ~= nil end, 3000, "the commands never finished")
    test.eq(test.ipc("l_failed"), 1, "a missing tool should count, and stop nothing")
    local gtk = morf.fs.read(home .. "/config/gtk-3.0/settings.ini")
    test.truthy(gtk:find("gtk-application-prefer-dark-theme=0", 1, true))
    test.truthy(gtk:find("gtk-cursor-theme-name=Bibata", 1, true))
    test.truthy(morf.fs.read(home .. "/config/gtk-4.0/settings.ini"):find("gtk-icon-theme-name=Papirus", 1, true))
    test.truthy(morf.fs.read(home .. "/config/qt6ct/qt6ct.conf"):find("icon_theme=Papirus", 1, true))
    test.truthy(morf.fs.read(home .. "/.icons/default/index.theme"):find("Inherits=Bibata", 1, true))
  end)

  test.it("leaves a file that is already right alone, a link included", function()
    test.stub_run("gsettings", { code = 0 })
    test.stub_run("hyprctl", { code = 0 })
    local home = load { live = true, settings = { appearance = { sync = false } } }
    local want = { mode = "dark" }
    test.ipc("l_apply", want)
    test.wait(function() test.advance(16) return test.ipc("l_failed") ~= nil end, 3000)
    -- The settings move elsewhere and a link takes their place, as a dotfile
    -- manager would have it.
    local file = home .. "/config/gtk-3.0/settings.ini"
    local kept = home .. "/kept-settings.ini"
    morf.fs.write(kept, morf.fs.read(file))
    morf.fs.remove(file)
    morf.fs.symlink(kept, file)
    test.ipc("l_apply", want)
    test.advance(32)
    test.eq(morf.fs.read_link(file), kept, "an unchanged file was rewritten over its link")
  end)

  test.it("gives Qt twenty-one roles in each of its three states", function()
    load {}
    local text = test.ipc("l_qt")
    for _, line in ipairs { "active_colors", "disabled_colors", "inactive_colors" } do
      local list = text:match(line .. "=([^\n]+)")
      test.truthy(list, "no " .. line)
      local count = select(2, list:gsub("#", ""))
      test.eq(count, 21)
    end
  end)

  test.it("lists what is installed, told apart", function()
    local dir = morf.env("XDG_CACHE_HOME") .. "/look-icons"
    morf.fs.mkdir(dir .. "/Bibata/cursors", { parents = true })
    morf.fs.mkdir(dir .. "/Papirus", { parents = true })
    morf.fs.write(dir .. "/Papirus/index.theme", "[Icon Theme]\nName=Papirus\n")
    morf.fs.mkdir(dir .. "/hicolor", { parents = true })
    morf.fs.write(dir .. "/hicolor/index.theme", "x")
    load { icons = dir }
    local found = test.ipc("l_themes")
    test.eq(found.cursors, { "Bibata" })
    test.eq(found.icons, { "Papirus" })
  end)

  test.it("speaks to terminals in their own escapes", function()
    local pts = morf.env("XDG_CACHE_HOME") .. "/look-pts"
    morf.fs.mkdir(pts, { parents = true })
    morf.fs.write(pts .. "/3", "")
    morf.fs.write(pts .. "/ptmx", "")
    load { live = true, pts = pts, settings = { appearance = { sync = false } } }
    local text = test.ipc("l_sequences", { color1 = "#ff0000", background = "#000000" })
    test.truthy(text:find("\27]4;1;#ff0000\27\\", 1, true))
    test.truthy(text:find("\27]11;#000000\27\\", 1, true))
    test.eq(test.ipc("l_terminals", { color1 = "#ff0000" }), 1)
    test.truthy(morf.fs.read(pts .. "/3"):find("#ff0000", 1, true))
    test.eq(morf.fs.read(pts .. "/ptmx"), "", "something other than a terminal was written")
  end)
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " proportions", function()
    test.it("takes a step along the grid with the density", function()
      local base = load { style = style }
      test.eq(test.ipc("l_space", "s"), 8)
      load { style = style, appearance = { density = "compact" } }
      test.eq(test.ipc("l_space", "s"), 4)
      test.eq(test.ipc("l_tokens").pad, test.ipc("l_space", "l"))
      load { style = style, appearance = { density = "spacious" } }
      test.eq(test.ipc("l_space", "s"), 12)
      test.eq(test.ipc("l_space", "TOUCH"), 48, "a density took a finger's room")
      test.truthy(base)
    end)

    test.it("scales the corners, and goes square at none", function()
      load { style = style, appearance = { corners = 0 } }
      test.eq(test.ipc("l_tokens").rounding, 0)
      test.eq(test.ipc("l_round", 16), 0)
      load { style = style, appearance = { corners = 2 } }
      test.truthy(test.ipc("l_round", 16) >= 16, "the corners did not open")
    end)

    test.it("rebuilds in place when the density or corners change", function()
      load { style = style }
      test.ipc("settings", "theme/look") test.settle(2500)
      test.click("look-density-compact")
      test.advance(16)
      test.eq(test.ipc("l_get", "appearance.density"), "compact")
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
    end)

    test.it("makes the frame, panels and displays glass, and takes it back", function()
      load { style = style, settings = { wallpaper = { path = ROOT .. "/dusk.png" } } }
      test.eq(test.ipc("l_alpha", "surface"), 1)
      test.falsy(test.find { id = "glass-plate", visible = true })
      test.ipc("l_set", "appearance.glass", true)
      test.wait(function() test.advance(16) return test.find { id = "glass-plate", visible = true } ~= nil end, 3000, "no plate")
      test.truthy(test.ipc("l_alpha", "surface") < 1, "a surface stayed solid")
      test.ipc("osd", "volume") test.settle(300)
      test.ipc("sidebar", "open", "settings") test.settle(900)
      test.eq(#test.logs("error"), 0, table.concat(test.logs("error"), "\n"))
      test.ipc("l_set", "appearance.glass", false) test.advance(32)
      test.falsy(test.find { id = "glass-plate", visible = true })
      test.eq(test.ipc("l_alpha", "surface"), 1)
    end)
  end)
end

test.describe("the font file", function()
  test.it("takes a file that is there and refuses one that is not", function()
    local face = morf.env("XDG_CACHE_HOME") .. "/face.ttf"
    morf.fs.write(face, "not really a font")
    load {}
    local ok = test.ipc("l_font", "/nonexistent/face.ttf")
    test.falsy(ok)
    test.eq(test.ipc("l_get", "appearance.font_file"), "")
    test.truthy(test.ipc("l_font", face))
    test.eq(test.ipc("l_get", "appearance.font_file"), face)
  end)

  test.it("reaches the one setter from the Look page's field", function()
    load {}
    test.ipc("settings", "theme/look") test.settle(2500)
    local field = test.get("look-font-file")
    test.wheel(0, field.y - 400, { x = field.x + 8, y = 400 }) test.advance(300)
    test.click("look-font-file") test.type("/nonexistent/face.ttf") test.key("Return") test.settle(200)
    test.eq(test.ipc("l_font_calls"), { "/nonexistent/face.ttf" })
    test.truthy(test.find { text = "No font file at /nonexistent/face.ttf", visible = true })
  end)
end)

test.describe("the song", function()
  test.it("reads Lule's palette, whatever noise comes before it", function()
    load {}
    test.eq(test.ipc("l_accent", 'warning: no init.lua\n{ "colors": { "color1": "#112233" }, "special": { "cursor": "#445566" } }'), "#112233")
    test.eq(test.ipc("l_accent", '{ "special": { "cursor": "#445566" } }'), "#445566")
    test.eq(test.ipc("l_accent", "nothing here"), nil)
  end)

  test.it("takes the art's colours through Lule, and lets them go with the music", function()
    test.stub_run("lule", { code = 0, stdout = '{ "colors": { "color1": "#8a2be2" } }' })
    load { settings = { theme = { source = "#336699" } } }
    local before = test.ipc("l_color", "primary")
    test.ipc("l_play", ROOT .. "/dusk.png", true)
    test.advance(600)
    test.wait(function() test.advance(16) return test.ipc("l_song") ~= "" end, 3000, "the song's colours never came")
    test.eq(test.ipc("l_song"), "#8a2be2")
    test.settle(600)
    test.truthy(test.ipc("l_color", "primary") ~= before, "the shell did not change")
    test.ipc("l_play", ROOT .. "/dusk.png", false)
    test.advance(32)
    test.eq(test.ipc("l_song"), "", "paused music kept its colours")
  end)

  test.it("falls to the engine's reading without Lule, and stays off until asked", function()
    test.stub_run("lule", { code = 127, stderr = "no lule" })
    load {}
    test.eq(test.ipc("l_song"), "")
    test.ipc("l_play", ROOT .. "/dusk.png", true)
    test.advance(600)
    test.wait(function() test.advance(16) return test.ipc("l_song") ~= "" end, 3000, "no colours from the engine")
  end)
end)
