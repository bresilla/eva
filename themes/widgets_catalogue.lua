-- The widgets a lock may name (models/desktop_widgets.lua). A lock reads no
-- shell state, so only what the time alone can draw is safe.
local morf = require("morf")
local M = {}

local function reading(view, format, size)
  return view.text { id = view.id, font_size = view.s(size), color = view.C.onSurface,
    text = function()
      morf.time.minute_clock:get()
      return morf.time.format(format)
    end }
end

--- Every widget: `{ id, name, lock_safe, build }`.
function M.list()
  return {
    { id = "clock", name = "Clock", lock_safe = true, build = function(view) return reading(view, "%H:%M", 40) end },
    { id = "date", name = "Date", lock_safe = true, build = function(view) return reading(view, "%A, %B %-d", 18) end },
  }
end

return M
