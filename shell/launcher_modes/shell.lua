-- The launcher's own house: its modes, favourites, hidden apps, aliases, what it
-- remembers, script commands and plugins; and things found by a folder of their
-- own, games and projects.
local morf = require("morf")
local config = require("config")
local registry = require("lib.shell.launcher.registry")
local index = require("lib.shell.launcher.search_index")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")
local pins = require("lib.shell.launcher.pins")
local scripts = require("lib.shell.launcher.scripts")

local M = {}

local row, note = rows.row, rows.note

registry.mode { id = "modes", name = "Modes", material = "category", shape = "cookie9", words = { "modes", "help" }, hidden = true,
  hint = "everything the box can do", search = function(term)
    return rows.fuzzy(require("providers").mode_rows(), term, { "name", { "keywords", 0.6 }, { "description", 0.3 } })
  end }

registry.mode { id = "favourites", name = "Favourites", material = "keep", shape = "cookie9", words = { "pins", "favourites", "favorites" },
  bare = false, hint = "what you pinned, in order", search = function(term)
    local providers = require("providers")
    local out = {}
    local names = pins.favourites()
    for i, name in ipairs(names) do
      local r = providers.resolve(name)
      if r then
        local actions = {}
        for _, a in ipairs(r.actions or {}) do actions[#actions + 1] = a end
        if i > 1 then
          actions[#actions + 1] = { name = "Move it up", material = "arrow_upward", run = function() pins.move(name, -1) rows.bump() return "keep" end }
        end
        if i < #names then
          actions[#actions + 1] = { name = "Move it down", material = "arrow_downward", run = function() pins.move(name, 1) rows.bump() return "keep" end }
        end
        r.actions = actions
        out[#out + 1] = r
      end
    end
    out = rows.fuzzy(out, term, "name")
    if #out == 0 then out[1] = note("favourites", "Nothing pinned yet", "Open a result's actions and pin it", "keep") end
    return out
  end }

registry.mode { id = "hidden", name = "Hidden apps", material = "visibility_off", shape = "cookie9", words = { "hidden" }, bare = false,
  hint = "what you hid; Return brings it back", search = function(term)
    local out = {}
    for _, id in ipairs(config.get("launcher.hidden")) do
      out[#out + 1] = row { id = "hidden:" .. id, name = id, description = "Return shows it again", material = "visibility",
        run = function()
          pins.set_hidden(id, false)
          require("apps").refresh(true)
          rows.bump()
          return "keep"
        end }
    end
    out = rows.fuzzy(out, term, "name")
    if #out == 0 then out[1] = note("hidden", "Nothing is hidden", "An app's actions can hide it", "visibility") end
    return out
  end }

registry.mode { id = "alias", name = "Aliases", material = "label", shape = "cookie9", words = { "alias" }, bare = false,
  hint = "alias add ff firefox  ·  a short word for anything", search = function(term)
    local name, target = term:match("^add%s+(%S+)%s*(.*)$")
    if name and target ~= "" then
      return { row { id = "alias:new", name = name .. " → " .. target, description = "Return keeps it", material = "label",
        run = function() pins.set_alias(name, target) return "close" end } }
    end
    if name then return { note("alias", "Type what it stands for after it", "alias add ff firefox", "label") } end
    local out = {}
    for _, alias in ipairs(pins.aliases()) do
      out[#out + 1] = row { id = "alias:" .. alias.name, name = alias.name, description = alias.target, material = "label",
        run = function() return alias.target end,
        actions = { { name = "Delete it", material = "delete", run = function() pins.set_alias(alias.name, "") rows.bump() return "keep" end } } }
    end
    out = rows.fuzzy(out, term)
    if #out == 0 then out[1] = note("alias", "No aliases yet", "alias add ff firefox", "label") end
    return out
  end }

registry.mode { id = "history", name = "History", material = "history", shape = "cookie9", words = { "history" }, bare = false,
  hint = "everything you picked here", search = function(term)
    local apps = require("apps")
    local list = {}
    for _, pick in ipairs(apps.history.picks()) do
      list[#list + 1] = { pick = pick, name = pick.name, description = pick.query }
    end
    local out = {}
    for _, item in ipairs(rows.fuzzy(list, term)) do
      local pick = item.pick
      out[#out + 1] = row {
        id = "history:" .. pick.id, name = pick.name, material = "history",
        description = (pick.query ~= "" and (pick.query .. "  ·  ") or "") .. require("lib.shell.launcher.dates").relative(pick.at),
        run = function()
          local again = require("providers").resolve(pick.id)
          if again then return require("apps").activate(again) end
          return pick.query
        end,
        actions = { { name = "Forget everything", material = "delete_sweep",
          run = require("providers").confirmed("history-clear", function() apps.history.clear() rows.bump() return "keep" end) } },
      }
      if #out >= 60 then break end
    end
    if #out == 0 then out[1] = note("history", "Nothing yet", "What you pick here shows up", "history") end
    return out
  end }

registry.mode { id = "large", name = "Large type", material = "text_fields", shape = "pill", words = { "large" }, bare = false,
  hint = "large some words  ·  across the screen", search = function(term)
    if term == "" then return { note("large", "Type what to show", "Big enough to read across the room", "text_fields") } end
    return { row { id = "large", name = term, description = "Return shows it", material = "text_fields",
      run = function() require("launcher").large_type:set(term) return "keep" end } }
  end }

registry.mode { id = "folder", name = "Folders", material = "folder_special", shape = "cookie9", words = { "appfolder" }, hidden = true, bare = false,
  search = function(term)
    local id, name = M.filing, term
    if not id then return { note("folder", "Choose an app first", "Its actions file it", "folder_special") } end
    local out = {}
    if name ~= "" then
      out[1] = row { id = "folder:new", name = "Put it in “" .. name .. "”", material = "create_new_folder",
        run = function() pins.file_under(id, name) return "close" end }
    end
    for _, folder in ipairs(pins.folders()) do
      if folder.name ~= name then
        out[#out + 1] = row { id = "folder:" .. folder.name, name = folder.name, description = #folder.apps .. " apps", material = "folder",
          run = function() pins.file_under(id, folder.name) return "close" end }
      end
    end
    if pins.folder_of(id) then
      out[#out + 1] = row { id = "folder:none", name = "Take it out of its folder", material = "folder_off",
        run = function() pins.file_under(id, "") return "close" end }
    end
    if #out == 0 then out[1] = note("folder", "Type a folder's name", "It is made if it is new", "create_new_folder") end
    return out
  end }

--- Asks which folder app `id` goes in. Returns the query that shows them.
function M.file(id)
  M.filing = id
  return "> appfolder "
end

-- ---------------------------------------------------------------- scripts --

local function run_script(script, argument)
  local argv = { script.path }
  if argument then argv[2] = argument end
  if script.mode == "terminal" then return run.terminal(argv) end
  if script.mode == "silent" then
    run.start(argv)
    return "close"
  end
  if run.dry() then morf.log("info", "eva: launcher (dry run): script " .. script.path) return "close" end
  morf.process.run(argv, { timeout_ms = 15000 }, function(result)
    local output = tostring(result and result.stdout or ""):gsub("%s+$", "")
    if script.mode == "copy" then run.copy(output)
    else require("notifs").push { app = script.title, summary = script.title, body = output } end
  end)
  return "close"
end

local function script_action(script)
  local function go()
    if script.argument then return "> script " .. script.file .. " " end
    return run_script(script)
  end
  if script.confirm then return require("providers").confirmed("script:" .. script.file, go) end
  return go
end

local watcher

--- Registers every script as a search entry, and again as the folder changes.
function M.sync_scripts()
  local list = scripts.scan()
  local seen = {}
  for _, script in ipairs(list) do
    local id = "script:" .. script.file
    seen[id] = true
    index.register { id = id, name = script.title, description = script.description, material = script.icon, tag = "Script",
      keywords = script.file, kind = "menu", pin = id, run = script_action(script) }
  end
  for _, entry in ipairs(index.all()) do
    if entry.id:sub(1, 7) == "script:" and not seen[entry.id] then index.forget(entry.id) end
  end
  M.scripts = list
  if not watcher and morf.fs.watch then
    watcher = morf.fs.watch(scripts.folder(), function() M.sync_scripts() end)
  end
end

registry.mode { id = "scripts", name = "Script commands", material = "code_blocks", shape = "square", words = { "script", "scripts" }, bare = false,
  hint = "your scripts in ~/.config/eva/scripts", search = function(term)
    local file, argument = term:match("^(%S+)%s(.*)$")
    for _, script in ipairs(M.scripts or {}) do
      if file and script.file == file then
        if argument == "" then return { note("scripts", script.argument or "An argument", script.title, script.icon) } end
        return { row { id = "script:run", name = script.title .. " " .. argument, description = "Return runs it", material = script.icon,
          run = function() return run_script(script, argument) end } }
      end
    end
    local out = {}
    for _, script in ipairs(M.scripts or {}) do
      out[#out + 1] = row { id = "script:" .. script.file, name = script.title, description = script.description, material = script.icon,
        tag = script.mode, pin = "script:" .. script.file, run = script_action(script) }
    end
    out = rows.fuzzy(out, term)
    if #out == 0 then out[1] = note("scripts", "No scripts yet", rows.tilde(scripts.folder()), "code_blocks") end
    return out
  end }

registry.mode { id = "plugins", name = "Plugins", material = "extension", shape = "cookie9", words = { "plugins" }, bare = false,
  hint = "what loaded from ~/.config/eva/plugin", search = function(term)
    local plugins = require("launcher_plugins")
    local out = {}
    for i, report in ipairs(plugins.report) do
      out[#out + 1] = row { id = "plugin:" .. i, name = report.path:match("([^/]+)$"), description = report.ok and rows.tilde(report.path) or report.why,
        material = report.ok and "extension" or "extension_off", tag = report.ok and "Loaded" or "Failed",
        run = function() return run.open(report.path) end }
    end
    out = rows.fuzzy(out, term)
    if #out == 0 then out[1] = note("plugins", "No plugins", rows.tilde(plugins.roots()[#plugins.roots()]) .. "/plugin/*.lua", "extension") end
    return out
  end }

-- ------------------------------------------------------------------ games --

local function steam_games()
  return rows.ask_run("steam", "all", { "sh", "-c", [[
for d in "$HOME/.local/share/Steam/steamapps" "$HOME/.steam/steam/steamapps" \
  "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps"; do
  [ -d "$d" ] && grep -h -E '"(appid|name)"' "$d"/appmanifest_*.acf 2>/dev/null && break
done]] }, function(stdout)
    local list, appid = {}, nil
    for key, value in stdout:gmatch('"(%a+)"%s+"([^"]*)"') do
      if key == "appid" then appid = value
      elseif key == "name" and appid then
        if not value:match("^Steamworks") and not value:match("^Proton") then list[#list + 1] = { name = value, appid = appid } end
        appid = nil
      end
    end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
  end, { debounce_ms = 0, ttl_ms = 60000, any_exit = true })
end

registry.mode { id = "games", name = "Games", material = "sports_esports", shape = "cookie9", words = { "game", "games", "steam" },
  hint = "game portal  ·  your Steam library", search = function(term)
    local out = {}
    for _, game in ipairs(rows.fuzzy(steam_games() or {}, term, "name")) do
      out[#out + 1] = row { id = "game:" .. game.appid, name = game.name, description = "Steam", material = "sports_esports", tag = "Game",
        pin = "url:steam://rungameid/" .. game.appid, run = function() return run.open("steam://rungameid/" .. game.appid) end }
      if #out >= 40 then break end
    end
    if #out == 0 then out[1] = note("games", "No games found", "It reads your Steam library", "sports_esports") end
    return out
  end }

-- --------------------------------------------------------------- projects --

local function project_rows(term)
  local roots = config.get("launcher.projects")
  local argv = { "sh", "-c", 'for r in "$@"; do find "$r" -maxdepth 4 -name .git -type d -prune 2>/dev/null; done', "sh" }
  for _, root in ipairs(roots) do argv[#argv + 1] = rows.untilde(root) end
  local list = rows.ask_run("projects", "all", argv, function(stdout)
    local out = {}
    for path in stdout:gmatch("[^\n]+") do
      local folder = path:gsub("/%.git$", "")
      out[#out + 1] = { path = folder, name = folder:match("([^/]+)$") or folder, description = rows.tilde(folder) }
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end, { debounce_ms = 0, ttl_ms = 60000, any_exit = true, timeout_ms = 6000 })
  local out = {}
  for _, p in ipairs(rows.fuzzy(list or {}, term)) do
    local r = rows.file(p.path, true, "Project")
    r.run = function() return run.terminal(nil, p.path) end
    out[#out + 1] = r
    if #out >= 40 then break end
  end
  return out
end

registry.mode { id = "projects", name = "Projects", material = "source", shape = "pill", words = { "project", "projects", "repo" },
  hint = "project eva  ·  repositories under launcher.projects", search = function(term)
    local out = project_rows(term)
    if #out == 0 then out[1] = note("projects", "No repositories found", "Set launcher.projects to your folders", "source") end
    return out
  end }

return M
