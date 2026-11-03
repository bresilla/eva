-- The look of the desktop beyond the shell: the sun's times for the colour mode,
-- and the mode and themes pushed to GTK, Qt and the terminals. State and actions
-- only.
local morf = require("morf")
local config = require("config")
local look = require("lib.services.desktop_look")
local color_mode = require("themes.color_mode")
local M = {}

local function primary() return not morf.window.primary or morf.window.primary() end
local function hex(color) return color:hex():sub(1, 7) end

--- The colour tool's mode right now.
function M.tool_mode()
  local tool = require("terminal_colors").current:get()
  return tool and tool.mode
end

--- "dark" or "light", now; tracked in a binding.
function M.mode() return color_mode.resolve(M.tool_mode()) end

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

-- Whether Lule can make the colours here.
local function can_color()
  local dry = morf.env("EVA_DRY_RUN")
  if dry and dry ~= "" and dry ~= "0" then return false end
  return require("services").installed("lule") == true
end

--- The terminals' colours, Lule's way: Lule makes them again in the mode.
local function push_terminals(mode)
  local studio = require("lule_studio")
  if color_mode.chosen() ~= "auto" and studio.scheme:get() and can_color() and (studio.scheme:get().theme ~= mode) then
    studio.mode:set(mode)
    studio.apply()
  end
end

--- Starts following: the sun and the desktop.
function M.start()
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
    local qt_colors = config.get("appearance.sync_qt_colors")
    config.get("theme.source")
    if settle then settle:cancel() settle = nil end
    if not on then return end
    settle = morf.time.timer(800, function()
      settle = nil
      if qt_colors then want.colors = M.qt_colors() end
      look.apply(look.plan(want))
      if want.mode ~= last_mode then
        if last_mode then push_terminals(want.mode) end
        last_mode = want.mode
      end
    end, false)
  end)
end

return M
