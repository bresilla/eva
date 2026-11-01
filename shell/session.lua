-- Session actions and navigation are shared; theme builders own their views.
--
-- What ends the session asks once more, with no reader and no password in the
-- way: pressing it starts a countdown on its row, pressing it again goes now,
-- Escape or the Cancel row stops it, and at nought it runs.
local morf = require("morf")
local config = require("config")
local drawer = require("drawer")
local model = require("session_model")
local M = {}

-- The rows the menu shows, set once as it is built.
M.actions = model.list()
M.available = model.available
M.focus = morf.signal("eva.session.focus", 1)
M.opened = morf.signal("eva.session.opened", false)
-- The action counting down, "" for none, and its seconds left.
M.pending = morf.signal("eva.session.pending", "")
M.left = morf.signal("eva.session.left", 0)
-- What blocks sleep and shutdown, read as the menu opens.
M.blocked = morf.signal("eva.session.blocked", { sleep = {}, shutdown = {} })
-- The session the next Switch user goes to.
M.others = morf.signal("eva.session.others", {})
M.username = morf.env("USER") or "user"
local face = morf.fs.home() .. "/.face"
M.picture = morf.fs.exists(face) and face or nil
local function dry_run()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

--- The command an action runs: a list of words, `$USER` read from the
--- environment.
function M.command(id)
  local words = config.get("session.commands." .. id)
  if type(words) ~= "table" then return nil end
  local user = (morf.env and morf.env("USER")) or ""
  local out = {}
  for i, w in ipairs(words) do out[i] = (tostring(w):gsub("%$USER", user)) end
  return out
end

local ticking
local function stop_count()
  if ticking then ticking:cancel() ticking = nil end
  M.pending:set("")
  M.left:set(0)
end

--- Lock first, whatever comes next. A reason goes with it for the lock to read.
local function lock_now(reason)
  if reason then require("models.lock_reason").mark(reason) end
  local argv = M.command("lock")
  if not argv or #argv == 0 then return false end
  if dry_run() then
    morf.log("info", "eva: session lock" .. (reason and " (" .. reason .. ")" or "") .. " (dry run)")
    return true
  end
  morf.process.run(argv, {}, function() end)
  return true
end

-- The actions that are not a command of the settings.
local SPECIAL = {
  lockdown = function() return lock_now("lockdown") end,
  switch = function()
    local list = M.others:get()
    local target = list[1]
    if not target then return false end
    lock_now()
    local bus = require("models.logind").connect()
    if dry_run() then morf.log("info", "eva: session switch to " .. target.user .. " (dry run)") end
    return bus.activate(target.id)
  end,
  firmware = function()
    local bus = require("models.logind").connect()
    if dry_run() then
      morf.log("info", "eva: session firmware (dry run)")
      return true
    end
    return bus.reboot_to_firmware(true)
  end,
}

--- Runs action `id` now (shutting the menu first).
function M.run(id)
  stop_count()
  M.drawer.set(false)
  if SPECIAL[id] then return SPECIAL[id]() end
  local argv = M.command(id)
  if not argv or #argv == 0 then return false end
  if dry_run() then
    morf.log("info", "eva: session " .. id .. " (dry run): " .. table.concat(argv, " "))
    return true
  end
  morf.log("info", "eva: session " .. id .. ": " .. table.concat(argv, " "))
  morf.process.run(argv, {}, function(result)
    if result and not result.ok then
      morf.log("warn", "eva: session " .. id .. " failed: " .. tostring(result.stderr or result.code))
    end
  end)
  return true
end

--- A press on action `id`: straight through, the countdown, or, while it is
--- counting, now.
function M.activate(id)
  local action = model.BY_ID[id]
  if M.pending:get() == id then return M.run(id) end
  local seconds = tonumber(config.get("session.countdown")) or 0
  if not (action and action.confirm) or seconds <= 0 then return M.run(id) end
  stop_count()
  M.pending:set(id)
  M.left:set(math.floor(seconds))
  ticking = morf.time.timer(1000, function()
    local left = M.left:get() - 1
    M.left:set(left)
    if left <= 0 then M.run(id) end
  end, true)
  return true
end

--- Stops a countdown; true if there was one.
function M.cancel()
  if M.pending:get() == "" then return false end
  stop_count()
  return true
end

function M.close()
  if M.cancel() then return end
  M.drawer.set(false)
end
function M.accept() return M.activate(M.actions[M.focus:get()].id) end
function M.key(_, text, _, _, key)
  local n = #M.actions
  if key == "Up" or key == "ISO_Left_Tab" or text == "k" then M.focus:set((M.focus:get()-2)%n+1) return true end
  if key == "Down" or key == "Tab" or text == "j" then M.focus:set(M.focus:get()%n+1) return true end
  -- Each action's own letter, shown on its row.
  for index, action in ipairs(M.actions) do
    if action.key == text then
      M.focus:set(index)
      M.activate(action.id)
      return true
    end
  end
  return true
end
local view = require("themes").view("session").build(M)
M.drawer = drawer.new { name="session", edge=view.edge, width=view.width, height=view.height,
  content=view.content, props=view.props, close_policy="outside" }
M.dim = view.dim
morf.effect("eva.session.open", function()
  local on = M.drawer.open:get()
  M.opened:set(on)
  if on then
    M.focus:set(1)
    M.blocked:set({ sleep = model.blockers("sleep"), shutdown = model.blockers("shutdown") })
    M.others:set(model.others())
  else
    M.cancel()
  end
  view.shown(on)
end)
return M
