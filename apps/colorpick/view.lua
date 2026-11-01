-- eva-colorpick: the window with the formats and recent colours, and the frozen
-- screen with its magnifier.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local formats = require("formats")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

local SWATCH = S.TARGET
local LENS = 176

local function picked() return model.picked:get() end

local function current(w)
  local inner = function() return P.inner(w) end
  local spec = { width = inner }
  for i, name in ipairs(formats.NAMES) do
    spec[i] = {
      id = "colorpick-format-" .. name, label = name,
      tone = function() return model.format:get() == name and "primary" or nil end,
      on_clicked = function()
        model.format:set(name)
        if picked() ~= "" then model.copy(picked()) end
      end,
    }
  end
  return P.section {
    id = "colorpick-current", width = w, title = "Colour",
    P.row {
      id = "colorpick-value", width = inner, title = function()
        return picked() ~= "" and formats.write(picked(), model.format:get()) or "Nothing picked yet"
      end,
      subtitle = function() return model.message:get() end,
      trailing = ui.Rect {
        id = "colorpick-swatch", width = SWATCH, height = SWATCH, radius = kit.round(S.s),
        color = function() return picked() ~= "" and morf.color(picked()) or C.surfaceContainerHighest end,
      },
    },
    P.buttons(spec),
  }
end

local function recent(w)
  local children = {}
  local function at(i) return model.recent:get()[i] end
  for i = 1, model.RECENT do
    children[#children + 1] = kit.action {
      id = "colorpick-recent-" .. i, width = SWATCH, height = SWATCH, cursor = "pointer",
      accessible_name = "Recent colour", visible = function() return at(i) ~= nil end,
      on_clicked = function()
        local hex = at(i)
        if hex then model.picked:set(hex) model.copy(hex) end
      end,
      ui.Rect {
        anchors = { fill = true }, radius = kit.round(S.s),
        color = function() return at(i) and morf.color(at(i)) or C.surface end,
      },
    }
  end
  children.gap = S.s
  children.width = function() return P.inner(w) end
  children.columns = function() return math.max(1, (P.inner(w) + S.s) // (SWATCH + S.s)) end
  return P.section {
    id = "colorpick-recent", width = w, title = "Recent",
    visible = function() return #model.recent:get() > 0 end,
    ui.Grid(children),
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  return P.page {
    id = "colorpick-page", width = w, height = h,
    current(w), recent(w),
    P.buttons {
      width = w,
      { id = "colorpick-pick", label = "Pick from screen", icon = "colorize", tone = "primary", on_clicked = model.freeze },
      { id = "colorpick-lule", label = "Send to Lule", icon = "palette",
        visible = function() return picked() ~= "" end,
        on_clicked = function() model.send_to_lule(picked()) end },
    },
  }
end

local function frozen_screen(done)
  local function picture() return model.picture:get() end
  local scale = model.scale
  local function hover() return model.hover:get() end
  local zoom = model.ZOOM
  local lens = ui.ClipRect {
    id = "colorpick-lens", width = LENS, height = LENS, radius = LENS / 2, z = 3,
    visible = function() return hover() ~= nil end,
    x = function() local at = hover() return at and at.x + S.xl or 0 end,
    y = function() local at = hover() return at and at.y + S.xl or 0 end,
    border_width = 2, border_color = function() return C.primary end,
    ui.Image {
      id = "colorpick-lens-image", scale = zoom, transform_origin_x = 0, transform_origin_y = 0,
      source = function() local p = picture() return p and p.path or "" end,
      width = function() local p = picture() return p and p.width or 1 end,
      height = function() local p = picture() return p and p.height or 1 end,
      x = function() local at = hover() return at and LENS / 2 - at.px * zoom or 0 end,
      y = function() local at = hover() return at and LENS / 2 - at.py * zoom or 0 end,
    },
    ui.Rect {
      anchors = { center_in = true }, width = zoom, height = zoom, color = "transparent",
      border_width = 1, border_color = function() return C.onSurface end,
    },
  }
  local label = kit.card {
    id = "colorpick-readout", z = 4, width = LENS, height = S.TARGET, radius = kit.round(S.s),
    visible = function() return hover() ~= nil end,
    x = function() local at = hover() return at and at.x + S.xl or 0 end,
    y = function() local at = hover() return at and at.y + S.xl + LENS + S.s or 0 end,
    kit.text {
      id = "colorpick-readout-text", anchors = { center_in = true }, color = kit.ink("hi"),
      font_size = theme.size.normal,
      text = function() local at = hover() return at and formats.write(at.hex, model.format:get()) or "" end,
    },
  }
  local hint = kit.card {
    id = "colorpick-hint", z = 4, width = S.TARGET * 8, height = S.TARGET, radius = kit.round(S.s),
    anchors = { horizontal_center = true, top = true, top_margin = S.l },
    kit.text {
      anchors = { center_in = true }, color = kit.ink("hi"), font_size = theme.size.normal,
      text = "Click to copy · Esc to cancel",
    },
  }
  local function finish(hex)
    if done then done(hex) end
  end
  local root = ui.Item {
    anchors = { fill = true },
    ui.Image {
      id = "colorpick-frozen", anchors = { fill = true },
      source = function() local p = picture() return p and p.path or "" end,
    },
    ui.MouseArea {
      id = "colorpick-area", anchors = { fill = true }, cursor = "crosshair",
      focus = function() return picture() ~= nil end,
      on_position_changed = function(sx, sy) model.point(sx, sy, scale()) end,
      on_clicked = function(sx, sy)
        model.point(sx, sy, scale())
        finish(model.pick())
      end,
      on_key_pressed = function(_, _, _, _, name)
        if name == "Escape" then
          model.thaw()
          finish(nil)
          return true
        end
      end,
    },
    lens, label, hint,
  }
  return require("common.frame").overlay { id = "colorpick", root = root }
end

--- The frozen screen for as long as there is a picture: a click takes a colour,
--- Escape lets go. `done(hex)` after either.
function M.overlay(done)
  local layer
  morf.effect("eva.colorpick.overlay", function()
    local shown = model.picture:get() ~= nil
    if shown and not layer then layer = frozen_screen(done)
    elseif not shown and layer then
      require("common.frame").dismiss(layer)
      layer = nil
    end
  end)
end

return M
