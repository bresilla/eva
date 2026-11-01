-- Snapping windows: a dragged window shows where it will land, near an edge or
-- a corner; a picker lays out the focused window or the whole workspace; and
-- once a window is snapped, the others are offered for the room left.
--
-- A drag belongs to the compositor. Its key binds call `snap drag` as the
-- button goes down and `snap drop` as it comes up; in between the pointer is
-- asked after, only for that long. A snapped window is a floating one, placed
-- exactly.
local morf = require("morf")
local theme = require("theme")
local services = require("services")
local windows = require("windows_model")
local model = require("snap_model")
local shots = require("window_shots")
local M = {}

local REACH, CORNER, POLL = 48, 160, 33
local GAP = theme.space.s

-- The cell the pointer is over while dragging, "" for none.
M.zone = morf.signal("eva.snap.zone", "")
M.dragging = morf.signal("eva.snap.dragging", false)
-- The picker is open.
M.picking = morf.signal("eva.snap.picking", false)
-- Snap assist: the cells on offer, and the windows to fill them.
M.assisting = morf.signal("eva.snap.assisting", false)
M.free = morf.signal("eva.snap.free", {})
M.offers = morf.list_model({})
M.offer_slots = morf.signal("eva.snap.offer_slots", {})

local hyprland = services.hyprland
local poll, target, monitor

local function area_of(m)
  return model.area(m or windows.monitor_of(windows.active()) or {})
end

--- A cell's box on this surface, in the shell's pixels.
function M.preview(cell)
  local m = monitor or windows.monitor_of(windows.active())
  if not m then return nil end
  local box = model.box(cell, area_of(m), GAP)
  if not box then return nil end
  local ratio = windows.ratio(m)
  return { x = (box.x - (m.x or 0)) * ratio, y = (box.y - (m.y or 0)) * ratio,
    width = box.width * ratio, height = box.height * ratio }
end

local function place(address, cell, m)
  local box = model.box(cell, area_of(m), GAP)
  if not box then return false end
  return windows.run(address, windows.steps.box(box.x, box.y, box.width, box.height))
end

--- Snaps a window to a cell; the focused one with no `address`.
function M.snap(cell, address)
  local c = address and windows.get(address) or windows.active()
  if not c then return false end
  local m = windows.monitor_of(c)
  local done = place(c.address, cell, m)
  if done and not address then M.offer(cell, c, m) end
  return done
end

--- Lays out this workspace's windows, most recent first, by the layout `key`.
function M.tile(key)
  local here = windows.int(services.workspace.active())
  local list = windows.recent(windows.on(here))
  local cells = model.assign(key, #list)
  for i, c in ipairs(list) do place(c.address, cells[i], windows.monitor_of(c)) end
  return #list
end

-- ------------------------------------------------------------------ assist --

--- Offers the other windows on the workspace for the cells left beside `cell`.
function M.offer(cell, c, m)
  if require("config").get("windows.snap_assist") == false then return false end
  local free = model.FREE[cell]
  if not free then return false end
  local rest = {}
  for _, other in ipairs(windows.recent(windows.on(c.workspace))) do
    if other.address ~= c.address then rest[#rest + 1] = other end
  end
  if #rest == 0 then return false end
  monitor = m
  M.free:set(free)
  M.show_offers(rest)
  M.assisting:set(true)
  return true
end

function M.show_offers(rest)
  local cell = M.free:get()[1]
  local box = cell and M.preview(cell)
  if not box then M.assisting:set(false) return end
  local sizes, rows = {}, {}
  for i, c in ipairs(rest) do
    local r = windows.rect(c)
    sizes[i] = { width = math.max(120, r.width), height = math.max(80, r.height) }
    rows[i] = { address = c.address, class = c.class, title = c.title, initial_class = c.initial_class, index = i }
  end
  local S = theme.space
  local boxes = require("overview_model").arrange(sizes, { x = box.x + S.l, y = box.y + S.l,
    width = box.width - 2 * S.l, height = box.height - 2 * S.l }, S.m)
  local slots = {}
  for i, c in ipairs(rest) do slots[c.address] = boxes[i] end
  M.offer_slots:set(slots)
  M.offers:replace(rows, "address")
  shots.refresh(rest)
end

--- Takes the window `address` into the next free cell.
function M.fill(address)
  local free = M.free:get()
  local cell = free[1]
  if not cell then M.assisting:set(false) return end
  place(address, cell, monitor)
  local left = {}
  for i = 2, #free do left[#left + 1] = free[i] end
  M.free:set(left)
  if #left == 0 then M.assisting:set(false) return end
  local rest = {}
  for r = 1, M.offers:len() do
    local row = M.offers:get(r)
    if row.address ~= address then rest[#rest + 1] = windows.get(row.address) end
  end
  if #rest == 0 then M.assisting:set(false) else M.show_offers(rest) end
end

function M.end_assist() M.assisting:set(false) end

-- -------------------------------------------------------------------- drag --

local function follow()
  hyprland.cursor_position(function(x, y)
    if not x or not M.dragging:get() then return end
    local best
    for _, m in ipairs(windows.monitors()) do
      local a = model.area(m)
      if x >= (m.x or 0) and x < (m.x or 0) + (m.width or 0) / (m.scale or 1) then best = { m = m, a = a } end
    end
    if not best then return end
    monitor = best.m
    M.zone:set(model.zone(x, y, best.a, REACH, CORNER) or "")
  end)
end

--- The drag's button went down.
function M.drag()
  if M.dragging:get() then return true end
  local c = windows.active()
  target = c and c.address or nil
  M.dragging:set(true)
  M.zone:set("")
  if poll then poll:cancel() end
  poll = morf.time.timer(POLL, follow, true)
  follow()
  return true
end

--- The drag's button came up: the window lands in the zone it is over.
function M.drop()
  if poll then poll:cancel() poll = nil end
  local zone = M.zone:get()
  M.dragging:set(false)
  M.zone:set("")
  if zone == "" or not target then return false end
  local c = windows.get(target)
  if not c then return false end
  place(c.address, zone, monitor)
  M.offer(zone, c, monitor)
  return true
end

-- ------------------------------------------------------------------ picker --

function M.pick() M.picking:set(true) end
function M.end_pick() M.picking:set(false) end
function M.toggle_pick() M.picking:set(not M.picking:get()) end

--- A cell chosen in the picker: the focused window goes there.
function M.choose(cell)
  M.end_pick()
  return M.snap(cell)
end

--- A whole layout chosen in the picker.
function M.choose_layout(key)
  M.end_pick()
  return M.tile(key)
end

function M.key(_, _, _, _, name)
  if name == "Escape" then
    M.end_pick()
    M.end_assist()
    return true
  end
  return false
end

local view = require("themes").view("snap").build(M)
M.node = view.node
morf.effect("eva.snap.keys", function() view.shown(M.picking:get() or M.assisting:get()) end)

return M
