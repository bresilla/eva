-- eva-kill's page in the Tools window: what it does, and a control that starts
-- it. Started from here it is the shell's own kill mode, as Super+X starts it;
-- with no shell, eva-kill's own program does the same over the whole screen.
local overlay = require("apps.common.overlay_page")

local M = {}

local function start() overlay.after_window(function() require("kill_mode").start() end) end

--- The page, `w` by `h`.
function M.build(w, h)
  return overlay.build({ id = "kill",
    text = "Press a window to end it, as the window menu's Force quit does: the screen goes dark round the window "
      .. "under the pointer. `eva-kill --active` ends the focused window with no press.",
    starts = { { id = "kill-start", icon = "dangerous", label = "Press a window to end it", run = start } },
    keys = { { "A click", "Ends the window under the pointer", "mouse" },
      { "Escape, or the right button", "Leaves it be", "close" }, { "Super+X", "Starts it from anywhere", "keyboard" } } },
    w, h)
end

M.verbs = { start = function() start() return true end }

return M
