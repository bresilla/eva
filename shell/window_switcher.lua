-- The window switcher: Alt+Tab. The compositor's key calls `switcher next`;
-- letting Alt go goes to what is chosen. A quick tap goes to the last window
-- without drawing anything; held, the windows show by application, most
-- recent first, and Alt with the backtick walks one application's windows.
local morf = require("morf")
local config = require("config")
local services = require("services")
local windows = require("windows_model")
local shots = require("window_shots")
local model = require("overview_model")
local M = {}

-- Drawn once a press has been held this long.
local SHOW_AFTER = 140

M.opened = morf.signal("eva.switcher.opened", false)
M.shown = morf.signal("eva.switcher.shown", false)
M.index = morf.signal("eva.switcher.index", 1)
M.rows = morf.list_model({})
M.slots = morf.signal("eva.switcher.slots", {})
M.plate = morf.signal("eva.switcher.plate", { x = 0, y = 0, width = 0, height = 0 })

local entries = {}
local held, waiting = false, nil
-- When Alt last came up with nothing open: the key's call may reach the shell
-- after the release's.
local released_at, RACE = -1e9, 200

--- Which windows it walks: "all", "workspace" or "output".
function M.scope()
  local v = config.get("windows.switcher.scope")
  return (v == "workspace" or v == "output") and v or "all"
end
function M.grouping() return config.get("windows.switcher.group") ~= false end

local function candidates()
  local scope, out = M.scope(), {}
  local here = windows.int(services.workspace.active())
  local monitor = windows.monitor_of()
  for _, c in ipairs(windows.list()) do
    local keep = c.workspace > 0
    if scope == "workspace" then keep = keep and c.workspace == here
    elseif scope == "output" then keep = keep and (not monitor or c.monitor == monitor.id) end
    if keep then out[#out + 1] = c end
  end
  return out
end

local function group_rows(list)
  local out = {}
  if M.grouping() then
    for _, g in ipairs(windows.grouped(list)) do
      out[#out + 1] = { window = g.windows[1], members = g.windows }
    end
  else
    for _, c in ipairs(windows.recent(list)) do out[#out + 1] = { window = c, members = { c } } end
  end
  return out
end

local function layout()
  local s = (morf.screens or {})[1] or {}
  local w, h = s.width or 1920, s.height or 1080
  local S = require("theme").space
  local sizes = {}
  for i, e in ipairs(entries) do
    local r = windows.rect(e.window)
    local scale = 180 / math.max(1, r.height)
    sizes[i] = { width = math.max(140, math.min(320, r.width * scale)), height = 180 }
  end
  local boxes = model.arrange(sizes, { x = 0, y = 0, width = w * .8, height = h * .6 }, S.l)
  local left, top, right, bottom = math.huge, math.huge, -math.huge, -math.huge
  for _, b in ipairs(boxes) do
    left, top = math.min(left, b.x), math.min(top, b.y)
    right, bottom = math.max(right, b.x + b.width), math.max(bottom, b.y + b.height)
  end
  if #boxes == 0 then return end
  local pad = S.xl
  local pw, ph = right - left + 2 * pad, bottom - top + 2 * pad
  local px, py = (w - pw) / 2, (h - ph) / 2
  local slots = {}
  for i, e in ipairs(entries) do
    local b = boxes[i]
    slots[e.window.address] = { x = b.x - left + pad, y = b.y - top + pad, width = b.width, height = b.height }
  end
  M.slots:set(slots)
  M.plate:set { x = px, y = py, width = pw, height = ph }
end

local function publish()
  local rows = {}
  for i, e in ipairs(entries) do
    local c = e.window
    rows[i] = { address = c.address, class = c.class, title = c.title, initial_class = c.initial_class,
      count = #e.members, index = i }
  end
  layout()
  M.rows:replace(rows, "address")
end

--- The window chosen now, or nil.
function M.chosen()
  local e = entries[M.index:get()]
  return e and e.window or nil
end

local function cancel_wait()
  if waiting then waiting:cancel() waiting = nil end
end

local function begin(list, start)
  entries = group_rows(list)
  if #entries == 0 then return false end
  M.index:set(math.min(start, #entries))
  publish()
  M.opened:set(true)
  cancel_wait()
  local visible = {}
  for _, e in ipairs(entries) do visible[#visible + 1] = e.window end
  shots.refresh(visible)
  waiting = morf.time.timer(SHOW_AFTER, function()
    waiting = nil
    if M.opened:get() then M.shown:set(true) end
  end, false)
  return true
end

local function move(delta)
  if #entries == 0 then return end
  M.index:set((M.index:get() - 1 + delta) % #entries + 1)
end

--- A press of Tab: opens on the last window, then walks. `hold` says Alt is
--- down and will come up; off, it stays until something is chosen.
function M.step(delta, hold)
  held = hold ~= false
  if M.opened:get() then move(delta) return true end
  local started = begin(candidates(), delta > 0 and 2 or math.huge)
  if started and held and morf.time.now_ms() - released_at < RACE then return M.commit() end
  return started
end

--- Walks the windows of the application on show.
function M.same(hold)
  held = hold ~= false
  if M.opened:get() then move(1) return true end
  local active = windows.active()
  if not active then return false end
  local list = {}
  for _, c in ipairs(candidates()) do if c.class == active.class then list[#list + 1] = c end end
  local keep = M.grouping
  M.grouping = function() return false end
  local started = begin(list, 2)
  M.grouping = keep
  return started
end

--- Puts it away without going anywhere.
function M.cancel()
  cancel_wait()
  M.opened:set(false)
  M.shown:set(false)
  held = false
end

--- Goes to what is chosen.
function M.commit()
  if not M.opened:get() then
    released_at = morf.time.now_ms()
    return false
  end
  local c = M.chosen()
  M.cancel()
  if c then windows.focus(c.address) end
  return c ~= nil
end

--- Chooses the entry `i`, and goes there when `go`.
function M.pick(i, go)
  M.index:set(i)
  if go then M.commit() end
end

--- Closes the chosen window, and walks on.
function M.close_chosen()
  local c = M.chosen()
  if not c then return end
  windows.close(c.address)
  table.remove(entries, M.index:get())
  if #entries == 0 then M.cancel() return end
  M.index:set(math.min(M.index:get(), #entries))
  publish()
end

function M.wheel(step) move(step > 0 and 1 or -1) end

local KEYS = { Tab = true, ISO_Left_Tab = true, Right = true, Left = true, Up = true, Down = true }
function M.key(_, _, modifiers, _, name)
  local shift = (modifiers or ""):find("shift") ~= nil
  if name == "Escape" then M.cancel() return true end
  if name == "Return" or name == "KP_Enter" or name == "space" then M.commit() return true end
  if KEYS[name] then
    local back = name == "Left" or name == "Up" or name == "ISO_Left_Tab" or shift
    move(back and -1 or 1)
    return true
  end
  if name == "grave" then move(1) return true end
  if name == "w" or name == "q" or name == "Delete" then M.close_chosen() return true end
  return true
end

--- A key coming up: Alt, while it was held, is the choice.
function M.released(_, _, _, _, name)
  if held and (name == "Alt_L" or name == "Alt_R" or name == "Super_L" or name == "Super_R") then M.commit() end
  return true
end

local view = require("themes").view("window_switcher").build(M)
M.node = view.node
morf.effect("eva.switcher.keys", function() view.shown(M.opened:get()) end)

return M
