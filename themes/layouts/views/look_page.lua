-- The Look page: where the colours come from, how the shell is proportioned,
-- what its panels are made of, and what the rest of the desktop is told.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local config = require("config")
local P = require("themes.layouts.page")
local C, S = theme.color, theme.space

local V = {}

local function label(text, width)
  return kit.subtitle { font_size = theme.size.small, color = kit.ink("lo"), text = text, height = S.l, width = width }
end

local function chunks(id, width, items, per)
  local rows = { width = width, gap = S.s }
  for start = 1, #items, per do
    local row = { id = id .. "-" .. start, width = width }
    for i = start, math.min(start + per - 1, #items) do row[#row + 1] = items[i] end
    rows[#rows + 1] = P.buttons(row)
  end
  return ui.Column(rows)
end

local function choice(id, width, key, choices, per, on_chosen)
  local items = {}
  for _, entry in ipairs(choices) do
    local value = entry[1]
    items[#items + 1] = { id = id .. "-" .. tostring(value), label = entry[2], group = id,
      selected = function() return config.get(key) == value end,
      on_clicked = function() if on_chosen then on_chosen(value) else config.set(key, value) end end }
  end
  return chunks(id, width, items, per or #items)
end

local function toggle(id, width, title, subtitle, icon, key)
  local on = function() return config.get(key) == true end
  return P.row { id = id, width = width, icon = icon, title = title, subtitle = subtitle, on = on,
    trailing = P.switch { id = id .. "-switch", name = title, on = on,
      on_toggled = function(now) config.set(key, now == true) end } }
end

-- A field that opens the list of `list()`, keeping setting `key`.
local function picker(id, width, key, list, placeholder)
  local composites = require("themes.kit.composites")
  local items = morf.signal("eva.look.items." .. id, {})
  local node = composites.combo_box { id = id, width = width, height = P.BUTTON_H, placeholder = placeholder,
    items = function() return items:get() end,
    current = function()
      for i, item in ipairs(items:get()) do if item == config.get(key) then return i end end
      return 0
    end,
    on_changed = function(_, item) config.set(key, item) end }
  morf.effect("eva.look.list." .. id, function() items:set(list()) end, { owner = node })
  return node
end

local function entry(id, width, placeholder, get_value, accept)
  local node, handle = kit.text_field("entry", { id = id, x = S.s, y = S.xs, width = width - 2 * S.s, height = P.BUTTON_H - 2 * S.xs,
    font_family = theme.font, font_size = theme.size.small, placeholder = placeholder,
    color = function() return C.onSurface end, placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(0.25) end,
    on_accepted = accept })
  local box = kit.surface { width = width, height = P.BUTTON_H, radius = kit.round(S.m),
    color = function() return C.surfaceContainerHighest end, node }
  morf.effect("eva.look.field." .. id, function() handle.text = get_value() end, { owner = box })
  return box
end

--- The page at `w` x `h`; `model` is shell/appearance_model.lua.
function V.build(model, w, h)
  local inner = P.inner(w)
  local narrow = inner < S.xxl * 16
  model.refresh()
  local sources = {}
  for _, source in ipairs(model.sources()) do sources[#sources + 1] = { source.id, source.name } end
  local status = morf.signal("eva.look.status", "")
  return P.page { id = "look-page", width = w, height = h,
    P.section { id = "look-colors", width = w, title = "Colours",
      label("Where they come from", inner),
      choice("look-source", inner, "theme.source", sources, narrow and 3 or 5),
      toggle("look-song", inner, "Follow the song", "Album art colours the shell while music plays", "music_note", "theme.follow_song"),
      toggle("look-black", inner, "Pure black", "Dark surfaces all the way down, for OLED", "contrast", "appearance.pure_black"),
      label("Scheme", inner),
      choice("look-variant", inner, "theme.variant", model.VARIANTS, narrow and 4 or 8),
    },
    P.section { id = "look-shape", width = w, title = "Shape",
      label("Density", inner),
      choice("look-density", inner, "appearance.density", model.DENSITIES),
      label("Corners", inner),
      choice("look-corners", inner, "appearance.corners", model.CORNERS, narrow and 3 or 5),
    },
    P.section { id = "look-material", width = w, title = "Material",
      toggle("look-glass", inner, "Glass", "Panels and displays of glass over the picture", "blur_on", "appearance.glass"),
      label("How much shows through", inner),
      choice("look-clarity", inner, "appearance.glass_clarity", { { 0.3, "A little" }, { 0.45, "Some" }, { 0.65, "A lot" } }),
    },
    P.section { id = "look-type", width = w, title = "Type",
      label("A font file for every label, or leave it empty", inner),
      entry("look-font-file", inner, "~/.local/share/fonts/face.ttf",
        function() return config.get("appearance.font_file") end,
        function(value)
          local ok, why = model.set_font_file(value)
          status:set(ok and "" or why)
        end),
      kit.subtitle { id = "look-status", font_size = theme.size.small, color = function() return C.error end, width = inner,
        visible = function() return status:get() ~= "" end, text = function() return status:get() end },
    },
    P.section { id = "look-desktop", width = w, title = "Desktop",
      toggle("look-sync", inner, "Keep GTK and Qt in step", "The mode, cursor and icons reach every toolkit", "sync", "appearance.sync"),
      label("Cursor", inner),
      picker("look-cursor", inner, "appearance.cursor_theme", function() return model.installed:get().cursors end, "As the desktop has it"),
      choice("look-cursor-size", inner, "appearance.cursor_size", model.CURSOR_SIZES),
      label("Icons", inner),
      picker("look-icons", inner, "appearance.icon_theme", function() return model.installed:get().icons end, "As the desktop has it"),
    },
  }
end

return V
