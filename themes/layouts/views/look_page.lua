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
local accents

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

-- Colours of one tone round the wheel, each pressed to make it the source.
function accents(model, width)
  local list = model.accents()
  local cell = math.floor((width - (#list - 1) * S.s) / #list)
  local row = { id = "look-accents", gap = S.s, align = "center" }
  for _, entry in ipairs(list) do
    local function chosen() return config.get("theme.source") == entry.color end
    row[#row + 1] = kit.action { id = "look-accent-" .. entry.hue, accessible_name = "Hue " .. entry.hue,
      width = cell, height = S.TARGET, cursor = "pointer",
      on_clicked = function() config.set("theme.source", entry.color) end,
      ui.Rect { anchors = { fill = true }, radius = function() return kit.round(chosen() and S.m or S.xl) end,
        color = entry.color, behavior = { radius = theme.spring.fast } } }
  end
  return ui.Row(row)
end

-- A look saved by name: a field for the name, then what has been kept.
local function profiles_section(w, inner)
  local profiles = require("profiles_model")
  local rows = morf.list_model({})
  local name = morf.signal("eva.look.profile.name", "")
  local node, handle = kit.text_field("entry", { id = "look-profile-name", x = S.s, y = S.xs, width = inner - 2 * S.s,
    height = P.BUTTON_H - 2 * S.xs, font_family = theme.font, font_size = theme.size.small, placeholder = "A name for this look",
    color = function() return C.onSurface end, placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(0.25) end,
    on_text_changed = function(value) name:set(value) end })
  local field = kit.surface { width = inner, height = P.BUTTON_H, radius = kit.round(S.m),
    color = function() return C.surfaceContainerHighest end, node }
  local list = ui.Repeater { as = "column", gap = S.s, model = rows, delegate = function(row)
    return ui.Row { width = inner, gap = S.s, align = "center",
      P.button { id = "look-profile-load-" .. row.key, label = row.key, icon = "style", width = inner - P.BUTTON_H - S.s,
        on_clicked = function() profiles.load(row.key) end },
      kit.action { id = "look-profile-remove-" .. row.key, accessible_name = "Remove " .. row.key, width = P.BUTTON_H,
        height = P.BUTTON_H, cursor = "pointer", on_clicked = function() profiles.remove(row.key) end,
        kit.icon("close", 20, kit.ink("lo"), { anchors = { center_in = true } }) } }
  end }
  local section = P.section { id = "look-profiles", width = w, title = "Saved looks", field,
    P.button { id = "look-profile-save", label = "Keep this look", icon = "bookmark_add", width = inner,
      on_clicked = function()
        if profiles.save(name:get()) then handle.text = "" name:set("") end
      end },
    list }
  morf.effect("eva.look.profiles", function()
    local out = {}
    for i, profile in ipairs(profiles.list()) do out[i] = { key = profile.name } end
    rows:replace(out, "key")
  end, { owner = section })
  return section
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
      kit.subtitle { id = "look-contrast", font_size = theme.size.small, color = kit.ink("lo"), width = inner,
        visible = function() return model.contrast_note() ~= "" end, text = model.contrast_note },
      label("Or one colour", inner),
      accents(model, inner),
      toggle("look-song", inner, "Follow the song", "Album art colours the shell while music plays", "music_note", "theme.follow_song"),
      toggle("look-black", inner, "Pure black", "Dark surfaces all the way down, for OLED", "contrast", "appearance.pure_black"),
      label("Scheme", inner),
      choice("look-variant", inner, "theme.variant", model.VARIANTS, 4),
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
    profiles_section(w, inner),
    P.section { id = "look-share", width = w, title = "Schemes of your own",
      kit.subtitle { font_size = theme.size.small, color = kit.ink("lo"), width = inner, wrap = true,
        text = "A file in " .. require("themes.schemes").folder() .. " joins the sources after a restart." },
      P.button { id = "look-export", label = "Save these colours as a scheme", icon = "save", width = inner,
        on_clicked = function()
          local path, why = model.export("saved")
          status:set(path and "" or tostring(why))
        end },
    },
  }
end

return V
