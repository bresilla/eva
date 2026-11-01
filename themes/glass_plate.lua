-- The picture behind glass: a small blurred copy of the wallpaper, drawn under
-- the frame's field and cut to its shape by a mask of the same tracked nodes, so
-- it travels with every panel that slides. No live blur runs for it: the copy is
-- made once on a worker, and a card's own glass reads it.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local glass = require("themes.glass")
local M = {}

local BLUR = 18

local serial = 0
local function blurred(path, done)
  serial = serial + 1
  local own = serial
  local w, h = require("workspace_wallpaper").screen_size()
  local stamp = morf.encoding.sha1(path .. "\n" .. w .. "x" .. h)
  local out = morf.paths.cache("eva-glass-" .. stamp .. ".jpg")
  if morf.fs.is_file(out) then done(out) return end
  morf.fs.mkdir(morf.paths.cache(), { parents = true })
  local queued = pcall(morf.image.process, { source = path, output = out, quality = 80,
    ops = { { "resize", math.ceil(w / 2), math.ceil(h / 2), "fill" }, { "blur", BLUR } },
    on_done = function(ok) if ok and own == serial then done(out) end end })
  if not queued then done("") end
end

--- The plate, or an empty item. `model` is what the frame was built from; a
--- drawer gives its `backing` and corners, a bud of the levels its panel.
function M.build(model, inset)
  local source = morf.signal("eva.glass.source", "")
  local shapes = { anchors = { fill = true }, blend = theme.SEAM, blend_profile = "circular",
    ui.SdfShape { shape = "box", anchors = { fill = true } },
    ui.SdfShape { shape = "box", operation = "subtract", radius = theme.ROUNDING,
      x = function() local x = model.desk() return x + inset.left end,
      y = function() local _, y = model.desk() return y + inset.top end,
      width = function() local _, _, w = model.desk() return w - inset.left - inset.right end,
      height = function() local _, _, _, h = model.desk() return h - inset.top - inset.bottom end },
  }
  for _, drawer in ipairs(model.drawers) do
    local d = drawer.shape
    shapes[#shapes + 1] = ui.SdfShape { shape = "box", operation = "smooth_union", blend_group = d.blend_group,
      track = drawer.backing, top_left_radius = d.top_left_radius, top_right_radius = d.top_right_radius,
      bottom_left_radius = d.bottom_left_radius, bottom_right_radius = d.bottom_right_radius }
  end
  for _, panel in ipairs(model.levels.panels or {}) do
    shapes[#shapes + 1] = ui.SdfShape { shape = "box", operation = "union", track = panel, radius = theme.ROUNDING }
  end
  if model.island then
    shapes[#shapes + 1] = ui.SdfShape { shape = "box", operation = "union", track = model.island.panel, radius = theme.ROUNDING }
  end
  local plate = ui.Item { id = "glass-plate", anchors = { fill = true },
    visible = function() return glass.on() and source:get() ~= "" end,
    mask = ui.Sdf(shapes),
    ui.Image { id = "glass-plate-picture", anchors = { fill = true }, fill_mode = "preserve_aspect_crop",
      source = function() return source:get() end },
  }
  morf.effect("eva.glass.source", function()
    if not glass.on() then return end
    local path = require("wallpaper").picture()
    if path == "" then source:set("") return end
    blurred(path, function(out) source:set(out) end)
  end, { owner = plate })
  return plate
end

return M
