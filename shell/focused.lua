-- Which screen things opened by a key or a verb appear on. Every screen runs
-- a copy of the configuration and hears every verb; only this one acts.
local morf = require("morf")
local hyprland = require("lib.compositor.hyprland")
local M = {}

-- The output this runtime draws on.
local function screen_name()
  return (morf.screens and morf.screens[1] and morf.screens[1].name) or ""
end
M.output = screen_name

-- Capture a destination once per authentication request. Later PAM updates
-- must not open a second dialog just because monitor focus has changed.
function M.active_output()
  if hyprland.available() then
    local focused=hyprland.state.focused_monitor
    if focused and focused~="" then return focused end
  end
  return screen_name()
end

--- Whether this screen is the one things opened by a key or a verb appear
--- on: the focused monitor on Hyprland, the primary screen elsewhere.
--- Every screen runs the shell and hears every verb; only this one acts.
function M.here()
  if hyprland.available() then
    local focused = hyprland.state.focused_monitor
    if focused and focused ~= "" then return focused == screen_name() end
  end
  if morf.window.primary then return morf.window.primary() end
  return true
end

return M
