-- The battery as distance fields: a rounded body and nub, a fill that follows
-- the level on a spring, and marks in full ink with a halo cut out of the fill
-- around them, so a state reads at any level and without its colour.
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
  --- height (16), `color` its ink, and `plain` (a binding) sets the fill in
  --- that ink whatever the tone: for a ground the tones do not read on.
  return function(spec)
    local H = spec.size or 16
    local NUB, STROKE = math.max(2, math.floor(H / 7)), math.max(1.5, H / 11)
    local BODY_W, R = 2 * H - NUB - 1, math.floor(H / 4)
    local PAD = STROKE + 1
    local INNER_W, INNER_H = BODY_W - 2 * PAD, H - 2 * PAD
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
    local fill = ui.Item { id = spec.id and (spec.id .. "-level") or nil, x = PAD, y = PAD, height = INNER_H,
      width = function()
        local level = status().level
        return level > 0 and math.max(2, INNER_W * level / 100) or 0
      end,
      behavior = { width = theme.spring.spatial } }
    local mark_box, mark_halo = seat(BODY_W / 2 - PAIR - 1)
    local leaf_box, leaf_halo = seat(BODY_W / 2 + 1)
    local source, source_to, progress = common.outline_morph(function() return status().mark end, asset, mark_box)
    local function mark_on() return status().mark ~= "" and 1 or 0 end
    local function leaf_on() return status().saver and 1 or 0 end
    local morph = { morph_progress = theme.spring.fast, opacity = theme.spring.effects }
    local fade = { opacity = theme.spring.effects }
    return ui.Item { id = spec.id, x = spec.x, y = spec.y, anchors = spec.anchors, width = 2 * H, height = H,
      accessible_hidden = true, fill, mark_box, leaf_box,
      ui.Sdf { anchors = { fill = true }, fill_color = function() return ink():alpha(0.62) end,
        behavior = { fill_color = theme.spring.effects },
        ui.SdfShape { shape = "box", width = BODY_W, height = H, radius = R },
        ui.SdfShape { shape = "box", x = STROKE, y = STROKE, width = BODY_W - 2 * STROKE, height = H - 2 * STROKE,
          radius = R - STROKE, operation = "subtract" },
        ui.SdfShape { shape = "box", x = BODY_W + 1, y = H / 4, width = NUB, height = H / 2,
          top_right_radius = NUB, bottom_right_radius = NUB, top_left_radius = 0, bottom_left_radius = 0 },
      },
      ui.Sdf { id = spec.id and (spec.id .. "-fill") or nil, anchors = { fill = true },
        fill_color = tone, behavior = { fill_color = theme.spring.effects },
        ui.SdfShape { shape = "box", x = PAD, y = PAD, width = INNER_W, height = INNER_H, radius = math.max(1, R - PAD) },
        ui.SdfShape { shape = "box", track = fill, operation = "intersect" },
        ui.SdfShape { source = source, source_morph_to = source_to, morph_progress = progress, track = mark_halo,
          operation = "subtract", opacity = mark_on, behavior = morph },
        ui.SdfShape { source = asset("leaf"), track = leaf_halo, operation = "subtract", opacity = leaf_on, behavior = fade },
      },
      ui.Sdf { id = spec.id and (spec.id .. "-marks") or nil, anchors = { fill = true }, fill_color = ink,
        ui.SdfShape { source = source, source_morph_to = source_to, morph_progress = progress, track = mark_box,
          opacity = mark_on, behavior = morph },
        ui.SdfShape { source = asset("leaf"), track = leaf_box, opacity = leaf_on, behavior = fade },
      },
    }
  end
end
