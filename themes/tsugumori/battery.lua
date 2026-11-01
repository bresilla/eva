-- The battery as an instrument: a square hairline frame and a row of cells a
-- spring wipes across, the same fields a Tsugumori gauge is cut from. Its
-- marks sit in full ink in a halo cut from the cells, so a state reads at any
-- level and without its colour.
local morf = require("morf")
local ui = require("morf.ui")
local common = require("themes.kit_common")

return function(theme, kit)
  local C = theme.color
  local function asset(name) return morf.paths.shell("assets/battery/" .. name .. ".svg") end
  local TONES = { ok = kit.signal("ok"), extra = kit.signal("extra"), warn = kit.signal("warn"), alert = kit.signal("alert") }
  local HALO = 1.5

  --- A battery in a `2 * size` by `size` box. `status` is a binding of the
  --- battery status (shell/battery_status_model.lua), `size` the body's
  --- height (16), `color` its ink, and `plain` (a binding) sets the cells in
  --- that ink whatever the tone: for a ground the tones do not read on.
  return function(spec)
    local H = spec.size or 16
    local NUB, STROKE = 2, 1
    local BODY_W = 2 * H - NUB - 1
    local PAD = STROKE + 1
    local INNER_W, INNER_H = BODY_W - 2 * PAD, H - 2 * PAD
    local CELLS, GAP = 5, 1
    local CELL_W = (INNER_W - (CELLS - 1) * GAP) / CELLS
    local MARK, PAIR = H - 3, math.floor(H * 0.68)
    local ink = spec.color or function() return C.onSurface end
    local function status() return spec.status() end
    local function tone()
      local paint = TONES[status().tone]
      if not paint or common.get(spec.plain) then return ink() end
      return paint()
    end
    local function paired() return status().mark ~= "" and status().saver end
    local function size() return paired() and PAIR or MARK end
    -- Where a mark rides: alone in the middle, or at `x` beside another.
    local function seat(x)
      local halo = ui.Item { anchors = { fill = true, margins = -HALO } }
      local box = ui.Item {
        x = function() return paired() and x or (BODY_W - MARK) / 2 end,
        y = function() return (H - size()) / 2 end,
        width = size, height = size,
        behavior = { x = theme.spring.fast, width = theme.spring.fast, height = theme.spring.fast },
        halo }
      return box, halo
    end
    local wipe = ui.Item { x = PAD, y = PAD, height = INNER_H,
      width = function()
        local level = status().level
        return level > 0 and math.max(CELL_W, INNER_W * level / 100) or 0
      end,
      behavior = { width = theme.spring.spatial } }
    local mark_box, mark_halo = seat(BODY_W / 2 - PAIR - 1)
    local leaf_box, leaf_halo = seat(BODY_W / 2 + 1)
    local source, source_to, progress = common.outline_morph(function() return status().mark end, asset, mark_box)
    local function mark_on() return status().mark ~= "" and 1 or 0 end
    local function leaf_on() return status().saver and 1 or 0 end
    local morph = { morph_progress = theme.spring.fast, opacity = theme.spring.effects }
    local fade = { opacity = theme.spring.effects }
    local cells = { id = spec.id and (spec.id .. "-fill") or nil, anchors = { fill = true },
      fill_color = tone, behavior = { fill_color = theme.spring.effects } }
    for i = 1, CELLS do
      cells[#cells + 1] = ui.SdfShape { shape = "box", x = PAD + (i - 1) * (CELL_W + GAP), y = PAD,
        width = CELL_W, height = INNER_H }
    end
    cells[#cells + 1] = ui.SdfShape { shape = "box", track = wipe, operation = "intersect" }
    cells[#cells + 1] = ui.SdfShape { source = source, source_morph_to = source_to, morph_progress = progress,
      track = mark_halo, operation = "subtract", opacity = mark_on, behavior = morph }
    cells[#cells + 1] = ui.SdfShape { source = asset("leaf"), track = leaf_halo, operation = "subtract",
      opacity = leaf_on, behavior = fade }
    return ui.Item { id = spec.id, x = spec.x, y = spec.y, anchors = spec.anchors, width = 2 * H, height = H,
      accessible_hidden = true, wipe, mark_box, leaf_box,
      ui.Sdf { anchors = { fill = true }, fill_color = function() return ink():alpha(0.7) end,
        behavior = { fill_color = theme.spring.effects },
        ui.SdfShape { shape = "box", width = BODY_W, height = H },
        ui.SdfShape { shape = "box", x = STROKE, y = STROKE, width = BODY_W - 2 * STROKE, height = H - 2 * STROKE,
          operation = "subtract" },
        ui.SdfShape { shape = "box", x = BODY_W + 1, y = math.floor(H / 4), width = NUB, height = H - 2 * math.floor(H / 4) },
      },
      ui.Sdf(cells),
      ui.Sdf { id = spec.id and (spec.id .. "-marks") or nil, anchors = { fill = true }, fill_color = ink,
        ui.SdfShape { source = source, source_morph_to = source_to, morph_progress = progress, track = mark_box,
          opacity = mark_on, behavior = morph },
        ui.SdfShape { source = asset("leaf"), track = leaf_box, opacity = leaf_on, behavior = fade },
      },
    }
  end
end
