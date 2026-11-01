-- The on-screen displays' workings: the output's volume and the screen's
-- brightness, read and set, every other kind's reading (osd_sources.lua),
-- and the watch that shows a change -- from anywhere: keys, another program
-- -- as a display in the place its kind stands (levels.lua). Over IPC: `osd
-- [KIND]`.
--
-- The volume is `morf.audio`'s default output; the brightness is the
-- backlight lib/services/sysinfo.lua reads (and writes when it may). Without
-- either the level rests at zero and its display never appears.

local morf = require("morf")
local model = require("osd_model")

local M = {}

local audio = morf.audio
local sysinfo = require("lib.services.sysinfo")

local function dry_run()
  local value = morf.env and morf.env("EVA_DRY_RUN")
  return value ~= nil and value ~= "" and value ~= "0"
end
local function sources() return require("osd_sources").sources end

-- What a dry run set: the level follows it, nothing on the machine does.
local dry = morf.state { volume = false, muted = false, brightness = false }
-- EVA_FAKE_OSD=1: levels to see where a sealed session has neither.
local fake = morf.env and morf.env("EVA_FAKE_OSD")
if fake and fake ~= "" and fake ~= "0" then dry.volume, dry.brightness = .42, .68 end

function M.volume()
  if dry.volume then return dry.volume, dry.muted, true end
  local ok, sink = pcall(function() return audio and audio.available() and audio.default_sink() end)
  if not ok or not sink then return 0, true, false end
  return sink.volume or 0, sink.muted, true
end

function M.brightness()
  if dry.brightness then return dry.brightness, true end
  local ok, b = pcall(sysinfo.backlight)
  if not ok or not b or not b.percent then return 0, false end
  return b.percent / 100, true
end

function M.set_volume(v)
  local ok, sink = pcall(function() return audio.default_sink() end)
  if ok and sink then pcall(audio.set_volume, sink.id, math.max(0, math.min(1, v))) end
end

function M.set_brightness(v)
  pcall(sysinfo.set_brightness, math.max(1, math.min(100, v * 100)))
end

local volume, brightness = M.volume, M.brightness

--- Sets a level from its display; dry, only the display moves.
function M.adjust(kind, v)
  v = math.max(0, math.min(1, v))
  if dry_run() then
    morf.log("info", ("eva: %s %.2f (dry run)"):format(kind, v))
    dry[kind] = v
  elseif kind == "brightness" then M.set_brightness(v)
  else M.set_volume(v) end
end

--- Mutes the output or lets it speak again.
function M.toggle_mute()
  local _, muted, known = volume()
  if not known then return end
  if dry_run() then
    morf.log("info", "eva: mute " .. tostring(not muted) .. " (dry run)")
    dry.volume, dry.muted = (volume()), not muted
    return
  end
  local ok, sink = pcall(function() return audio.default_sink() end)
  if ok and sink then pcall(audio.set_mute, sink.id, not sink.muted) end
end

--- The icon for a volume, and for a brightness.
function M.volume_icon()
  local v, muted = volume()
  if muted or v <= 0 then return "volume_mute" end
  if v < 0.5 then return "volume_down" end
  return "volume_up"
end
function M.brightness_icon()
  local b = brightness()
  if b < 0.34 then return "brightness_low" end
  if b < 0.67 then return "brightness_medium" end
  return "brightness_high"
end

--- Whether `kind` has what it reports on: a kind without its service never
--- appears.
function M.present(kind)
  if kind == "volume" then return (select(3, volume())) == true end
  if kind == "brightness" then return (select(2, brightness())) == true end
  local source = sources()[kind]
  return source ~= nil and source.present() == true
end

--- What a status or media display says: `{ icon, title, detail, note, on }`.
function M.read(kind)
  local source = sources()[kind]
  return source and source.read() or { icon = "info", title = "", detail = "", on = false }
end

function M.artwork() return require("osd_sources").artwork() end

--- Shows `kind` (the volume, without one) for a moment, as a change does;
--- `forced` shows one its setting turned off. False when it cannot appear.
function M.flash(kind, forced)
  kind = kind or "volume"
  if not model.BY_ID[kind] then error("`" .. tostring(kind) .. "`: no such display") end
  if not M.present(kind) or not (forced or model.enabled(kind)) then return false end
  return require("levels").pop(kind)
end

-- The settings, whose own controls show what they change, keep it quiet.
local function shown_there()
  local sidebar = package.loaded["sidebar"]
  return type(sidebar) == "table" and sidebar.drawer and sidebar.drawer.open:get() and sidebar.showing("settings")
end

-- On the focused screen only: every screen hears the change.
local function fire(kind)
  local source = sources()[kind]
  local quiet = (not source or source.shown_in_settings) and shown_there()
  if not quiet and require("services").here() then M.flash(kind) end
end

--- Starts following every other kind (once the shell's services are up).
function M.watch() require("osd_sources").watch(fire) end

-- A change is a reading that moved from one known value to another: the
-- first reading of either, when its service answers, is not one.
local seen_volume, seen_brightness
morf.effect("eva.osd.follow", function()
  local v, muted, known_v = volume()
  local b, known_b = brightness()
  local changed
  if known_v then
    local now = ("%.3f/%s"):format(v, tostring(muted))
    if seen_volume and now ~= seen_volume then changed = "volume" end
    seen_volume = now
  end
  if known_b then
    local now = ("%.3f"):format(b)
    if seen_brightness and now ~= seen_brightness then changed = "brightness" end
    seen_brightness = now
  end
  if changed then fire(changed) end
end)

return M
