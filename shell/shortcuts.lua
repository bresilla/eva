-- Keyboard shortcuts for what was reachable only through IPC: while any
-- of the shell's surfaces has the keyboard (a drawer open, the launcher
-- typing), these move between the drawers without the compositor's binds.
-- They are the IPC verbs themselves, so a key and `morf ipc` do the same.
--
-- Super-chords belong to the compositor, so these use Ctrl; a text field
-- keeps its editing chords (Ctrl+A, C, V, ...) whatever is listed here.
local M = {}

--- What each key does, for eva-keys.
M.LABELS = {
  { "ctrl+space", "Open the launcher" }, { "ctrl+d", "Open the dashboard" },
  { "ctrl+,", "Open the quick settings" }, { "ctrl+n", "Open the notifications" },
  { "ctrl+t", "Open the tasks" }, { "ctrl+shift+c", "Open the calendar" },
  { "ctrl+l", "Open the colour tool" }, { "ctrl+q", "Open the session menu" },
  { "ctrl+shift+s", "Open the capture panel" }, { "ctrl+w", "Shut what is open" },
  { "alt+Left", "Back one page" },
}

--- The table for a node's `shortcuts`, from the shell's IPC verbs.
function M.table(ipc)
  local function call(name, ...)
    local args = { ... }
    return function() ipc[name](table.unpack(args)) end
  end
  local close = call("close")
  local function back()
    local settings = package.loaded["settings_model"]
    local pages = settings and settings.navigation
    if pages and settings.opened:get() and pages.can_go_back() then pages.back() return end
    close()
  end
  return {
    scope = "surface",
    ["ctrl+space"] = call("launcher", "toggle"),
    ["ctrl+d"] = call("dashboard", "toggle"),
    ["ctrl+,"] = call("utilities", "toggle"),
    ["ctrl+n"] = call("sidebar", "toggle", "notifications"),
    ["ctrl+t"] = call("tasks", "toggle"),
    ["ctrl+shift+c"] = call("calendar", "toggle"),
    ["ctrl+l"] = call("lule", "toggle"),
    ["ctrl+q"] = call("session", "toggle"),
    ["ctrl+shift+s"] = call("capture", "toggle"),
    ["ctrl+w"] = call("close"),
    -- A mouse's back button, or Alt+Left: one settings page back while a
    -- page is open on the Settings stack, else shut what is open.
    ["back"] = back,
    ["alt+Left"] = back,
  }
end

return M
