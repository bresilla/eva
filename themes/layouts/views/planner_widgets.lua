-- Small form controls shared by the Tasks and Calendar pages.
local ui = require("morf.ui")
local kit = require("kit")
local rows = require("themes.layouts.rows")
local theme = require("theme")
local C = theme.color
local M = {}

function M.label(text, props)
  props = props or {}
  props.text = text
  props.font_size = props.font_size or theme.size.small
  props.color = props.color or function() return C.onSurfaceVariant end
  return kit.section_label(props)
end
function M.subtitle(text, props)
  props = props or {}
  props.text = text
  props.font_size = props.font_size or theme.size.small
  props.color = props.color or function() return C.onSurfaceVariant end
  return kit.subtitle(props)
end
function M.button(id, text, icon, width, action, selected)
  return kit.pill {
    id = id, label = text, icon = icon, width = width, height = 36,
    on_clicked = action,
    color = function() return selected and selected() and C.primary or C.surfaceContainerHighest end,
    ink = function() return selected and selected() and C.onPrimary or C.onSurface end,
  }
end
--- A labelled one-line field: the page template's field under `label`.
function M.field(id, label, placeholder, width, changed, accepted, escaped)
  local box, input = require("themes.layouts.page").field { id = id, width = width, placeholder = placeholder,
    name = label, on_changed = changed, on_accepted = accepted, on_escape = escaped }
  return ui.Column { width = width, gap = 4, M.label(label), box }, input
end
function M.message(text, width, height)
  return kit.subtitle { text = text, width = width, height = height or 46, wrap = true,
    font_size = theme.size.small, color = function() return C.onSurfaceVariant end }
end
return M
