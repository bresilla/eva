-- The widgets on the desktop: which are shown, how big, and where. The board is
-- the quick settings' (tiles_model.lua): the same add, hide, resize and reorder,
-- kept per form factor. A desk or a tablet also places each one freely, snapped
-- to the spacing grid; a phone's flow down the home screen in the board's order.
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

local function form() return require("responsive").form() end

M.board = require("tiles_model").new(M.CATALOGUE, form, { order = "desktop.widgets.", small = "desktop.small.", name = "eva.desktop" })
M.CHROMES = { { "glass", "Glass" }, { "solid", "Solid" }, { "none", "Bare" }, { "stencil", "Cut" } }

function M.editing() return M.board.editing:get() end
function M.set_editing(on) M.board.editing:set(on == true) end
--- Whether a person places widgets by hand here; a phone's flow instead.
function M.free() return form() ~= "phone" end
--- Whether the desktop has anything to draw.
function M.wanted() return #M.board.shown() > 0 or M.editing() end

--- The size `id` stands at.
function M.size(id, small)
  local widget = M.BY_ID[id]
  if small == nil then small = M.board.small(id) end
  if small then return widget.small_w, widget.small_h end
  return widget.w, widget.h
end

local function screen()
  morf.window.screens_revision()
  local s = (morf.screens or {})[1] or {}
  return s.width or 1280, s.height or 800
end

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
-- screen's right side, the next column left when one is full.
local function flowed(shown)
  local sw, sh = screen()
  local out, x, y, widest = {}, nil, M.MARGIN, 0
  x = sw - M.MARGIN
  for _, item in ipairs(shown) do
    if not M.saved(item.id) and not M.roams(item.id) then
      local w, h = M.size(item.id, item.small)
      if y + h > sh - M.MARGIN and y > M.MARGIN then
        x, y, widest = x - widest - M.GAP, M.MARGIN, 0
      end
      widest = math.max(widest, w)
      out[item.id] = { x = x - w, y = y }
      y = y + h + M.GAP
    end
  end
  return out
end

-- A phone's widgets, down the screen in the board's order, two small to a row.
local function phone_flow(shown)
  local sw = screen()
  local inner = math.max(1, sw - 2 * M.GAP)
  local half = (inner - M.GAP) / 2
  local items = {}
  for _, item in ipairs(shown) do items[#items + 1] = { id = item.id, small = item.small } end
  local out, y, x, tallest = {}, M.MARGIN * 3, 0, 0
  for _, item in ipairs(items) do
    local _, h = M.size(item.id, item.small)
    local w = item.small and half or inner
    if x + w > inner + 1 then x, y, tallest = 0, y + tallest + M.GAP, 0 end
    out[item.id] = { x = M.GAP + x, y = y, width = w }
    x, tallest = x + w + M.GAP, math.max(tallest, h)
  end
  return out
end

--- Where every shown widget stands: `{ id = { x, y, width } }` in pixels.
function M.layout()
  local shown = M.board.shown()
  if not M.free() then return phone_flow(shown) end
  local sw, sh = screen()
  local out = flowed(shown)
  for _, item in ipairs(shown) do
    local place = M.saved(item.id)
    local w, h = M.size(item.id, item.small)
    if M.roams(item.id) then
      local x, y = M.quiet_place(w, h)
      out[item.id] = { x = x or M.MARGIN, y = y or M.MARGIN }
    elseif place then
      local x, y = M.snap(place.x * sw, place.y * sh, w, h)
      out[item.id] = { x = x, y = y }
    end
  end
  return out
end

--- On a phone, where carrying `id` to (x, y) puts it among the others.
function M.reorder(id, x, y)
  local shown = M.board.shown()
  local sw = screen()
  local inner = sw - 2 * M.GAP
  local metrics = { half = (inner - M.GAP) / 2, gap = M.GAP, height = 176 }
  local index = grid.nearest(shown, id, x, y, 1, metrics)
  if index and (shown[index] or {}).id ~= id then M.board.move(id, index) end
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
