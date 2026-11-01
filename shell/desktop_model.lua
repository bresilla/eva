-- The widgets on the desktop: which are shown, how big, and where. The board is
-- the quick settings' (tiles_model.lua): the same add, hide, resize and reorder,
-- kept per form factor. A desk or a tablet also places each one freely, snapped
-- to the spacing grid; a phone's flow down the home screen in the board's order.
--
-- A phone's and a tablet's home is this board with pages: each page a zone of it,
-- holding widgets and, as `app:ID` and `folder:NAME`, apps and the launcher's
-- folders. The first page is `desktop.widgets.<form>`, the rest `desktop.pages`.
-- A desk has the one page, of widgets.
local morf = require("morf")
local config = require("config")
local grid = require("tile_grid")
local M = {}

-- `w` and `h` are a widget's size, large and small.
M.CATALOGUE = {
  { id = "clock", name = "Clock", icon = "schedule", w = 360, h = 176, small_w = 176, small_h = 176 },
  { id = "date", name = "Date", icon = "today", w = 360, h = 84, small_w = 176, small_h = 84 },
  { id = "weather", name = "Weather", icon = "partly_cloudy_day", w = 360, h = 176, small_w = 176, small_h = 176 },
  { id = "system", name = "System", icon = "monitoring", w = 360, h = 176, small_w = 176, small_h = 176 },
  { id = "media", name = "Media", icon = "music_note", w = 360, h = 176, small_w = 176, small_h = 176 },
  { id = "visualiser", name = "Audio visualiser", icon = "graphic_eq", w = 360, h = 176, small_w = 176, small_h = 176 },
  { id = "calendar", name = "Calendar", icon = "calendar_month", w = 360, h = 348, small_w = 176, small_h = 176 },
  { id = "quote", name = "Quote", icon = "format_quote", w = 360, h = 128, small_w = 176, small_h = 176 },
  { id = "command", name = "Custom command", icon = "terminal", w = 360, h = 176, small_w = 176, small_h = 84 },
  { id = "note", name = "Note", icon = "sticky_note_2", w = 360, h = 176, small_w = 176, small_h = 176 },
  { id = "countdown", name = "Countdown", icon = "hourglass_bottom", w = 360, h = 84, small_w = 176, small_h = 84 },
  { id = "photo", name = "Photo", icon = "image", w = 360, h = 240, small_w = 176, small_h = 176 },
  { id = "orb", name = "Liquid orb", icon = "bubble_chart", w = 176, h = 176, small_w = 176, small_h = 176 },
}
M.BY_ID = {}
for _, widget in ipairs(M.CATALOGUE) do M.BY_ID[widget.id] = widget end

M.GAP = 16
M.MARGIN = 32
M.SNAP = 8
M.PHONE_COLUMNS = 1
-- A home's pages at most, how tall an icon stands with its name, and the band
-- that holds the page dots.
M.MAX_PAGES = 9
M.ICON_H = 104
M.DOTS = 24

local function form() return require("responsive").form() end

--- Whether this machine's desktop is a home of pages.
function M.home() return form() ~= "desk" and config.get("desktop.home.enabled") == true end

--- Whether `id` is an app or a folder rather than a widget.
function M.is_icon(id) return id:find(":", 1, true) ~= nil end

local function further()
  local list = config.get("desktop.pages." .. form())
  return type(list) == "table" and list or {}
end

--- How many pages there are.
function M.page_count() return M.home() and 1 + #further() or 1 end

-- The page on show.
M.page = require("themes.session").keep("eva.desktop.page", 1)

--- The page on show, within those there are.
function M.current() return math.max(1, math.min(M.page:get(), M.page_count())) end

-- The board's lists: its first zone is the settings' own list, the others pages.
local function page_store()
  local function widgets() return "desktop.widgets." .. form() end
  local function small() return "desktop.small." .. form() end
  return {
    order = function(zone)
      local page = tonumber(zone) or 1
      if page == 1 then return config.get(widgets()) end
      return further()[page - 1] or {}
    end,
    set_order = function(zone, list)
      local page = tonumber(zone) or 1
      if page == 1 then config.set(widgets(), list) return end
      local out = {}
      for i, items in ipairs(further()) do out[i] = items end
      out[page - 1] = list
      config.set("desktop.pages." .. form(), out)
    end,
    small = function() return config.get(small()) end,
    set_small = function(list) config.set(small(), list) end,
    reset = function()
      config.reset(widgets())
      config.reset(small())
      config.reset("desktop.pages." .. form())
    end,
  }
end

-- What an icon on a page stands for: gone from the page as it goes from the
-- machine, and from a desk altogether.
local function icon_tile(id)
  local kind, rest = id:match("^(%a+):(.*)$")
  if kind ~= "app" and kind ~= "folder" then return nil end
  return { id = id, present = function()
    if not M.home() then return false end
    local apps = require("apps")
    if kind == "app" then return apps.row(rest) ~= nil end
    return apps.folder(rest) ~= nil
  end }
end

local ZONES = {}
for page = 1, M.MAX_PAGES do ZONES[page] = tostring(page) end

M.board = require("tiles_model").new(M.CATALOGUE, form, { store = page_store(), zones = ZONES, name = "eva.desktop",
  extra = icon_tile, zone = function() return tostring(M.current()) end })
M.CHROMES = { { "glass", "Glass" }, { "solid", "Solid" }, { "none", "Bare" }, { "stencil", "Cut" } }

function M.editing() return M.board.editing:get() end
function M.set_editing(on)
  M.board.editing:set(on == true)
  if on ~= true then M.tidy() end
end
--- Whether a person places widgets by hand here; a phone's flow instead.
function M.free() return form() ~= "phone" end
--- Whether the desktop has anything to draw.
function M.wanted() return M.home() or #M.everything() > 0 or M.editing() end

--- Everything on the pages, each `{ id, small, page }`.
function M.everything()
  local out = {}
  for page = 1, M.page_count() do
    for _, item in ipairs(M.board.shown(tostring(page))) do
      out[#out + 1] = { id = item.id, small = item.small, page = page }
    end
  end
  return out
end

--- A new page at the end. Its number, or nil past the most there can be.
function M.add_page()
  if not M.home() or M.page_count() >= M.MAX_PAGES then return nil end
  local out = {}
  for i, items in ipairs(further()) do out[i] = items end
  out[#out + 1] = {}
  config.set("desktop.pages." .. form(), out)
  return M.page_count()
end

--- Page `page` gone, if nothing stands on it and it is not the first. Whether it went.
function M.drop_page(page)
  if page <= 1 or page > M.page_count() or #M.board.shown(tostring(page)) > 0 then return false end
  local out = {}
  for i, items in ipairs(further()) do
    if i ~= page - 1 then out[#out + 1] = items end
  end
  config.set("desktop.pages." .. form(), out)
  if M.page:get() > M.page_count() then M.page:set(M.page_count()) end
  return true
end

--- Empty pages gone.
function M.tidy()
  if not M.home() then return end
  for page = M.page_count(), 2, -1 do M.drop_page(page) end
end

local function screen()
  morf.window.screens_revision()
  local s = (morf.screens or {})[1] or {}
  return s.width or 1280, s.height or 800
end

-- What fits across a phone: the width inside the gaps, how many icons stand
-- across it, and each one's cell.
local function across()
  local sw = screen()
  local inner = math.max(1, sw - 2 * M.GAP)
  local columns, cell = grid.icons(inner, config.get("desktop.home.columns"))
  return inner, columns, cell
end

--- The size `id` stands at.
function M.size(id, small)
  if M.is_icon(id) then
    local _, _, cell = across()
    return cell, M.ICON_H
  end
  local widget = M.BY_ID[id]
  if small == nil then small = M.board.small(id) end
  if small then return widget.small_w, widget.small_h end
  return widget.w, widget.h
end

--- What the pages leave free at the screen's foot: the dock and the dots.
function M.foot() return require("dock_model").depth() + M.DOTS + M.GAP end

local function place_key() return "desktop.place." .. form() end

--- The saved place of `id`, in fractions of the screen, or nil.
function M.saved(id)
  for _, item in ipairs(config.get(place_key())) do
    if item.id == id then return item end
  end
end

--- Snaps a position to the grid, keeping the widget on the screen.
function M.snap(x, y, w, h)
  local sw, sh = screen()
  local function step(value, room)
    local snapped = math.floor(value / M.SNAP + 0.5) * M.SNAP
    return math.max(M.SNAP, math.min(snapped, math.max(M.SNAP, room - M.SNAP)))
  end
  return step(x, sw - w), step(y, sh - h)
end

--- Saves where `id` now stands, from its left and top in pixels.
function M.move_to(id, x, y)
  local w, h = M.size(id)
  local sw, sh = screen()
  x, y = M.snap(x, y, w, h)
  local out = {}
  for _, item in ipairs(config.get(place_key())) do
    if item.id ~= id then out[#out + 1] = item end
  end
  out[#out + 1] = { id = id, x = x / sw, y = y / sh }
  config.set(place_key(), out)
  return x, y
end

--- Whether `id` keeps to the picture's quiet part rather than a place.
function M.roams(id) return id == "clock" and config.get("desktop.quiet_clock") == true and M.free() and not M.editing() end

-- Where the widgets without a place of their own fall: a column down the
-- screen's right side, the next column left when one is full. Icons without a
-- place fill from the top left, a row at a time, over the screen's left half.
local function flowed(shown)
  local sw, sh = screen()
  local top = M.home() and M.MARGIN * 2 or M.MARGIN
  local out, x, y, widest = {}, nil, top, 0
  x = sw - M.MARGIN
  local cell = grid.ICON_MAX
  local row_of = math.max(1, (sw // 2 - M.MARGIN) // cell)
  local icons = 0
  for _, item in ipairs(shown) do
    if M.is_icon(item.id) then
      if not M.saved(item.id) then
        out[item.id] = { x = M.MARGIN + (icons % row_of) * cell, y = M.MARGIN * 2 + (icons // row_of) * M.ICON_H,
          width = cell, height = M.ICON_H }
        icons = icons + 1
      end
    elseif not M.saved(item.id) and not M.roams(item.id) then
      local w, h = M.size(item.id, item.small)
      if y + h > sh - M.MARGIN and y > top then
        x, y, widest = x - widest - M.GAP, top, 0
      end
      widest = math.max(widest, w)
      out[item.id] = { x = x - w, y = y }
      y = y + h + M.GAP
    end
  end
  return out
end

-- A phone's page, down the screen in the board's order: two small widgets to a
-- row, a large one to itself, icons side by side in their cells.
local function phone_flow(shown)
  local inner, _, cell = across()
  local half = (inner - M.GAP) / 2
  local out, y, x, tallest = {}, M.MARGIN * 3, 0, 0
  for _, item in ipairs(shown) do
    local icon = M.is_icon(item.id)
    local _, h = M.size(item.id, item.small)
    local w = icon and cell or item.small and half or inner
    if x + w > inner + 1 then x, y, tallest = 0, y + tallest + (icon and 0 or M.GAP), 0 end
    out[item.id] = { x = M.GAP + x, y = y, width = w, height = h }
    x, tallest = x + w + (icon and 0 or M.GAP), math.max(tallest, h)
  end
  return out
end

-- Where the widgets and icons of `shown` stand on a page a person places by hand.
local function placed(shown)
  local sw, sh = screen()
  local out = flowed(shown)
  for _, item in ipairs(shown) do
    local place = M.saved(item.id)
    local w, h = M.size(item.id, item.small)
    if not M.is_icon(item.id) and M.roams(item.id) then
      local x, y = M.quiet_place(w, h)
      out[item.id] = { x = x or M.MARGIN, y = y or M.MARGIN }
    elseif place then
      local x, y = M.snap(place.x * sw, place.y * sh, w, h)
      out[item.id] = { x = x, y = y, width = M.is_icon(item.id) and w or nil, height = M.is_icon(item.id) and h or nil }
    end
  end
  return out
end

--- Where everything shown stands: `{ id = { x, y, width, height, page } }` in
--- pixels, each within its page.
function M.layout()
  local out = {}
  for page = 1, M.page_count() do
    local shown = M.board.shown(tostring(page))
    for id, spot in pairs(M.free() and placed(shown) or phone_flow(shown)) do
      spot.page = page
      out[id] = spot
    end
  end
  return out
end

--- On a phone, where carrying `id` to (x, y) puts it among the others on its page.
function M.reorder(id, x, y)
  local zone = M.board.zone_of(id)
  if not zone then return end
  local shown = M.board.shown(zone)
  local best, distance
  for index = 1, #shown do
    local spot = phone_flow(grid.moved(shown, id, index))[id]
    local d = (spot.x - x) ^ 2 + (spot.y - y) ^ 2
    if not distance or d < distance then best, distance = index, d end
  end
  if best and shown[best].id ~= id then M.board.move(id, best) end
end

--- Whether `id` would fit at the foot of page `page`.
function M.fits(page, id)
  local items = M.board.shown(tostring(page))
  items[#items + 1] = { id = id, small = M.board.small(id) }
  local _, sh = screen()
  local spot = (M.free() and placed(items) or phone_flow(items))[id]
  if not spot then return true end
  local _, h = M.size(id)
  return spot.y + (spot.height or h) <= sh - M.foot()
end

--- Puts `id` on the first page from this one with room, on a new one when none
--- has. Whether it was placed.
function M.place(id)
  if M.board.zone_of(id) then return false end
  for page = M.current(), M.page_count() do
    if M.fits(page, id) then
      M.page:set(page)
      return M.board.add(id, tostring(page))
    end
  end
  local page = M.add_page()
  if not page then return false end
  M.page:set(page)
  return M.board.add(id, tostring(page))
end

--- Moves `id` to page `page`, at its end.
function M.to_page(id, page)
  if page < 1 or page > M.page_count() then return false end
  return M.board.move(id, #M.board.shown(tostring(page)) + 1, tostring(page))
end

--- The quietest place for a box of this size, in pixels, or nil before the
--- picture has been read.
function M.quiet_place(w, h)
  local quiet = require("wallpaper_quiet")
  local reading = quiet.reading:get()
  if not reading then return nil end
  local sw, sh = screen()
  local x, y = quiet.quietest(reading, w / sw, h / sh)
  return x * sw, y * sh
end

-- ------------------------------------------------------------------ icons --

--- The name a home knows the app `id` by.
function M.app_item(id) return "app:" .. id end

--- Whether the app `id` stands on a page.
function M.has_app(id) return M.board.zone_of(M.app_item(id)) ~= nil end

--- Puts the app `id` on the home, or takes it off. Whether it is there now.
function M.toggle_app(id)
  local item = M.app_item(id)
  if M.has_app(id) then M.board.hide(item) return false end
  return M.place(item)
end

--- The icon `old` under the name `new`, where it stands.
function M.rename_item(old, new)
  local zone = M.board.zone_of(old)
  if not zone then return end
  local store, list = page_store(), {}
  for index, id in ipairs(store.order(zone)) do list[index] = id == old and new or id end
  store.set_order(zone, list)
end

--- What the icon `id` stands for, as a tile the launcher's grid would draw:
--- `{ id, key, kind, name, icon, material, members }`, or nil once it is gone.
function M.icon_row(id)
  local kind, rest = id:match("^(%a+):(.*)$")
  local apps = require("apps")
  local row = kind == "app" and apps.row(rest) or kind == "folder" and apps.folder(rest) or nil
  if not row then return nil end
  return { id = id, kind = row.kind, name = row.name, icon = row.icon, material = row.material, members = row.members }
end

--- What a press on the icon `id` does: an app starts, a folder opens in the grid.
function M.open(id)
  local kind, rest = id:match("^(%a+):(.*)$")
  local launcher = require("launcher")
  if kind == "app" then
    local row = require("apps").row(rest)
    if row then launcher.activate(row) end
  elseif kind == "folder" then
    launcher.show_folder(rest)
  end
end

--- What a hold on the icon `id` offers: `{ label, icon, run }`.
function M.menu(id)
  local kind, rest = id:match("^(%a+):(.*)$")
  local apps, launcher = require("apps"), require("launcher")
  local items = {}
  local row = kind == "app" and apps.row(rest) or nil
  if row then
    items[#items + 1] = { label = "Open", icon = "open_in_new", run = function() M.open(id) end }
    for _, action in ipairs(row.desktop_actions or {}) do
      items[#items + 1] = { label = action.name, icon = "bolt", run = function() apps.run_action(row, action.id) end }
    end
    local dock = require("dock_model")
    items[#items + 1] = { label = dock.pinned(rest) and "Take off the dock" or "Keep on the dock", icon = "push_pin",
      run = function() dock.toggle_pin(rest) end }
  elseif kind == "folder" then
    items[#items + 1] = { label = "Open", icon = "folder_open", run = function() M.open(id) end }
  end
  items[#items + 1] = { label = "Take off the home screen", icon = "remove", run = function() M.board.hide(id) end }
  items[#items + 1] = { label = "Arrange", icon = "dashboard_customize", run = function() M.set_editing(true) end }
  if row then
    items[#items + 1] = { label = "More…", icon = "more_horiz", run = function() launcher.act_on_row(row) end }
  end
  return items
end

--- Whether ink over this box should be dark.
function M.dark_ink(x, y, w, h)
  local quiet = require("wallpaper_quiet")
  local reading = quiet.reading:get()
  if not reading or config.get("desktop.chrome") == "solid" then return nil end
  local sw, sh = screen()
  return quiet.dark_ink(quiet.brightness(reading, x / sw, y / sh, w / sw, h / sh))
end

-- -------------------------------------------------------------- the data --

--- The minutes and hours as a clock draws them.
function M.clock_text(time)
  local twelve = config.get("bar.clock.twelve_hour")
  return morf.time.format(twelve and "%I:%M" or "%H:%M", time)
end

M.QUOTES = {
  "The quieter you become, the more you can hear.",
  "Make it work, make it right, make it fast.",
  "Simplicity is the ultimate sophistication.",
  "What I cannot create, I do not understand.",
  "The best way to predict the future is to invent it.",
  "Well begun is half done.",
  "Slow is smooth, and smooth is fast.",
}

--- The day's quote, from `desktop.quotes` where that file is readable.
function M.quote(day)
  local file = config.get("desktop.quotes")
  local lines = {}
  if file ~= "" then
    local ok, text = pcall(morf.fs.read, (file:gsub("^~/", morf.fs.home() .. "/")))
    if ok and type(text) == "string" then
      for line in text:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    end
  end
  if #lines == 0 then lines = M.QUOTES end
  return lines[(day or tonumber(morf.time.format("%j")) or 1) % #lines + 1]
end

--- Days until `date` from `today` (both "YYYY-MM-DD"; today by default), or nil
--- for a date it cannot read.
function M.days_until(date, today)
  local function days(text)
    local y, m, d = tostring(text):match("^(%d+)-(%d+)-(%d+)$")
    if not y then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    -- Days from a fixed epoch in the proleptic Gregorian calendar.
    local a = (14 - m) // 12
    local yy, mm = y + 4800 - a, m + 12 * a - 3
    return d + (153 * mm + 2) // 5 + 365 * yy + yy // 4 - yy // 100 + yy // 400
  end
  local there, here = days(date), days(today or morf.time.format("%Y-%m-%d"))
  if not there or not here then return nil end
  return there - here
end

--- What the custom command said: a signal, kept current while it is on show.
M.command_output = morf.signal("eva.desktop.command", "")

local timer
--- Runs the custom command while `shown()` holds.
function M.watch_command(shown)
  morf.effect("eva.desktop.command.run", function()
    local on, run, every = shown(), config.get("desktop.command.run"), config.get("desktop.command.interval")
    if timer then timer:cancel() timer = nil end
    if not on or run == "" then M.command_output:set("") return end
    local dry = morf.env("EVA_DRY_RUN")
    if dry and dry ~= "" and dry ~= "0" then M.command_output:set("Commands are held in this preview") return end
    local function tick()
      morf.process.run({ "sh", "-c", run }, { timeout_ms = 15000, max_output = 8192 }, function(result)
        local text = result.ok and result.stdout or (result.stderr or result.error or "")
        M.command_output:set((tostring(text):gsub("%s+$", "")))
      end)
    end
    tick()
    timer = morf.time.timer(math.max(5, every) * 1000, tick, true)
  end)
end

return M
