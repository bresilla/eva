-- Compatibility facade: palette roles and visual design are independent.
local morf = require("morf")
local config = require("config")
local appearance = require("themes")
local M = require("palette")
M.appearance = appearance.current
for key, value in pairs(M.appearance.tokens) do M[key] = value end
M.font_file = morf.env("EVA_FONT_FILE") or config.get("appearance.font_file")
if M.font_file ~= "" and not morf.fs.exists(M.font_file) then M.font_file = "" end
if appearance.font and appearance.font ~= "" then
  M.font, M.mono, M.font_file = appearance.font, appearance.font, ""
end
M.space = require("themes.spacing")
-- The density's steps and the corner scale, as every layout reads them.
do
  local corners = math.max(0, tonumber(config.get("appearance.corners")) or 1)
  M.corners = corners
  M.ROUNDING, M.SEAM = M.ROUNDING * corners, M.SEAM * corners
  M.PAD, M.GAP = M.space.l, M.space.m
end
-- Large text: every size the theme names, before anything is built with it.
do
  local scale = tonumber(config.get("appearance.text_scale")) or 1
  if scale ~= 1 and M.size then
    local sized = {}
    for name, value in pairs(M.size) do sized[name] = math.floor(value * scale * 2 + 0.5) / 2 end
    M.size = sized
  end
end
-- Reduce motion lands everything at once, before anything is built to move.
if require("themes.motion_style").reduced() then
  require("themes.motion_landing").install()
  for name in pairs(M.stretch or {}) do M.stretch[name] = false end
end
-- Each named spring two ways: `theme.spring.spatial` for a behavior,
-- `theme.bounce.spatial` as a `duration` and `easing`.
do
  local spring = require("themes.spring")
  local style = config.get("appearance.motion")
  local speed = tonumber(config.get("appearance.speed")) or 1
  M.spring, M.bounce = {}, {}
  for name, raw in pairs(M.springs or {}) do
    local styled = spring.styled(raw, style, speed)
    M.spring[name], M.bounce[name] = spring.behavior(styled), spring.curve(styled)
  end
  local deform = tonumber(config.get("appearance.deform")) or 1
  for _, stretch in pairs(M.stretch or {}) do
    if stretch then stretch.scale = stretch.scale * deform end
  end
end
M.motion = require(M.appearance.motion)(M)
return M
