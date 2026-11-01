-- The right panel's On-screen keyboard page: its languages, how it stands, what
-- it does while typing and what it may keep. In the page template
-- (themes/layouts/page.lua).
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")

local M = {}

local HEIGHTS = { { .85, "density_small", "Small" }, { 1, "density_medium", "Normal" }, { 1.2, "density_large", "Large" } }
local GAPS = { { 0, "vertical_align_bottom", "None" }, { 16, "vertical_align_center", "Small" }, { 32, "vertical_align_top", "Large" } }
local HANDS = { { "both", "keyboard", "Both" }, { "left", "dock_to_left", "Left" }, { "right", "dock_to_right", "Right" } }

local function choices(w, group, title, items, now, pick)
  local row = { width = P.inner(w) }
  for _, c in ipairs(items) do
    row[#row + 1] = { id = group .. "-" .. tostring(c[1]), icon = c[2], label = c[3], group = group,
      selected = function() return now() == c[1] end, on_clicked = function() pick(c[1]) end }
  end
  return P.section { id = group, width = w, title = title, P.buttons(row) }
end

function M.build(model, w, h)
  local inner = P.inner(w)
  local function toggle(name, icon, title, subtitle)
    local flag = model.flag(name)
    return P.row { id = "keyboard-" .. name, width = inner, icon = icon, title = title, subtitle = subtitle, on = flag.on,
      trailing = P.switch { id = "keyboard-" .. name .. "-switch", name = title, on = flag.on, on_toggled = flag.set } }
  end
  local languages = { id = "keyboard-languages", width = w, title = "Languages" }
  for _, layout in ipairs(model.languages) do
    local function on() return model.has_language(layout.id) end
    languages[#languages + 1] = P.row { id = "keyboard-language-" .. layout.id, width = inner, icon = "language",
      title = layout.name, subtitle = layout.words and "With prediction" or "Letters only", on = on,
      trailing = P.switch { id = "keyboard-language-" .. layout.id .. "-switch", name = layout.name, on = on,
        on_toggled = function(now) model.set_language(layout.id, now) end } }
  end
  return P.page {
    id = "keyboard-page", width = w, height = h,
    P.section { id = "keyboard-typing", width = w, title = "Typing",
      toggle("predict", "lightbulb", "Word prediction", "From the offline word lists"),
      toggle("autocaps", "text_fields", "Automatic capitals", "At the start of a sentence"),
      toggle("double_space", "space_bar", "Double space full stop"),
      toggle("auto_space", "keyboard_tab", "Automatic spaces", "After a picked word"),
      toggle("emoji_names", "mood", "Emoji by name", "A word that names one offers it"),
      toggle("keywords", "today", "Date keywords", "today, date and now"),
      toggle("haptics", "vibration", "Vibrate on keys"),
    },
    P.section { id = "keyboard-standing", width = w, title = "Layout",
      toggle("number_row", "pin", "Number row", "Languages that need those keys for letters go without"),
      toggle("floating", "picture_in_picture_alt", "Floating", "Drag it about by its handle"),
      toggle("split", "vertical_split", "Split", "Two halves, on a wide screen"),
    },
    choices(w, "keyboard-hand", "One hand", HANDS, model.hand, model.set_hand),
    choices(w, "keyboard-height", "Key height", HEIGHTS, model.height, model.set_height),
    choices(w, "keyboard-gap", "Space below the keys", GAPS, model.bottom_gap, model.set_bottom_gap),
    P.section(languages),
    P.section { id = "keyboard-private", width = w, title = "Privacy",
      toggle("clipboard", "content_paste", "Clipboard strip", "What eva-clipboard holds, over the keys"),
      toggle("autocorrect", "spellcheck", "Autocorrect", "Replaces a misspelt word on space"),
      toggle("learn", "school", "Learn new words", "Keeps what you type on this machine"),
      P.row { id = "keyboard-forget", width = inner, icon = "delete", title = "Forget learned words",
        trailing = P.chevron(), on_clicked = model.forget_words },
    },
    kit.subtitle { width = w, wrap = true, font_size = theme.size.small, color = kit.ink("lo"),
      text = "A text field in another program cannot say it holds a password yet, so autocorrect and learning stay off until you turn them on." },
  }
end

return M
