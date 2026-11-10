-- The Mouse sharing page's model: lan-mouse's daemon as the page reads it,
-- and what the page asks of it (lib/services/lan_mouse.lua). No nodes.
local morf = require("morf")
local page_model = require("page_model")
local mouse = require("lib.services.lan_mouse")

local M = {}

-- Where another machine stands, as the page says it.
M.SIDES = { { "left", "arrow_back", "Left" }, { "right", "arrow_forward", "Right" },
  { "top", "arrow_upward", "Above" }, { "bottom", "arrow_downward", "Below" } }
local WHERE = { left = "On the left", right = "On the right", top = "Above", bottom = "Below" }
local ICON = { left = "arrow_back", right = "arrow_forward", top = "arrow_upward", bottom = "arrow_downward" }

--- A fingerprint short enough for a row: its first and last four pairs.
function M.short(fingerprint)
  fingerprint = tostring(fingerprint or "")
  if #fingerprint <= 30 then return fingerprint end
  return fingerprint:sub(1, 11) .. " … " .. fingerprint:sub(-11)
end

function M.new(active)
  local model = page_model.new("lan_mouse", active)
  mouse.watch(model.active)
  local function now() return mouse.get() end
  model.installed = mouse.installed
  model.short = M.short
  model.SIDES = M.SIDES
  function model.on() return now().service == "active" end
  function model.up() return model.on() and now().up end
  function model.port() return now().port end
  function model.fingerprint() return now().fingerprint end
  function model.clients() return now().clients end
  function model.allowed() return now().allowed end
  function model.asking() return now().asking end
  function model.blocked() return model.up() and not (now().capture and now().emulation) end
  function model.where(pos) return WHERE[pos] or "" end
  function model.icon(pos) return ICON[pos] or "swap_horiz" end
  function model.release_keys() return mouse.release_keys() end

  function model.set_on(on)
    return model.action(function(done) mouse.run(on, done) return true end)
  end
  --- What a page change says when the daemon is not there to take it.
  local function sent(ok)
    if not ok then model.say("lan-mouse is not answering", true) end
    return ok
  end
  function model.add(hostname, pos)
    hostname = tostring(hostname or ""):match("^%s*(.-)%s*$")
    if hostname == "" then return false end
    return sent(mouse.add(hostname, pos))
  end
  function model.activate(handle, on) return sent(mouse.activate(handle, on)) end
  function model.remove(handle) return sent(mouse.remove(handle)) end
  function model.place(handle, pos) return sent(mouse.place(handle, pos)) end
  function model.allow(fingerprint, name) return sent(mouse.allow(fingerprint, name)) end
  function model.forget(fingerprint) return sent(mouse.forget(fingerprint)) end
  function model.dismiss(fingerprint) mouse.dismiss(fingerprint) end
  function model.retake() return sent(mouse.retake()) end
  function model.copy()
    local ok = pcall(morf.clipboard.set, now().fingerprint)
    model.say(ok and "Copied" or "Could not reach the clipboard", not ok)
  end
  return model
end

return M
