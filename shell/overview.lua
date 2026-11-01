-- The overview: every workspace along the top, and the windows of the one
-- being looked at spread out beneath, each flying out of where it really is.
-- Typing filters across all of them. A card goes to another workspace or
-- monitor by dragging it onto one. Under a phone's finger the same windows
-- are a row of cards, swiped along and thrown away.
--
-- `pull` runs from 0 (every card on its window) to 1 (every card in its
-- slot): a key sets it at once and a finger follows it, and the springs on
-- the cards do the rest.
local morf = require("morf")
local theme = require("theme")
local services = require("services")
local windows = require("windows_model")
local model = require("overview_model")
local shots = require("window_shots")
local S = theme.space
local M = {}

M.opened = morf.signal("eva.overview.opened", false)
M.pull = morf.signal("eva.overview.pull", 0)
M.query = morf.signal("eva.overview.query", "")
-- The window the keys are on.
M.selected = morf.signal("eva.overview.selected", "")
-- The workspace whose windows are spread out.
M.viewing = morf.signal("eva.overview.viewing", 1)
M.cards = morf.list_model({})
M.desks = morf.list_model({})
-- Where each card and each desk goes, by address and by workspace id as text.
M.slots = morf.signal("eva.overview.slots", {})
M.strip = morf.signal("eva.overview.strip", {})
M.drag = morf.state { address = "", x = 0, y = 0, width = 0, height = 0, over = 0, grab_x = 0, grab_y = 0 }

local LIVE_MS = 700
local MIN_THROW = 120
M.STRIP_H, M.SEARCH_H, M.BOTTOM = 148, 48, S.xxl

--- "cards" under a phone's finger, "spread" elsewhere.
function M.layout()
  local r = require("responsive")
  return r.phone() and "cards" or "spread"
end

local function size()
  local s = (morf.screens or {})[1] or {}
  return s.width or 1920, s.height or 1080
end
M.size = size

--- Where `address` really is, on this surface.
function M.rect(address)
  local c = windows.get(address)
  if not c then
    local w, h = size()
    return { x = w / 2, y = h / 2, width = 1, height = 1 }
  end
  return windows.rect(c)
end

-- The windows on show: the workspace looked at, or everywhere that matches.
local function shown()
  local query = M.query:get()
  local list = {}
  local source = query ~= "" and windows.list() or windows.on(M.viewing:get())
  if M.layout() == "cards" then source = windows.recent() end
  for _, c in ipairs(source) do
    if windows.matches(c, query) then list[#list + 1] = c end
  end
  if M.layout() == "cards" then return list end
  if query ~= "" then return windows.recent(list) end
  return list
end

local function slots_spread(list)
  local w, h = size()
  local top = S.xl + M.STRIP_H + S.l + M.SEARCH_H + S.l
  local area = { x = S.xxl, y = top, width = w - 2 * S.xxl, height = h - top - M.BOTTOM }
  local sizes = {}
  for i, c in ipairs(list) do
    local r = windows.rect(c)
    sizes[i] = { width = math.max(120, r.width), height = math.max(80, r.height) }
  end
  local boxes = model.arrange(sizes, area, S.l)
  local out = {}
  for i, c in ipairs(list) do out[c.address] = boxes[i] end
  return out
end

--- A card's box in the phone's row, before the row is scrolled.
function M.card_box(i)
  local w, h = size()
  local cw, ch = math.floor(w * .72), math.floor(h * .68)
  return { x = (w - cw) / 2 + (i - 1) * (cw + S.l), y = (h - ch) / 2, width = cw, height = ch }
end

local function slots_cards(list)
  local out = {}
  for i, c in ipairs(list) do out[c.address] = M.card_box(i) end
  return out
end

local function rebuild()
  local list = shown()
  local rows = {}
  for i, c in ipairs(list) do
    rows[i] = { address = c.address, class = c.class, title = c.title, initial_class = c.initial_class, index = i,
      workspace = c.workspace, pinned = c.pinned }
  end
  M.slots:set(M.layout() == "cards" and slots_cards(list) or slots_spread(list))
  M.cards:replace(rows, "address")
  local chosen, found = M.selected:get(), false
  for _, c in ipairs(list) do if c.address == chosen then found = true end end
  if not found then M.selected:set(list[1] and list[1].address or "") end
  local desks = model.desks()
  local rows_d, w = {}, (size())
  local boxes = model.strip(#desks, { x = S.xxl, y = S.xl, width = w - 2 * S.xxl, height = M.STRIP_H },
    (select(1, size())) / math.max(1, (select(2, size()))), S.m)
  local strip = {}
  for i, d in ipairs(desks) do
    rows_d[i] = { id = d.id, name = d.name, named = d.named, monitor = d.monitor, active = d.active }
    strip[tostring(d.id)] = boxes[i]
  end
  M.strip:set(strip)
  M.desk_rows = desks
  M.desks:replace(rows_d, "id")
end

morf.effect("eva.overview.rebuild", function()
  M.query:get()
  M.viewing:get()
  services.hyprland.state.clients:len()
  windows.list()
  windows.workspaces()
  if M.opened:get() then rebuild() end
end)

local function others()
  local list = {}
  for _, c in ipairs(windows.list()) do list[#list + 1] = c end
  return list
end

local live
local function stop_live()
  if live then live:cancel() live = nil end
end
local function start_live()
  stop_live()
  shots.refresh(others())
  live = morf.time.timer(LIVE_MS, function() shots.refresh(others()) end, true)
end

--- Shows it, the cards leaving their windows.
function M.open()
  if M.opened:get() then return true end
  require("drawer").close_all()
  M.viewing:set(model.here())
  M.query:set("")
  local active = windows.active()
  M.selected:set(active and active.address or "")
  M.pull:set(0)
  rebuild()
  M.opened:set(true)
  start_live()
  morf.time.timer(1, function() if M.opened:get() then M.pull:set(1) end end, false)
  return true
end

--- Puts it away, the cards going back to their windows.
function M.close()
  if not M.opened:get() then return false end
  stop_live()
  M.drag.address = ""
  M.menu_for:set("")
  M.pull:set(0)
  M.opened:set(false)
  return false
end

function M.toggle()
  if M.opened:get() then return M.close() end
  return M.open()
end

--- A finger's pull from the bottom edge: `amount` of it, from 0 to 1.
function M.follow(amount)
  if not M.opened:get() then M.open() end
  M.pull:set(math.max(0, math.min(1, amount)))
end

--- Lets the finger go: the rest of the way, or back.
function M.settle(keep)
  if keep then M.pull:set(1) else M.close() end
end

--- Goes to the window, closing the overview.
function M.activate(address)
  address = address or M.selected:get()
  M.close()
  if address ~= "" then windows.focus(address) end
end

--- Closes the window behind a card.
function M.close_window(address)
  address = address or M.selected:get()
  if address == "" then return end
  shots.forget(address)
  windows.close(address)
end

--- Looks at workspace `id`.
function M.view(id) M.viewing:set(id) end

--- Goes to workspace `id`, closing the overview.
function M.enter(id)
  M.close()
  services.workspace.go(id)
end

--- The next or previous desk from the one looked at.
function M.scroll(delta)
  local rows = M.desk_rows or {}
  for i, d in ipairs(rows) do
    if d.id == M.viewing:get() then
      local next_desk = rows[math.max(1, math.min(#rows, i + delta))]
      M.viewing:set(next_desk.id)
      return next_desk.id
    end
  end
end

-- ------------------------------------------------------------------- drag --

--- A card picked up at `x, y`.
function M.drag_start(address, x, y)
  local box = M.slots:get()[address]
  if not box then return end
  local d = M.drag
  d.grab_x, d.grab_y = x - box.x, y - box.y
  d.width, d.height = box.width, box.height
  d.x, d.y, d.over = box.x, box.y, 0
  d.address = address
end

function M.drag_move(x, y)
  local d = M.drag
  if d.address == "" then return end
  d.x, d.y = x - d.grab_x, y - d.grab_y
  d.over = tonumber(model.hit(M.strip:get(), x, y) or 0)
end

--- Where the card lands: onto a desk moves its window there, and onto a desk
--- on another monitor, to that monitor.
function M.drag_end()
  local d = M.drag
  local address, over = d.address, d.over
  d.address = ""
  d.over = 0
  if address == "" or over == 0 then return false end
  local c = windows.get(address)
  if not c or c.workspace == over then return false end
  M.drop(address, over)
  return true
end

--- Moves a window to workspace `id`.
function M.drop(address, id)
  shots.refresh({ windows.get(address) })
  return windows.to_workspace(address, id, false)
end

-- ------------------------------------------------------------------- keys --

local DIRECTIONS = { Up = { 0, -1 }, Down = { 0, 1 }, Left = { -1, 0 }, Right = { 1, 0 } }

function M.key(_, _, modifiers, _, name)
  if name == "Escape" then M.close() return true end
  if name == "Return" or name == "KP_Enter" then M.activate() return true end
  local d = DIRECTIONS[name]
  if d then
    local chosen = model.step(M.slots:get(), M.selected:get(), d[1], d[2])
    if chosen then M.selected:set(chosen) end
    return true
  end
  if name == "Tab" then
    local chosen = model.step(M.slots:get(), M.selected:get(), (modifiers or ""):find("shift") and -1 or 1, 0)
    if chosen then M.selected:set(chosen) end
    return true
  end
  if name == "Page_Up" then M.scroll(-1) return true end
  if name == "Page_Down" then M.scroll(1) return true end
  if name == "Delete" and M.query:get() == "" then M.close_window() return true end
  if (modifiers or ""):find("ctrl") then
    if name == "w" then M.close_window() return true end
    local digit = tonumber(name or "")
    if digit and digit > 0 then
      local desk = (M.desk_rows or {})[digit]
      if desk then M.view(desk.id) end
      return true
    end
  end
  return false
end

--- Whether a throw of `dy`, at `vy`, sends a card away.
function M.thrown(dy, vy)
  return dy <= -MIN_THROW or (vy or 0) <= -900
end

-- ------------------------------------------------------------------- menu --

M.menu_for = morf.signal("eva.overview.menu_for", "")
-- The windows Clear all passes over.
M.kept = require("themes.session").keep("eva.overview.kept", {})

function M.is_kept(address) return M.kept:get()[address] == true end

function M.toggle_kept(address)
  local all = {}
  for k, v in pairs(M.kept:get()) do all[k] = v end
  all[address] = not all[address] or nil
  M.kept:set(all)
end

--- Closes every window on show, but for those kept.
function M.clear_all()
  for r = 1, M.cards:len() do
    local address = M.cards:get(r).address
    if not M.is_kept(address) then M.close_window(address) end
  end
end

--- What a card offers: `{ label, icon, run }`.
function M.card_actions(address)
  local c = windows.get(address)
  if not c then return {} end
  local modes = require("window_modes")
  local items = {
    { label = "Split with the last app", icon = "splitscreen", run = function()
      M.close()
      modes.split_with(address)
    end },
    { label = c.floating and "Back to the tiles" or "Float", icon = "open_in_new", run = function()
      M.close()
      modes.toggle_float(address)
    end },
    { label = modes.pip:get() == address and "Leave picture in picture" or "Picture in picture",
      icon = "picture_in_picture", run = function()
        M.close()
        modes.toggle_pip(address)
      end },
    { label = M.is_kept(address) and "Let go" or "Keep open", icon = "lock", run = function() M.toggle_kept(address) end },
    { label = "Close", icon = "close", run = function() M.close_window(address) end },
    { label = "Force quit", icon = "dangerous", run = function()
      shots.forget(address)
      windows.kill(address)
    end },
  }
  return items
end

M.scrolled = morf.signal("eva.overview.scrolled", 0)

local view = require("themes").view("overview").build(M)
M.node = view.node
morf.effect("eva.overview.shown", function() view.shown(M.opened:get()) end)

return M
