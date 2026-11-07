-- eva-ruler's page in the Tools window: what it measures, and a control that
-- starts it. The ruler itself is eva-ruler's own program, over a frozen picture
-- of the whole screen.
local morf = require("morf")
local overlay = require("apps.common.overlay_page")

local M = {}

-- What it measures first, as `eva-ruler MODE` takes it.
local mode = morf.signal("eva.tools.ruler.mode", "spacing")

local function start() overlay.start("ruler", { mode:get() }) end

--- The page, `w` by `h`.
function M.build(w, h)
  return overlay.build({ id = "ruler",
    text = "Measures what is on the screen in pixels, and in millimetres and inches where the screen says its "
      .. "size. Edges are found by walking the pixels from the pointer; a click copies the measure.",
    choices = { { id = "ruler-mode", title = "It measures", value = mode, per_row = 2, items = {
      { "spacing", "straighten", "Both ways" }, { "horizontal", "width", "Across" },
      { "vertical", "height", "Down" }, { "bounds", "crop_free", "A dragged box" } } } },
    starts = { { id = "ruler-start", icon = "straighten", label = "Measure the screen", run = start } },
    keys = { { "S H V B, 1 to 4", "The modes", "keyboard" },
      { "The wheel, + -", "How much a colour may change before it is an edge", "tune" },
      { "A click", "Copies the measure", "content_copy" }, { "Escape", "Ends it", "close" } } }, w, h)
end

M.verbs = {
  mode = function(name) mode:set(name) return true end,
  start = function() start() return true end,
}

return M
