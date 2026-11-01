-- The dock's state and arithmetic: which applications it shows, how an icon
-- swells near the pointer, when it hides. No nodes.
local morf = require("morf")
local config = require("config")
local services = require("services")
local windows = require("windows_model")
local M = {}

-- A field holds 16 layers: the plate, this many icons and the overflow.
M.MAX_ICONS = 14
M.GAIN, M.REACH = .6, 2.2
M.EDGES = { "bottom", "left", "right" }

--- What the dock is here: "dock", "taskbar" along a tablet's edge, "hotseat",
--- the pinned row on a phone's home, or "off": on a phone without a home, and
--- on a desk unless it is asked for.
function M.mode()
  local responsive = require("responsive")
  local form = responsive.form and responsive.form() or "desk"
  local wish = config.get("dock.enabled")
  if wish == "off" then return "off" end
  if form == "phone" then
    local home = config.get("desktop.home.enabled") == true and config.get("desktop.home.dock") == true
    return home and "hotseat" or "off"
  end
  if form == "tablet" then return "taskbar" end
  return wish == "on" and "dock" or "off"
end

function M.on() return M.mode() ~= "off" end
function M.edge()
  local mode = M.mode()
  if mode == "taskbar" or mode == "hotseat" then return "bottom" end
  local v = config.get("dock.edge")
  return (v == "left" or v == "right") and v or "bottom"
end
function M.vertical() return M.edge() ~= "bottom" end
function M.size() return math.max(32, math.min(72, tonumber(config.get("dock.size")) or 48)) end
function M.magnifies() return M.mode() == "dock" and config.get("dock.magnify") ~= false end
--- "off", "on" or "windows": it hides only while a window lies under it.
function M.autohide()
  if M.mode() == "taskbar" then return config.get("dock.taskbar_hide") == true and "on" or "off" end
  if M.mode() == "hotseat" then return "windows" end
  local v = config.get("dock.autohide")
  return (v == "off" or v == "on") and v or "windows"
end

--- How far the dock stands in from its edge, where one is up: for what lays out
--- above it.
function M.depth()
  if not M.on() then return 0 end
  local space = require("themes.spacing")
  local margin = M.mode() == "taskbar" and 0 or space.l
  return M.size() + 2 * space.s + margin + require("theme").BORDER
end

--- The sizes of `count` icons with the pointer `at` along the row, nil for
--- none, each `gap` apart: a size per icon, and the row's length.
function M.sizes(count, base, gap, at, gain, reach)
  local out, total = {}, 0
  for i = 1, count do
    local size = base
    if at then
      local centre = (i - .5) * (base + gap)
      local d = (at - centre) / (reach * base)
      size = base * (1 + gain * math.exp(-d * d))
    end
    out[i] = size
    total = total + size
  end
  return out, total + gap * math.max(0, count - 1)
end

--- Whether two boxes overlap.
function M.overlaps(a, b)
  return a.x < b.x + b.width and b.x < a.x + a.width and a.y < b.y + b.height and b.y < a.y + a.height
end

-- ---------------------------------------------------------------- the rows --

M.rows = morf.list_model({})
M.overflow = morf.signal("eva.dock.overflow", 0)
-- Bouncing while an application it started has no window yet.
M.launching = morf.signal("eva.dock.launching", "")

local function pins()
  local list = config.get("dock.pins")
  return type(list) == "table" and list or {}
end

--- The window's application: the desktop entry's id where there is one.
local function app_of(c)
  local apps = require("apps")
  local entry = apps.entry_for(c.class) or apps.entry_for(c.initial_class)
  return entry and entry.id or c.class, entry
end

local function unread(name, class)
  local n = 0
  local notifs = package.loaded.notifs
  if not notifs then return 0 end
  for _, e in ipairs(notifs.history:get()) do
    local app = tostring(e.app or ""):lower()
    if app ~= "" and (app == (name or ""):lower() or app == (class or ""):lower()) then n = n + 1 end
  end
  return n
end

local function here(c)
  if config.get("dock.isolate") ~= true then return true end
  local m = windows.monitor_of()
  return not m or c.monitor == m.id
end

--- The dock's entries in order: pinned first, then what else is running.
function M.entries()
  local apps = require("apps")
  local running, order = {}, {}
  local focused = (services.hyprland.state.active_window or {}).address
  for _, c in ipairs(windows.recent()) do
    if c.workspace > 0 and here(c) then
      local key = app_of(c)
      if not running[key] then
        running[key] = { windows = {}, class = c.class, initial = c.initial_class }
        order[#order + 1] = key
      end
      table.insert(running[key].windows, c)
    end
  end
  local out, seen = {}, {}
  local function add(key, pinned)
    if seen[key] then return end
    seen[key] = true
    local run = running[key]
    local entry = apps.entry(key) or (run and apps.entry_for(run.class))
    local class = run and run.class or key:gsub("%.desktop$", "")
    local count, active, urgent = 0, false, false
    for _, c in ipairs(run and run.windows or {}) do
      count = count + 1
      if c.address == focused then active = true end
      if c.urgent then urgent = true end
    end
    local name = entry and entry.name or class
    out[#out + 1] = { key = key, name = name, class = class, initial_class = run and run.initial or "",
      icon = entry and entry.icon or "", count = count, active = active, urgent = urgent, pinned = pinned,
      missing = pinned and not entry and not run, unread = unread(name, class) }
  end
  if config.get("dock.buttons") ~= false then
    out[1] = { key = "eva:launcher", name = "Launcher", class = "", initial_class = "", glyph = "apps", icon = "",
      count = 0, active = false, urgent = false, pinned = false, missing = false, unread = 0 }
  end
  for _, key in ipairs(pins()) do add(key, true) end
  local pinned_count = #out
  if M.mode() == "hotseat" then return out, pinned_count end
  for _, key in ipairs(order) do add(key, false) end
  if config.get("dock.buttons") ~= false then
    out[#out + 1] = { key = "eva:overview", name = "Overview", class = "", initial_class = "", glyph = "grid_view", icon = "",
      count = 0, active = false, urgent = false, pinned = false, missing = false, unread = 0 }
  end
  return out, pinned_count
end

--- The windows of the entry `key`, most recent first.
function M.windows_of(key)
  local out = {}
  for _, c in ipairs(windows.recent()) do
    if c.workspace > 0 and here(c) and app_of(c) == key then out[#out + 1] = c end
  end
  return out
end

-- Hiding under windows reads where they are: a moved one tells nothing until
-- the focus moves.
if services.hyprland.on then
  services.hyprland.on("activewindowv2", function()
    if M.on() and M.autohide() == "windows" then windows.refresh() end
  end)
end

morf.effect("eva.dock.rows", function()
  if not M.on() then return end
  local list, pinned = M.entries()
  local rows = {}
  for i = 1, math.min(#list, M.MAX_ICONS) do
    local row = list[i]
    row.index = i
    row.first_running = i == pinned + 1 and pinned > 0
    rows[i] = row
  end
  M.overflow:set(math.max(0, #list - M.MAX_ICONS))
  M.rows:replace(rows, "key")
end)

-- -------------------------------------------------------------- what it does --

--- A press: starts the application, or goes to its window, or to the next.
function M.activate(key)
  if key == "eva:launcher" then
    local launcher = require("launcher").drawer
    return launcher.set(not launcher.open:get())
  end
  if key == "eva:overview" then return require("overview").toggle() end
  local list = M.windows_of(key)
  if #list == 0 then return M.launch(key) end
  local focused = (services.hyprland.state.active_window or {}).address
  if list[1].address == focused and #list > 1 then return windows.focus(list[#list].address) end
  return windows.focus(list[1].address)
end

--- Starts another of the application.
function M.launch(key)
  require("apps").launch(key)
  M.launching:set(key)
  morf.time.timer(6000, function() if M.launching:get() == key then M.launching:set("") end end, false)
  return true
end

-- A window turning up ends the bounce.
morf.effect("eva.dock.launched", function()
  local key = M.launching:get()
  if key ~= "" and #M.windows_of(key) > 0 then M.launching:set("") end
end)

--- The wheel on an icon: the next or previous window.
function M.cycle(key, step)
  local list = M.windows_of(key)
  if #list < 2 then return false end
  return windows.focus(list[step > 0 and #list or 2].address)
end

--- A middle press: closes the application's latest window.
function M.close(key)
  local list = M.windows_of(key)
  if list[1] then return windows.close(list[1].address) end
  return false
end

function M.close_all(key)
  for _, c in ipairs(M.windows_of(key)) do windows.close(c.address) end
end

function M.pinned(key)
  for _, k in ipairs(pins()) do if k == key then return true end end
  return false
end

--- Pins an application, or lets it go.
function M.toggle_pin(key)
  local out, had = {}, false
  for _, k in ipairs(pins()) do
    if k == key then had = true else out[#out + 1] = k end
  end
  if not had then out[#out + 1] = key end
  config.set("dock.pins", out)
  return not had
end

--- Where the pin `key` stands among the pins, or nil.
function M.pin_index(key)
  for i, k in ipairs(pins()) do if k == key then return i end end
end

--- The pin a place along the row falls on: the row starts with the launcher.
function M.pin_at(row_index)
  return row_index - (config.get("dock.buttons") ~= false and 1 or 0)
end

--- Moves the pin at `from` to `to`.
function M.reorder(from, to)
  local list = {}
  for i, k in ipairs(pins()) do list[i] = k end
  if not list[from] or to < 1 or to > #list or from == to then return false end
  table.insert(list, to, table.remove(list, from))
  config.set("dock.pins", list)
  return true
end

--- What the right button offers: `{ label, run }`.
function M.menu(key)
  if key:sub(1, 4) == "eva:" then return {} end
  local items, list = {}, M.windows_of(key)
  local entry = require("apps").entry(key)
  items[#items + 1] = { label = "New window", icon = "add", run = function() M.launch(key) end }
  for _, action in ipairs(entry and entry.actions or {}) do
    items[#items + 1] = { label = action.name, icon = "bolt",
      run = function() require("apps").launch_action(key, action.id) end }
  end
  for _, c in ipairs(list) do
    items[#items + 1] = { label = c.title ~= "" and c.title or c.class, icon = "select_window",
      run = function() windows.focus(c.address) end }
  end
  items[#items + 1] = { label = M.pinned(key) and "Unpin" or "Pin", icon = "push_pin", run = function() M.toggle_pin(key) end }
  if #list > 0 then
    items[#items + 1] = { label = #list > 1 and "Close all" or "Close", icon = "close", run = function() M.close_all(key) end }
  end
  return items
end

return M
