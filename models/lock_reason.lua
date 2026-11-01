-- Why the session is being locked: one small file under the runtime directory,
-- used once. `take` answers "idle" or "lockdown" and when it was marked, or
-- "manual" with no fresh mark.
local morf = require("morf")
local M = { FRESH = 20 }
local KNOWN = { idle = true, lockdown = true }

local function file()
  local run = morf.env("XDG_RUNTIME_DIR")
  if not run or run == "" then return nil end
  return run .. "/eva/lock-reason"
end

--- Seconds since boot, suspended time included, or nil.
function M.uptime()
  local ok, text = pcall(morf.fs.read, "/proc/uptime")
  return ok and type(text) == "string" and tonumber(text:match("^[%d.]+")) or nil
end

function M.mark(reason)
  local path, at = file(), M.uptime()
  if not path or not at or not KNOWN[reason] then return false end
  return pcall(morf.fs.write, path, morf.json.encode { reason = reason, at = at },
    { atomic = true, parents = true, mode = 384 })
end

function M.clear()
  local path = file()
  if path then pcall(morf.fs.remove, path) end
end

function M.take()
  local path = file()
  if not path then return "manual" end
  local ok, text = pcall(morf.fs.read, path)
  M.clear()
  if not ok or type(text) ~= "string" then return "manual" end
  local fine, value = pcall(morf.json.decode, text)
  if not fine or type(value) ~= "table" or not KNOWN[value.reason] then return "manual" end
  local now, at = M.uptime(), tonumber(value.at)
  if not now or not at or at > now or now - at > M.FRESH then return "manual" end
  return value.reason, at
end

return M
