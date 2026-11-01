-- A monitor's name across it, while eva-displays is told which is which.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local C, S = theme.color, theme.space

local M = {}

M.SHOWN = 3000

local function known(text) return (text == nil or text == "Unknown") and "" or text end

--- Shows this output's name for a moment, then `done()`.
function M.show(done)
  local screen = morf.screens[1] or {}
  local words = (known(screen.make) .. " " .. known(screen.model)):match("^%s*(.-)%s*$")
  local column = ui.Column {
    anchors = { center_in = true }, gap = S.s, align = "center",
    kit.text { id = "displays-identify-name", text = screen.name or "Monitor", font_size = S.xxl * 2,
      font_weight = 700, color = function() return C.primary end },
    words ~= "" and kit.text { text = words, font_size = theme.size.normal, color = kit.ink("lo") } or nil,
  }
  local plate = kit.card {
    id = "displays-identify-plate", anchors = { center_in = true }, radius = kit.round(S.xl),
    width = function() return (column.layout_width or 0) + 2 * S.xxl end,
    height = function() return (column.layout_height or 0) + 2 * S.xl end,
    column,
  }
  local layer
  layer = morf.window.layer {
    blend = "srgb", namespace = "eva-identify", layer = "overlay",
    anchors = { top = true, bottom = true, left = true, right = true },
    width = 0, height = 0, exclusive_zone = -1, keyboard_focus = "none", visible = true,
    root = ui.Item { anchors = { fill = true }, plate },
  }
  morf.time.timer(M.SHOWN, function()
    layer:destroy()
    if done then done() end
  end, false)
end

return M
