-- Files: found by name or by content, browsed by path, recent ones, the named
-- places, and "open with".
local morf = require("morf")
local config = require("config")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")

local M = {}

local home = rows.home
local LIMIT = 60

local function excluded()
  local list = config.get("launcher.exclude")
  return type(list) == "table" and list or {}
end

--- The search for `term`: fd, then locate, then find. `kind` is "d" for
--- folders alone.
local function finder(term, kind)
  local fd = rows.first_of { "fd", "fdfind" }
  if fd then
    local argv = { fd, "--ignore-case", "--max-results", tostring(LIMIT) }
    if kind then argv[#argv + 1] = "--type" argv[#argv + 1] = kind end
    for _, name in ipairs(excluded()) do argv[#argv + 1] = "--exclude" argv[#argv + 1] = name end
    argv[#argv + 1] = "--"
    argv[#argv + 1] = term
    argv[#argv + 1] = home
    return argv
  end
  local locate = rows.first_of { "plocate", "locate" }
  if locate then return { locate, "--ignore-case", "--limit", tostring(LIMIT * 4), "--", term } end
  local argv = { "find", home }
  for _, name in ipairs(excluded()) do
    for _, word in ipairs { "-name", name, "-prune", "-o" } do argv[#argv + 1] = word end
  end
  if kind then argv[#argv + 1] = "-type" argv[#argv + 1] = kind end
  for _, word in ipairs { "-iname", "*" .. term .. "*", "-print" } do argv[#argv + 1] = word end
  return argv
end

local function parsed(stdout)
  local out = {}
  for path in stdout:gmatch("[^\n]+") do
    local folder = path:sub(-1) == "/"
    path = path:gsub("/$", "")
    out[#out + 1] = { path = path, folder = folder }
    if #out >= LIMIT then break end
  end
  return out
end

local function found(slot, term, kind)
  local list = rows.ask_run(slot, term, finder(term, kind), parsed, { timeout_ms = 4000, any_exit = true })
  return list or {}
end

local function file_rows(list, tag)
  local out = {}
  for _, f in ipairs(list) do out[#out + 1] = rows.file(f.path, f.folder, tag) end
  return out
end

--- The entries of the folder `text` names, the last word as a start of a name.
local function browsed(text)
  local dir, partial = text:match("^(.*/)([^/]*)$")
  if not dir then return nil end
  local ok, entries = pcall(morf.fs.list, dir)
  if not ok or type(entries) ~= "table" then
    return { rows.note("files", "No such folder", rows.tilde(dir), "folder_off") }
  end
  local list = {}
  for _, e in ipairs(entries) do
    local name = e.name or ""
    local shown = partial ~= "" or name:sub(1, 1) ~= "."
    if shown then list[#list + 1] = { name = name, path = e.path, folder = e.is_dir == true } end
  end
  table.sort(list, function(a, b)
    if a.folder ~= b.folder then return a.folder end
    return a.name:lower() < b.name:lower()
  end)
  local out = {}
  for _, e in ipairs(rows.fuzzy(list, partial, "name")) do
    local r = rows.file(e.path, e.folder)
    if e.folder then
      r.complete = (e.path:sub(1, #home) == home and ("~" .. e.path:sub(#home + 1)) or e.path) .. "/"
    end
    out[#out + 1] = r
    if #out >= LIMIT then break end
  end
  if #out == 0 then out[1] = rows.note("files", "Nothing here by that name", rows.tilde(dir), "folder_off") end
  return out
end

local function search(rest, query)
  local first = query:sub(1, 1)
  if first == "~" then return browsed(home .. (rest:sub(1, 1) == "/" and rest or ("/" .. rest))) end
  if rest:find("/", 1, true) then return browsed("/" .. rest) end
  if rest == "" then
    return { rows.note("files", "Type to find files and folders", "Searched from " .. rows.tilde(home), "folder_open") }
  end
  return file_rows(found("files", rest))
end

registry.mode { id = "files", name = "Files", material = "folder_open", shape = "pill", prefix = "/",
  words = { "files", "find" }, hint = "a name, or a path: /etc/  ·  ~/Doc", search = search }
registry.PREFIXES["~"] = "files"

registry.mode { id = "folders", name = "Folders", material = "folder", shape = "pill", words = { "dir", "folder" },
  hint = "folders alone", search = function(term)
    if term == "" then return { rows.note("folders", "Type a folder's name", "Searched from " .. rows.tilde(home), "folder") } end
    return file_rows(found("folders", term, "d"))
  end }

local function grep_argv(term)
  local rg = rows.first_of { "rg" }
  if rg then
    local argv = { rg, "--files-with-matches", "--ignore-case", "--max-count", "1", "--max-filesize", "1M", "--fixed-strings" }
    for _, name in ipairs(excluded()) do argv[#argv + 1] = "--glob" argv[#argv + 1] = "!" .. name end
    argv[#argv + 1] = "--"
    argv[#argv + 1] = term
    argv[#argv + 1] = home
    return argv
  end
  local argv = { "grep", "--recursive", "--files-with-matches", "--ignore-case", "--fixed-strings", "--binary-files=without-match" }
  for _, name in ipairs(excluded()) do argv[#argv + 1] = "--exclude-dir=" .. name end
  argv[#argv + 1] = "--"
  argv[#argv + 1] = term
  argv[#argv + 1] = home
  return argv
end

registry.mode { id = "grep", name = "File contents", material = "manage_search", shape = "pill", words = { "grep", "content" },
  hint = "the words inside files", search = function(term)
    if #term < 3 then return { rows.note("grep", "Type at least three letters", "Searches inside text files", "manage_search") } end
    local list = rows.ask_run("grep", term, grep_argv(term), parsed, { timeout_ms = 8000, any_exit = true, debounce_ms = 300 })
    local out = file_rows(list or {})
    if #out == 0 then out[1] = rows.note("grep", list and "No file has that in it" or "Searching…", term, "manage_search") end
    return out
  end }

-- ---------------------------------------------------------------- recent --

local recent = require("lib.shell.launcher.recent")

--- The recent files, read off the loop at most every half minute.
local function recent_list()
  local list = rows.ask("recent", "all", function(done)
    return morf.fs.read_async({ recent.path() }, function(_, contents)
      local text = type(contents) == "table" and contents[1] or nil
      done(recent.parse(type(text) == "string" and text or "", 200))
    end, 4 * 1024 * 1024)
  end, { debounce_ms = 0, ttl_ms = 30000 })
  return list or {}
end

registry.mode { id = "recent", name = "Recent files", material = "history", shape = "pill", words = { "recent" },
  hint = "what applications opened lately", search = function(term)
    local list = {}
    for _, f in ipairs(recent_list()) do
      list[#list + 1] = { path = f.path, name = f.path:match("([^/]+)$") or f.path, description = rows.tilde(f.path) }
    end
    local out = {}
    for _, f in ipairs(rows.fuzzy(list, term)) do
      if morf.fs.exists(f.path) then
        out[#out + 1] = rows.file(f.path, morf.fs.is_dir(f.path), "Recent")
        if #out >= LIMIT then break end
      end
    end
    if #out == 0 then out[1] = rows.note("recent", "Nothing recent", rows.tilde(recent.path()), "history") end
    return out
  end }

-- ---------------------------------------------------------------- places --

local function user_dirs()
  local out = { { name = "Home", path = home } }
  local base = (morf.env and morf.env("XDG_CONFIG_HOME")) or (home .. "/.config")
  local ok, text = pcall(morf.fs.read, base .. "/user-dirs.dirs")
  if ok and type(text) == "string" then
    for name, path in text:gmatch('XDG_(%u+)_DIR="([^"]*)"') do
      path = path:gsub("%$HOME", home)
      if path ~= home then
        out[#out + 1] = { name = name:sub(1, 1) .. name:sub(2):lower(), path = path }
      end
    end
  else
    for _, name in ipairs { "Documents", "Downloads", "Music", "Pictures", "Videos" } do
      out[#out + 1] = { name = name, path = home .. "/" .. name }
    end
  end
  local fine, marks = pcall(morf.fs.read, base .. "/gtk-3.0/bookmarks")
  if fine and type(marks) == "string" then
    for line in marks:gmatch("[^\n]+") do
      local uri, label = line:match("^file://(%S+)%s*(.*)$")
      if uri then
        local path = morf.encoding.url_decode(uri)
        out[#out + 1] = { name = label ~= "" and label or (path:match("([^/]+)$") or path), path = path }
      end
    end
  end
  return out
end

local places
--- The named folders, as rows.
function M.place_rows()
  if not places then
    places = {}
    for _, place in ipairs(user_dirs()) do
      if morf.fs.is_dir(place.path) then
        local r = rows.file(place.path, true, "Place")
        r.name = place.name
        places[#places + 1] = r
      end
    end
  end
  return places
end

registry.mode { id = "places", name = "Places", material = "bookmark", shape = "pill", words = { "places", "place" },
  hint = "your named folders", search = function(term) return rows.fuzzy(M.place_rows(), term) end }

--- Rows for universal search: files found by name, once there is enough to go
--- on, and recent files.
function M.universal(q)
  local out = {}
  if #q >= 3 and config.get("launcher.search_files") then
    for _, r in ipairs(file_rows(found("files-all", q), "File")) do out[#out + 1] = r end
  end
  return out
end

--- Recent files as candidates: `{ path, name, description }`, rows on demand.
function M.recent_candidates()
  local out = {}
  for _, f in ipairs(recent_list()) do
    out[#out + 1] = rows.file(f.path, false, "Recent")
  end
  return out
end

-- -------------------------------------------------------------- open with --

local opening

--- Lists applications to open `path` with. Returns the query that shows them.
function M.open_with(path)
  opening = path
  return "> with "
end

registry.mode { id = "with", name = "Open with", material = "apps", words = { "with" }, hidden = true, bare = false,
  search = function(term)
    if not opening then return { rows.note("with", "Nothing to open", "Choose a file first", "apps") } end
    local path = opening
    local apps = require("apps")
    local out = {}
    for _, a in ipairs(rows.fuzzy(apps.rows(), term)) do
      out[#out + 1] = rows.row {
        id = "with:" .. a.id, name = a.name, description = rows.tilde(path), icon = a.icon, tag = "App",
        run = function() return apps.open_file(a, path) end,
      }
      if #out >= 40 then break end
    end
    return out
  end }

return M
