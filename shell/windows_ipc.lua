-- The window features' verbs. Each is kept in `ipc`, as the shell's others
-- are, so a key and `morf ipc` do the same.
local morf = require("morf")
local M = {}

--- A window for an answer: what a test or a script reads.
local function brief(c)
  return { address = c.address, class = c.class, title = c.title, workspace = c.workspace, x = c.x, y = c.y,
    width = c.width, height = c.height, floating = c.floating, pinned = c.pinned, fullscreen = c.fullscreen,
    opacity = c.opacity, toplevel = c.toplevel, focus_history = c.focus_history }
end

function M.register(ipc)
  local windows = require("windows_model")
  local hyprland = require("services").hyprland
  -- `windows`: the list as the shell has it. `windows wire`: what was sent
  -- to the stand-in. `windows real`: what morf.toplevels says.
  ipc.windows = function(how)
    if how == "wire" then return hyprland.wire or {} end
    if how == "real" then return morf.toplevels and morf.toplevels.list() or {} end
    if how == "shots" then
      local shots, out = require("window_shots"), { refused = require("window_shots").refused }
      for _, c in ipairs(windows.list()) do out[c.address] = shots.source(c.address) end
      return out
    end
    local out = {}
    for _, c in ipairs(windows.recent()) do out[#out + 1] = brief(c) end
    return out
  end
  local here = require("services").here
  local overview = require("overview")
  -- `overview [open|close|toggle|state]`.
  ipc.overview = function(how)
    how = how or "toggle"
    if how == "close" then overview.close() end
    if how == "close" or how == "state" then
      if here() then return overview.opened:get() end
      return
    end
    if how ~= "open" and how ~= "toggle" then error("`" .. tostring(how) .. "`: open, close, toggle or state") end
    if not here() then overview.close() return end
    if how == "open" then return overview.open() end
    return overview.toggle()
  end
  local switcher = require("window_switcher")
  -- `switcher next|prev|same [free]`: a press of the key, Alt held unless
  -- `free` says it is not. `commit`, `cancel`, `state`.
  ipc.switcher = function(how, free)
    how = how or "next"
    if not here() then switcher.cancel() return end
    local hold = free ~= "free"
    if how == "next" then return switcher.step(1, hold) end
    if how == "prev" then return switcher.step(-1, hold) end
    if how == "same" then return switcher.same(hold) end
    if how == "commit" then return switcher.commit() end
    if how == "cancel" then switcher.cancel() return false end
    if how == "state" then
      local c = switcher.chosen()
      return { open = switcher.opened:get(), shown = switcher.shown:get(), title = c and c.title or "" }
    end
    error("`" .. tostring(how) .. "`: next, prev, same, commit, cancel or state")
  end
  ipc.switcher_scope = function(scope)
    if scope then require("config").set("windows.switcher.scope", scope) end
    return switcher.scope()
  end
end

return M
