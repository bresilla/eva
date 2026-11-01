-- The wallpaper picker: a preview that changes through the chosen transition,
-- where the picture goes, and the folder as a grid; a second tab holds what the
-- shell does with pictures. `state` is Lule's page model, `pictures` the
-- wallpaper model.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local config = require("config")
local P = require("themes.layouts.page")
local swaps = require("themes.wallpaper_swap")
local thumbs = require("wallpaper_thumbs")
local C, S = theme.color, theme.space

local V = {}

local function get(v) if type(v) == "function" then return v() end return v end
local function basename(path) return (path or ""):match("([^/]+)$") or "" end

--- Rows of buttons from `items` (P.buttons specs), `per` to a row.
local function chunks(id, width, items, per)
  local rows = { width = width, gap = S.s }
  for start = 1, #items, per do
    local row = { id = id .. "-" .. start, width = width }
    for i = start, math.min(start + per - 1, #items) do row[#row + 1] = items[i] end
    rows[#rows + 1] = P.buttons(row)
  end
  return ui.Column(rows)
end

--- A choice of one setting: `key` holds a value of `choices` (`{ value, label }`).
local function choice(id, width, key, choices, per)
  local items = {}
  for _, entry in ipairs(choices) do
    local value = entry[1]
    items[#items + 1] = { id = id .. "-" .. tostring(value), label = entry[2], group = id,
      selected = function() return config.get(key) == value end,
      on_clicked = function() config.set(key, value) end }
  end
  return chunks(id, width, items, per or #items)
end

local function toggle(id, width, title, subtitle, icon, key)
  local on = function() return config.get(key) == true end
  return P.row { id = id, width = width, icon = icon, title = title, subtitle = subtitle, on = on,
    trailing = P.switch { id = id .. "-switch", name = title, on = on,
      on_toggled = function(now) config.set(key, now == true) end } }
end

-- ------------------------------------------------------------------ tiles --

local function tile_view(state, pictures, cell_w, cell_h)
  return function(row, s)
    local function now() return s.row() or row end
    local function selected() return state.selected:get() == now().path end
    local radius = function() return kit.round(selected() and S.xl or S.m) end
    local face = ui.ClipRect { x = S.xs, y = S.xs, width = cell_w - 2 * S.xs, height = cell_h - 2 * S.xs,
      radius = radius, scale = function() return selected() and 0.94 or 1 end,
      behavior = { radius = theme.spring.fast, scale = theme.spring.fast },
      ui.Rect { anchors = { fill = true }, color = function() return C.surfaceContainerHighest end },
      ui.Image { anchors = { fill = true }, fill_mode = "preserve_aspect_crop",
        source = function()
          thumbs.made:get()
          return thumbs.get(now().path, now().modified)
        end },
      ui.Item { anchors = { top = true, right = true, top_margin = S.xs, right_margin = S.xs }, width = S.l, height = S.l,
        visible = function() return pictures.favourite(now().path) end,
        kit.icon("favorite", 16, function() return C.primary end, { anchors = { center_in = true }, fill = true }) },
    }
    local mark = ui.Rect { x = S.xxs, y = S.xxs, width = cell_w - 2 * S.xxs, height = cell_h - 2 * S.xxs,
      radius = function() return kit.round(S.xl + S.xxs) end, color = "transparent", border_width = 2,
      border_color = function() return C.primary end, visible = selected }
    local area = ui.Item { id = "wallpaper-thumb-" .. tostring(row.key), width = cell_w, height = cell_h, face, mark }
    return area
  end
end

-- --------------------------------------------------------------- pictures --

local function pictures_tab(state, pictures, w, h)
  local inner = w
  local PREVIEW_H = math.min(math.floor(w * 9 / 16), S.xxl * 7)
  local swap = swaps.new { id = "wallpaper-preview" }
  local at = {}
  local frame = kit.surface { id = "wallpaper-preview-frame", width = inner, height = PREVIEW_H, clip = true,
    radius = kit.round(P.RADIUS), color = function() return C.surfaceContainerLowest end,
    swap.node,
    ui.Column { anchors = { center_in = true }, gap = S.s, align = "center",
      visible = function() return state.preview:get() == "" end,
      kit.icon("wallpaper", 32, kit.ink("accent")),
      kit.subtitle { font_size = theme.size.small, color = kit.ink("lo"),
        text = function() return state.selected:get() == "" and "Choose a wallpaper" or "Preparing preview…" end } },
  }
  -- Two fingers look closer at the picture.
  local zoom = require("pinch_zoom").attach { node = swap.node, area = frame }
  morf.effect("eva.wallpaper.preview", function()
    local source = state.preview:get()
    if source == "" then return end
    morf.time.timer(1, zoom.reset, false)
    swap.show(source, { kind = config.get("wallpaper.transition.kind"), width = inner, height = PREVIEW_H,
      x = at.x, y = at.y, soft = math.min(32, config.get("wallpaper.transition.softness")),
      time = math.min(800, config.get("wallpaper.transition.duration")), ease = theme.ease.emphasized,
      instant = config.get("appearance.reduce_motion") == true })
  end, { owner = frame })

  local name = ui.Item { width = inner, height = S.xl,
    kit.menu_label { id = "wallpaper-name", anchors = { vertical_center = true }, width = inner - S.TARGET - S.s,
      elide = "middle", font_size = theme.size.small, font_weight = 600,
      text = function() return basename(state.selected:get()) end },
    kit.action { id = "wallpaper-favourite", accessible_name = "Favourite", anchors = { right = true, vertical_center = true },
      width = S.TARGET, height = S.xl, cursor = "pointer",
      on_clicked = function() if state.selected:get() ~= "" then pictures.toggle_favourite(state.selected:get()) end end,
      kit.icon("favorite", 20, function()
        return pictures.favourite(state.selected:get()) and C.primary or C.onSurfaceVariant
      end, { anchors = { center_in = true }, fill = function() return pictures.favourite(state.selected:get()) end }) },
  }

  local target_items = {}
  for _, target in ipairs(pictures.targets()) do
    target_items[#target_items + 1] = { id = "wallpaper-target-" .. target.id:gsub("[^%w]", "-"), label = target.name,
      group = "wallpaper-target", selected = function() return pictures.target:get() == target.id end,
      on_clicked = function() pictures.target:set(target.id) end }
  end
  local targets = chunks("wallpaper-targets", inner, target_items, 3)
  local target_h = math.ceil(#target_items / 3) * P.BUTTON_H + (math.ceil(#target_items / 3) - 1) * S.s

  local apply = {
    { id = "wallpaper-shuffle", label = "Shuffle", icon = "shuffle", on_clicked = function() state.shuffle() end },
    { id = "wallpaper-apply", tone = "primary", label = function()
        if pictures.target:get() ~= "all" then return "Set here" end
        return pictures.can_color() and "Apply & colour" or "Set wallpaper"
      end,
      on_clicked = function(x, y)
        if state.selected:get() ~= "" then pictures.choose(state.selected:get(), x and { x = x, y = y } or nil) end
      end },
  }
  local foot = P.buttons { id = "wallpaper-foot", width = inner, table.unpack(apply) }

  local COLUMNS = inner >= S.xxl * 18 and 4 or 3
  local CELL_W = math.floor(inner / COLUMNS)
  local CELL_H = math.floor(CELL_W * 2 / 3)
  local rows = morf.list_model({})
  local used = PREVIEW_H + S.xl + target_h + P.BUTTON_H + 4 * S.s
  local function grid_h() return math.max(CELL_H, get(h) - used) end
  local grid = kit.widgets.grid_view { id = "wallpaper-grid", rows = rows, width = inner, height = grid_h,
    cell_width = CELL_W, cell_height = CELL_H, grid_columns = COLUMNS, focus_policy = "tab",
    accessible_name = "Wallpapers",
    delegate = tile_view(state, pictures, CELL_W, CELL_H),
    on_activated = function(i)
      local row = rows:get(i)
      if not row then return end
      at.x, at.y = ((i - 1) % COLUMNS + 0.5) * CELL_W, PREVIEW_H
      state.select(row.path)
    end }
  morf.effect("eva.wallpaper.rows", function()
    local out = {}
    for i, file in ipairs(state.files:get()) do
      out[i] = { key = file.path, path = file.path, name = file.name, modified = file.modified }
    end
    rows:replace(out, "key")
  end, { owner = frame })
  local empty = kit.subtitle { width = inner, wrap = true, horizontal_alignment = "center", font_size = theme.size.small,
    color = kit.ink("lo"), visible = function() return #state.files:get() == 0 end, y = S.xl,
    text = "No images in this folder. Set one on the Lule page." }

  return ui.Column { id = "wallpaper-pictures", width = inner, gap = S.s,
    frame, name, targets,
    ui.Item { width = inner, height = grid_h, grid, empty },
    foot }
end

-- ---------------------------------------------------------------- options --

local function slot(id, width, title, icon, which, state, pictures)
  local key = "wallpaper." .. which
  return P.row { id = id, width = width, icon = icon, title = title,
    subtitle = function()
      local path = config.get(key)
      return path ~= "" and basename(path) or "The usual picture"
    end,
    trailing = P.button { id = id .. "-use", label = function() return config.get(key) ~= "" and "Clear" or "Use selected" end,
      on_clicked = function()
        pictures.set_timed(which, config.get(key) ~= "" and "" or state.selected:get())
      end } }
end

local function options_tab(state, pictures, w, h)
  local inner = P.inner(w)
  local narrow = inner < S.xxl * 16
  local kinds = { { "random", "Random" } }
  for _, kind in ipairs(swaps.KINDS) do kinds[#kinds + 1] = { kind.id, kind.name } end
  local intervals = {}
  for _, entry in ipairs(pictures.INTERVALS) do intervals[#intervals + 1] = entry end
  return P.page { id = "wallpaper-options", width = w, height = h,
    P.section { id = "wallpaper-painter", width = w, title = "On the desktop",
      toggle("wallpaper-draw", inner, "Eva paints the desktop", function() return pictures.painter_note() end,
        "format_paint", "wallpaper.draw"),
      kit.subtitle { font_size = theme.size.small, color = kit.ink("lo"), text = "Fill", height = S.l, width = inner },
      choice("wallpaper-fit", inner, "wallpaper.fit", pictures.FITS),
      kit.subtitle { font_size = theme.size.small, color = kit.ink("lo"), text = "Parallax across workspaces",
        height = S.l, width = inner },
      choice("wallpaper-parallax", inner, "wallpaper.parallax", pictures.PARALLAX),
      toggle("wallpaper-glow", inner, "Glow with the music", "The picture brightens on every beat", "graphic_eq", "wallpaper.glow"),
      P.row { id = "wallpaper-xray", width = inner, icon = "flare", title = "A second picture under the pointer",
        subtitle = function() return basename(config.get("wallpaper.xray")) ~= "" and basename(config.get("wallpaper.xray")) or "Off" end,
        trailing = P.button { id = "wallpaper-xray-use",
          label = function() return config.get("wallpaper.xray") ~= "" and "Clear" or "Use selected" end,
          on_clicked = function() config.set("wallpaper.xray", config.get("wallpaper.xray") ~= "" and "" or state.selected:get()) end } },
    },
    P.section { id = "wallpaper-transition", width = w, title = "Transition",
      choice("wallpaper-transition", inner, "wallpaper.transition.kind", kinds, narrow and 3 or 5),
      choice("wallpaper-duration", inner, "wallpaper.transition.duration",
        { { 600, "Quick" }, { 1100, "Steady" }, { 2000, "Slow" } }),
      choice("wallpaper-softness", inner, "wallpaper.transition.softness",
        { { 2, "Sharp" }, { 24, "Soft" }, { 72, "Feathered" } }),
      toggle("wallpaper-startup", inner, "When the shell starts", "The first picture arrives the same way", "play_arrow",
        "wallpaper.transition.startup"),
    },
    P.section { id = "wallpaper-slideshow", width = w, title = "Slideshow",
      toggle("wallpaper-slides", inner, "Change by itself", function() return pictures.folder() end, "slideshow",
        "wallpaper.slideshow.on"),
      choice("wallpaper-interval", inner, "wallpaper.slideshow.interval", intervals, narrow and 4 or 7),
      choice("wallpaper-order", inner, "wallpaper.slideshow.order", { { "shuffle", "Shuffle" }, { "name", "By name" } }),
      toggle("wallpaper-slide-colors", inner, "Colours follow", "Lule colours each picture", "palette",
        "wallpaper.slideshow.colors"),
      toggle("wallpaper-slide-deep", inner, "Folders inside", "Look in the folder's folders too", "folder_open",
        "wallpaper.slideshow.recursive"),
      toggle("wallpaper-slide-favourites", inner, "Favourites only", "Marked pictures alone", "favorite",
        "wallpaper.slideshow.favourites"),
      toggle("wallpaper-slide-pause", inner, "Hold when busy", "Nothing changes behind a fullscreen window or a lock",
        "pause_circle", "wallpaper.slideshow.pause"),
      P.buttons { id = "wallpaper-slide-steps", width = inner,
        { id = "wallpaper-previous", label = "Previous", icon = "chevron_left", on_clicked = function() pictures.step(-1) end },
        { id = "wallpaper-next", label = "Next", icon = "chevron_right", on_clicked = function() pictures.step(1) end },
      },
    },
    P.section { id = "wallpaper-timed", width = w, title = "Day and night",
      slot("wallpaper-day", inner, "Light", "light_mode", "day", state, pictures),
      slot("wallpaper-night", inner, "Dark", "dark_mode", "night", state, pictures),
    },
  }
end

--- The page at `w` x `h`.
function V.build(state, pictures, w, h)
  local tab = morf.signal("eva.wallpaper.tab", "pictures")
  local tabs = P.buttons { id = "wallpaper-tabs", width = w,
    { id = "wallpaper-tab-pictures", label = "Pictures", icon = "photo_library", group = "wallpaper-tab",
      selected = function() return tab:get() == "pictures" end, on_clicked = function() tab:set("pictures") end },
    { id = "wallpaper-tab-options", label = "Options", icon = "tune", group = "wallpaper-tab",
      selected = function() return tab:get() == "options" end, on_clicked = function() tab:set("options") end },
  }
  local function body_h() return math.max(0, get(h) - P.BUTTON_H - S.s) end
  return ui.Column { id = "wallpaper-page", width = w, height = h, gap = S.s,
    tabs,
    ui.Item { width = w, height = body_h,
      ui.Item { width = w, height = body_h, visible = function() return tab:get() == "pictures" end,
        pictures_tab(state, pictures, w, body_h) },
      ui.Item { width = w, height = body_h, visible = function() return tab:get() == "options" end,
        options_tab(state, pictures, w, body_h) },
    },
  }
end

return V
