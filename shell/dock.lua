-- The dock: pinned and running applications along an edge, on a desk where it
-- is asked for and on a tablet as the taskbar. This is its running part: the
-- pointer, the hiding, the menu. The theme's view (themes/*/views/dock.lua)
-- draws it.
local morf = require("morf")
local model = require("dock_model")
local windows = require("windows_model")
local M = setmetatable({}, { __index = model })

local DWELL, GRACE, PEEK = 120, 400, 450

-- How far along the row the pointer is, nil away from it.
M.pointer = morf.signal("eva.dock.pointer", -1)
-- The pointer has reached the edge, or is on the dock.
M.near = morf.signal("eva.dock.near", false)
M.menu_for = morf.signal("eva.dock.menu_for", "")
M.preview_for = morf.signal("eva.dock.preview_for", "")

local leaving, arriving, peeking

--- The dock's box on this surface, from where the view lays it.
local box = function() return { x = 0, y = 0, width = 0, height = 0 } end
function M.attach(fn) box = fn end

--- Whether a window lies under the dock on this workspace.
function M.covered()
  local here = windows.int(require("services").workspace.active())
  local dock = box()
  for _, c in ipairs(windows.on(here)) do
    if model.overlaps(windows.rect(c), dock) then return true end
  end
  return false
end

--- Whether a panel hangs from the dock's edge, or a sheet is over the screen.
local function panel_in_the_way()
  local sheets = require("responsive").sheets()
  for _, d in ipairs(require("drawer").all) do
    if d.name ~= "keyboard" and d.open:get() and (sheets or d.edge == model.edge()) then return true end
  end
  return false
end

--- Whether the dock is out.
function M.shown()
  if not model.on() or panel_in_the_way() then return false end
  if M.near:get() or M.menu_for:get() ~= "" then return true end
  local how = model.autohide()
  if how == "off" then return true end
  if how == "on" then return false end
  return not M.covered()
end

--- What it keeps clear on its edge, for windows: only while it stays out.
function M.reserve()
  if not model.on() or model.autohide() ~= "off" then return 0 end
  return model.size() + 2 * require("theme").space.s
end

function M.edge_entered()
  if leaving then leaving:cancel() leaving = nil end
  local snap = package.loaded.snap
  if arriving or M.near:get() or (snap and snap.busy:get()) then return end
  arriving = morf.time.timer(DWELL, function()
    arriving = nil
    M.near:set(true)
  end, false)
end

function M.edge_left()
  if arriving then arriving:cancel() arriving = nil end
end

function M.entered()
  if leaving then leaving:cancel() leaving = nil end
  M.near:set(true)
end

function M.left()
  M.pointer:set(-1)
  M.peek("")
  if leaving then return end
  leaving = morf.time.timer(GRACE, function()
    leaving = nil
    M.near:set(false)
  end, false)
end

--- Shows the windows of `key` once the pointer has stayed on it.
function M.peek(key)
  if peeking then peeking:cancel() peeking = nil end
  if key == "" then M.preview_for:set("") return end
  peeking = morf.time.timer(PEEK, function()
    peeking = nil
    if #model.windows_of(key) > 0 then
      M.preview_for:set(key)
      require("window_shots").refresh(model.windows_of(key))
    end
  end, false)
end

function M.open_menu(key) M.preview_for:set("") M.menu_for:set(key) end
function M.close_menu() M.menu_for:set("") end

local view = require("themes").view("dock").build(M)
M.node = view.node

return M
