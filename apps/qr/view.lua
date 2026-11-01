-- eva-qr's window: the fields, the code on its plate, and the code alone over the
-- whole screen. The code is one path, its side a whole multiple of its modules,
-- the darker of the palette's two on the lighter.
local ui = require("morf.ui")
local morf = require("morf")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("common.controls")
local composites = require("themes.kit.composites")
local frame = require("common.frame")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

-- The clear margin a code asks for, in modules.
local QUIET = 4
local SAVED_W = S.TARGET * 4
local WIFI_H = 3 * (S.TARGET + S.s) + P.BUTTON_H + S.s

local function light(color)
  local rgb = color:rgb8()
  return 0.2126 * rgb.r + 0.7152 * rgb.g + 0.0722 * rgb.b
end

local function paper()
  if light(C.surface) > light(C.onSurface) then return C.surface end
  return C.onSurface
end

local function ink()
  if light(C.surface) > light(C.onSurface) then return C.onSurface end
  return C.surface
end

-- The code on a plate that fits `w` by `h`, whole pixels to a module.
local function plate(id, w, h)
  local function pitch()
    local size = model.size()
    if size == 0 then return 1 end
    return math.max(1, math.floor(math.min(w(), h()) / (size + 2 * QUIET)))
  end
  local function plate_side() return pitch() * (model.size() + 2 * QUIET) end
  local function code_side() return pitch() * model.size() end
  return ui.Rect {
    id = id, width = plate_side, height = plate_side, radius = kit.round(S.s), color = paper,
    x = function() return (w() - plate_side()) / 2 end, y = function() return (h() - plate_side()) / 2 end,
    visible = model.ready,
    ui.Path {
      id = id .. "-modules", anchors = { center_in = true }, width = code_side, height = code_side,
      view_box = function() return { 0, 0, math.max(1, model.size()), math.max(1, model.size()) } end,
      d = model.path, fill_color = ink,
    },
  }
end

-- The networks NetworkManager has, hidden where it has none.
local function saved_networks()
  local function names() return model.saved:get() end
  local node = composites.combo_box {
    id = "qr-saved", width = SAVED_W, height = S.TARGET, items = names, variant = "dropdown", placeholder = "Saved",
    current = function() return 0 end,
    on_changed = function(index) if names()[index] then model.pick_saved(names()[index]) end end,
  }
  return ui.Item { width = SAVED_W, height = S.TARGET, visible = model.has_saved, node }
end

local function wifi_fields(w)
  local security = {}
  for index, name in ipairs(model.SECURITY) do security[index] = name == "nopass" and "Open" or name end
  local field, input = kit.text_field("password", {
    id = "qr-password", width = w, height = S.TARGET, placeholder = "Password", color = kit.ink("hi"),
    placeholder_color = kit.ink("lo"), on_text_changed = model.set_password,
  })
  model.on_fill(function(value) input.text = value end)
  M.password_input = input
  local function name_w() return math.max(1, w() - (model.has_saved() and SAVED_W + S.s or 0)) end
  return ui.Column {
    id = "qr-wifi", width = w, gap = S.s,
    ui.Row {
      gap = S.s,
      controls.entry { id = "qr-ssid", width = name_w, value = model.ssid, placeholder = "Network name" },
      saved_networks(),
    },
    field,
    controls.segments {
      id = "qr-security", width = w, items = security, current = function() return model.security:get() end,
      on_changed = function(index) model.security:set(index) end,
    },
    P.row {
      id = "qr-hidden-row", width = w, height = S.TARGET, title = "Hidden network",
      trailing = P.switch { id = "qr-hidden", name = "Hidden network", on = function() return model.hidden:get() end,
        on_toggled = function(on) model.hidden:set(on) end },
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local function is_wifi() return model.mode:get() == 2 end
  local levels = {}
  for index, name in ipairs(model.LEVELS) do levels[index] = name end
  local function fields_h() return is_wifi() and WIFI_H or S.TARGET end
  local foot = 2 * (P.BUTTON_H + S.s) + L.lh(theme.size.small) + S.s
  local top_h = function() return P.BUTTON_H + S.s + fields_h() + S.s end
  local function code_h() return math.max(S.TARGET * 3, h() - top_h() - foot) end
  return ui.Item {
    id = "qr-root", width = w, height = h,
    ui.Column {
      width = w, gap = S.s,
      controls.segments {
        id = "qr-mode", width = w, items = model.MODES, current = function() return model.mode:get() end,
        on_changed = function(index) model.mode:set(index) end,
      },
      ui.Item {
        width = w, height = fields_h,
        ui.Item {
          width = w, height = S.TARGET, visible = function() return not is_wifi() end,
          (controls.entry { id = "qr-text", width = w, value = model.text, placeholder = "Text or a link", focus = true }),
        },
        ui.Item { width = w, height = WIFI_H, visible = is_wifi, wifi_fields(w) },
      },
      ui.Item {
        id = "qr-face", width = w, height = code_h,
        plate("qr-plate", w, code_h),
        kit.text {
          id = "qr-empty", anchors = { center_in = true }, color = kit.ink("lo"), font_size = theme.size.normal,
          visible = function() return not model.ready() end,
          text = function() return is_wifi() and "Name a network" or "Type something to make a code" end,
        },
      },
      controls.segments {
        id = "qr-level", width = w, items = levels, current = function() return model.level:get() end,
        on_changed = function(index) model.level:set(index) end,
      },
      P.buttons {
        width = w,
        { id = "qr-copy", icon = "content_copy", label = "Copy", enabled = model.ready, on_clicked = model.copy },
        { id = "qr-save", icon = "save", label = "Save", enabled = model.ready,
          on_clicked = function() model.save(model.default_path()) end },
        { id = "qr-show", icon = "fullscreen", label = "Show", tone = "primary", enabled = model.ready,
          on_clicked = function() model.full:set(true) end },
      },
      controls.note { id = "qr-note", width = w, text = function() return model.message:get() end },
    },
  }
end

local function full_screen(done)
  -- The root, before what is sized from it.
  local root = ui.Rect { id = "qr-full", anchors = { fill = true }, color = paper }
  local function room_w() return math.max(1, root.layout_width or 1) end
  local function room_h() return math.max(1, root.layout_height or 1) end
  local function close()
    model.full:set(false)
    if done then done() end
  end
  ui.reparent(plate("qr-full-plate", room_w, room_h), root)
  ui.reparent(ui.MouseArea {
    id = "qr-full-area", anchors = { fill = true }, cursor = "pointer", focus = true, on_clicked = close,
    on_key_pressed = function() close() return true end,
  }, root)
  return frame.overlay { id = "qr", root = root, close = close }
end

--- The code alone on the screen while `model.full` holds; a press or a key lets
--- go, `done()` after it.
function M.overlay(done)
  local layer
  morf.effect("eva.qr.overlay", function()
    local shown = model.full:get()
    if shown and not layer then layer = full_screen(done)
    elseif not shown and layer then
      layer:destroy()
      layer = nil
    end
  end)
end

return M
