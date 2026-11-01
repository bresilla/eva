-- What the lock shows of the shell: a small file under the runtime directory,
-- filtered to the chosen level before it is written. Per-app rules come from the
-- notifications stream through `rules()`.
local morf = require("morf")
local config = require("config")
local view = require("models.lock_notifications")
local M = {}

local function dry_fake_rules()
  local spec = morf.env("EVA_FAKE_LOCK_RULES")
  if not spec or spec == "" then return nil end
  local ok, value = pcall(morf.json.decode, spec)
  return ok and type(value) == "table" and value or nil
end

--- An app's own level on the lock, or nil. The notifications stream's signal
--- is `notifs.lock_rules`, a table of app name to level; until it lands,
--- EVA_FAKE_LOCK_RULES stands in.
function M.rules()
  local notifs = package.loaded.notifs
  local signal = notifs and notifs.lock_rules
  local table_of = signal and signal:get() or dry_fake_rules() or {}
  return function(app) return table_of[app] end
end

local viewed = morf.signal("eva.lock.viewed", morf.time.now())
--- The person has been at the screen: only what comes later is new.
function M.seen() viewed:set(morf.time.now()) end

local function ringer_mode()
  local ok, mode = pcall(config.get, "ringer.mode")
  return ok and mode or "sound"
end

--- What goes in the file, from what the shell holds now.
function M.snapshot(history)
  local level = config.get("lock.notifications.level")
  local since = config.get("lock.notifications.new_only") and viewed:get() or nil
  local notifications = view.project(history, level, M.rules(),
    { silent = config.get("lock.notifications.silent"), since = since })
  local notifs = package.loaded.notifs
  return { notifications = notifications, written = morf.time.now(), mode = {
    dnd = notifs and notifs.dnd and notifs.dnd:get() == true or false,
    ringer = ringer_mode(),
    airplane = config.get("airplane.on") == true,
  } }
end

--- Opens what the lock's shortcut `id` stands for. It comes after the password,
--- and it is an id: the command is the settings', never the caller's.
function M.open(id)
  local argv = id == "camera" and config.get("lock.camera")
    or id == "command" and config.get("lock.command.argv") or nil
  if type(argv) ~= "table" or #argv == 0 then return false end
  local dry = morf.env("EVA_DRY_RUN")
  if dry and dry ~= "" and dry ~= "0" then
    morf.log("info", "eva: lock shortcut " .. id .. " (dry run)")
    return true
  end
  return morf.process.spawn { command = argv, detached = true } ~= nil
end

--- Starts writing, from the runtime that holds the history.
function M.start()
  local notifs = require("notifs")
  local path = view.path()
  if not path then return end
  local pending
  morf.effect("eva.lock.bridge", function()
    if morf.window.primary and not morf.window.primary() then return end
    local text = morf.json.encode(M.snapshot(notifs.history:get()))
    if pending then pending:cancel() end
    pending = morf.time.timer(120, function()
      pending = nil
      pcall(morf.fs.write, path, text, { atomic = true, parents = true, mode = 384 })
    end, false)
  end)
end

return M
