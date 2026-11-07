-- eva-draw's page in the Tools window: what it does, the keys it takes, and a
-- control that starts it. The drawing itself is eva-draw's own program, over
-- the whole screen.
local overlay = require("apps.common.overlay_page")

local M = {}

--- The page, `w` by `h`.
function M.build(w, h)
  return overlay.build({ id = "draw",
    text = "Strokes and words over everything, with a mouse, a finger or a pen, until Escape.",
    starts = { { id = "draw-start", icon = "draw", label = "Draw on the screen",
      run = function() overlay.start("draw", { "start" }) end } },
    keys = { { "R Y G C B P", "The pens, in the theme's colours", "palette" },
      { "+ - [ ] and the wheel", "The pen's width", "line_weight" },
      { "T", "Words: press where they go, type, Return keeps them", "text_fields" },
      { "W", "A plain board behind the marks", "rectangle" },
      { "U, Ctrl+Z", "Takes back the last mark", "undo" }, { "E", "Clears everything", "delete" },
      { "Escape", "Ends it", "close" } } }, w, h)
end

M.verbs = { start = function() overlay.start("draw", { "start" }) return true end }

return M
