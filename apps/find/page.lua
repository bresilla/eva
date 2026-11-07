-- eva-find's page in the Tools window: how it shows where the pointer is, and a
-- control that shows it. The showing itself is eva-find's own program, over the
-- whole screen.
local morf = require("morf")
local overlay = require("apps.common.overlay_page")

local M = {}

-- How it shows the pointer, as `eva-find --MODE` takes it.
local mode = morf.signal("eva.tools.find.mode", "spotlight")

local function start() overlay.start("find", { "--" .. mode:get() }) end

--- The page, `w` by `h`.
function M.build(w, h)
  return overlay.build({ id = "find",
    text = "Shows where the pointer is, over the whole screen: a spotlight that goes once the pointer rests, "
      .. "lines through it, or rings on each press.",
    choices = { { id = "find-mode", title = "It shows", value = mode, items = {
      { "spotlight", "highlight", "Spotlight" }, { "crosshairs", "add", "Crosshairs" },
      { "ripple", "radio_button_checked", "Rings" } } } },
    starts = { { id = "find-start", icon = "my_location", label = "Show the pointer", run = start } },
    keys = { { "Any input", "Ends a spotlight", "mouse" }, { "Escape", "Ends crosshairs and rings", "close" } } }, w, h)
end

M.verbs = {
  mode = function(name) mode:set(name) return true end,
  start = function() start() return true end,
}

return M
