-- Kill mode: the screen goes dark round the window under the pointer, and a
-- click there force-quits it. Escape, or the right button, leaves it be.
local morf = require("morf")
local services = require("services")
local windows = require("windows_model")
local M = {}

M.active = morf.signal("eva.kill_mode.active", false)
-- The window under the pointer, "" for none.
M.target = morf.signal("eva.kill_mode.target", "")

--- The topmost window at a point on this surface: floating ones lie over
--- tiled ones, and the more recently used over the rest.
function M.at(x, y)
  local here = windows.int(services.workspace.active())
  local list = windows.recent(windows.on(here))
  table.sort(list, function(a, b)
    if a.floating ~= b.floating then return a.floating end
    return (a.focus_history or 0) < (b.focus_history or 0)
  end)
  for _, c in ipairs(list) do
    local r = windows.rect(c)
    if x >= r.x and x < r.x + r.width and y >= r.y and y < r.y + r.height then return c.address end
  end
  return ""
end

function M.aim(x, y) M.target:set(M.at(x, y)) end

--- The window aimed at, on this surface; nil with none.
function M.rect()
  local c = windows.get(M.target:get())
  return c and windows.rect(c) or nil
end

function M.start()
  require("drawer").close_all()
  require("overview").close()
  windows.refresh()
  M.target:set("")
  M.active:set(true)
  -- Lights what is under the pointer at once, before it moves.
  services.hyprland.cursor_position(function(x, y)
    if not x or not M.active:get() then return end
    local m = windows.monitor_of() or {}
    local ratio = windows.ratio(m)
    M.aim((x - (m.x or 0)) * ratio, (y - (m.y or 0)) * ratio)
  end)
  return true
end

function M.stop() M.active:set(false) end

--- Force-quits what is under `x, y`, and leaves the mode.
function M.fire(x, y)
  local address = M.at(x, y)
  M.stop()
  if address == "" then return false end
  return windows.kill(address)
end

function M.key(_, _, _, _, name)
  if name == "Escape" then M.stop() end
  return true
end

local view = require("themes").view("kill_mode").build(M)
M.node = view.node
morf.effect("eva.kill_mode.keys", function() view.shown(M.active:get()) end)

return M
