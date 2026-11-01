-- eva-ruler's overlay over the frozen picture: the measure is one field of bars
-- and end caps joined on the theme's seam, each riding a spring to where the
-- edges are; bounds a box of its own; the reading on a card by the pointer; the
-- modes on a pill at the top.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local frame = require("common.frame")
local L = require("themes.layouts.parts")
local pill = require("themes.layouts.tool_pill")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

M.BAR = S.xxs
M.CAP = S.l
M.CARD_W = S.TARGET * 9
M.CARD_H = S.TARGET + S.xl

local function picture() return model.picture:get() end
local function mode() return model.mode:get() end
local function at() return model.at:get() end
local function surface(px) return px / model.scale() end

local function screen()
  local s = (morf.screens or {})[1] or {}
  return s.width or 1920, s.height or 1080
end

local function shows_across() local m = mode() return m == "spacing" or m == "horizontal" end
local function shows_down() local m = mode() return m == "spacing" or m == "vertical" end

-- The bars and caps of an axis: `box()` gives x, y, w, h.
local function ride(id, box)
  return ui.Item {
    id = id,
    x = function() return box().x end, y = function() return box().y end,
    width = function() return box().w end, height = function() return box().h end,
    behavior = { x = theme.spring.fast, y = theme.spring.fast, width = theme.spring.fast, height = theme.spring.fast },
  }
end

local function nothing() return { x = 0, y = 0, w = 0, h = 0 } end

local function across_bar()
  local e, p = model.edges:get(), at()
  if not e or not p or not shows_across() then return nothing() end
  return { x = surface(e.left), y = p.y - M.BAR / 2, w = surface(e.right + 1 - e.left), h = M.BAR }
end

local function down_bar()
  local e, p = model.edges:get(), at()
  if not e or not p or not shows_down() then return nothing() end
  return { x = p.x - M.BAR / 2, y = surface(e.top), w = M.BAR, h = surface(e.bottom + 1 - e.top) }
end

local function cap(side)
  return function()
    local e, p = model.edges:get(), at()
    if not e or not p then return nothing() end
    if side == "left" and shows_across() then return { x = surface(e.left) - M.BAR, y = p.y - M.CAP / 2, w = M.BAR, h = M.CAP } end
    if side == "right" and shows_across() then return { x = surface(e.right + 1), y = p.y - M.CAP / 2, w = M.BAR, h = M.CAP } end
    if side == "top" and shows_down() then return { x = p.x - M.CAP / 2, y = surface(e.top) - M.BAR, w = M.CAP, h = M.BAR } end
    if side == "bottom" and shows_down() then return { x = p.x - M.CAP / 2, y = surface(e.bottom + 1), w = M.CAP, h = M.BAR } end
    return nothing()
  end
end

local function measure_field()
  local parts = {
    ride("ruler-across", across_bar), ride("ruler-down", down_bar),
    ride("ruler-left", cap("left")), ride("ruler-right", cap("right")),
    ride("ruler-top", cap("top")), ride("ruler-bottom", cap("bottom")),
  }
  local field = {
    id = "ruler-field", anchors = { fill = true }, fill_color = kit.stroke("hot"),
    blend = S.xs, blend_profile = "circular",
    shadow_color = function() return C.surface:alpha(0.8) end, shadow_blur = S.xs,
  }
  for index, part in ipairs(parts) do
    field[index] = ui.SdfShape {
      id = "ruler-shape-" .. index, shape = "box", track = part, operation = index == 1 and "union" or "smooth_union",
    }
  end
  parts.id = "ruler-parts"
  parts.anchors = { fill = true }
  return ui.Item { id = "ruler-measure", anchors = { fill = true }, ui.Sdf(field), ui.Item(parts) }
end

local function bounds_box()
  local function box()
    local b = model.box:get()
    if not b then return nothing() end
    return { x = math.min(b.x0, b.x1), y = math.min(b.y0, b.y1), w = math.abs(b.x1 - b.x0), h = math.abs(b.y1 - b.y0) }
  end
  local node = ride("ruler-box", box)
  return ui.Item {
    id = "ruler-bounds", anchors = { fill = true },
    visible = function() return mode() == "bounds" and model.box:get() ~= nil end,
    ui.Sdf {
      id = "ruler-box-field", anchors = { fill = true },
      fill_color = function() return C.primary:alpha(0.16) end,
      stroke_color = kit.stroke("hot"), stroke_width = M.BAR,
      ui.SdfShape { shape = "box", radius = kit.round(S.xs), track = node },
    },
    node,
  }
end

local function reading_card()
  local function place()
    local p = at() or { x = 0, y = 0 }
    local b = model.box:get()
    if mode() == "bounds" and b then p = { x = math.max(b.x0, b.x1), y = math.max(b.y0, b.y1) } end
    local w, h = screen()
    local x, y = p.x + S.l, p.y + S.l
    if x + M.CARD_W + S.s > w then x = p.x - S.l - M.CARD_W end
    if y + M.CARD_H + S.s > h then y = p.y - S.l - M.CARD_H end
    return math.max(S.s, x), math.max(S.s, y)
  end
  return kit.card {
    id = "ruler-reading", z = 4, width = M.CARD_W, height = M.CARD_H, radius = kit.round(S.s),
    x = function() return (place()) end,
    y = function() local _, y = place() return y end,
    visible = function() return model.reading() ~= "" end,
    behavior = { x = theme.spring.fast, y = theme.spring.fast },
    ui.Column {
      x = S.m, width = M.CARD_W - 2 * S.m, anchors = { vertical_center = true }, gap = S.xxs,
      kit.text {
        id = "ruler-px", text = function() return model.reading() end, width = M.CARD_W - 2 * S.m, elide = "right",
        font_size = L.SIZE.title, font_weight = 600, color = kit.ink("hi"),
      },
      kit.text {
        id = "ruler-physical", width = M.CARD_W - 2 * S.m, elide = "right", font_size = theme.size.small,
        color = kit.ink("lo"),
        text = function()
          local words = model.physical_reading()
          if words ~= "" then return words end
          return model.copied:get() == model.reading() and "Copied" or "Click to copy"
        end,
      },
    },
  }
end

local ICONS = { spacing = "open_with", horizontal = "swap_horiz", vertical = "swap_vert", bounds = "crop_free" }

local function modes_pill(done)
  local cells = {}
  for index, name in ipairs(model.MODES) do
    cells[index] = L.icon_button {
      id = "ruler-mode-" .. name, name = name, icon = ICONS[name], width = pill.CELL, height = pill.CELL,
      on_clicked = function() model.choose(name) end,
    }
  end
  cells[#cells + 1] = L.icon_button {
    id = "ruler-end", name = "End", icon = "close", width = pill.CELL, height = pill.CELL, on_clicked = done,
  }
  return pill.new {
    id = "ruler-modes", top = true, cells = cells,
    chosen = function()
      for index, name in ipairs(model.MODES) do
        if name == mode() then return index end
      end
      return 1
    end,
  }
end

local KEYS = { s = "spacing", h = "horizontal", v = "vertical", b = "bounds",
  ["1"] = "spacing", ["2"] = "horizontal", ["3"] = "vertical", ["4"] = "bounds" }

local function frozen_screen(done)
  local dragged = false
  local function pressed(x, y)
    dragged = false
    model.point(x, y)
    if mode() == "bounds" then model.box_start(x, y) end
  end
  local function moved(x, y)
    dragged = true
    model.point(x, y)
    if mode() == "bounds" then model.box_move(x, y) end
  end
  local root = ui.Item {
    anchors = { fill = true },
    ui.Image {
      id = "ruler-frozen", anchors = { fill = true },
      source = function() local p = picture() return p and p.path or "" end,
    },
    measure_field(), bounds_box(),
    ui.MouseArea {
      id = "ruler-area", anchors = { fill = true }, cursor = "crosshair", focus = true,
      on_position_changed = function(x, y) model.point(x, y) end,
      on_pressed = pressed,
      on_dragged = moved,
      on_released = function() if mode() == "bounds" and dragged then model.copy() end end,
      on_clicked = function(x, y)
        if mode() ~= "bounds" then
          model.point(x, y)
          model.copy()
        end
      end,
      on_wheel = function(_, _, _, _, _, step_y) model.tune(step_y > 0 and -1 or 1) end,
      on_key_pressed = function(_, text, _, _, name)
        if name == "Escape" then done() return true end
        if KEYS[name] then model.choose(KEYS[name]) return true end
        if text == "+" or text == "=" then model.tune(1) return true end
        if text == "-" then model.tune(-1) return true end
      end,
    },
    reading_card(), modes_pill(done),
  }
  return frame.overlay { id = "ruler", root = root, close = done }
end

--- The frozen screen for as long as there is a picture.
function M.overlay(done)
  model.overlay(function() return frozen_screen(done) end)
end

return M
