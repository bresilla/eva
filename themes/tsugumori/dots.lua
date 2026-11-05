-- A faint dot grid behind a panel's cards: one path of dashed rows at a
-- fixed pitch, whose data changes only when the panel's size crosses a step.
local ui = require("morf.ui")
return function(theme)
  local C = theme.color
  return function(host, id, pitch)
    pitch = pitch or 12
    local function steps(v) return math.floor((v or 0) / pitch) end
    local node = ui.Path { id = id .. "-dots", z = -50, anchors = { fill = true },
      d = function()
        local cols, rows = steps(host.layout_width), steps(host.layout_height)
        if cols < 1 or rows < 1 then return "M0 0" end
        local out, w = {}, cols * pitch
        for r = 1, rows do out[r] = ("M%g %g H%g "):format(pitch / 2 - .5, (r - .5) * pitch, w) end
        return table.concat(out)
      end,
      fill_color = "transparent", stroke_width = 1, stroke_cap = "butt", dash = { 1, pitch - 1 },
      stroke_color = function() return C.primary:alpha(.2) end }
    ui.reparent(node, host)
    return node
  end
end
