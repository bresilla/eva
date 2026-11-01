-- The session's actions, for the menu and the quick settings' row: which there
-- are, which this machine can do, and what stands in the way. No nodes.
--
-- An action logind says it cannot do is not offered. Where logind does not
-- answer (no bus, a machine without it) what has a command is offered, as ever.
local morf = require("morf")
local config = require("config")
local M = {}

M.ACTIONS = {
  { id = "lock", icon = "lock", name = "Lock", detail = "Lock this session", key = "l", tone = "accent", quick = true,
    signal = "accent" },
  { id = "lockdown", icon = "shield_lock", name = "Lockdown", key = "d", signal = "warn",
    detail = "Password only, nothing on show" },
  { id = "suspend", icon = "bedtime", name = "Suspend", detail = "Sleep, and keep the session", key = "s",
    can = "suspend", blocked_by = "sleep", hold = true, tone = "accent", quick = true, signal = "accent" },
  { id = "hibernate", icon = "downloading", name = "Hibernate", detail = "Save the session to disk", key = "h",
    can = "hibernate", blocked_by = "sleep", confirm = true, signal = "accent" },
  { id = "suspend_hibernate", icon = "hotel", name = "Suspend, then hibernate", detail = "Sleep now, save to disk later",
    key = "n", can = "suspend_then_hibernate", needs_yes = true, blocked_by = "sleep", signal = "accent" },
  { id = "logout", icon = "logout", name = "Log out", detail = "End this session", key = "o", hold = true,
    quick = true, confirm = true, signal = "info" },
  { id = "switch", icon = "switch_account", name = "Switch user", detail = "Lock, and go to another session", key = "u",
    signal = "info" },
  { id = "reboot", icon = "restart_alt", name = "Restart", detail = "Reboot the computer", key = "r", can = "reboot",
    blocked_by = "shutdown", hold = true, quick = true, confirm = true, signal = "warn" },
  { id = "firmware", icon = "developer_board", name = "Firmware", detail = "Restart into firmware setup",
    key = "f", blocked_by = "shutdown", confirm = true, signal = "warn" },
  { id = "shutdown", icon = "power_settings_new", name = "Power off", detail = "Shut the computer down", key = "p",
    can = "power_off", blocked_by = "shutdown", hold = true, quick = true, confirm = true, signal = "alert" },
}
M.BY_ID = {}
for _, action in ipairs(M.ACTIONS) do M.BY_ID[action.id] = action end

local function login() return require("models.logind").connect() end

-- What logind's `Can*` questions are called, for the stand-in system.
local CAN = { suspend = "CanSuspend", hibernate = "CanHibernate", reboot = "CanReboot", power_off = "CanPowerOff" }

--- What logind answers for one of its `Can*` questions, or nil if it does not.
function M.can(what)
  local host = require("lib.services.host")
  if host.fake() and CAN[what] then
    return host.bus("system").call1("org.freedesktop.login1", "/org/freedesktop/login1",
      "org.freedesktop.login1.Manager", CAN[what])
  end
  local bus = login()
  if not bus or not bus.available() then return nil end
  local ok, answer = pcall(bus.can, what)
  return ok and answer or nil
end

--- Whether the action `id` has a command to run.
function M.has_command(id)
  local words = config.get("session.commands." .. id)
  return type(words) == "table" and #words > 0
end

--- The other people's sessions on this seat, to go to: `{ id, user }`.
function M.others()
  local bus = login()
  if not bus or not bus.available() then return {} end
  local me = morf.env("USER") or ""
  local ok, rows = pcall(bus.sessions)
  local out = {}
  for _, row in ipairs(ok and rows or {}) do
    if row.user ~= me and row.user ~= "greeter" and row.seat ~= "" then out[#out + 1] = row end
  end
  return out
end

--- Whether the action `id` can be done here.
function M.available(id)
  local action = M.BY_ID[id]
  if not action then return false end
  for _, hidden in ipairs(config.get("session.hide") or {}) do
    if hidden == id then return false end
  end
  if id == "switch" then return #M.others() > 0 end
  if id == "lockdown" then return M.has_command("lock") end
  if id == "firmware" then
    local bus = login()
    return bus ~= nil and bus.available() and bus.can_firmware() == "yes"
  end
  if action.custom then return true end
  if not M.has_command(id) then return false end
  if action.can then
    local answer = M.can(action.can)
    if answer == "no" or answer == "na" then return false end
    if action.needs_yes and answer ~= "yes" then return false end
  end
  return true
end

-- The person's own entries: `{ id, name, icon, command }`, after the rest.
local function own_entries()
  for _, entry in ipairs(config.get("session.custom") or {}) do
    local command = type(entry) == "table" and entry.command
    if type(command) == "string" then command = require("settings_forms").split(command) end
    local listed = type(entry) == "table" and type(entry.id) == "string" and type(command) == "table"
      and #command > 0 and not M.BY_ID[entry.id]
    if listed then
      local action = { id = entry.id, icon = entry.icon or "terminal", name = entry.name or entry.id,
        detail = entry.detail or "Your command", key = "", custom = true, command = command,
        confirm = entry.confirm == true, signal = "info" }
      M.BY_ID[entry.id] = action
      M.ACTIONS[#M.ACTIONS + 1] = action
    end
  end
end

--- The actions on offer, in order; `quick` keeps the quick settings' row's.
function M.list(quick)
  own_entries()
  local out = {}
  for _, action in ipairs(M.ACTIONS) do
    if (not quick or action.quick) and M.available(action.id) then out[#out + 1] = action end
  end
  return out
end

--- Whether a session action is held up by someone: logind's blocking inhibitors
--- of `what` ("sleep" or "shutdown"), as `{ who, why }`, the shell's own aside.
function M.blockers(what)
  local bus = login()
  if not bus or not bus.available() then return {} end
  local ok, rows = pcall(bus.inhibitors)
  local out = {}
  for _, row in ipairs(ok and rows or {}) do
    if row.mode == "block" and tostring(row.what):find(what, 1, true) and row.who ~= "eva" then
      out[#out + 1] = { who = row.who, why = row.why }
    end
  end
  return out
end

return M
