-- The launcher's view: a panel floating in the middle of the screen.
--
-- A caption names what is being searched and counts what was found; the
-- search sits under it and stays there; the results stack below, and the
-- panel grows and shrinks with them. The mode shows as a badge at the
-- field's head, an M3 shape that morphs from mode to mode. What the
-- prefixes do is a legend outside the panel, beside it. An instrument
-- theme (Tsugumori) numbers the rows and brackets the
-- panel, the field and the legend. Searching, choosing and running belong
-- to the controller.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local rubber = require("themes.rubber_band")
local C = theme.color
local S = theme.space
local V = {}

-- The badge of what is not a mode: the shape it morphs to, and the glyph on it. A
-- mode brings its own.
local BADGES = {
  Search = { "circle", "search" }, Apps = { "cookie9", "apps" }, Commands = { "soft_burst", "bolt" },
  Actions = { "soft_burst", "bolt" },
}

-- The prefixes the legend lists, most useful first.
local CHIPS = {
  { "=", "Calc" }, { "/", "Files" }, { "?", "Web" }, { "@", "Win" }, { "!", "Sys" }, { ":", "Emoji" },
  { ";", "Clip" }, { ">", "More" },
}

function V.build(M)
  local row_of = M.row_of
  local responsive = require("responsive")
  local grid_view = require("themes").view("launcher_grid")
  local preview_view = require("themes").view("launcher_preview")
  local WIDTH, WIDE = responsive.fit(620, 8), 1180
  local PAD = 12
  local SEARCH = 50
  local HEAD = 30
  local INSTRUMENT = theme.appearance.id == "tsugumori"
  local NUMBER = INSTRUMENT and 26 or 0
  local ROW, ROW_GAP = 48, 2
  local HEADER = 28
  local HERO = 92
  local EMPTY = 96
  local CAROUSEL = 196
  local SLOT, SLOT_ON = 224, 280
  local INNER = WIDTH - 2 * PAD
  local PANE, PANE_H = 340, 372
  local THUMBNAIL_LIMIT = 4 * 1024 * 1024
  -- The grid: as wide as the desk lets it, up to this.
  local GRID_MAX = 960
  local ALPHABET = theme.space.xl
  local GRID_ROOM = responsive.fit(GRID_MAX, 8) - 2 * PAD - ALPHABET
  local COLUMNS = math.max(3, math.min(GRID_ROOM // grid_view.CELL_MIN,
    math.ceil(GRID_ROOM / grid_view.CELL_MAX)))
  local CELL = math.min(grid_view.CELL_MAX, GRID_ROOM // COLUMNS)
  local TILES = COLUMNS * CELL
  local GRID_W_FIT = TILES + 2 * PAD + ALPHABET
  M.columns:set(COLUMNS)

  local function wide() return M.mode:get() == "wallpapers" end
  local function gridded() return M.mode:get() == "grid" end
  local function wide_width()
    local _, _, desk_w = require("bar").desk()
    return math.max(WIDTH, math.min(WIDE, (desk_w or WIDE) - 80))
  end
  local function pane_room() return responsive.desk_width() >= WIDTH + PANE + 80 end
  local function previewing() return M.previewed() ~= nil end
  local function pane_beside() return previewing() and pane_room() end
  local function pane_over() return previewing() and not pane_room() end
  local function width()
    if wide() then return wide_width() end
    if gridded() then return GRID_W_FIT end
    return pane_beside() and WIDTH + PANE or WIDTH
  end
  local function chips_height() return gridded() and grid_view.CHIPS_H or 0 end

  local function entry_height(entry)
    if not entry then return ROW end
    if entry.kind == "header" then return HEADER end
    if entry.kind == "hero" then return HERO end
    if entry.kind == "tiles" then return grid_view.CELL_H end
    return ROW
  end
  --- Where entry `index` starts in the list, and how tall it is.
  local function entry_span(index)
    local y = 0
    for i = 1, index - 1 do y = y + entry_height(M.results:get(i)) + ROW_GAP end
    return y, entry_height(M.results:get(index))
  end
  local function list_height()
    local n = M.count:get()
    if n <= 0 then return EMPTY end
    local y, h = entry_span(n)
    return y + h
  end

  local SHEET_TOP = theme.space.xl
  local function top_margin()
    if responsive.sheets() then return SHEET_TOP end
    local _, _, _, h = require("bar").desk()
    return math.floor(h * 0.16)
  end
  -- As much of the list as the output has room for; the rest scrolls.
  local function view_height()
    if not M.opened:get() then return EMPTY end
    local _, _, _, desk_h = require("bar").desk()
    desk_h = desk_h or 1080
    local tall = gridded() or responsive.sheets()
    local room = (tall and (desk_h - 2 * top_margin()) or math.floor(desk_h * 0.66)) - HEAD - SEARCH - 3 * PAD - chips_height()
    if gridded() then return math.max(ROW, room) end
    if pane_over() then return math.max(ROW, room) end
    if pane_beside() then return math.max(ROW, math.min(room, math.max(PANE_H, list_height()))) end
    return math.max(ROW, math.min(list_height(), room))
  end
  local function body_height() return wide() and CAROUSEL or view_height() end
  local TOP = PAD + HEAD + SEARCH + PAD
  local function body_top() return TOP + chips_height() end
  local function height() return body_top() + body_height() + PAD end
  -- The rows' heights, which the controller reads before the panel is built.
  M.row_heights = { header = HEADER + ROW_GAP, hero = HERO + ROW_GAP, row = ROW + ROW_GAP,
    tiles = grid_view.CELL_H + ROW_GAP }

  -- The search field once there is one, and the focus asked for till then.
  local field
  local focused = false

  -- The panel itself, built when the launcher first opens or, before that,
  -- while the shell is idle.
  local function build()
    -- ------------------------------------------------------------------ rows --

    local function centred(node) return kit.centred(32, 32, node) end
    -- A picture too big to decode for a row's corner.
    local function small_picture(path)
      local ok, stat = pcall(morf.fs.stat, path)
      return ok and type(stat) == "table" and (stat.size or math.huge) < THUMBNAIL_LIMIT
    end
    local function row_icon(row)
      if row.glyph then return centred(kit.text { text = row.glyph, font_size = 24 }) end
      local paint = row.swatch or (row.kind == "scheme" and row.color)
      if paint then
        local ok, color = pcall(morf.color, paint)
        return centred(kit.shape {
          width = 26, height = 26, shape = "cookie9", color = ok and color or paint,
        })
      end
      if row.kind == "scheme" then
        return centred(kit.icon("wallpaper", 26, function() return C.onSurfaceVariant end))
      end
      if row.kind == "calc" then
        return centred(kit.icon("function", 28, function() return C.onSurface end))
      end
      if row.image and small_picture(row.image) then
        return ui.Image { width = 32, height = 32, source = row.image, source_width = 64,
          fill_mode = "preserve_aspect_crop" }
      end
      if row.image then return centred(kit.icon("image", 26, function() return C.onSurfaceVariant end)) end
      if row.kind == "action" or row.kind == "variant" or row.material then
        return centred(kit.icon(row.material or row.icon, 26, function() return C.onSurfaceVariant end))
      end
      local hit = M.icon(row.icon)
      if hit and hit.name then
        return ui.Icon { width = 32, height = 32, name = hit.name, source_width = 64, source_height = 64 }
      elseif hit and hit.path then
        return ui.Image { width = 32, height = 32, source = hit.path, fill_mode = "preserve_aspect_fit" }
      end
      return centred(kit.icon("apps", 26, function() return C.onSurfaceVariant end))
    end

    local function index_of(key)
      for i = 1, M.results:len() do
        if M.results:get(i).key == key then return i end
      end
    end
    local function is_selected(key)
      local sel = M.results:get(M.selected:get())
      return sel ~= nil and sel.key == key
    end

    -- The chosen row's own hint: Tab, while it has other actions to list.
    local function hints(selected, has_actions)
      return ui.Row {
        anchors = { right = true, right_margin = 12, vertical_center = true }, gap = 8, align = "center",
        opacity = function() return (selected() and has_actions()) and 1 or 0 end,
        behavior = { opacity = { duration = theme.duration.small } },
        kit.text { text = "Actions", font_size = theme.size.smaller, color = kit.ink("lo") },
        kit.keycap { text = "Tab", height = 20 },
      }
    end

    -- The small word at a row's end, saying what kind of thing it is.
    local function tag(now, selected, has_actions)
      return kit.text {
        anchors = { right = true, right_margin = 12, vertical_center = true },
        text = function() return tostring(now().tag or "") end, font_size = theme.size.smaller,
        color = kit.ink("lo"), visible = function() return (now().tag or "") ~= "" and not (selected() and has_actions()) end,
      }
    end

    local results
    local carrier = grid_view.carrier(M, TILES)
    carrier.target.x, carrier.target.y = PAD, body_top
    local function header(entry)
      return ui.Item {
        id = "launcher-header-" .. entry.key,
        width = INNER, height = HEADER,
        enter = { opacity = 0, duration = theme.duration.small },
        kit.heading {
          id = "launcher-section-" .. entry.key, scope = "launcher", level = "section",
          viewport = function() return results end,
          anchors = { left = true, left_margin = 12, bottom = true, bottom_margin = 4 }, width = INNER - 24,
          elide = "right", text = entry.name, font_size = theme.size.smaller, font_weight = 600,
          color = kit.ink("lo"), ink = kit.ink("accent"),
        },
      }
    end

    --- The question and its answer, the answer in large type: what an
    --- arithmetic, a conversion or `>calc` comes back with.
    local function hero(entry)
      local row = row_of(entry) or entry
      local answer, question
      if row.kind == "calc" and not row.failed and row.result then
        answer = tostring(row.result)
        question = tostring(row.name):gsub("%s*=%s*[^=]*$", "")
      else
        answer = tostring(row.name or "")
        question = tostring(row.question or (row.kind ~= "calc" and row.description) or "")
      end
      return kit.action {
        id = "launcher-row-" .. entry.key,
        width = INNER, height = HERO, cursor = "pointer",
        enter = { opacity = 0, scale = 0.97, duration = theme.duration.small, easing = theme.ease.standard_decel },
        on_clicked = function() M.activate(row) end,
        kit.card {
          anchors = { fill = true, top_margin = 4, bottom_margin = 4 }, radius = kit.round(16),
          color = function() return C.surfaceContainerHigh end,
          ui.Column {
            anchors = { left = true, left_margin = 16, vertical_center = true }, gap = 2,
            kit.text {
              text = question, font_size = theme.size.small, width = INNER - 160, elide = "middle",
              color = function() return C.onSurfaceVariant end, visible = question ~= "",
            },
            ui.Row {
              gap = 8, align = "center",
              kit.text {
                text = "=", font_size = 28, visible = question ~= "",
                color = function() return C.primary end,
              },
              kit.text {
                id = "launcher-answer", text = answer, width = INNER - 190, elide = "middle",
                font_size = row.failed and theme.size.larger or 30, font_weight = 700,
                color = function() return row.failed and C.onSurfaceVariant or C.onSurface end,
              },
            },
          },
        },
      }
    end

    -- An ordinary row, rebindable: scrolled out of sight, the list view hands
    -- it the row scrolling in rather than building another.
    local serial = 0
    local function plain_row(entry)
      serial = serial + 1
      local bound = { entry = entry, row = row_of(entry) or entry }
      local revision = morf.signal("eva.launcher.row." .. serial, 0)
      local function now() revision:get() return bound.row end
      local function selected() revision:get() return is_selected(bound.entry.key) end
      local function has_actions() return M.has_actions(now()) and M.acting:get() == "" end
      -- What is left for the words once the row's end has what it shows.
      local function text_width()
        local trailing = (selected() and has_actions()) and 120 or ((now().tag or "") ~= "" and 76 or 0)
        return INNER - 70 - NUMBER - trailing
      end
      local icon = row_icon(bound.row)
      local icon_box = ui.Item { width = 32, height = 32, icon }
      local area = kit.action {
        id = "launcher-row-" .. entry.key,
        enter = kit.enter(index_of(entry.key)),
        width = INNER, height = ROW, cursor = "pointer",
        on_entered = function()
          local i = index_of(bound.entry.key)
          if i then M.selected:set(i) end
        end,
        on_clicked = function() M.activate(bound.row) end,
        on_long_pressed = function() M.act_on(bound.entry.key) end,
        ui.MouseArea { anchors = { fill = true }, accepted_buttons = "right",
          on_clicked = function() M.act_on(bound.entry.key) end },
        ui.Row {
          anchors = { left = true, left_margin = 8, vertical_center = true }, gap = 12, align = "center",
          INSTRUMENT and kit.text {
            width = NUMBER - 12, horizontal_alignment = "right", font_size = theme.size.smaller, font_weight = 600,
            text = function()
              revision:get()
              local i, n = index_of(bound.entry.key), 0
              for j = 1, (i or 0) do if M.results:get(j).kind ~= "header" then n = n + 1 end end
              return ("%02d"):format(n)
            end,
            color = function() return selected() and C.primary or C.onSurfaceVariant end,
          } or nil,
          icon_box,
          ui.Column {
            gap = 1,
            kit.text {
              id = "launcher-name", text = function() return tostring(now().name or "") end,
              spans = function() revision:get() return bound.entry.spans end,
              font_size = theme.size.normal, font_weight = 500, elide = "right",
              width = text_width,
              color = function() return C.onSurface end,
            },
            kit.text {
              text = function() return tostring(now().description or "") end, font_size = theme.size.smaller,
              visible = function() return (now().description or "") ~= "" end, elide = "right",
              width = text_width,
              color = function() return C.onSurfaceVariant end,
            },
          },
        },
        kit.icon("check", 20, function() return C.primary end, {
          anchors = { right = true, right_margin = 16, vertical_center = true },
          visible = function() return now().current and true or false end,
        }),
        tag(now, selected, has_actions),
        hints(selected, has_actions),
      }
      return area, function(next_entry)
        bound.entry, bound.row = next_entry, row_of(next_entry) or next_entry
        area.id = "launcher-row-" .. next_entry.key
        ui.destroy(icon, true)
        icon = row_icon(bound.row)
        ui.reparent(icon, icon_box)
        revision:set(revision:get() + 1)
      end
    end

    -- The selection changes no row's binding by itself; the rows that show
    -- hints read it through their revision, so they follow it here.
    local function delegate(entry)
      if entry.kind == "header" then return header(entry) end
      if entry.kind == "hero" then return hero(entry) end
      if entry.kind == "tiles" then
        return grid_view.row(M, entry, COLUMNS, { index_of = index_of, cell = CELL, carrier = carrier })
      end
      return plain_row(entry)
    end

    -- -------------------------------------------------------------- carousel --

    local MAX_SLOTS = 64
    -- The slots are a window on the wallpapers that follows the chosen one,
    -- so a folder of more than MAX_SLOTS still reaches its last picture.
    local function offset()
      local count = M.wall_count:get()
      return math.max(0, math.min(M.selected:get() - MAX_SLOTS // 2, count - MAX_SLOTS))
    end
    local function carousel()
      local slots = {}
      local motion = { duration = theme.duration.normal, easing = theme.ease.emphasized_decel }
      for i = 1, MAX_SLOTS do
        local function index() return offset() + i end
        local function wall() return index() <= M.wall_count:get() and M.walls[index()] or nil end
        local function on() return M.selected:get() == index() end
        -- Only pictures near the chosen one are loaded.
        local function near() return math.abs(M.selected:get() - index()) <= 4 end
        slots[i] = kit.action {
          id = "launcher-wallpaper-" .. i,
          height = CAROUSEL, cursor = "pointer",
          width = function() return on() and SLOT_ON or SLOT end,
          visible = function() return wall() ~= nil end,
          behavior = { width = motion },
          on_clicked = function()
            if on() then
              local w = wall()
              if w then M.activate(w) end
            else
              M.selected:set(index())
            end
          end,
          ui.Column {
            anchors = { horizontal_center = true }, gap = 8, align = "center",
            y = function() return on() and 8 or 26 end,
            behavior = { y = motion },
            kit.surface {
              radius = kit.round(14), clip = true,
              width = function() return on() and SLOT_ON - 16 or SLOT - 24 end,
              height = function() return on() and 152 or 122 end,
              behavior = { width = motion, height = motion },
              color = function() return C.surfaceContainerHigh end,
              ui.Image {
                anchors = { fill = true }, fill_mode = "preserve_aspect_crop",
                source = function()
                  local w = wall()
                  return (w and near()) and w.path or ""
                end,
              },
            },
            kit.text {
              text = function() local w = wall() return w and w.name or "" end,
              font_size = function() return on() and theme.size.normal or theme.size.small end,
              font_weight = 500, width = function() return on() and SLOT_ON - 16 or SLOT - 24 end,
              horizontal_alignment = "center", elide = "right",
              color = function() return on() and C.onSurface or C.onSurfaceVariant end,
            },
          },
        }
      end
      local strip = ui.Row {
        gap = 0,
        translate_x = function()
          local sel = math.max(1, M.selected:get() - offset())
          return (wide_width() - 2 * PAD) / 2 - ((sel - 1) * SLOT + SLOT_ON / 2)
        end,
        behavior = { translate_x = motion },
        table.unpack(slots),
      }
      return ui.Item {
        id = "launcher-wallpapers",
        x = PAD, y = TOP, width = function() return wide_width() - 2 * PAD end, height = CAROUSEL, clip = true,
        visible = wide,
        strip,
        kit.text {
          anchors = { center_in = true },
          text = function() return wide() and ("No wallpapers in " .. M.wallpaper_folder()) or "" end,
          font_size = theme.size.larger, color = function() return C.onSurfaceVariant end,
          visible = function() return M.wall_count:get() == 0 end,
        },
      }
    end

    -- ---------------------------------------------------------------- results --

    local empty = ui.Column {
      id = "launcher-empty",
      anchors = { center_in = true }, gap = 4, align = "center",
      visible = function() return M.count:get() == 0 end,
      kit.icon("search_off", 30, function() return C.onSurfaceVariant end),
      kit.text { text = "Nothing matches", font_size = theme.size.normal, font_weight = 500,
        color = function() return C.onSurface end },
    }

    -- Keeps the chosen row, and its section's heading, in view. The wheel and a
    -- finger move the list too; only the highlight moving brings it back.
    local scroll = morf.signal("eva.launcher.scroll", 0)
    local offset = 0
    local function scroll_to(y)
      y = math.max(0, math.min(y, math.max(0, list_height() - view_height())))
      offset = y
      scroll:set(y)
    end
    morf.effect("eva.launcher.scroll", function()
      local count = M.results:len()
      if wide() or count == 0 then if offset ~= 0 then scroll_to(0) end return end
      local at = math.max(1, math.min(M.selected:get(), count))
      local start, h = entry_span(at)
      local top = start
      local before = at > 1 and M.results:get(at - 1) or nil
      if before and before.kind == "header" then top = entry_span(at - 1) end
      local view, now = view_height(), offset
      local next_scroll = now
      if top < now then next_scroll = top end
      if start + h > now + view then next_scroll = start + h - view end
      if next_scroll ~= now then scroll_to(next_scroll) end
    end)

    -- A flick coasts on, slowing, until a finger comes down.
    local coasting
    local function stop_coasting()
      if coasting then coasting:cancel() coasting = nil end
    end
    local function coast(speed)
      stop_coasting()
      local FRAME = 16
      coasting = morf.time.timer(FRAME, function()
        speed = speed * 0.94
        scroll_to(offset - speed * FRAME / 1000)
        if math.abs(speed) < 40 then stop_coasting() end
      end, true)
    end

    -- The rows: the engine's list view, virtualised by each row's height and
    -- recycling within a kind, scrolled by the effect above.
    local list = ui.ListView {
      id = "launcher-list", model = M.results, delegate = delegate, width = INNER, height = 1,
      item_extent = ROW + ROW_GAP, size_field = "height", kind_field = "kind", overscan = 3,
    }
    morf.effect("eva.launcher.list", function()
      local y = scroll:get()
      list.height = view_height()
      list.width = gridded() and TILES or INNER
      morf.sync_view(list, y)
    end, { owner = list })

    -- The selection: one box in a distance field riding an item that springs
    -- from row to row, so it stretches towards the next row and settles there.
    local highlight = ui.Item {
      id = "launcher-highlight",
      x = function() return gridded() and (M.cell:get() - 1) * CELL or 0 end,
      width = function() return gridded() and CELL or INNER end,
      y = function() return (entry_span(math.max(1, M.selected:get()))) - scroll:get() end,
      height = function() local _, h = entry_span(math.max(1, M.selected:get())) return h end,
      behavior = { x = theme.spring.spatial, y = theme.spring.spatial, height = theme.spring.spatial },
      visible = function()
        local sel = M.results:get(M.selected:get())
        return M.count:get() > 0 and sel ~= nil and sel.kind ~= "hero"
      end,
    }
    local selection = kit.selection {
      id = "launcher-selection", track = highlight, radius = kit.round(14),
      color = function() return C.primary:alpha(0.14) end,
    }

    local pan_from, pan_pages, pages = 0, false, nil
    results = ui.Item {
      id = "launcher-results",
      x = PAD, y = body_top, width = function() return gridded() and TILES or INNER end, height = view_height,
      visible = function() return not wide() and not pane_over() end,
      clip = true,
      on_panned = function(phase, dx, dy, vx, vy, x, y)
        if phase == "begin" then
          if carrier.held() then return false end
          -- Sideways the grid turns to the next category, if there is one;
          -- past the last, or down from the top, the launcher shuts.
          if math.abs(dy) < math.abs(dx) then
            pan_pages = gridded() and pages.on_panned(phase, dx, dy, vx, vy, x, y) ~= false
            return pan_pages
          end
          if dy > 0 and offset <= 0 then return false end
          stop_coasting()
          pan_from = offset
          return true
        elseif pan_pages then
          pages.on_panned(phase, dx, dy, vx, vy, x, y)
          if phase ~= "update" then pan_pages = false end
        elseif phase == "update" then
          local room = math.max(0, list_height() - view_height())
          scroll_to(pan_from - dy)
          -- Past the end the list runs on elastically.
          scroll:set(rubber.between(pan_from - dy, 0, room, S.xxl * 3))
        else
          scroll:set(offset)
          coast(vy or 0)
        end
      end,
      ui.MouseArea { anchors = { fill = true }, z = -1,
        on_wheel = function(_, _, _, pixel_y)
          stop_coasting()
          scroll_to(offset + (pixel_y or 0))
        end },
      selection,
      highlight,
      list,
      empty,
    }
    local function neighbour(way)
      local chips = M.chips()
      for i, chip in ipairs(chips) do
        if chip.key == M.category:get() then
          local next_chip = chips[i + (way == "left" and 1 or -1)]
          return next_chip and next_chip.key
        end
      end
    end
    pages = require("themes.swipe_dismiss").new { id = "launcher.pages", node = results, axes = { x = true },
      ways = function() return { left = neighbour("left") ~= nil, right = neighbour("right") ~= nil } end,
      on_dismiss = function(way)
        M.choose_category(neighbour(way))
        pages.arrive(way)
      end,
    }

    -- The row and column of the grid at a point of the surface: the tile's
    -- entry index and its place in the row.
    local function grid_cell(x, y)
      local inside = y - (results.layout_y or 0) + scroll:get()
      local column = math.floor((x - (results.layout_x or 0)) / CELL) + 1
      for i = 1, M.results:len() do
        local start, h = entry_span(i)
        if inside >= start and inside < start + h then
          local entry = M.results:get(i)
          local tile = entry.cells and entry.cells[column]
          if tile then return i, column, tile end
          return nil
        end
      end
    end
    function carrier.under(x, y)
      local _, _, tile = grid_cell(x, y)
      return tile and tile.key
    end
    function carrier.hover(x, y)
      local at, column = grid_cell(x, y)
      if at then
        M.selected:set(at)
        M.cell:set(column)
      end
    end

    --- Goes to the first app of the grid whose name starts at `letter` or later.
    local function jump_to(letter)
      for i = 1, M.results:len() do
        local entry = M.results:get(i)
        for j, tile in ipairs(entry.cells or {}) do
          if tile.kind == "app" and tile.name:sub(1, 1):upper() >= letter then
            M.selected:set(i)
            M.cell:set(j)
            return
          end
        end
      end
    end
    local alphabet = grid_view.alphabet(M, view_height, jump_to)
    alphabet.x = PAD + TILES
    alphabet.y = body_top
    alphabet.visible = function() return gridded() and M.folder:get() == "" and M.category:get() == "" end

    local chips = grid_view.chips(M, TILES)
    chips.x = PAD
    chips.y = TOP
    chips.visible = gridded

    -- Quick look: beside the list where there is room, over it where not.
    local function pane_width() return pane_room() and PANE - PAD or INNER end
    local pane = preview_view.build(M, pane_width, view_height)
    pane.x = function() return pane_room() and WIDTH or PAD end
    pane.y = TOP
    pane.visible = previewing


    -- ----------------------------------------------------------------- legend --

    -- What the prefixes do, beside the panel: a strip of its own, read, not
    -- pressed (a press out there shuts the panel), and only after a wait.
    local prefixes = {}
    for i, spec in ipairs(CHIPS) do
      prefixes[i] = ui.Row {
        gap = 8, align = "center", height = 22,
        kit.text { text = spec[1], font_size = theme.size.small, font_weight = 700, width = 10,
          horizontal_alignment = "center", color = function() return C.primary end },
        kit.text { text = INSTRUMENT and spec[2]:upper() or spec[2], font_size = theme.size.smaller,
          color = kit.ink("lo") },
      }
    end
    local LEGEND_W = 96
    -- Shown only to someone who opened the launcher and then waited: five
    -- seconds untouched brings it; a key typed first keeps it away until the
    -- next opening.
    local LEGEND_DELAY = 5000
    local legend_due = morf.signal("eva.launcher.legend", false)
    local legend_timer, typed = nil, false
    local function stop_legend_timer()
      if legend_timer then legend_timer:cancel() legend_timer = nil end
    end
    morf.effect("eva.launcher.legend.open", function()
      local open = M.opened:get()
      stop_legend_timer()
      typed = false
      legend_due:set(false)
      if open then
        legend_timer = morf.time.timer(LEGEND_DELAY, function()
          legend_timer = nil
          if not typed and M.query:get() == "" then legend_due:set(true) end
        end, false)
      end
    end)
    morf.effect("eva.launcher.legend.typed", function()
      if M.query:get() ~= "" and M.opened:get() then
        typed = true
        stop_legend_timer()
        legend_due:set(false)
      end
    end)
    local legend = ui.Item {
      id = "launcher-legend",
      x = function() return width() + 10 end, y = 0, width = LEGEND_W, height = #CHIPS * 22 + 20,
      opacity = function()
        -- And only where there is room beside the panel for it.
        local room = (require("responsive").desk_width() - width()) / 2 >= LEGEND_W + 16
        return (room and legend_due:get() and M.opened:get() and not wide() and not gridded()
          and M.acting:get() == "") and 1 or 0
      end,
      behavior = { opacity = { duration = theme.duration.normal } },
      ui.Rect {
        anchors = { fill = true }, radius = INSTRUMENT and 0 or 14,
        color = function() return C.surface:alpha(0.92) end,
        border_width = 1, border_color = kit.stroke("quiet"),
      },
      kit.decor("corners", { length = 7 }) or ui.Item {},
      ui.Column {
        anchors = { left = true, left_margin = 12, top = true, top_margin = 8 }, gap = 0,
        table.unpack(prefixes),
      },
    }

    -- ----------------------------------------------------------------- header --

    local function caption(id, caption_width)
      return kit.caption {
        id = id,
        x = PAD + 4, y = PAD + 8, width = caption_width,
        text = function() return INSTRUMENT and ((M.mode_name()) .. " //"):upper() or (M.mode_name()) end,
        note = function()
          local n = 0
          for i = 1, M.results:len() do
            local entry = M.results:get(i)
            if entry.cells then n = n + #entry.cells
            elseif entry.kind ~= "header" then n = n + 1 end
          end
          if wide() then n = M.wall_count:get() end
          return INSTRUMENT and ("%02d MATCHES"):format(n) or (n == 1 and "1 result" or n .. " results")
        end,
      }
    end
    local header_row = caption("launcher-caption", INNER - 8)
    header_row.visible = function() return not gridded() end
    local grid_caption = caption("launcher-grid-caption", GRID_W_FIT - 2 * PAD - 8)
    grid_caption.visible = gridded

    -- ----------------------------------------------------------------- search --

    -- What the query is searching, as the badge at the field's head: an M3
    -- shape that morphs from one mode's to the next, the mode's glyph on it.
    local function badge_of()
      local name, material, shape = M.mode_name()
      if shape or not BADGES[name] then return { shape or "soft_burst", material or "search" } end
      return BADGES[name]
    end
    local badge = ui.Item {
      id = "launcher-badge",
      anchors = { left = true, left_margin = 8, vertical_center = true }, width = 36, height = 36,
      kit.shape {
        anchors = { fill = true }, shape = function() return badge_of()[1] end,
        color = function() return C.primaryContainer end,
      },
      kit.icon(function() return badge_of()[2] end, 20, function() return C.onPrimaryContainer end,
        { anchors = { center_in = true } }),
    }

    field = ui.TextInput {
      id = "launcher-search",
      anchors = { left = true, right = true, top = true, bottom = true, left_margin = 56, right_margin = 48 },
      vertical_alignment = "center", tab_navigation = false,
      font_family = theme.font, font_size = theme.size.larger,
      color = function() return C.onSurface end,
      placeholder = "Search everything…",
      placeholder_color = function() return C.onSurfaceVariant end,
      caret_color = function() return C.primary end,
      selection_color = function() return C.primary:alpha(0.35) end,
      on_text_changed = M.typed,
      on_accepted = function() M.activate(M.chosen()) end,
      on_escape = M.escape,
      on_key_pressed = M.key,
      on_key_released = M.release,
    }
    require("themes.kit.text_touch").attach(field)
    local clear = kit.action {
      id = "launcher-clear",
      width = 32, height = 32, cursor = "pointer",
      anchors = { right = true, right_margin = 8, vertical_center = true },
      visible = function() return M.query:get() ~= "" end,
      on_clicked = function() field.text = "" M.query:set("") field.focus = true end,
      kit.icon("close", 18, function() return C.onSurfaceVariant end, { anchors = { center_in = true } }),
    }
    -- Over the grid the on-screen keyboard waits for a press on the field.
    local summon = kit.action {
      id = "launcher-summon-keyboard", accessible_name = "Search",
      anchors = { fill = true }, visible = gridded,
      on_clicked = function()
        field.focus = true
        M.bring_keyboard()
      end,
    }
    local search = ui.Item {
      id = "launcher-field",
      anchors = { left = true, right = true, top = true, left_margin = PAD, right_margin = PAD, top_margin = PAD + HEAD },
      height = SEARCH,
      kit.surface {
        anchors = { fill = true }, radius = kit.round(SEARCH / 2),
        color = function() return C.surfaceContainerHigh end,
      },
      -- A rail along its foot that lights while something is typed.
      ui.Rect {
        anchors = { left = true, right = true, bottom = true, left_margin = INSTRUMENT and 0 or SEARCH / 2,
          right_margin = INSTRUMENT and 0 or SEARCH / 2 },
        height = 2, color = function() return C.primary end,
        opacity = function() return M.query:get() ~= "" and 1 or 0 end,
        behavior = { opacity = { duration = theme.duration.small } },
      },
      kit.decor("corners", { length = 8 }) or ui.Item {},
      badge,
      field,
      summon,
      clear,
    }

    -- The wallpapers' strip is built the first time the launcher shows them.
    local walls = morf.signal("eva.launcher.walls.built", wide())
    morf.effect("eva.launcher.walls.build", function()
      if wide() and not walls:get() then walls:set(true) end
    end)
    local content = ui.Item {
      anchors = { fill = true },
      -- Pulled down, or back toward the side it came from, it follows the
      -- finger and shuts.
      on_panned = function(phase, ...)
        if phase == "begin" and carrier.held() then return false end
        return M.swipe.on_panned(phase, ...)
      end,
      -- The sheet's empty parts take presses too.
      ui.MouseArea { anchors = { fill = true }, z = -1 },
      -- An instrument's panel: a hairline frame, and L-brackets on its corners.
      INSTRUMENT and ui.Rect {
        anchors = { fill = true }, color = "transparent", border_width = 1, border_color = kit.stroke("quiet"),
      } or nil,
      kit.decor("corners", { length = 14, inset = 4 }) or ui.Item {},
      header_row,
      grid_caption,
      chips,
      results,
      alphabet,
      pane,
      carrier.node,
      ui.Loader {
        anchors = { fill = true }, keep = true,
        active = function() return walls:get() end,
        source = function() return ui.Item { anchors = { fill = true }, carousel() } end,
      },
      search,
      legend,
      preview_view.large(M, width, height),
    }
    field.text = M.query:get()
    field.cursor_position = #field.text
    field.focus = focused
    return content
  end

  return {
    content = build, width = width, height = height, pane_room = pane_room,
    set_query = function(text, select_it)
      if field then
        field.text = text
        field.cursor_position = #text
        if select_it then field:select_all() end
      end
    end,
    focus = function(on)
      focused = on
      if field then field.focus = on end
    end,
    props = responsive.sheets() and {
      anchors = { top = true, horizontal_center = true, top_margin = top_margin() },
      behavior = { width = theme.spring.spatial, height = theme.spring.spatial },
    } or {
      -- On a desk it keeps clear of the side panels (shell/panel_room.lua).
      anchors = { top = true, top_margin = top_margin() },
      x = function()
        if not M.opened:get() then return 0 end
        return (require("panel_room").span(width()))
      end,
      behavior = { x = theme.spring.spatial, width = theme.spring.spatial, height = theme.spring.spatial },
    },
  }
end
return V
