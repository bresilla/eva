-- A pill of the kit's controls at a screen's edge, for a tool that covers the
-- screen: square cells in as many rows as the screen needs, a mark riding the
-- theme's spring onto the chosen one, a field of its own.
--
--     pill.new { id = "draw-toolbar", cells = { node, ... },
--       chosen = function() return 2 end }
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local C, S = theme.color, theme.space

local M = {}

M.CELL = S.TARGET
M.GAP = S.xs
M.PAD = S.s

local function step() return M.CELL + M.GAP end

local function columns(count)
  morf.window.screens_revision()
  local width = ((morf.screens or {})[1] or {}).width or 1920
  return math.max(1, math.min(count, (width - 2 * S.l - 2 * M.PAD) // step()))
end

--- `id`, `cells` (nodes `M.CELL` square), `chosen` (fn: the index of the cell
--- marked; none, no mark), `top` (at the screen's top, else its foot), `opacity`,
--- `behavior`, `z`. Returns the card.
function M.new(spec)
  local count = #spec.cells
  local function across() return columns(count) end
  local function down() return math.ceil(count / across()) end
  local card = {
    id = spec.id, z = spec.z or 5, radius = kit.round(S.l),
    width = function() return across() * step() - M.GAP + 2 * M.PAD end,
    height = function() return down() * step() - M.GAP + 2 * M.PAD end,
    anchors = spec.top and { horizontal_center = true, top = true, top_margin = S.l }
      or { horizontal_center = true, bottom = true, bottom_margin = S.l },
    opacity = spec.opacity, behavior = spec.behavior,
    ui.MouseArea { id = spec.id .. "-area", anchors = { fill = true } },
  }
  if spec.chosen then
    local mark = ui.Item {
      id = spec.id .. "-mark", width = M.CELL, height = M.CELL,
      x = function() return M.PAD + ((spec.chosen() - 1) % across()) * step() end,
      y = function() return M.PAD + ((spec.chosen() - 1) // across()) * step() end,
      behavior = { x = theme.spring.spatial, y = theme.spring.spatial },
      stretch = kit.STRETCH,
    }
    card[#card + 1] = mark
    card[#card + 1] = ui.Sdf {
      id = spec.id .. "-mark-field", anchors = { fill = true }, fill_color = C.primary:alpha(0),
      stroke_color = kit.stroke("hot"), stroke_width = S.xxs,
      ui.SdfShape { shape = "box", radius = kit.round(S.m), track = mark },
    }
  end
  local grid = { x = M.PAD, y = M.PAD, gap = M.GAP, columns = across }
  for index, cell in ipairs(spec.cells) do grid[index] = cell end
  card[#card + 1] = ui.Grid(grid)
  return kit.card(card)
end

return M
