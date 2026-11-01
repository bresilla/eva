-- The launcher's lists: installed applications, ranked by `morf.text.fuzzy`
-- and lifted by how often and how lately each was launched from here
-- (lib/util/frecency.lua); and, after the action prefix (">"), the shell's own
-- actions, and the pickers some of them open: "> scheme " (source
-- colours), "> variant " (Material 3 scheme variants), "> wallpaper " (the
-- pictures in the Lule folder) and "> calc " (calc.lua). A plain search goes
-- to universal.lua.

local morf = require("morf")
local frecency = require("lib.shell.launcher.frecency")
local history = require("lib.shell.launcher.history")
local pins = require("lib.shell.launcher.pins")
local run = require("lib.shell.launcher.run")
local rowkit = require("lib.shell.launcher.rows")
local config = require("config")
local calc = require("calc")

local M = {}

local index
local rows = {}
local by_id = {}
-- Whether the entries may have changed since they were last read.
local dirty = true
local watchers = {}

local function origin_of(entry)
  local source = entry.source or ""
  if source:find("flatpak", 1, true) then return "Flatpak" end
  if (entry.exec or ""):lower():find("%.appimage") then return "AppImage" end
  if source:find("snapd", 1, true) then return "Snap" end
  if source:find("/nix/", 1, true) or source:find(".nix-profile", 1, true) then return "Nix" end
  return nil
end
M.origin_of = origin_of

-- The ids seen before, so what appears after that wears a badge for a week.
local KNOWN_FOR = 7 * 86400
local known

local function read_known()
  if known then return known end
  known = {}
  local ok, text = pcall(morf.fs.read, morf.paths.state("eva-launcher-known.json"))
  local fine, data = pcall(morf.json.decode, ok and text or "")
  if fine and type(data) == "table" then known = data end
  return known
end

local function note_new(ids)
  local seen = read_known()
  local empty = next(seen) == nil
  local now, changed = morf.time.now(), false
  for _, id in ipairs(ids) do
    if not seen[id] then
      seen[id] = empty and 0 or now
      changed = true
    end
  end
  if changed then
    morf.fs.write(morf.paths.state("eva-launcher-known.json"), morf.json.encode(seen), { atomic = true, parents = true })
  end
end

local function is_new(id)
  local at = read_known()[id]
  return at ~= nil and at > 0 and morf.time.now() - at < KNOWN_FOR
end

--- Rings when an applications folder changes, so a launcher opening reads them
--- only then.
local function watch(folder)
  if watchers[folder] or not morf.fs.watch then return end
  local ok, handle = pcall(morf.fs.watch, folder, function() dirty = true end)
  if ok and handle then watchers[folder] = handle end
end

--- Reads the desktop entries again if something changed; `force` reads them
--- whatever. True when they changed.
function M.refresh(force)
  if not dirty and not force then return false end
  dirty = false
  if not index then
    local ok, made = pcall(morf.apps.entries)
    if not ok then
      morf.log("warn", "eva: cannot read the applications: " .. tostring(made))
      return false
    end
    index = made
  else
    local ok, changed = pcall(index.refresh, index)
    if (not ok or not changed) and not force then return false end
  end
  local list, seen, ids = {}, {}, {}
  local ok, all = pcall(index.applications, index)
  if not ok or type(all) ~= "table" then return false end
  for _, entry in ipairs(all) do
    local name = (entry.name or ""):match("^%s*(.-)%s*$")
    if not entry.no_display and name ~= "" and not seen[entry.id] then
      seen[entry.id] = true
      ids[#ids + 1] = entry.id
      local comment = (entry.comment or ""):match("^%s*(.-)%s*$")
      if comment == "" then comment = entry.generic_name or "" end
      if entry.source and entry.source ~= "" then watch(entry.source) end
      local origin = origin_of(entry)
      local row = {
        kind = "app",
        id = entry.id,
        name = name,
        description = comment,
        icon = entry.icon or "",
        keywords = table.concat(entry.keywords or {}, " "),
        pin = "app:" .. entry.id,
        origin = origin,
        categories = entry.categories or {},
        desktop_actions = entry.actions or {},
        command = entry.command or {},
        terminal = entry.run_in_terminal == true,
        window_class = entry.startup_class ~= "" and entry.startup_class or nil,
        source = entry.source,
        folder = entry.source,
      }
      if not pins.hidden(entry.id) then list[#list + 1] = row end
      by_id[entry.id] = row
    end
  end
  note_new(ids)
  for _, row in ipairs(list) do
    row.fresh = is_new(row.id)
    row.tag = row.fresh and "New" or row.origin
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  rows = list
  return true
end

M.refresh()

--- The installed applications the launcher lists, by name.
function M.installed() return rows end

local used = frecency.open { path = morf.paths.state("eva-launches.json") }
M.used = used
M.history = history.open { path = morf.paths.state("eva-launcher-history.json") }

--- The applications, by name.
function M.rows() return rows end

--- The application `id`, or nil.
function M.row(id) return by_id[id] end

local function launch(row)
  if run.dry() then
    morf.log("info", "eva: launcher (dry run): launch " .. row.id)
    return
  end
  if row.terminal and #row.command > 0 then
    run.terminal(row.command)
    return
  end
  local ok, err = pcall(index.launch, index, row.id)
  if not ok then morf.log("warn", "eva: could not launch " .. row.id .. ": " .. tostring(err)) end
end

--- Opens `path` with `row`'s application.
function M.open_file(row, path)
  local argv = {}
  for i, word in ipairs(row.command) do argv[i] = word end
  argv[#argv + 1] = path
  run.start(argv)
  return "close"
end

--- `row`'s application as root, through polkit, on the session's display.
local function as_root(row)
  local argv = { "pkexec", "env" }
  for _, name in ipairs { "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "DISPLAY", "XAUTHORITY" } do
    local value = morf.env and morf.env(name)
    if value and value ~= "" then argv[#argv + 1] = name .. "=" .. value end
  end
  for _, word in ipairs(row.command) do argv[#argv + 1] = word end
  run.start(argv)
  return "close"
end

--- The open window `row`'s application has, as a row of the windows mode, or nil.
local function running(row)
  local class = (row.window_class or row.id:gsub("%.desktop$", "")):lower()
  for _, window in ipairs((require("launcher_modes.windows").window_rows())) do
    if tostring(window.keywords or ""):lower() == class then return window end
  end
end

--- What `row`'s application can do: its desktop file's actions first.
function M.actions_for(row)
  local out = {}
  local window = running(row)
  if window then
    out[#out + 1] = { name = "Switch to its window", material = "open_in_browser", run = window.run }
    out[#out + 1] = { name = "Open another", material = "open_in_new", run = function() launch(row) return "close" end }
  else
    out[#out + 1] = { name = "Open", material = "open_in_new", run = function() launch(row) return "close" end }
  end
  for _, action in ipairs(row.desktop_actions) do
    local id = action.id
    out[#out + 1] = { name = action.name ~= "" and action.name or id, material = "bolt", icon = action.icon,
      run = function() return M.run_action(row, id) end }
  end
  out[#out + 1] = { name = "Run as root", material = "admin_panel_settings", run = function() return as_root(row) end }
  if row.source and row.source ~= "" then
    out[#out + 1] = { name = "Open containing folder", material = "folder_open",
      run = function() return require("providers").reveal(row.source .. "/" .. row.id) end }
  end
  local home, dock = require("desktop_model"), require("dock_model")
  if home.home() then
    local there = home.has_app(row.id)
    out[#out + 1] = { name = there and "Take it off the home screen" or "Add it to the home screen",
      material = "add_to_home_screen", run = function() home.toggle_app(row.id) return "keep" end }
  end
  if dock.on() then
    out[#out + 1] = { name = dock.pinned(row.id) and "Take it off the dock" or "Keep it on the dock", material = "push_pin",
      run = function() dock.toggle_pin(row.id) return "keep" end }
  end
  out[#out + 1] = { name = "Put it in a folder…", material = "create_new_folder",
    run = function() return require("launcher_modes.shell").file(row.id) end }
  local filed = pins.folder_of(row.id)
  if filed then
    out[#out + 1] = { name = "Take it out of " .. filed.name, material = "folder_off", run = function()
      pins.file_under(row.id, "")
      rowkit.bump()
      return "keep"
    end }
  end
  local hidden = pins.hidden(row.id)
  out[#out + 1] = { name = hidden and "Show it again" or "Hide it", material = hidden and "visibility" or "visibility_off",
    run = function()
      pins.set_hidden(row.id, not hidden)
      M.refresh(true)
      rowkit.bump()
      return "keep"
    end }
  out[#out + 1] = { name = "Copy its command", material = "content_copy",
    run = function() return run.copy(table.concat(row.command, " ")) end }
  out[#out + 1] = M.removal(row)
  return out
end

--- The action panel's last word on `row`: uninstalling it, in two presses, or a
--- line saying why that is not this shell's to do.
function M.removal(row)
  local software = require("software_model")
  local source = software.source(row)
  if not source.removable then
    return { name = "Cannot be removed here", material = "lock", description = source.why,
      run = function() return "stay" end }
  end
  local confirm = require("providers").confirmed("uninstall:" .. row.id, function()
    software.uninstall(row)
    return "close"
  end)
  local armed = require("providers").armed("uninstall:" .. row.id)
  return { name = armed and "Press again to uninstall" or "Uninstall it", material = "delete", description = source.what,
    run = function()
      local step = confirm()
      return step == "keep" and "stay" or step
    end }
end

--- Runs the desktop action `id` of `row`'s application.
function M.run_action(row, id)
  if run.dry() then
    morf.log("info", "eva: launcher (dry run): action " .. id .. " of " .. row.id)
    return "close"
  end
  local ok, err = pcall(index.launch_action, index, row.id, id)
  if not ok then morf.log("warn", "eva: could not run " .. id .. ": " .. tostring(err)) end
  return "close"
end

local action_rows

--- Every desktop action, as a row of its own: "Firefox: New Private Window".
function M.action_rows()
  if action_rows and action_rows.of == rows then return action_rows end
  action_rows = { of = rows }
  for _, row in ipairs(rows) do
    for _, action in ipairs(row.desktop_actions) do
      local id = action.id
      action_rows[#action_rows + 1] = rowkit.row {
        id = "app-action:" .. row.id .. ":" .. id, name = row.name .. ": " .. action.name, description = row.description,
        icon = action.icon ~= "" and action.icon or row.icon, tag = "App action",
        run = function() return M.run_action(row, id) end,
      }
    end
  end
  return action_rows
end

local CATEGORIES = {
  { "Internet", { "Network", "WebBrowser", "Email" } }, { "Media", { "AudioVideo", "Audio", "Video", "Player" } },
  { "Office", { "Office", "Publishing" } }, { "Graphics", { "Graphics", "Photography" } },
  { "Games", { "Game" } }, { "Development", { "Development", "IDE" } }, { "Education", { "Education", "Science" } },
  { "Utilities", { "Utility", "Accessibility" } }, { "System", { "System", "Settings", "Monitor" } },
}

--- The category `row` falls in, or "Other".
function M.category_of(row)
  for _, category in ipairs(CATEGORIES) do
    for _, name in ipairs(category[2]) do
      for _, have in ipairs(row.categories or {}) do
        if have == name then return category[1] end
      end
    end
  end
  return "Other"
end

--- The categories that hold something, in their order, and the apps of each.
function M.categories()
  local out, by_name = {}, {}
  for _, category in ipairs(CATEGORIES) do by_name[category[1]] = {} end
  by_name.Other = {}
  for _, row in ipairs(rows) do
    local list = by_name[M.category_of(row)]
    list[#list + 1] = row
  end
  for _, category in ipairs(CATEGORIES) do
    if #by_name[category[1]] > 0 then out[#out + 1] = { name = category[1], apps = by_name[category[1]] } end
  end
  if #by_name.Other > 0 then out[#out + 1] = { name = "Other", apps = by_name.Other } end
  return out
end

-- The chip of what the person hid.
M.HIDDEN = "Hidden"

--- The apps the person hid, by name.
function M.hidden_rows()
  local out = {}
  for _, id in ipairs(config.get("launcher.hidden")) do
    if by_id[id] then out[#out + 1] = by_id[id] end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

--- Files app `id` with the app of `row`, or in the folder `row` is: dropped on an
--- app it makes a folder named for that app's category. The folder's name.
function M.gather(id, row)
  if id == row.id then return nil end
  if row.kind == "folder" then pins.file_under(id, row.id) return row.id end
  local filed = pins.folder_of(row.id)
  local name = filed and filed.name or pins.free_name(M.category_of(row))
  if not filed then pins.file_under(row.id, name) end
  pins.file_under(id, name)
  return name
end

--- A folder as the grid shows it: its icons, and what can be done to it.
local function folder_row(folder)
  local shell = "launcher_modes.shell"
  local members = {}
  for _, id in ipairs(folder.apps) do
    local app = by_id[id]
    if app and #members < 4 then members[#members + 1] = app.icon end
  end
  local actions = {
    { name = "Rename it…", material = "edit", run = function() return require(shell).rename(folder.name) end },
    { name = "Take everything out", material = "folder_off", run = function()
      pins.dissolve(folder.name)
      rowkit.bump()
      return "keep"
    end },
  }
  local home = require("desktop_model")
  if home.home() then
    actions[#actions + 1] = { name = "Add it to the home screen", material = "add_to_home_screen",
      run = function() home.place("folder:" .. folder.name) return "keep" end }
  end
  return { kind = "folder", id = folder.name, name = folder.name, count = #folder.apps, material = "folder",
    members = members, private = true, actions = actions, pin = "folder:" .. folder.name }
end

--- The folder called `name` as a row, or nil.
function M.folder(name)
  for _, folder in ipairs(pins.folders()) do
    if folder.name == name then return folder_row(folder) end
  end
end

--- What the grid shows: a list of `{ name, rows }`. Inside `folder`, its apps;
--- within `category`, that category's; else the favourites, what is used most,
--- the folders, and every app.
function M.grid(folder, category)
  if folder ~= "" then
    for _, f in ipairs(pins.folders()) do
      if f.name == folder then
        local list = {}
        for _, id in ipairs(f.apps) do
          if by_id[id] then list[#list + 1] = by_id[id] end
        end
        return { { rows = list } }
      end
    end
    return {}
  end
  if category == M.HIDDEN then return { { rows = M.hidden_rows() } } end
  if category ~= "" then
    for _, c in ipairs(M.categories()) do
      if c.name == category then return { { rows = c.apps } } end
    end
    return {}
  end
  local out = {}
  local favourites = {}
  local providers = require("providers")
  local shown = {}
  for _, name in ipairs(pins.favourites()) do
    local r = providers.resolve(name)
    if r then
      r.pinned = true
      shown[r.id] = true
      favourites[#favourites + 1] = r
    end
  end
  if #favourites > 0 then out[#out + 1] = { name = "Favourites", rows = favourites } end
  local suggested = {}
  for _, hit in ipairs(used.rank("", rows, { key = "name", id = "id" })) do
    if (hit.frecency or 0) <= 0 or #suggested >= 4 then break end
    if not shown[hit.item.id] then suggested[#suggested + 1] = hit.item end
  end
  if #suggested > 0 then out[#out + 1] = { name = "Suggested", rows = suggested } end
  local filed, folders = {}, {}
  for _, f in ipairs(pins.folders()) do
    folders[#folders + 1] = folder_row(f)
    for _, id in ipairs(f.apps) do filed[id] = true end
  end
  local loose = {}
  for _, row in ipairs(rows) do
    if not filed[row.id] then loose[#loose + 1] = row end
  end
  if #folders > 0 then out[#out + 1] = { name = "Folders", rows = folders } end
  out[#out + 1] = { name = #out > 0 and "All apps" or nil, rows = loose }
  return out
end

-- ---------------------------------------------------------------- actions --

-- The shell's own actions, as the reference lists them after ">".
-- `run(query)` returns what the launcher does next: "close", or a new query.
M.ACTIONS = {
  { id = "calc", name = "Calculator", description = "Do simple maths equations", icon = "calculate",
    run = function() return "> calc " end },
  { id = "scheme", name = "Scheme", description = "Change the current colour scheme", icon = "palette",
    run = function() return "> scheme " end },
  { id = "wallpaper", name = "Wallpaper", description = "Change the current wallpaper", icon = "image",
    run = function() return "> wallpaper " end },
  { id = "variant", name = "Variant", description = "Change the current scheme variant", icon = "format_paint",
    run = function() return "> variant " end },
  { id = "random", name = "Random", description = "Switch to a random wallpaper", icon = "casino",
    run = function()
      local pics = M.wallpapers()
      if #pics > 0 then require("wallpaper").set(pics[math.random(#pics)].path) end
      return "close"
    end },
  { id = "light", name = "Light", description = "Change the scheme to light mode", icon = "light_mode",
    run = function() require("themes.color_mode").set("light") return "close" end },
  { id = "dark", name = "Dark", description = "Change the scheme to dark mode", icon = "dark_mode",
    run = function() require("themes.color_mode").set("dark") return "close" end },
}
for _, a in ipairs(M.ACTIONS) do a.kind = "action" end

-- ---------------------------------------------------------------- pickers --

--- The source colours "> scheme " offers: the wallpaper's, then named
--- ones. Each builds a Material 3 scheme through lib/util/material.lua.
M.SCHEMES = {
  { id = "wallpaper", name = "Dynamic", description = "Colours from the wallpaper", color = nil },
  { id = "#ffb0ca", name = "Rosé", description = "A soft pink" },
  { id = "#f4a261", name = "Apricot", description = "A warm orange" },
  { id = "#e9c46a", name = "Saffron", description = "A mellow yellow" },
  { id = "#8fbf7f", name = "Sage", description = "A quiet green" },
  { id = "#4fb3bf", name = "Lagoon", description = "A clear teal" },
  { id = "#7aa2f7", name = "Cornflower", description = "A calm blue" },
  { id = "#b39ddb", name = "Lavender", description = "A light violet" },
  { id = "#e57373", name = "Coral", description = "A bright red" },
  { id = "#9e9e9e", name = "Graphite", description = "Hardly any colour" },
}

--- The variants "> variant " offers, in lib/util/material.lua's names.
M.VARIANTS = {
  { id = "vibrant", name = "Vibrant", icon = "sentiment_very_dissatisfied",
    description = "Colours at their fullest, the accents pushed to the edge of the gamut." },
  { id = "tonal_spot", name = "Tonal Spot", icon = "android",
    description = "The default: calm, pastel accents with a little colour in the greys." },
  { id = "expressive", name = "Expressive", icon = "compare_arrows",
    description = "The accents turned away from the source's hue for a livelier mix." },
  { id = "fidelity", name = "Fidelity", icon = "compare",
    description = "Keeps the source colour as it is, however bright or dark." },
  { id = "content", name = "Content", icon = "sentiment_satisfied",
    description = "Much like fidelity: follows the source closely." },
  { id = "fruit_salad", name = "Fruit Salad", icon = "nutrition",
    description = "Playful: the accents wander well away from the source's hue." },
  { id = "rainbow", name = "Rainbow", icon = "looks",
    description = "Playful: bright accents over plain grey surfaces." },
  { id = "neutral", name = "Neutral", icon = "contrast",
    description = "Almost grey: only a hint of the source colour." },
  { id = "monochrome", name = "Monochrome", icon = "filter_b_and_w",
    description = "Greys only, with no colour at all." },
}

--- The folder the wallpapers are in: the one Lule uses.
function M.wallpaper_folder()
  local current = require("wallpaper").current:get()
  return require("lib.integrations.lule").folder(config.get("lule.folder"), current)
end

--- The pictures in that folder (and the current one), by name: `{ path, name }`
--- each.
function M.wallpapers()
  local out, seen = {}, {}
  for _, picture in ipairs(require("lib.integrations.lule").pictures(M.wallpaper_folder()) or {}) do
    seen[picture.path] = true
    out[#out + 1] = picture
  end
  local current = require("wallpaper").current:get()
  if current ~= "" and not seen[current] then
    out[#out + 1] = { path = current, name = current:match("([^/]+)$") }
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- ----------------------------------------------------------------- search --

local function picked(list, term, kind, make)
  local hits = morf.text.fuzzy(term, list, { key = { "name", { "description", 0.3 } } })
  local out = {}
  for _, hit in ipairs(hits) do out[#out + 1] = make(hit.item) end
  return out
end

--- What `query` finds: `rows, mode` -- rows best first (apps, actions,
--- schemes, variants, wallpapers or one calculation) and the mode the
--- launcher draws them in: "apps", "actions", "schemes", "variants",
--- "wallpapers" or "calc".
function M.search(query, limit)
  -- A prefix of providers.lua's: its rows alone.
  local providers = require("providers")
  local routed, routed_mode = providers.search(query)
  if routed then return routed, routed_mode end
  local prefix = config.get("launcher.action_prefix")
  if query:sub(1, #prefix) == prefix then
    local rest = query:sub(#prefix + 1):gsub("^%s+", "")
    local word, after = rest:match("^(%a+)%s(.*)$")
    word = word and word:lower()
    if word == "scheme" then
      local source = config.get("theme.source")
      return picked(M.SCHEMES, after:match("^%s*(.-)%s*$"), "scheme", function(item)
        return {
          kind = "scheme", id = item.id, name = item.name, icon = "palette",
          description = item.id == "wallpaper" and item.description or (item.description .. " · " .. item.id),
          color = item.id ~= "wallpaper" and item.id or nil, current = source == item.id,
          run = function() config.set("theme.source", item.id) return "close" end,
        }
      end), "schemes"
    elseif word == "variant" then
      local variant = config.get("theme.variant")
      return picked(M.VARIANTS, after:match("^%s*(.-)%s*$"), "variant", function(item)
        return {
          kind = "variant", id = item.id, name = item.name, icon = item.icon, description = item.description,
          current = variant == item.id,
          run = function() config.set("theme.variant", item.id) return "close" end,
        }
      end), "variants"
    elseif word == "wallpaper" then
      local term = after:match("^%s*(.-)%s*$")
      local list = M.wallpapers()
      local out = {}
      if term == "" then
        out = list
      else
        for _, hit in ipairs(morf.text.fuzzy(term, list, { key = "name" })) do out[#out + 1] = hit.item end
      end
      local rows = {}
      for _, w in ipairs(out) do
        rows[#rows + 1] = {
          kind = "wallpaper", id = w.path, name = w.name, description = w.path, icon = "image", path = w.path,
          run = function() require("wallpaper").set(w.path) return "close" end,
        }
      end
      return rows, "wallpapers"
    elseif word == "calc" then
      local value, shown, result = calc.evaluate(after)
      if not value then
        return { {
          kind = "calc", id = "calc", name = after:match("^%s*(.-)%s*$") == "" and "Type an expression" or shown,
          description = "", icon = "function", failed = true, run = function() return "keep" end,
        } }, "calc"
      end
      return { {
        kind = "calc", id = "calc", name = shown, description = result, icon = "function", result = result,
        run = function()
          pcall(morf.clipboard.set, result)
          return "close"
        end,
      } }, "calc"
    end
    local term = rest:match("^%s*(.-)%s*$")
    local pool, named = {}, {}
    for _, action in ipairs(M.ACTIONS) do
      pool[#pool + 1] = action
      named[action.name] = true
    end
    for _, mode in ipairs(providers.mode_rows()) do
      if not named[mode.name] then pool[#pool + 1] = mode end
    end
    local hits = morf.text.fuzzy(term, pool, { key = { "name", { "keywords", 0.6 }, { "description", 0.3 } } })
    local out = {}
    for _, hit in ipairs(hits) do out[#out + 1] = hit.item end
    out.cap = #out
    return out, "actions"
  end
  local universal = require("universal")
  local cap = config.get("launcher.max_results")
  if query == "" then return universal.home(cap), "apps" end
  return universal.search(query, cap), "apps"
end

--- Whether a match's characters are one unbroken run (bytes in order,
--- each character right after the one before).
local function contiguous(text, positions)
  for i = 2, #(positions or {}) do
    local prev = positions[i - 1]
    local step = utf8.offset(text, 2, prev)
    if not step or positions[i] ~= step then return false end
  end
  return true
end

--- Whether every run of matched characters starts a word: "lw" in
--- "LibreOffice Writer", "ki" in "kitty", not "fire" strung through
--- "LibreOffice Impress".
local function at_words(text, positions)
  local prev
  for _, p in ipairs(positions or {}) do
    local continues = prev and utf8.offset(text, 2, prev) == p
    if not continues then
      local before = p > 1 and text:sub(p - 1, p - 1) or ""
      local here = text:sub(p, p)
      local starts = p == 1 or before:match("[%s%-_%./]")
        or (before:match("%l") and here:match("%u"))
      if not starts then return false end
    end
    prev = p
  end
  return true
end

--- The fuzzy hits worth showing, as the reference is strict about them: a
--- match in a name may skip letters only from one word to the start of the
--- next; one found only in the keywords or the description must be the
--- query as written, in one run; and nothing scoring under half the best
--- hit's score is listed. "fire" finds Firefox, not LibreOffice with an f,
--- an i, an r and an e somewhere in it.
function M.strict(query, hits)
  if (query or "") == "" then return hits end
  local best = 0
  for _, hit in ipairs(hits) do best = math.max(best, hit.score or 0) end
  local out = {}
  for _, hit in ipairs(hits) do
    local ok = (hit.score or 0) >= best * 0.5
    if ok and hit.key == "name" then
      ok = at_words(tostring(hit.item.name or ""), hit.positions)
    elseif ok then
      -- Every term of the query in one run somewhere in that field.
      local text = tostring(hit.item[hit.key] or ""):lower()
      for term in query:lower():gmatch("%S+") do
        if not text:find(term, 1, true) then ok = false break end
      end
      if ok and not query:find("%s") then ok = contiguous(tostring(hit.item[hit.key] or ""), hit.positions) end
    end
    if ok then out[#out + 1] = hit end
  end
  return out
end

--- The application among `ids`, in their order, or else the first that says
--- `word` in its keywords or categories: its row, or nil.
function M.find(ids, word)
  for _, id in ipairs(ids) do
    for _, row in ipairs(rows) do
      if row.id == id or row.id == id .. ".desktop" then return row end
    end
  end
  if not word then return nil end
  for _, row in ipairs(rows) do
    if (row.keywords .. " " .. table.concat(row.categories, " ")):lower():find(word, 1, true) then return row end
  end
end

--- Runs a row: launches an app (and remembers it), or an action. Returns
--- "close" or a new query.
function M.activate(row)
  if not row then return "keep" end
  if row.kind == "app" then
    if config.get("launcher.remember") then used.record(row.id) end
    launch(row)
    return "close"
  end
  if row.pin and not row.private and config.get("launcher.remember") then used.record(row.pin) end
  return row.run() or "close"
end

--- The desktop entry a window's class names, or nil.
function M.entry_for(class)
  if not index or not class or class == "" then return nil end
  local ok, entry = pcall(index.heuristic_lookup, index, class)
  if ok and type(entry) == "table" then return entry end
  return nil
end

--- The desktop entry `id`, or nil.
function M.entry(id)
  if not index then return nil end
  local ok, entry = pcall(index.by_id, index, id)
  if ok and type(entry) == "table" then return entry end
  return nil
end

local function held_back(what)
  local v = morf.env and morf.env("EVA_DRY_RUN")
  if not (v and v ~= "" and v ~= "0") then return false end
  morf.log("info", "eva: launch (dry run): " .. what)
  return true
end

--- Starts the application `id`, as the launcher does.
function M.launch(id)
  if held_back(id) then return "close" end
  return M.activate { kind = "app", id = id }
end

--- Runs a desktop action of the application `id`.
function M.launch_action(id, action)
  if held_back(id .. " " .. tostring(action)) or not index then return false end
  local ok, err = pcall(index.launch_action, index, id, action)
  if not ok then morf.log("warn", "eva: could not run " .. tostring(action) .. ": " .. tostring(err)) end
  return ok
end

-- ------------------------------------------------------------------ icons --

local found = {}

--- `{ name }` for a themed icon, `{ path }` for a file, or nil.
function M.icon(name)
  name = tostring(name or "")
  if name == "" then return nil end
  if found[name] ~= nil then return found[name] or nil end
  local hit
  if name:sub(1, 1) == "/" then
    hit = morf.fs.exists(name) and { path = name } or nil
  else
    local ok, has = pcall(morf.image.has_icon, name)
    if ok and has then hit = { name = name }
    else
      for _, ext in ipairs { ".svg", ".png" } do
        local path = "/usr/share/pixmaps/" .. name .. ext
        if morf.fs.exists(path) then hit = { path = path } break end
      end
    end
  end
  found[name] = hit or false
  return hit
end

return M
