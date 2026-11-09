-- A way to choose a file where a finger has nothing to drag: a button, and the
-- kit's file chooser opening under it, built the first time it is asked for.
--
--     local button, box = M.make { id = "drop", width = w, on_path = send }
local morf = require("morf")
local ui = require("morf.ui")
local P = require("themes.layouts.page")
local M = {}

local HEIGHT = 360

--- `id`, `width` (a number or fn), `on_path(path)`. The button goes in a row,
--- the box under it.
function M.make(spec)
  local open = morf.signal("eva.file_pick." .. spec.id .. "." .. tostring({}), false)
  local chooser
  local holder = ui.Item { width = spec.width, height = HEIGHT }
  local box = P.fold { width = spec.width, shown = function() return open:get() end, holder }
  morf.effect("file_pick." .. spec.id, function()
    if not open:get() or chooser then return end
    chooser = require("themes.kit.composites").file_chooser { id = spec.id .. "-chooser", width = spec.width,
      height = HEIGHT, mode = "open", path = "~",
      on_accepted = function(path)
        open:set(false)
        spec.on_path(path)
      end,
      on_cancelled = function() open:set(false) end }
    ui.reparent(chooser, holder)
  end, { owner = holder })
  local button = P.button { id = spec.id .. "-choose", label = "Choose", icon = "folder_open",
    on_clicked = function() open:set(not open:get()) end }
  return button, box
end

return M
