-- Global key remapping: what is chosen, kept in the settings and handed to the
-- system. No nodes.
--
-- `programs.eva.remap.enable` sets EVA_REMAP to a folder this session may write
-- to; a choices file there is what the system's kanata follows
-- (nix/nixos/remap.nix). Without the option nothing here touches the machine.
local morf = require("morf")
local config = require("config")
local host = require("lib.services.host")

local M = {}

M.UNIT = "kanata-eva.service"

-- Whether the system's service is up, as last asked.
M.running = morf.signal("eva.remap.running", false)

local function folder()
  local value = morf.env("EVA_REMAP")
  return value ~= "" and value or nil
end

--- Whether the system lets the shell remap keys.
function M.allowed() return folder() ~= nil end

local KEYS = { "caps", "hyper", "swap_alt_super", "home_row", "tap", "hold" }

--- What goes in the choices file.
function M.choices()
  local out = {}
  for _, key in ipairs(KEYS) do out[key] = config.get("remap." .. key) end
  return out
end

--- Whether anything is asked of the keyboard.
function M.anything()
  local c = M.choices()
  return c.caps ~= "" or c.hyper ~= "" or c.swap_alt_super == true or c.home_row == true
end

--- What the service is asked to do, in a line.
function M.summary()
  if not M.allowed() then return "Off in the system's configuration: programs.eva.remap.enable turns it on" end
  if not M.anything() then return "Nothing chosen, so nothing reads the keyboards" end
  return M.running:get() and "Running" or "Starting"
end

--- The file as the system will read it, for a look at what is sent.
function M.text() return morf.json.encode(M.choices()) end

--- Asks whether the service is up.
function M.refresh()
  if not M.allowed() then return end
  host.read({ "systemctl", "is-active", M.UNIT }, function(text)
    M.running:set(tostring(text or ""):match("^active") ~= nil)
  end)
end

--- Writes the choices, for the system to take up.
function M.send()
  local path = folder()
  if not path then return false end
  if host.held("remap choices") then return true end
  local ok, why = morf.fs.write(path .. "/choices.json", morf.json.encode(M.choices()), { atomic = true, parents = true, mode = 384 })
  if not ok then morf.log("warn", "eva: remap: " .. tostring(why)) end
  morf.time.timer(1500, M.refresh, false)
  return ok == true
end

--- Follows the choices, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  if not M.allowed() then return end
  local first = true
  morf.effect("eva.remap.follow", function()
    M.choices()
    if first then first = false return end
    morf.time.timer(1, M.send, false)
  end)
  M.refresh()
end

--- Sets a choice.
function M.set(key, value) config.set("remap." .. key, value) end

return M
