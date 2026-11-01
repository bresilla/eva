-- Launcher state and actions. Theme views own its geometry and presentation.
local morf = require("morf")
local config = require("config")
local apps = require("apps")
local drawer = require("drawer")
local M = {}
local view

M.query = morf.signal("eva.launcher.query", "")
M.selected = morf.signal("eva.launcher.selected", 1)
M.results = morf.list_model({})
-- How tall each kind of row is, with the gap under it: the results view
-- lists them virtualised by these, and its build sets its own.
M.row_heights = { header = 32, hero = 118, row = 52, tiles = 112 }
-- Bumped once the view has set its own heights, so the rows found before
-- it was built are found again at those.
local heights_set = morf.signal("eva.launcher.heights", 0)
M.count = morf.signal("eva.launcher.count", 0)
M.mode = morf.signal("eva.launcher.mode", "apps")
-- The row whose actions are listed instead of the results (Tab, Ctrl+K),
-- by key; "" for none.
M.acting = morf.signal("eva.launcher.acting", "")
-- The carousel's pictures: `{ path, name }` each, and how many.
M.walls = {}
M.wall_count = morf.signal("eva.launcher.walls", 0)
-- Whether the chosen row is being looked at (Space), and the words shown across
-- the panel in large type ("" for none).
M.preview_open = morf.signal("eva.launcher.preview", false)
M.large_type = morf.signal("eva.launcher.large", "")
-- The grid: the folder open, the category chosen, and which tile of the chosen
-- row of tiles has the highlight.
M.folder = morf.signal("eva.launcher.folder", "")
M.category = morf.signal("eva.launcher.category", "")
M.cell = morf.signal("eva.launcher.cell", 1)
-- How many tiles a row of the grid holds; the view sets it.
M.columns = morf.signal("eva.launcher.columns", 4)

local function max_shown() return config.get("launcher.max_shown") end

local by_key = {}

--- The full row behind a model entry.
local function row_of(entry) return entry and by_key[entry.key] end

local function providers() return require("providers") end

-- The row with the highlight, by key, and the query it was found for.
local chosen_key, searched_query = nil, nil
-- Whether the highlight was walked there by a key since the last edit.
local walked = false
local active_mode

--- Tells the mode on show when `query` leaves it.
local function follow_mode(query)
  local route = providers().route
  local mode = route and route(query) or nil
  if active_mode and active_mode ~= mode and active_mode.leave then active_mode.leave() end
  active_mode = mode
end

--- The spans of `name` with the characters at `positions` drawn stronger.
local function spans_of(name, positions)
  if not positions or #positions == 0 then return nil end
  local marked = {}
  for _, at in ipairs(positions) do marked[at] = true end
  local spans, i, length = {}, 1, #name
  while i <= length do
    local on = marked[i] == true
    local start = i
    while i <= length and (marked[i] == true) == on do i = i + 1 end
    local piece = name:sub(start, i - 1)
    spans[#spans + 1] = on and { text = piece, weight = 800 } or piece
  end
  return spans
end

local function entry_of(row, hero, key)
  return {
    key = key .. (row.kind == "calc" and (":" .. row.name) or ""),
    kind = hero and "hero" or row.kind, id = row.id, name = row.name,
    description = row.description, icon = row.icon, material = row.material,
    swatch = row.swatch, glyph = row.glyph, question = row.question, image = row.image, tag = row.tag,
    spans = spans_of(tostring(row.name or ""), row.positions), pinned = row.pinned,
    height = hero and M.row_heights.hero or M.row_heights.row,
  }
end

-- ------------------------------------------------------------------- grid --

--- Whether the launcher is showing its icon grid: on a phone or a tablet, before
--- anything is typed, unless the setting says otherwise.
function M.grid_on()
  if not (M.opened and M.opened:get()) then return false end
  local layout = config.get("launcher.layout")
  if layout == "list" or M.query:get() ~= "" or M.acting:get() ~= "" then return false end
  if require("menus").source:get() ~= "" then return false end
  if layout == "grid" then return true end
  return require("responsive").sheets()
end

local function tile_row(key, cells)
  return { key = "tiles:" .. key, kind = "tiles", id = key, cells = cells, height = M.row_heights.tiles }
end

local function section(out, name, tiles, columns)
  if #tiles == 0 then return end
  if name then
    out[#out + 1] = { key = "header:" .. name, kind = "header", id = name, name = name, height = M.row_heights.header }
  end
  for i = 1, #tiles, columns do
    local cells = {}
    for j = i, math.min(i + columns - 1, #tiles) do cells[#cells + 1] = tiles[j] end
    out[#out + 1] = tile_row((name or "all") .. ":" .. i, cells)
  end
end

local function tile_of(row)
  by_key["tile:" .. row.id] = row
  return { key = "tile:" .. row.id, name = row.name, icon = row.icon, material = row.material, pinned = row.pinned,
    fresh = row.fresh, kind = row.kind, count = row.count }
end

local function tiles_of(list)
  local out = {}
  for _, row in ipairs(list) do out[#out + 1] = tile_of(row) end
  return out
end

--- The entries of the grid for `columns` tiles a row.
local function grid_entries(columns)
  local out = {}
  local grid = apps.grid and apps.grid(M.folder:get(), M.category:get()) or {}
  for _, part in ipairs(grid) do section(out, part.name, tiles_of(part.rows), columns) end
  return out
end

--- The chips over the grid: "All" and each category.
function M.chips()
  local out = { { name = "All", key = "" } }
  for _, category in ipairs(apps.categories and apps.categories() or {}) do
    out[#out + 1] = { name = category.name, key = category.name }
  end
  return out
end

--- Opens a folder of the grid ("" for none) or chooses a category.
function M.open_folder(name) M.folder:set(name) M.cell:set(1) end
function M.choose_category(name) M.category:set(name) M.folder:set("") M.cell:set(1) end

-- ----------------------------------------------------------------- search --

local function show_walls(found, mode)
  M.walls = found
  local current = require("wallpaper").current:get()
  local at = 1
  for i, w in ipairs(found) do
    by_key["wallpaper:" .. w.id] = w
    if w.path == current then at = i end
  end
  M.results:replace({}, "key")
  M.count:set(0)
  M.wall_count:set(#found)
  M.mode:set(mode)
  M.selected:set(at)
end

-- The results follow the query, and whatever lands for it later: the highlight
-- stays on its row while the same search grows.
morf.effect("eva.launcher.search", function()
  heights_set:get()
  local q = M.query:get()
  local menus = require("menus")
  local found, mode
  local acting = M.acting:get()
  local owner = acting ~= "" and by_key[acting] or nil
  follow_mode(q)
  if owner then
    -- The action panel: the chosen row's actions, filtered by the field.
    found, mode = {}, "apps"
    local list = M.actions_of(owner)
    for i, a in ipairs(list) do
      if q == "" or a.name:lower():find(q:lower(), 1, true) then
        found[#found + 1] = { kind = "menu", id = acting .. ":action:" .. i, name = a.name,
          description = owner.name, material = a.material, icon = a.icon, run = a.run }
      end
    end
    found.cap = #found
  elseif M.grid_on() then
    local entries = grid_entries(M.columns:get())
    M.results:replace(entries, "key")
    M.count:set(#entries)
    M.wall_count:set(0)
    M.mode:set("grid")
    local first = 1
    while entries[first] and entries[first].kind == "header" do first = first + 1 end
    M.selected:set(entries[first] and first or 1)
    return
  elseif menus.source:get() ~= "" then
    found, mode = menus.search(q, config.get("launcher.max_results"))
    found.cap = config.get("launcher.max_results")
  else
    found, mode = apps.search(q, max_shown())
  end
  if mode == "wallpapers" then show_walls(found, mode) return end
  local out = {}
  local shown = 0
  local cap = found.cap or max_shown()
  for i = 1, #found do
    local row = found[i]
    local hero = row.id == "answer" or row.kind == "calc"
    if not hero and shown >= cap then break end
    local key = row.kind .. ":" .. row.id
    -- A model row is plain data; the row itself (an action's function
    -- among it) stays in Lua, by key.
    by_key[key] = row
    local entry = entry_of(row, hero, key)
    if row.kind == "header" then entry.height = M.row_heights.header end
    out[#out + 1] = entry
    by_key[entry.key] = row
    if not hero and row.kind ~= "header" then shown = shown + 1 end
  end
  M.results:replace(out, "key")
  M.count:set(#out)
  M.wall_count:set(0)
  M.mode:set(mode)
  local first = 1
  while out[first] and out[first].kind == "header" do first = first + 1 end
  local same = q == searched_query and chosen_key
  searched_query = q
  if same then
    for i, entry in ipairs(out) do
      if entry.key == chosen_key then first = i break end
    end
  end
  M.selected:set(out[first] and first or 1)
end)

-- What the highlight is on, for the search above to keep.
morf.effect("eva.launcher.chosen", function()
  local entry = M.results:get(M.selected:get())
  chosen_key = entry and entry.key or nil
end)

M.row_of = row_of
M.icon = apps.icon

--- Where the wallpapers are looked for, as a person would write it.
function M.wallpaper_folder()
  return apps.wallpaper_folder and require("lib.shell.launcher.rows").tilde(apps.wallpaper_folder()) or ""
end

local function wide() return M.mode:get() == "wallpapers" end
local function grid() return M.mode:get() == "grid" end
M.is_grid = grid

function M.set_query(text)
  walked = false
  M.query:set(text)
  if view then view.set_query(text) end
end

local opening_query

--- Opens the launcher with `text` in the field.
function M.open_on(text)
  if M.drawer.open:get() then M.set_query(text) return end
  opening_query = text
  M.drawer.set(true)
end

--- The field changed under the person's fingers. A space after walking the list
--- opens quick look and leaves the field as it was.
function M.typed(text)
  local before = M.query:get()
  if walked and text == before .. " " and M.toggle_preview() then
    view.set_query(before)
    return
  end
  walked = false
  if apps.history then apps.history.reset() end
  M.query:set(text)
end

--- Everything that can be done to `row`.
function M.actions_of(row)
  local p = providers()
  if p.actions_for then return p.actions_for(row) end
  return row.actions or {}
end

--- Whether `row` has an action panel.
function M.has_actions(row)
  if row.silent or row.kind == "header" then return false end
  if providers().actions_for then return true end
  return row.actions ~= nil and #row.actions > 0
end

local function remember(row)
  if not apps.history or row.silent or row.private then return end
  if not config.get("launcher.remember") then return end
  local q = M.query:get()
  local route = providers().route
  local mode = route and route(q) or nil
  if mode and mode.quiet then q = "" end
  apps.history.add(q, row.pin or row.id, tostring(row.name or ""))
end

function M.activate(row)
  if row and row.kind == "folder" then M.open_folder(row.id) return end
  M.acting:set("")
  if row then remember(row) end
  local next_step = apps.activate(row)
  if row and package.loaded.launcher_api then package.loaded.launcher_api.chosen(row, M.query:get()) end
  if next_step == "close" then
    M.drawer.set(false)
  elseif type(next_step) == "string" and next_step ~= "keep" then
    M.set_query(next_step)
  end
end

-- The list's choosing is a kit Collection (crates/morf-kit): it skips the
-- section headings, walks the wallpapers sideways, and answers the Page
-- keys; the view draws the rows.
local headers = function()
  local out = {}
  for i = 1, M.results:len() do
    if M.results:get(i).kind == "header" then out[#out + 1] = i end
  end
  return out
end
local choice = require("lib.kit.control").headless("Collection", {
  layout = "list",
  orientation = function() return wide() and "horizontal" or "vertical" end,
  count = function() return wide() and M.wall_count:get() or M.count:get() end,
  disabled = function() return wide() and {} or headers() end,
  current = function() return M.selected:get() end,
  page = 5,
  on_current_changed = function(i) M.selected:set(i) end,
})
M.choice = choice

local function tile_count()
  local entry = M.results:get(M.selected:get())
  return entry and entry.cells and #entry.cells or 1
end

local function move(delta)
  walked = true
  -- The carousel steps by itself: the Collection can keep the list's
  -- orientation across an empty search, and a wallpaper has no headings
  -- to skip anyway.
  if wide() then
    local count = M.wall_count:get()
    if count > 0 then M.selected:set(math.max(1, math.min(count, M.selected:get() + delta))) end
    return
  end
  local back, forth = "Up", "Down"
  for _ = 1, math.abs(delta) do
    if not choice.key(delta > 0 and forth or back) then break end
  end
  if grid() then M.cell:set(math.min(M.cell:get(), tile_count())) end
end
M.move = move

--- Moves the highlight sideways in the grid.
local function step_cell(delta)
  local cell = M.cell:get() + delta
  if cell >= 1 and cell <= tile_count() then M.cell:set(cell) return end
  local before = M.selected:get()
  move(delta > 0 and 1 or -1)
  if M.selected:get() ~= before then M.cell:set(delta > 0 and 1 or tile_count()) end
end

local function chosen()
  if wide() then return M.walls[M.selected:get()] end
  local entry = M.results:get(M.selected:get())
  if entry and entry.cells then
    local tile = entry.cells[M.cell:get()]
    return tile and by_key[tile.key]
  end
  return row_of(entry)
end
M.chosen = chosen

--- The row of tile `key`.
function M.tile_row(key) return by_key[key] end

--- The nth result, counting what can be picked.
local function nth(n)
  local seen = 0
  for i = 1, M.results:len() do
    local entry = M.results:get(i)
    if entry.kind == "tiles" then
      for j, tile in ipairs(entry.cells) do
        seen = seen + 1
        if seen == n then return by_key[tile.key], i, j end
      end
    elseif entry.kind ~= "header" then
      seen = seen + 1
      if seen == n then return row_of(entry), i end
    end
  end
end

--- Picks the nth result. True when there was one.
function M.pick(n)
  local row, at, cell = nth(n)
  if not row then return false end
  M.selected:set(at)
  if cell then M.cell:set(cell) end
  M.activate(row)
  return true
end

-- ---------------------------------------------------------------- preview --

--- The row being looked at, or nil: Space, or a row that shows itself, or a file
--- beside a pane with room.
function M.previewed()
  if wide() or M.acting:get() ~= "" then return nil end
  M.selected:get()
  local row = chosen()
  if not row or not row.preview then return nil end
  if M.preview_open:get() or row.auto_preview then return row end
  if config.get("launcher.preview_pane") and view and view.pane_room and view.pane_room() and row.path then return row end
  return nil
end

--- Opens or shuts quick look on the chosen row. True when there is something to
--- look at.
function M.toggle_preview()
  if M.preview_open:get() then M.preview_open:set(false) return true end
  local row = chosen()
  if row and row.preview then M.preview_open:set(true) return true end
  return false
end

-- ---------------------------------------------------------------- the keys --

function M.escape()
    if M.large_type:get() ~= "" then
      M.large_type:set("")
    elseif M.preview_open:get() then
      M.preview_open:set(false)
    elseif M.acting:get() ~= "" then
      M.acting:set("")
    elseif M.folder:get() ~= "" then
      M.open_folder("")
    elseif require("menus").back() then
      M.set_query("")
    else
      M.drawer.set(false)
    end
end

local function toggle_actions()
  if M.acting:get() ~= "" then
    M.acting:set("")
    return
  end
  local row = chosen()
  if not row or not M.has_actions(row) then return end
  local entry = M.results:get(M.selected:get())
  local key = entry and entry.key
  if entry and entry.cells then
    local tile = entry.cells[M.cell:get()]
    key = tile and tile.key
  end
  M.acting:set(key)
  M.set_query("")
end
M.toggle_actions = toggle_actions

--- Opens the action panel on the row `key`, as a long press or a right click does.
function M.act_on(key)
  if not by_key[key] or not M.has_actions(by_key[key]) then return end
  M.acting:set(key)
  M.set_query("")
end

--- Tab: the chosen row's completion, or the mode a word begins. True when it
--- completed something.
local function complete()
  local q = M.query:get()
  local row = chosen()
  if M.acting:get() == "" and row and row.complete and row.complete ~= q then
    M.set_query(row.complete)
    return true
  end
  local p = providers()
  if p.completing and q ~= "" then
    local mode = p.completing(q)
    if mode then
      M.set_query(p.mode_entry(mode))
      return true
    end
  end
  return false
end

-- Up in an empty box walks back through what was searched.
local function walk_history(delta)
  local history = apps.history
  if not history then return false end
  local empty = M.query:get() == ""
  local top = true
  for i = 1, M.selected:get() - 1 do
    if M.results:get(i) and M.results:get(i).kind ~= "header" then top = false end
  end
  if delta < 0 then
    if not (history.walking() or (empty and top)) then return false end
    local older = history.older()
    if older then M.set_query(older) end
    return history.walking()
  end
  if not history.walking() then return false end
  M.set_query(history.newer() or "")
  return true
end

-- The modes Ctrl+Tab goes through: nothing, then each of these.
local CYCLE = { "", "/", ";", "@", "!", ":", "?", "> " }

local function cycle(delta)
  local q = M.query:get()
  local at = 1
  for i, prefix in ipairs(CYCLE) do
    if prefix ~= "" and q:sub(1, #prefix) == prefix then at = i end
  end
  M.set_query(CYCLE[(at - 1 + delta) % #CYCLE + 1])
end

function M.key(_, _, modifiers, _, key)
  local mods = tostring(modifiers or "")
  local ctrl, alt, shift = mods:find("ctrl", 1, true), mods:find("alt", 1, true), mods:find("shift", 1, true)
  if (ctrl or alt) and key and key:match("^[1-9]$") then return M.pick(tonumber(key)) or true end
  if key == "Up" or (ctrl and key == "p") then
    if key == "Up" and walk_history(-1) then return true end
    move(-1)
    return true
  end
  if key == "Down" or (ctrl and key == "j") then
    if key == "Down" and walk_history(1) then return true end
    move(1)
    return true
  end
  if key == "Page_Up" or key == "Page_Down" then return choice.key(wide() and "" or key) end
  if key == "Tab" or key == "ISO_Left_Tab" then
    if ctrl then cycle(shift and -1 or 1) return true end
    if not complete() then toggle_actions() end
    return true
  end
  if (ctrl and key == "k") or key == "F10" or key == "Menu" then toggle_actions() return true end
  if ctrl and key == "u" then M.set_query("") return true end
  if ctrl and key == "g" then
    config.set("launcher.layout", config.get("launcher.layout") == "grid" and "list" or "grid")
    return true
  end
  if key == "F1" or (ctrl and key == "y") then M.toggle_preview() return true end
end
-- TextInput consumes horizontal arrow presses for its caret. Releases reach
-- the controller, so the wallpaper chooser and the grid can use them without an
-- engine hook.
function M.release(_, _, modifiers, _, key)
  if modifiers and modifiers ~= "" then return end
  if grid() then
    if key == "Left" then step_cell(-1) elseif key == "Right" then step_cell(1) end
    return
  end
  if not wide() then return end
  if key == "Left" then move(-1) elseif key == "Right" then move(1) else return end
  view.set_query(M.query:get())
end

local MODE_NAMES = {
  calculator = { "Calculator", "calculate" }, run = { "Run", "terminal" }, files = { "Files", "folder_open" },
  web = { "Web", "travel_explore" }, windows = { "Windows", "desktop_windows" }, system = { "System", "settings_power" },
  emoji = { "Emoji", "mood" }, clipboard = { "Clipboard", "content_paste" }, colour = { "Colour", "palette" },
}
local function mode_name()
  if M.acting:get() ~= "" then return "Actions", "bolt" end
  local menus = require("menus")
  if menus.source:get() == "apps" then return "Apps", "apps" end
  if menus.source:get() == "web" then return "Web", "language" end
  if menus.source:get() == "dmenu" then return menus.prompt(), "list" end
  if grid() then
    if M.folder:get() ~= "" then return M.folder:get(), "folder_open" end
    return M.category:get() ~= "" and M.category:get() or "Apps", "apps"
  end
  local q = M.query:get()
  local p = providers()
  local mode = p.route and p.route(q)
  if mode then return mode.name, mode.material, mode.shape end
  local what = p.PREFIXES[q:sub(1, 1)]
  if what and MODE_NAMES[what] then return MODE_NAMES[what][1], MODE_NAMES[what][2] end
  if q:sub(1, 1) == config.get("launcher.action_prefix") then return "Commands", "bolt" end
  return "Search", "search"
end
M.mode_name = mode_name
M.opened = morf.signal("eva.launcher.opened", false)
view = require("themes").view("launcher").build(M)
heights_set:set(1)
M.width = view.width
M.drawer = drawer.new {
  name = "launcher", edge = "center", width = view.width, height = view.height,
  content = view.content, props = view.props,
  -- Escape is the launcher's own: it backs out of a menu first.
  close_policy = "outside",
}
-- Without a real keyboard (a phone) the on-screen one comes up with the
-- launcher -- its field is the shell's own, which no program asks text
-- for -- and goes with it, when the launcher was what brought it. Over the grid
-- it waits for the field to be pressed.
local brought_keyboard = false
local function keyboard_attached()
  local ok, attached = pcall(function() return require("models.keyboards").attached() end)
  return not ok or attached ~= false
end

--- Brings the on-screen keyboard up, where there is no real one.
function M.bring_keyboard()
  local keyboard = package.loaded.keyboard
  if keyboard and not keyboard_attached() and not keyboard.drawer.open:get() then
    keyboard.drawer.set(true)
    brought_keyboard = true
  end
end

local was_open = false
morf.effect("eva.launcher.open", function()
  local open = M.drawer.open:get()
  M.opened:set(open)
  if open == was_open then return end
  was_open = open
  if open then
    apps.refresh()
    if opening_query then M.set_query(opening_query)
    elseif config.get("launcher.keep_query") then view.set_query(M.query:get(), true)
    else M.set_query("") end
    opening_query = nil
    -- A focused field brings the on-screen keyboard; over the grid it waits.
    local waits = M.grid_on() and not keyboard_attached()
    view.focus(not waits)
    if not waits then M.bring_keyboard() end
    -- It rests small while shut: it lands at its size, unstretched, as it opens.
    morf.time.timer(1, function()
      morf.animation.finish(M.drawer.panel, "height")
      morf.animation.finish(M.drawer.panel, "width")
    end, false)
  else
    view.focus(false)
    local menus = require("menus")
    if menus.finish then menus.finish(nil) end
    menus.open("")
    M.acting:set("")
    M.preview_open:set(false)
    M.large_type:set("")
    M.open_folder("")
    M.category:set("")
    if active_mode and active_mode.leave then active_mode.leave() end
    active_mode = nil
    if brought_keyboard and package.loaded.keyboard then package.loaded.keyboard.drawer.set(false) end
    brought_keyboard = false
  end
end)
return M
