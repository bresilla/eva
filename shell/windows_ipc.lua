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
  if hyprland.stand_in then
    ipc.stand_in_cursor = function(x, y) hyprland.set_cursor(tonumber(x), tonumber(y)) end
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
  local snap = require("snap")
  -- `snap CELL`: the focused window into a cell (left, right, top, bottom,
  -- top_left, ..., full, center). `snap layout KEY`: the workspace into a
  -- layout. `snap picker`, and `snap drag` and `snap drop` as the compositor's
  -- drag begins and ends.
  ipc.snap = function(how, key)
    if how == "drag" then return snap.drag() end
    if how == "drop" then return snap.drop() end
    if not here() then return end
    if how == "picker" then snap.toggle_pick() return snap.picking:get() end
    if how == "layout" then return snap.tile(key) end
    if require("snap_model").CELLS[how or ""] then return snap.snap(how) end
    error("`" .. tostring(how) .. "`: a cell, layout KEY, picker, drag or drop")
  end
  -- `dock [on|off|auto]`: asks for it on a desk. `dock pin ID` pins an
  -- application or lets it go, `dock state` says what there is.
  ipc.dock = function(how, id)
    local dock = require("dock")
    local config = require("config")
    if how == "on" or how == "off" or how == "auto" then config.set("dock.enabled", how)
    elseif how == "pin" then return dock.toggle_pin(id)
    elseif how == "peek" then dock.entered() end
    return { mode = dock.mode(), shown = dock.shown(), rows = dock.rows:len(), overflow = dock.overflow:get() }
  end
  ipc.dock_clear = function() require("config").set("dock.pins", {}) end
  -- `dock_magnify [AT]`: the swell as if the pointer were AT along the row.
  ipc.dock_magnify = function(at) require("dock").pointer:set(tonumber(at) or -1) end
  ipc.dock_menu = function(index)
    local dock = require("dock")
    local row = dock.rows:get(tonumber(index) or 1)
    if row then dock.open_menu(row.key) end
  end
  ipc.dock_reserve = function() return require("dock").reserve() end
  ipc.dock_order = function()
    local out, dock = {}, require("dock")
    for i = 1, dock.rows:len() do out[i] = dock.rows:get(i).key end
    return out
  end
  ipc.dock_reorder = function(from, to) return require("dock").reorder(tonumber(from), tonumber(to)) end
  -- `kill_mode`: press a window to force quit it.
  ipc.kill_mode = function(how)
    local kill = require("kill_mode")
    if how == "stop" then kill.stop() return false end
    if not here() then return end
    return kill.start()
  end
end

return M
