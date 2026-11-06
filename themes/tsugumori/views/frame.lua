-- The Tsugumori desktop frame: a square opening with ruler ticks along
-- its inner lip. The workspace rail and level pills sit in the side bands.
-- Rulers are cached paths, static while the desktop geometry is unchanged.
local ui = require("morf.ui")
local theme = require("theme")
local C = theme.color
local V = {}

function V.insets(bar)
  bar = bar or { left = 0, top = 0, right = 0, bottom = 0 }
  return { left = theme.LEFT + bar.left, top = theme.BORDER + bar.top,
    right = theme.BORDER + bar.right, bottom = theme.BORDER + bar.bottom }
end

local PITCH, MAJOR = 8, 10        -- side rulers: a tick every PITCH px, every MAJORth long
local EDGE_PAD = 4                -- keep ticks clear of the opening ends
local STEP, NUMBERED = 10, 100    -- top and bottom: a tick every STEP px, numbered every NUMBERED
local digits = require("themes.tsugumori.digits")

-- A ruler along one edge of the opening: ticks rise out of the band from
-- the opening's lip, continuing evenly behind the pills. Along the top and
-- bottom they count screen pixels: a long tick every hundred with its number
-- beside it in segment digits, a middle one every fifty, a short one every
-- ten. `edge` is top/bottom/left/right.
local function ruler(model, edge)
  local B, L = theme.BORDER, theme.LEFT
  local function size() local _, _, w, h = model.desk() return w, h end
  local horizontal = edge == "top" or edge == "bottom"
  local function d(major)
    local w, h = size()
    local a0, a1 = horizontal and L + EDGE_PAD or B + EDGE_PAD,
      horizontal and w - B - EDGE_PAD or h - B - EDGE_PAD
    local out = {}
    if horizontal then
      for at = math.ceil(a0 / STEP) * STEP, a1, STEP do
        local long = at % NUMBERED == 0
        if long == major then
          local s = long and 7 or (at % 50 == 0 and 4 or 2)
          local p = at + .5
          if edge == "top" then out[#out + 1] = ("M%g %g V%g "):format(p, B, B - s)
          else out[#out + 1] = ("M%g %g V%g "):format(p, h - B, h - B + s) end
          if long and at + 20 < a1 then digits.put(out, tostring(at), at + 3, edge == "top" and 1 or h - B + 4) end
        end
      end
      return #out > 0 and table.concat(out) or "M0 0"
    end
    local rail = require("rail").geometry()
    -- Three evenly spaced workspaces between consecutive major ticks.
    local origin = rail.top - rail.gap / 2
    local every = 3 * (rail.item + rail.gap) / PITCH
    for k = math.ceil((a0 - origin) / PITCH), math.floor((a1 - origin) / PITCH) do
      local at = origin + k * PITCH
      if (k % every == 0) == major then
        local s = major and 5 or 2
        local p = math.floor(at) + .5
        if edge == "left" then out[#out + 1] = ("M%g %g H%g "):format(L, p, L - s)
        else out[#out + 1] = ("M%g %g H%g "):format(w - B, p, w - B + s) end
      end
    end
    return #out > 0 and table.concat(out) or "M0 0"
  end
  return ui.Item { id = "tsugumori-frame-ruler-" .. edge, anchors = { fill = true },
    ui.Path { id = "tsugumori-frame-ruler-" .. edge .. "-minor", anchors = { fill = true }, d = function() return d(false) end,
      fill_color = "transparent", stroke_color = function() return C.primary:alpha(.5) end, stroke_width = 1 },
    ui.Path { id = "tsugumori-frame-ruler-" .. edge .. "-major", anchors = { fill = true }, d = function() return d(true) end,
      fill_color = "transparent", stroke_color = function() return C.primary:alpha(.85) end, stroke_width = 1 },
  }
end

-- Registration reticles in the band at the opening's four corners: a heavy
-- L along both edges with a square pip in the band's corner past it, and a
-- short index notch where each edge's centre is.
local REACH, HEAVY, PIP = 46, 2, 3
local function corners(model)
  local function d()
    local _, _, w, h = model.desk()
    local B, L = theme.BORDER, theme.LEFT
    local out = {}
    local function bar(x, y, bw, bh) out[#out + 1] = ("M%g %g h%g v%g h%g Z "):format(x, y, bw, bh, -bw) end
    for _, c in ipairs { { L, B, 1, 1 }, { w - B, B, -1, 1 }, { L, h - B, 1, -1 }, { w - B, h - B, -1, -1 } } do
      local x, y, sx, sy = c[1], c[2], c[3], c[4]
      local ox, oy = x - sx * (HEAVY + 2), y - sy * (HEAVY + 2)
      bar(sx > 0 and ox or ox - REACH - HEAVY, sy > 0 and oy or oy - HEAVY, REACH + HEAVY, HEAVY)
      bar(sx > 0 and ox or ox - HEAVY, sy > 0 and oy or oy - REACH - HEAVY, HEAVY, REACH + HEAVY)
      local px, py = ox - sx * (PIP + 2), oy - sy * (PIP + 2)
      bar(sx > 0 and px or px - PIP, sy > 0 and py or py - PIP, PIP, PIP)
    end
    local mx, my = math.floor((L + w - B) / 2), math.floor(h / 2)
    bar(mx - 1, 1, HEAVY, B - 3)
    bar(mx - 1, h - B + 2, HEAVY, B - 3)
    bar(w - B + 2, my - 1, B - 3, HEAVY)
    return table.concat(out)
  end
  return ui.Path { id = "tsugumori-frame-corners", anchors = { fill = true }, d = d,
    fill_color = function() return C.primary:alpha(.92) end }
end

local function decorations(model)
  return ui.Item { id = "tsugumori-frame-marks", anchors = { fill = true },
    ruler(model, "top"),
    ruler(model, "bottom"),
    ruler(model, "left"),
    ruler(model, "right"),
    corners(model),
  }
end

--- The frame's paint on `props`, for any field that joins it.
function V.paint(props)
  props.fill_color, props.blend = function() return C.surface end, 0
  return props
end

function V.build(model)
  local reveal = require("themes.reveal")
  local hidden, rest = reveal.opening(model.desk, theme.LEFT, theme.BORDER, 2 * theme.ROUNDING)
  local opening = reveal.part(ui.SdfShape, { id = "frame-opening", shape = "box", operation = "subtract", radius = require("kit").round(25),
    x = function() local x = model.desk() return x + theme.LEFT end,
    y = function() local _, y = model.desk() return y + theme.BORDER end,
    width = function() local _, _, w = model.desk() return w - theme.LEFT - theme.BORDER end,
    height = function() local _, _, _, h = model.desk() return h - 2 * theme.BORDER end }, 0, hidden, rest)
  local transition = require("themes.session").transition
  require("themes.switcher").morph(opening, "radius", 0, transition and transition.frame_rounding)
  local field = V.paint { id = "frame", anchors = { fill = true },
    ui.SdfShape { shape = "box", anchors = { fill = true } },
    opening,
  }
  for _, drawer in ipairs(model.drawers) do field[#field + 1] = drawer.shape end
  field[#field + 1] = model.rail.shape
  -- The rail's lip swells the frame at the workspace on show.
  local rail = require("themes.tsugumori.views.rail")
  for _, shape in ipairs(rail.extra_shapes or {}) do field[#field + 1] = shape end
  field[#field + 1] = model.levels.shape
  if model.island then field[#field + 1] = model.island.shape end
  return require("themes.frame_host")(model, ui.Sdf(field), V.insets(), decorations(model))
end
return V
