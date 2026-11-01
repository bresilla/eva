-- The look of the desktop beyond the shell: the sun's times for the colour mode,
-- the mode and themes pushed to GTK, Qt and the terminals, and the choices the
-- Look page offers. State and actions only.
local morf = require("morf")
local config = require("config")
local look = require("lib.services.desktop_look")
local color_mode = require("themes.color_mode")
local schemes = require("themes.schemes")
local M = {}

M.DENSITIES = { { "compact", "Compact" }, { "normal", "Normal" }, { "spacious", "Spacious" } }
M.CORNERS = { { 0, "Square" }, { 0.5, "Small" }, { 1, "Normal" }, { 1.5, "Round" }, { 2, "Rounder" } }
M.CURSOR_SIZES = { { 16, "16" }, { 24, "24" }, { 32, "32" }, { 48, "48" } }
M.VARIANTS = { { "tonal_spot", "Tonal" }, { "vibrant", "Vibrant" }, { "expressive", "Expressive" }, { "neutral", "Neutral" },
  { "monochrome", "Mono" }, { "fidelity", "Fidelity" }, { "content", "Content" }, { "rainbow", "Rainbow" } }

local function primary() return not morf.window.primary or morf.window.primary() end
local function hex(color) return color:hex():sub(1, 7) end
local function dry()
  local value = morf.env("EVA_DRY_RUN")
  return value and value ~= "" and value ~= "0"
end

--- The colour tool's mode right now.
function M.tool_mode()
  local tool = require("terminal_colors").current:get()
  return tool and tool.mode
end

--- "dark" or "light", now; tracked in a binding.
function M.mode() return color_mode.resolve(M.tool_mode()) end

--- Named sources beside Lule: `{ id, name }`, Lule's and the desktop's first.
function M.sources()
  local out = { { id = "auto", name = "Lule" }, { id = "wallpaper", name = "Picture" }, { id = "system", name = "Desktop" } }
  for _, scheme in ipairs(schemes.LIST) do out[#out + 1] = { id = scheme.id, name = scheme.name } end
  return out
end

--- Hues to pick an accent from, each a colour of one tonal palette.
function M.accents()
  local out = {}
  for hue = 0, 315, 45 do
    local palette = morf.color.tonal_palette(hue, 48)
    out[#out + 1] = { hue = hue, color = palette(70):hex():sub(1, 7) }
  end
  return out
end

--- The contrast of the scheme on show, as the page says it ("" for none).
function M.contrast_note()
  local source = config.get("theme.source")
  if not schemes.is(source) then return "" end
  local ratio, grade = schemes.contrast(source, M.mode())
  return ("Text on its ground reads at %.1f to 1%s"):format(ratio, grade ~= "" and (", WCAG " .. grade) or "")
end

--- Writes the palette on show as a scheme file, and returns its path.
function M.export(name)
  local C, lule = require("theme").color, require("theme").lule
  local flavour = { ground = hex(C.surface), low = hex(C.surfaceContainerLowest), mid = hex(C.surfaceContainer),
    high = hex(C.surfaceContainerHigh), top = hex(C.surfaceContainerHighest), ink = hex(C.onSurface),
    soft = hex(C.onSurfaceVariant), accent = hex(C.primary), second = hex(C.secondary), third = hex(C.tertiary),
    alert = hex(C.error), colors = {} }
  for i = 0, 15 do flavour.colors[i + 1] = hex(lule["color" .. i]) end
  local mode = M.mode()
  local path = schemes.folder() .. "/" .. name .. ".json"
  local ok, why = morf.fs.write(path, morf.json.encode({ name = name, [mode] = flavour }, true), { atomic = true, parents = true })
  if not ok then return nil, why end
  return path
end

-- ------------------------------------------------------------------- sun --

--- Local "HH:MM" from a UTC "HH:MM" and a zone like "+0130".
function M.local_time(utc, zone)
  local at = color_mode.minutes(utc)
  local sign, hours, minutes = tostring(zone or ""):match("^([+-])(%d%d):?(%d%d)$")
  if not at or not sign then return nil end
  local shift = (tonumber(hours) * 60 + tonumber(minutes)) * (sign == "-" and -1 or 1)
  local total = (at + shift) % 1440
  return ("%02d:%02d"):format(total // 60, total % 60)
end

--- The tool that knows the sun: on the path, or beside the shell.
local function sun_tool()
  if require("services").installed("eva-nightlight") then return "eva-nightlight" end
  return morf.paths.shell("../apps/bin/eva-nightlight")
end

--- Asks for today's sunrise and sunset, and keeps them where the lock and the
--- greeter read them too.
function M.find_sun(done)
  local ok = pcall(morf.process.run, { sun_tool(), "times" }, { timeout_ms = 20000, max_output = 1024 }, function(result)
    local text = result.stdout or ""
    local rise, set = text:match("sunrise%s+(%d%d:%d%d)"), text:match("sunset%s+(%d%d:%d%d)")
    local zone = morf.time.format("%z")
    local found = result.ok and rise and set
    if found then
      local preferences = require("themes").preferences
      preferences.set("sunrise", M.local_time(rise, zone))
      preferences.set("sunset", M.local_time(set, zone))
      preferences.flush()
      require("themes.ui_scale").share { sunrise = preferences.get("sunrise"), sunset = preferences.get("sunset") }
    end
    if done then done(found and true or false) end
  end)
  if not ok and done then done(false) end
end

-- ----------------------------------------------------------------- sync --

--- The roles Qt draws with, from the shell's palette.
function M.qt_colors()
  local C = require("theme").color
  return { foreground = hex(C.onSurface), surface = hex(C.surfaceContainer), light = hex(C.surfaceContainerHighest),
    midlight = hex(C.surfaceContainerHigh), dark = hex(C.surfaceDim), mid = hex(C.outlineVariant), bright = "#ffffff",
    base = hex(C.surface), shadow = "#000000", highlight = hex(C.primary), on_highlight = hex(C.onPrimary),
    link = hex(C.tertiary) }
end

--- What a sync asks for, now.
function M.wanted()
  return { mode = M.mode(), system = color_mode.chosen() == "system",
    cursor_theme = config.get("appearance.cursor_theme"), cursor_size = config.get("appearance.cursor_size"),
    icon_theme = config.get("appearance.icon_theme"), gtk_theme = config.get("appearance.gtk_theme") }
end

--- The terminals' colours: Lule's way where it made them, written here for a
--- scheme by name.
local function push_terminals(mode)
  local source = config.get("theme.source")
  if schemes.is(source) then
    look.terminals(schemes.tool(source, mode).palette)
    return "scheme"
  end
  local model = require("wallpaper_model")
  local studio = require("lule_studio")
  if color_mode.chosen() ~= "auto" and studio.scheme:get() and model.can_color() and (studio.scheme:get().theme ~= mode) then
    studio.mode:set(mode)
    studio.apply()
    return "lule"
  end
  return nil
end
M.push_terminals = push_terminals

local function run_hook(mode)
  if dry() then return end
  local argv = {}
  for i, word in ipairs(config.get("theme.hook")) do argv[i] = tostring(word):gsub("%$MODE", mode) end
  if #argv > 0 then pcall(morf.process.run, argv, { timeout_ms = 30000, max_output = 4096 }, function() end) end
end

--- Starts following: the sun, the desktop, and the song.
function M.start()
  require("song_theme").start()
  if not primary() then return end
  morf.effect("eva.appearance.sun", function()
    if color_mode.chosen() ~= "sun" then return end
    morf.time.hour_clock:get()
    M.find_sun()
  end)
  local settle
  local last_mode
  morf.effect("eva.appearance.sync", function()
    local want = M.wanted()
    local on = config.get("appearance.sync")
    config.get("theme.source")
    if settle then settle:cancel() settle = nil end
    if not on then return end
    settle = morf.time.timer(800, function()
      settle = nil
      want.colors = M.qt_colors()
      look.apply(look.plan(want))
      if want.mode ~= last_mode then
        if last_mode then
          push_terminals(want.mode)
          run_hook(want.mode)
        end
        last_mode = want.mode
      end
    end, false)
  end)
end

-- ----------------------------------------------------------------- lists --

M.installed = morf.signal("eva.appearance.installed", { cursors = {}, icons = {} })

--- Reads what is installed, when the page opens.
function M.refresh() M.installed:set(look.themes()) end

--- The font file: a file that exists, or "" for the installed faces. Applied by
--- building the shell again, as a font is.
function M.set_font_file(path)
  path = (path or ""):gsub("^~/", morf.fs.home() .. "/")
  if path ~= "" and not morf.fs.is_file(path) then return false, "No font file at " .. path end
  config.set("appearance.font_file", path)
  if path ~= "" then
    local kept = require("themes").preferences
    kept.set("font", "")
    kept.flush()
  end
  require("themes.session").hold()
  morf.reload()
  return true
end

return M
