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
-- Each named spring two ways: `theme.spring.spatial` for a behavior,
-- `theme.bounce.spatial` as a `duration` and `easing`.
do
  local spring = require("themes.spring")
  local style = config.get("appearance.motion")
  M.spring, M.bounce = {}, {}
  for name, raw in pairs(M.springs or {}) do
    local styled = spring.styled(raw, style)
    M.spring[name], M.bounce[name] = spring.behavior(styled), spring.curve(styled)
  end
end
M.motion = require(M.appearance.motion)(M)
return M
