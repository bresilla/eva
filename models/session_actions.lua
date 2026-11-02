-- The session's actions, what each is called and drawn with, for everything that
-- offers them: the session menu and the quick settings' row (shell/session_model.lua),
-- the lock and the greeter (models/auth_power.lua), Settings and the launcher.
-- Plain data, no nodes.
--
-- `can` is logind's question for it, `blocked_by` the inhibitors that hold it up,
-- and `quick` puts it in the quick settings' row. An action with `login` is offered
-- on a login screen under that name: `method` is logind's call, `verb` the word a
-- message uses.
local M = {}

M.LIST = {
  { id = "lock", icon = "lock", name = "Lock", detail = "Lock this session", key = "l", tone = "accent", quick = true,
    signal = "accent" },
  { id = "lockdown", icon = "shield_lock", name = "Lockdown", key = "d", signal = "warn",
    detail = "Password only, nothing shown" },
  { id = "suspend", icon = "bedtime", name = "Suspend", detail = "Sleep, and keep the session", key = "s",
    can = "suspend", blocked_by = "sleep", hold = true, tone = "accent", quick = true, signal = "accent",
    login = "suspend", method = "Suspend", verb = "suspend" },
  { id = "hibernate", icon = "downloading", name = "Hibernate", detail = "Save the session to disk", key = "h",
    can = "hibernate", blocked_by = "sleep", confirm = true, signal = "accent" },
  { id = "suspend_hibernate", icon = "hotel", name = "Suspend, then hibernate", detail = "Sleep, then save to disk",
    key = "n", can = "suspend_then_hibernate", needs_yes = true, blocked_by = "sleep", signal = "accent" },
  { id = "logout", icon = "logout", name = "Log out", detail = "End this session", key = "o", hold = true,
    quick = true, confirm = true, signal = "info" },
  { id = "switch", icon = "switch_account", name = "Switch user", detail = "Lock, go to another session", key = "u",
    signal = "info" },
  { id = "reboot", icon = "restart_alt", name = "Restart", detail = "Reboot the computer", key = "r", can = "reboot",
    blocked_by = "shutdown", hold = true, quick = true, confirm = true, signal = "warn",
    login = "reboot", method = "Reboot", verb = "reboot" },
  { id = "firmware", icon = "developer_board", name = "Firmware", detail = "Restart into firmware setup",
    key = "f", blocked_by = "shutdown", confirm = true, signal = "warn" },
  { id = "shutdown", icon = "power_settings_new", name = "Power off", detail = "Shut the computer down", key = "p",
    can = "power_off", blocked_by = "shutdown", hold = true, quick = true, confirm = true, signal = "alert",
    login = "poweroff", method = "PowerOff", verb = "power off" },
}

M.BY_ID = {}
for _, action in ipairs(M.LIST) do M.BY_ID[action.id] = action end

return M
