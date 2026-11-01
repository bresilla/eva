-- What the system's configuration says about idle: the stages it fixes and the
-- commands it provides, from /etc/eva/idle.json (EVA_IDLE_POLICY names another
-- file). A stage it fixes wins over Settings, and runs under the system's idle
-- daemon. Empty where nothing configures it.
local morf = require("morf")
local M = {}

local function dry()
  local v = morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

--- `{ managed = { lock, blank, suspend }, commands = { lock, dpms } }`.
function M.load()
  local path = morf.env("EVA_IDLE_POLICY") or "/etc/eva/idle.json"
  local ok, text = pcall(morf.fs.read, path)
  if ok and type(text) == "string" then
    local fine, value = pcall(morf.json.decode, text)
    if fine and type(value) == "table" then
      value.managed = type(value.managed) == "table" and value.managed or {}
      value.commands = type(value.commands) == "table" and value.commands or {}
      return value
    end
  end
  return { managed = {}, commands = {} }
end

--- Turns every output "off" or "on".
function M.dpms(action)
  local helper = M.load().commands.dpms
  local argv = type(helper) == "string" and { helper, action } or { "hyprctl", "dispatch", "dpms", action }
  if dry() then
    morf.log("info", "eva: displays " .. action .. " (dry run)")
    return true
  end
  morf.process.run(argv, { timeout_ms = 5000, max_output = 512 }, function() end)
  return true
end

return M
