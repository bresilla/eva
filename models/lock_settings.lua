-- What the lock reads of its settings: the defaults, then the `lock` table of
-- the person's settings file, then the system's policy over both. Read once as
-- the lock starts, and never written. Anything missing, unreadable or of the
-- wrong type stands at its default.
--
--   local prefs = require("models.lock_settings").load()
--   prefs.notifications.level
--
-- Under EVA_DRY_RUN, EVA_LOCK_POLICY names another policy file (specs).
local morf = require("morf")
local defaults = require("models.lock_defaults")
local M = { LEVELS = { "all", "senders", "count", "none" }, GRACE_MAX = 60 }

local function decode(path)
  local ok, text = pcall(morf.fs.read, path)
  if not ok or type(text) ~= "string" then return nil end
  local fine, value = pcall(morf.json.decode, text)
  return fine and type(value) == "table" and value or nil
end

local function is_list(value) return next(value) == nil or value[1] ~= nil end

-- A copy of `base` with what `over` gives of the same shape laid on it.
local function merged(base, over)
  local out = {}
  for key, value in pairs(base) do
    local given
    if type(over) == "table" then given = over[key] end
    if type(value) == "table" and not is_list(value) then
      out[key] = merged(value, given)
    elseif given ~= nil and type(given) == type(value)
      and (type(value) ~= "table" or is_list(given)) then
      out[key] = given
    elseif type(value) == "table" then
      out[key] = merged(value, nil)
    else
      out[key] = value
    end
  end
  return out
end

local function one_of(value, list, fallback)
  for _, candidate in ipairs(list) do if candidate == value then return value end end
  return fallback
end

--- The settings file the shell uses: EVA_SETTINGS, CAELESTIA_SETTINGS, or the
--- path the shell left under the state directory.
function M.path()
  local named = morf.env("EVA_SETTINGS") or morf.env("CAELESTIA_SETTINGS")
  if named and named ~= "" then return named end
  local state = morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")
  local ok, text = pcall(morf.fs.read, state .. "/eva/settings-path")
  local kept = ok and type(text) == "string" and text:match("^%s*(.-)%s*$")
  if kept and kept ~= "" then return kept end
  return morf.paths.state("eva.json")
end

function M.policy_path()
  local named = morf.env("EVA_DRY_RUN") == "1" and morf.env("EVA_LOCK_POLICY")
  return named or "/etc/eva/lock.json"
end

--- The system's policy, as written.
function M.policy() return decode(M.policy_path()) or {} end

--- The settings as they apply now.
function M.load()
  local file = decode(M.path()) or {}
  local policy = M.policy()
  local values = merged(merged(defaults, file.lock), policy)
  values.notifications.level = one_of(values.notifications.level, M.LEVELS, defaults.notifications.level)
  values.notifications.style = one_of(values.notifications.style, { "list", "dots" }, "list")
  values.keypad = one_of(values.keypad, { "text", "digits" }, "text")
  values.grace_seconds = math.max(0, math.min(M.GRACE_MAX, math.floor(tonumber(values.grace_seconds) or 0)))
  values.blur = math.max(0, math.min(64, tonumber(values.blur) or defaults.blur))
  values.tint = math.max(0, math.min(1, tonumber(values.tint) or defaults.tint))
  values.reader_tries = math.max(0, math.floor(tonumber(values.reader_tries) or defaults.reader_tries))
  values.attempts.limit = math.max(1, math.floor(tonumber(values.attempts.limit) or defaults.attempts.limit))
  values.attempts.wait = math.max(0, tonumber(values.attempts.wait) or defaults.attempts.wait)
  values.clock.size = math.max(.5, math.min(1.5, tonumber(values.clock.size) or 1))
  values.managed = policy
  return values
end

--- The settings a lockdown leaves: no readers, nothing read out, no way
--- around the password.
function M.lockdown(values)
  values.notifications.level = "none"
  values.readers = false
  values.grace_seconds = 0
  values.widgets = {}
  values.media = false
  values.power_buttons = false
  values.status = { battery = true, network = false, bluetooth = false, mode = false }
  values.shortcuts = { "flashlight" }
  values.lockdown = true
  return values
end

return M
