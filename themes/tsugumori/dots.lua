-- A quiet dot grid behind a panel's cards: one path of dashed rows at a
-- fixed pitch, and one of small crosses every fourth step, whose data
-- changes only when the panel's size crosses a step.
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
        for r = 1, rows do out[r] = ("M%g %g H%g "):format(pitch / 2, (r - .5) * pitch + .5, w) end
        return table.concat(out)
      end,
      fill_color = "transparent", stroke_width = 1, stroke_cap = "butt", dash = { 1, pitch - 1 },
      stroke_color = function() return C.primary:alpha(.3) end }
    ui.reparent(node, host)
    local every = 4 * pitch
    local crosses = ui.Path { id = id .. "-crosses", z = -50, anchors = { fill = true },
      d = function()
        local cols, rows = (steps(host.layout_width) + 1) // 4, (steps(host.layout_height) + 1) // 4
        if cols < 1 or rows < 1 then return "M0 0" end
        local out = {}
        for r = 1, rows do
          for c = 1, cols do
            local x, y = pitch / 2 + (4 * c - 2) * pitch, pitch / 2 + (4 * r - 2) * pitch
            out[#out + 1] = ("M%g %g H%g M%g %g V%g "):format(x - 3, y + .5, x + 4, x + .5, y - 3, y + 4)
          end
        end
        return table.concat(out)
      end,
      fill_color = "transparent", stroke_width = 1, stroke_cap = "butt",
      -- Darker than the ground they sit on, in either mode.
      stroke_color = function()
        return C.shadow:alpha(require("themes.color_mode").resolve() == "light" and .18 or .55)
      end }
    ui.reparent(crosses, host)
    return node
  end
end
