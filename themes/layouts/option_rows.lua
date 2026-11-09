-- Settings rows that edit one value: a row of preset choices, a switch, and a
-- line of text. Used by the pages whose rows are mostly this. A value the system
-- fixes shows and does not move.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local C = theme.color
local F = {}

--- Pieces of `text` split on spaces: a command as a list of words.
function F.words(text)
  local out = {}
  for word in tostring(text or ""):gmatch("%S+") do out[#out + 1] = word end
  return out
end

--- A title over a row of buttons, one per choice: `id`, `width`, `title`,
--- `subtitle`, `icon`, `choices` (`{ value, label }`), `read` (fn), `set` (fn),
--- `enabled` (fn), `per_row` (all of them, without it).
function F.choices(spec)
  local per_row = spec.per_row or math.max(1, #spec.choices)
  local lines = { width = spec.width, gap = P.ROW_GAP }
  for start = 1, #spec.choices, per_row do
    local buttons = { id = spec.id .. "-choices" .. (start > 1 and "-" .. start or ""), width = spec.width }
    for index = start, math.min(start + per_row - 1, #spec.choices) do
      local choice = spec.choices[index]
      buttons[#buttons + 1] = { id = spec.id .. "-" .. tostring(choice[1]), label = choice[2], group = spec.id,
        enabled = spec.enabled, selected = function() return spec.read() == choice[1] end,
        on_clicked = function() spec.set(choice[1]) end }
    end
    lines[#lines + 1] = P.buttons(buttons)
  end
  return ui.Column { id = spec.id, width = spec.width, gap = P.ROW_GAP / 2,
    P.row { id = spec.id .. "-row", width = spec.width, height = 44, icon = spec.icon, title = spec.title,
      subtitle = spec.subtitle },
    ui.Column(lines),
  }
end

--- One line for one of a few choices: the title, and at the right a list to
--- pick from (`<id>-field`). The same `spec` as F.choices.
function F.select(spec)
  local FIELD = 136
  local labels = {}
  for index, choice in ipairs(spec.choices) do labels[index] = choice[2] end
  local function current()
    local now = spec.read()
    for index, choice in ipairs(spec.choices) do
      if choice[1] == now then return index end
    end
    return 1
  end
  local field = (require("themes.kit.composites").combo_box {
    id = spec.id .. "-field", width = FIELD, height = theme.space.TARGET, items = labels, current = current,
    variant = "select", accessible_name = spec.title,
    on_changed = function(index)
      local choice = spec.choices[index]
      if choice and choice[1] ~= spec.read() then spec.set(choice[1]) end
    end })
  return P.row { id = spec.id, width = spec.width, icon = spec.icon, title = spec.title, subtitle = spec.subtitle,
    trailing = ui.Item { width = FIELD, height = theme.space.TARGET, field } }
end

--- A row with a switch: `id`, `width`, `icon`, `title`, `subtitle`, `on` (fn),
--- `set` (fn), `enabled` (fn).
function F.switch(spec)
  return P.row { id = spec.id, width = spec.width, height = 56, icon = spec.icon, title = spec.title,
    subtitle = spec.subtitle, on = spec.on, visible = spec.visible,
    trailing = P.switch { id = spec.id .. "-switch", name = spec.title, on = spec.on, enabled = spec.enabled,
      on_toggled = spec.set } }
end

--- A labelled line of text: `id`, `width`, `title`, `value` (fn), `set` (fn), saved
--- as it is typed.
function F.text(spec)
  local node = kit.text_field("entry", { id = spec.id, x = 10, y = 3, width = spec.width - 20, height = 30,
    font_family = theme.font, font_size = theme.size.small, placeholder = spec.title, text = spec.value(),
    read_only = spec.enabled and function() return not spec.enabled() end or nil,
    color = function() return C.onSurface end, placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(.25) end,
    on_text_changed = spec.set })
  return kit.surface { width = spec.width, height = 36, radius = kit.round(10),
    color = function() return C.surfaceContainerHighest end, node }
end

return F
