-- The desktop's widgets as the lock may name them (models/desktop_widgets.lua).
-- A lock reads no shell state, so only what the time alone can draw is safe; the
-- rest are listed as not safe, so a setting that names one draws nothing.
local morf = require("morf")
local M = {}

local function reading(view, format, size)
  return view.text { id = view.id, font_size = view.s(size), color = view.C.onSurface,
    text = function()
      morf.time.minute_clock:get()
      return morf.time.format(format)
    end }
end

local function unsafe(id, name) return { id = id, name = name, lock_safe = false } end

--- Every widget: `{ id, name, lock_safe, build }`.
function M.list()
  return {
    { id = "clock", name = "Clock", lock_safe = true, build = function(view) return reading(view, "%H:%M", 40) end },
    { id = "date", name = "Date", lock_safe = true, build = function(view) return reading(view, "%A, %B %-d", 18) end },
    unsafe("weather", "Weather"), unsafe("system", "System"), unsafe("media", "Media"), unsafe("visualiser", "Visualiser"),
    unsafe("quote", "Quote"), unsafe("command", "Custom command"), unsafe("note", "Note"), unsafe("countdown", "Countdown"),
    unsafe("photo", "Photo"), unsafe("orb", "Orb"),
  }
end

return M
