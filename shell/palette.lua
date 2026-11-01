-- Wallpaper-derived colors, independent of the selected visual theme.
--
-- Colours are a Material 3 scheme (lib/util/material.lua): every role --
-- primary, onSurfaceVariant, surfaceContainerHigh, ... -- is a token of one
-- `morf.theme`, so a binding that reads `theme.color.primary` follows a new
-- wallpaper with no wiring. The scheme comes from the wallpaper (tonal_spot,
-- dark) unless the settings name a source colour.
--
-- Sizes were measured off the reference at 1920x1080: a 10 px frame, a
-- 60 px bar, 25 px corners, 40 px pills.

local morf = require("morf")
local material = require("lib.theme.material")
local config = require("config")
local color_mode = require("themes.color_mode")

local M = {}

-- ------------------------------------------------------------------ colour --

-- A pink source until the wallpaper's scheme is in: the colours the
-- reference shows before it has a scheme of its own.
M.FALLBACK_SOURCE = "#ffb0ca"

--- Scheme `s` as high contrast has it: text at full strength, outlines as
--- strong as text, surfaces plain.
local function sharpened(s)
  if config.get("appearance.high_contrast") ~= true then return s end
  local out = {}
  for name, value in pairs(s) do out[name] = value end
  out.onSurfaceVariant, out.outline, out.outlineVariant = s.onSurface, s.onSurface, s.onSurface
  local ground = morf.color(color_mode.resolve() == "light" and "#ffffff" or "#000000")
  for _, name in ipairs { "surface", "surfaceDim", "surfaceBright", "surfaceContainerLowest", "surfaceContainerLow",
    "surfaceContainer", "background" } do
    if s[name] ~= nil then out[name] = ground end
  end
  return out
end

local function initial()
  local source = config.get("theme.source")
  if source == "" or source == "wallpaper" or source == "auto" or source == "lule" or source == "system" then
    source = M.FALLBACK_SOURCE
  end
  local named = require("themes.schemes").flavour(source, color_mode.resolve())
  if named then source = named.accent end
  return material.scheme(source, { variant = config.get("theme.variant"), mode = color_mode.resolve() })
end

local roles = {}
for name, value in pairs(sharpened(initial())) do
  local ok, red = pcall(function() return value.r end)
  if type(value) ~= "string" and ok and type(red) == "number" then roles[name] = value end
end
-- A new scheme, variant or mode eases every colour there, as one.
local session = require("themes.session")
for name,value in pairs(session.restore("palette",{})) do if roles[name] then roles[name]=morf.color(value) end end
M.color = morf.theme(roles, { transition = { duration = 400, easing = "in_out_cubic" } })

session.register("palette",function()
  local saved={}
  for name in pairs(roles) do saved[name]=M.color[name]:hex() end
  return saved
end)

-- The colour tool's own palette (lule, pywal: terminal_colors.lua), beside
-- the Material scheme: `theme.lule.accent`, `.background`, `.foreground`,
-- `.cursor`, `.color0`..`.color15`. A part that wants the desk's terminal
-- colours rather than Material's reads these; they ease to new values as
-- the tool re-themes. Grey until a tool has set anything.
local lule_tokens = { accent = "#888888", background = "#111111", foreground = "#eeeeee", cursor = "#888888" }
for i = 0, 15 do lule_tokens["color" .. i] = "#888888" end
M.lule = morf.theme(lule_tokens, { transition = { duration = 400, easing = "in_out_cubic" } })

--- Puts the colour tool's palette in `theme.lule`.
function M.apply_lule(tool)
  if not tool then return end
  if tool.accent then M.lule.accent = tool.accent end
  for name, value in pairs(tool.palette or {}) do
    if value and lule_tokens[name] then M.lule[name] = value end
  end
end

--- Puts every role of scheme `s` in place.
function M.apply(s)
  s = sharpened(s)
  for name in pairs(roles) do
    if s[name] ~= nil then M.color[name] = s[name] end
  end
end

-- A dark scheme's surfaces taken down to black, each keeping its place.
local function finish(s, mode)
  if mode == "dark" and config.get("appearance.pure_black") then
    local black = morf.color("#000000")
    s.surface, s.background, s.surfaceDim, s.surfaceContainerLowest = black, black, black, black
    for name, amount in pairs { surfaceContainerLow = 0.5, surfaceContainer = 0.6, surfaceContainerHigh = 0.72,
      surfaceContainerHighest = 0.84, surfaceBright = 0.9 } do
      if s[name] then s[name] = s[name]:mix(black, amount, "oklab") end
    end
  end
  return s
end

--- The scheme for `source` (a colour, or "wallpaper" with `wallpaper` the
--- picture's path), applied when it is made.
function M.follow(source, wallpaper, mode)
  mode = mode or color_mode.resolve()
  local opts = { variant = config.get("theme.variant"), mode = mode }
  if source ~= "wallpaper" and source ~= "" then
    local hue = tonumber(config.get("theme.hue")) or 0
    if hue ~= 0 then source = morf.color(source):rotate(hue):hex() end
    M.apply(finish(material.scheme(source, opts), mode))
    return
  end
  if not wallpaper or wallpaper == "" then return end
  material.from_image(wallpaper, opts, function(ok, s)
    if ok then M.apply(finish(s, mode)) else morf.log("warn", "eva: no scheme from the wallpaper: " .. tostring(s)) end
  end)
end

--- The palette the settings ask for, from what the colour tool made (`tool`)
--- and the picture: a scheme by name, the song's colours, the desktop's accent,
--- Lule's, the picture's, or a colour.
function M.track(tool, wallpaper)
  local schemes = require("themes.schemes")
  local source = config.get("theme.source")
  local mode = color_mode.resolve(tool and tool.mode)
  config.get("theme.variant")
  config.get("theme.hue")
  config.get("appearance.pure_black")
  local song = M.song and M.song:get()
  if song and song ~= "" then
    M.follow(song, nil, mode)
  elseif schemes.is(source) then
    M.apply(finish(schemes.roles(source, mode), mode))
    M.apply_lule(schemes.tool(source, mode))
  elseif source == "system" then
    local accent = morf.prefers and morf.prefers.accent_color
    M.follow(accent and morf.color(accent):hex() or M.FALLBACK_SOURCE, nil, mode)
  elseif (source == "auto" or source == "lule") and tool then
    M.follow(tool.accent, nil, mode)
  else
    M.follow(source == "auto" and "wallpaper" or source, wallpaper, mode)
  end
  return mode
end

-- The song's accent while the colours follow it ("" for none); it is carried
-- across a reload so the shell does not flash back between tracks.
M.song = morf.signal("eva.palette.song", "")

return M
