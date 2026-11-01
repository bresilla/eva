-- The compositor keys that reach the window features: one table, which the
-- NixOS module binds into a session with no compositor configuration of its
-- own (nix/nixos/compositor.nix) and eva-keys lists. Plain Lua: the compositor
-- loads this file too, with no shell around it.
local M = {}

-- `keys`, as Hyprland spells them with modifiers in eva-keys' order; `verb`,
-- the shell's IPC call; `label`, what it does. `opts` go to `hl.bind`.
M.BINDS = {
  { keys = "SUPER + Tab", verb = "overview toggle", label = "Show every workspace and window" },
  { keys = "ALT + Tab", verb = "switcher next", label = "Switch to the next window" },
  { keys = "ALT + SHIFT + Tab", verb = "switcher prev", label = "Switch to the previous window" },
  { keys = "ALT + grave", verb = "switcher same", label = "Walk this application's windows" },
  { keys = "ALT + ALT_L", verb = "switcher commit", label = "Go to the window chosen",
    opts = { release = true, non_consuming = true }, quiet = true },
  { keys = "SUPER + W", verb = "window_menu toggle", label = "Open the window menu" },
  { keys = "SUPER + Z", verb = "snap picker", label = "Pick a snap layout" },
  { keys = "SUPER + CTRL + left", verb = "snap left", label = "Snap to the left half" },
  { keys = "SUPER + CTRL + right", verb = "snap right", label = "Snap to the right half" },
  { keys = "SUPER + CTRL + up", verb = "snap full", label = "Snap to the whole screen" },
  { keys = "SUPER + CTRL + down", verb = "snap bottom", label = "Snap to the bottom half" },
  { keys = "SUPER + mouse:272", verb = "snap drag", label = "Show where a dragged window lands",
    opts = { non_consuming = true }, quiet = true },
  { keys = "SUPER + mouse:272", verb = "snap drop", label = "Land the dragged window",
    opts = { non_consuming = true, release = true }, quiet = true },
  { keys = "SUPER + X", verb = "kill_mode", label = "Force quit the window pressed" },
  { keys = "SUPER + A", verb = "keep_above", label = "Keep the window above the others" },
  { keys = "SUPER + O", verb = "opacity", label = "Step the window's opacity" },
  { keys = "SUPER + I", verb = "pip", label = "Picture in picture" },
  { keys = "SUPER + SHIFT + V", verb = "float", label = "Float the window, or tile it" },
  { keys = "SUPER + SHIFT + E", verb = "split", label = "Split the screen with the last window" },
  { keys = "SUPER + BackSpace", verb = "show_desktop", label = "Show the desktop" },
  { keys = "SUPER + SHIFT + L", verb = "workspace_layout next", label = "Next layout on this workspace" },
  { keys = "SUPER + grave", verb = "scratchpad scratch", label = "Show the scratchpad" },
  { keys = "SUPER + SHIFT + grave", verb = "scratchpad send scratch", label = "Send the window to the scratchpad" },
  { keys = "SUPER + SPACE", verb = "launcher toggle", label = "Open the launcher" },
  { keys = "SUPER + D", verb = "dashboard toggle", label = "Open the dashboard" },
  { keys = "SUPER + N", verb = "sidebar toggle notifications", label = "Open the notifications" },
  { keys = "SUPER + comma", verb = "utilities toggle", label = "Open the quick settings" },
}

-- Swipes on a touchpad: `action` is the verb.
M.GESTURES = {
  { fingers = 4, direction = "up", verb = "overview toggle", label = "Show every workspace and window" },
}

--- The bindings, for `hl` (Hyprland's Lua API), calling `morf` for the shell.
function M.apply(hl, morf)
  local function call(verb) return ("%s ipc call %s"):format(morf, verb) end
  for _, bind in ipairs(M.BINDS) do
    local opts = {}
    for k, v in pairs(bind.opts or {}) do opts[k] = v end
    opts.description = bind.label
    hl.bind(bind.keys, hl.dsp.exec_cmd(call(bind.verb)), opts)
  end
  for _, gesture in ipairs(M.GESTURES) do
    hl.gesture { fingers = gesture.fingers, direction = gesture.direction,
      action = function() hl.dispatch(hl.dsp.exec_cmd(call(gesture.verb))) end }
  end
end

return M
