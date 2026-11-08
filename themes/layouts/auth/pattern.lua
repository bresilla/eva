-- A login sheet's entry: patty's grid or keypad, else the password field, as
-- models/pattern_entry says; and the chip between them. Skins add `pattern_look`.
local M = {}

--- `spec`: `prefix`, `width`, `field`, `field_h`, `entry`, `grid` (its side),
--- `cell_h`, `skin`, `busy`, `bad`, `shake`, `typed`, `max_dots`, `on_done`, `send`, `submit`.
function M.entry(view, spec)
  local ui, s, C = view.ui, view.s, view.C
  local entry, skin = spec.entry, spec.skin or {}
  local look = { ring = function() return C.outlineVariant end, dot = function() return C.onSurfaceVariant end,
    lit = function() return C.primary end, line = function() return C.primary end,
    error = function() return C.error end, round = function(r) return r end }
  if skin.pattern_look then look = skin.pattern_look(look) end
  local grid = require("themes.layouts.pattern_grid").build { ui = ui, id = spec.prefix .. "-pattern",
    size = spec.grid, trace = entry.trace, look = look,
    enabled = function() return not spec.busy:get() end, bad = function() return spec.bad:get() end,
    shake = function() return spec.shake:get() end, on_start = spec.on_start, on_done = spec.on_done }
  local GAP, KEY_GAP = s(12), require("themes.spacing").s
  local cell_w = math.floor((spec.width - 2 * KEY_GAP) / 3)
  local keys_w, keys_h = 3 * cell_w + 2 * KEY_GAP, 4 * spec.cell_h + 3 * KEY_GAP
  local keys = require("themes.phone_pad").build { prefix = spec.prefix .. "-pattern-key",
    look = { C = C, text = view.text, icon = view.icon, action = ui.MouseArea,
      round = function(r) return skin.key_radius and math.min(r, skin.key_radius) or r end },
    order = function() return M.KEYS end, enabled = function() return not spec.busy:get() end,
    cell_w = cell_w, cell_h = spec.cell_h,
    on_key = function(key)
      if key == "backspace" or key == "enter" then spec.send { key = key } else spec.send { text = key } end
    end }
  local dots = require("themes.auth_form").password {
    prefix = spec.prefix .. "-pattern", ui = ui, s = s, C = C, width = spec.width, height = spec.field_h,
    text = view.text, icon = view.icon, typed = spec.typed, shake = spec.shake, bad = spec.bad,
    busy = spec.busy, max_dots = spec.max_dots, submit = spec.submit, placeholder = "Pattern",
    icon_name = "dialpad", focus = function() end }
  local keypad_h = spec.field_h + GAP + keys_h
  local function shown() return entry.shown() end
  local function height()
    local kind = shown()
    if kind == "grid" then return spec.grid end
    if kind == "keypad" then return keypad_h end
    return spec.field_h
  end
  local node = ui.Item { id = spec.prefix .. "-entry", width = spec.width, height = height,
    ui.Item { anchors = { horizontal_center = true }, width = spec.width, height = spec.field_h,
      visible = function() return shown() == nil end, spec.field },
    ui.Item { anchors = { horizontal_center = true }, width = spec.grid, height = spec.grid,
      visible = function() return shown() == "grid" end, grid },
    ui.Column { id = spec.prefix .. "-keypad", anchors = { horizontal_center = true }, gap = GAP, align = "center",
      visible = function() return shown() == "keypad" end, dots,
      ui.Item { width = keys_w, height = keys_h, keys.node } },
  }
  return { node = node, height = height }
end

M.KEYS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "backspace", "0", "enter" }

--- "Use password" or "Use pattern": `prefix`, `entry`, `width`, `on_clicked(method)`.
function M.switch(view, spec)
  local entry = spec.entry
  local function pattern() return entry.shown() ~= nil end
  local function words() return pattern() and "Use password" or "Use pattern" end
  return require("themes.layouts.auth.button").chip(view, { id = spec.prefix .. "-method",
    width = spec.width, label_width = spec.width - view.s(56),
    icon = function() return pattern() and "password" or "pattern" end, name = words, text = words,
    visible = entry.taken,
    on_clicked = function() spec.on_clicked(pattern() and "password" or "pattern") end })
end

return M
