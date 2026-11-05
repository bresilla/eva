-- The launcher's other menus, opened over IPC so a key can bring either straight
-- up: `launcher apps`, `launcher web`, and `eva dmenu`.
--
--   apps     the Flatpak apps, and with Tab the AppImages in the folders of
--            `launcher.menus.appimages`; Return starts one, detached
--   web      history, bookmarks, search and the like; anything else typed opens
--            as an address, or is searched on the first engine, in $BROWSER
--   dmenu    lines handed in, and the one picked handed back
--
-- What they read lies in the settings under `launcher.menus`. The history is any
-- Firefox's or Chromium's; the pages named after the `bookmark` tool's files
-- (proxmox, playlist, app-list) show when those files are there. Escape on a page
-- goes back to the menu, then shuts the launcher. EVA_DRY_RUN=1 logs what would be
-- started instead.

local morf = require("morf")
local config = require("config")
local run = require("lib.shell.launcher.run")
local rows = require("lib.shell.launcher.rows")
local bookmarks = require("lib.shell.launcher.bookmarks")
local appimage_icons = require("lib.shell.launcher.appimage_icons")

local M = {}

--- Which menu the launcher shows ("" for its own), and the page of it.
M.source = morf.signal("eva.menus.source", "")
M.page = morf.signal("eva.menus.page", "")

local start = run.start

local function browser_open(url)
  return run.browse(url)
end

local function fuzzy(list, term, key)
  return rows.fuzzy(list, term, key or { "name", { "description", 0.5 } })
end

local function setting(key) return config.get("launcher.menus." .. key) end
local function tool_file(name) return rows.untilde(setting("bookmarks")) .. "/" .. name end

-- -------------------------------------------------------------------- apps --

local app_rows = morf.signal("eva.menus.apps", {})

-- The kinds the apps menu lists, one at a time, in the order Tab goes through.
M.GROUPS = { { id = "flatpak", name = "Flatpak" }, { id = "appimage", name = "AppImages" } }
M.group = morf.signal("eva.menus.group", M.GROUPS[1].id)

local function filled(id)
  for _, r in ipairs(app_rows:get()) do
    if r.group == id then return true end
  end
  return false
end

--- The group on show: the chosen one while it has apps, else the first that has.
function M.shown_group()
  if filled(M.group:get()) then return M.group:get() end
  for _, g in ipairs(M.GROUPS) do
    if filled(g.id) then return g.id end
  end
  return M.group:get()
end

--- The name of the group on show.
function M.group_name()
  local id = M.shown_group()
  for _, g in ipairs(M.GROUPS) do
    if g.id == id then return g.name end
  end
  return "Apps"
end

--- The next group with apps, `delta` 1 or -1; true when it moved.
function M.next_group(delta)
  local at, count = 1, #M.GROUPS
  for i, g in ipairs(M.GROUPS) do
    if g.id == M.shown_group() then at = i end
  end
  for step = 1, count - 1 do
    local g = M.GROUPS[(at - 1 + step * (delta or 1)) % count + 1]
    if filled(g.id) then
      M.group:set(g.id)
      return true
    end
  end
  return false
end

--- Reads the Flatpak apps and the AppImages afresh.
function M.refresh_apps()
  local list = {}
  for _, folder in ipairs(setting("appimages")) do
    local dir = rows.untilde(folder)
    local ok, entries = pcall(morf.fs.list, dir)
    if ok and type(entries) == "table" then
      for _, e in ipairs(entries) do
        local name = e.name or ""
        if e.is_file and name:lower():match("%.appimage$") then
          local row = {
            id = "appimage:" .. name, group = "appimage", name = (name:gsub("%.[Aa]pp[Ii]mage$", "")),
            description = dir .. "/" .. name, material = "deployed_code",
            argv = { dir .. "/" .. name },
          }
          list[#list + 1] = row
          -- Its own icon once read; the plain glyph until then.
          local icon = appimage_icons.cached(row.argv[1])
          if icon then
            row.icon, row.material = icon, nil
          elseif icon == nil then
            appimage_icons.fetch(row.argv[1], function(found)
              if not found then return end
              row.icon, row.material = found, nil
              local shown = {}
              for i, r in ipairs(app_rows:get()) do
                if r.id == row.id then
                  local copy = {}
                  for k, v in pairs(r) do copy[k] = v end
                  copy.icon, copy.material = found, nil
                  r = copy
                end
                shown[i] = r
              end
              app_rows:set(shown)
            end)
          end
        end
      end
    end
  end
  app_rows:set(list)
  morf.process.run({ "flatpak", "list", "--app", "--columns=application,name" }, {}, function(result)
    if not (result and result.ok) then return end
    local all = {}
    for _, r in ipairs(list) do all[#all + 1] = r end
    for line in tostring(result.stdout or ""):gmatch("[^\n]+") do
      local id, name = line:match("^(%S+)\t(.*)$")
      if id then
        all[#all + 1] = {
          id = "flatpak:" .. id, group = "flatpak", name = name ~= "" and name or id, description = id, icon = id,
          argv = { "flatpak", "run", id },
        }
      end
    end
    table.sort(all, function(a, b) return a.name:lower() < b.name:lower() end)
    app_rows:set(all)
  end)
end

-- --------------------------------------------------------------------- web --

local function mark_rows(file, group, icon, act)
  local out = {}
  for _, item in ipairs(bookmarks.tool_file(tool_file(file), group)) do
    out[#out + 1] = {
      kind = "menu", id = file .. ":" .. tostring(item.id or item.url), name = item.name,
      description = item.url, material = icon,
      run = function() return act(item.url) end,
    }
  end
  return out
end

-- The browser's history, newest first: read from a copy (the browser holds the
-- database open), off the main loop.
local history = morf.signal("eva.menus.history", {})
local FIREFOX_QUERY = "SELECT url, title FROM moz_places WHERE url NOT LIKE '%google%search%' "
  .. "ORDER BY last_visit_date DESC, visit_count DESC LIMIT 3000;"
local CHROMIUM_QUERY = "SELECT url, title FROM urls ORDER BY last_visit_time DESC LIMIT 3000;"
local HISTORY_SCRIPT = [[
db=$(ls -t "$HOME"/.var/app/app.zen_browser.zen/.zen/*/places.sqlite "$HOME"/.zen/*/places.sqlite \
  "$HOME"/.mozilla/firefox/*/places.sqlite \
  "$HOME"/.var/app/org.mozilla.firefox/.mozilla/firefox/*/places.sqlite 2>/dev/null | head -1)
query=$0
if [ -z "$db" ]; then
  db=$(ls -t "$HOME"/.config/chromium/Default/History "$HOME"/.config/google-chrome/Default/History \
    "$HOME"/.config/BraveSoftware/Brave-Browser/Default/History 2>/dev/null | head -1)
  query=$1
fi
[ -n "$db" ] || exit 1
copy=$(mktemp) && cp -f "$db" "$copy" && sqlite3 -separator "$(printf '\t')" "$copy" "$query"; rm -f "$copy"]]

local function refresh_history()
  morf.process.run({ "sh", "-c", HISTORY_SCRIPT, FIREFOX_QUERY, CHROMIUM_QUERY }, { max_output = 4 * 1024 * 1024 }, function(result)
    if not (result and result.ok) then return end
    local list = {}
    for line in tostring(result.stdout or ""):gmatch("[^\n]+") do
      local url, title = line:match("^([^\t]*)\t?(.*)$")
      if url and url ~= "" then
        local shown = url:gsub("^https?://", ""):gsub("/$", "")
        list[#list + 1] = {
          id = "history:" .. #list, name = title ~= "" and title or shown,
          description = shown, material = "history", url = url,
        }
      end
    end
    history:set(list)
  end)
end

local web = require("web")
local search_url = web.search_url

--- What typed text does on the menu itself: an address opens, anything
--- else is searched on the first engine.
local function typed_row(query)
  local engine = web.engines()[1]
  local address = query:match("^https?://") or query:match("^[%w-]+%.[%a][%a]+")
  return {
    kind = "menu", id = "typed", name = query,
    description = address and "Open" or ("Search " .. engine.name), material = address and "open_in_new" or "search",
    run = function()
      if address then return browser_open(query:match("^https?://") and query or ("https://" .. query)) end
      return browser_open(search_url(engine, query))
    end,
  }
end

local function go(page)
  return function()
    M.page:set(page)
    if page == "history" then refresh_history() end
    return ""
  end
end

--- The pages of the menu: those whose source is there.
local function categories()
  local out = {
    { page = "history", name = "history", description = "What your browser visited, newest first", material = "history" },
    { page = "bookmarks", name = "bookmarks", description = "Your bookmarks", material = "bookmark" },
  }
  if #bookmarks.tool_file(tool_file("webmarks_v0.1.json"), "proxmox") > 0 then
    out[#out + 1] = { page = "proxmox", name = "proxmox", description = "The cluster's pages", material = "dns" }
  end
  out[#out + 1] = { page = "search", name = "search", description = "Search one engine for something", material = "travel_explore" }
  if morf.fs.exists(tool_file("playmarks_v0.1.json")) then
    out[#out + 1] = { page = "playlist", name = "playlist", description = "Play a list", material = "playlist_play" }
  end
  if morf.fs.exists(tool_file("climarks_v0.1.json")) then
    out[#out + 1] = { page = "app-list", name = "app-list", description = "Tools worth knowing", material = "terminal" }
  end
  out[#out + 1] = { page = "packages", name = "packages", description = "Search pkgs.org", material = "inventory_2" }
  return out
end

local function play(url)
  local argv = {}
  for i, word in ipairs(setting("player")) do argv[i] = rows.untilde(tostring(word)) end
  argv[#argv + 1] = url
  start(argv)
  return "close"
end

local function web_page(query)
  local page = M.page:get()
  if page == "" then
    local out = {}
    for _, c in ipairs(categories()) do
      out[#out + 1] = {
        kind = "menu", id = "category:" .. c.page, name = c.name, description = c.description,
        material = c.material, run = go(c.page),
      }
    end
    out = fuzzy(out, query)
    -- Typed text that is no category is an address or a search.
    if query ~= "" then
      local exact = out[1] and out[1].name:lower():find(query:lower(), 1, true) == 1
      if exact then out[#out + 1] = typed_row(query) else table.insert(out, 1, typed_row(query)) end
    end
    return out
  elseif page == "history" then
    local out = {}
    for i, h in ipairs(fuzzy(history:get(), query)) do
      if i > 200 then break end
      out[i] = { kind = "menu", id = h.id, name = h.name, description = h.description, material = h.material,
        run = function() return browser_open(h.url) end }
    end
    return out
  elseif page == "bookmarks" then
    local marks = require("launcher_modes.web")
    local out = {}
    for i, mark in ipairs(marks.bookmarks()) do out[i] = marks.mark_row(mark) end
    return fuzzy(out, query)
  elseif page == "proxmox" then
    return fuzzy(mark_rows("webmarks_v0.1.json", "proxmox", "dns", browser_open), query)
  elseif page == "playlist" then
    return fuzzy(mark_rows("playmarks_v0.1.json", nil, "playlist_play", play), query)
  elseif page == "app-list" then
    return fuzzy(mark_rows("climarks_v0.1.json", nil, "terminal", browser_open), query)
  elseif page == "packages" then
    if query == "" then
      return { { kind = "menu", id = "packages", name = "Type a package", description = "pkgs.org", material = "inventory_2",
        run = function() return "keep" end } }
    end
    return { { kind = "menu", id = "packages", name = query, description = "Search pkgs.org", material = "inventory_2",
      run = function() return browser_open("https://pkgs.org/search/?q=" .. morf.encoding.url_encode(query)) end } }
  elseif page == "search" then
    local out = {}
    for _, e in ipairs(web.engines()) do
      out[#out + 1] = { kind = "menu", id = "engine:" .. e.id, name = e.name, description = e.url:gsub("%%s", "…"),
        material = "travel_explore", run = go("search:" .. e.id) }
    end
    return fuzzy(out, query)
  elseif page:match("^search:") then
    local e = web.engine(page:sub(8))
    if e then
      if query == "" then
        return { { kind = "menu", id = "engine", name = "Search " .. e.name, description = "Type what to look for",
          material = "travel_explore", run = function() return "keep" end } }
      end
      return { { kind = "menu", id = "engine", name = query, description = "Search " .. e.name, material = "travel_explore",
        run = function() return browser_open(search_url(e, query)) end } }
    end
  end
  return {}
end

-- ------------------------------------------------------------------- dmenu --

local picking

--- Lists `lines` under `prompt`; `done(line)` hears the one picked, or nil.
function M.dmenu(lines, prompt, done)
  local list = {}
  for i, line in ipairs(lines) do
    list[i] = { id = "line:" .. i, name = line, material = "chevron_right" }
  end
  picking = { rows = list, prompt = prompt or "Choose", done = done }
  M.page:set("")
  M.source:set("dmenu")
end

--- What the dmenu on show is called.
function M.prompt() return picking and picking.prompt or "Choose" end

--- Hands the pick back, or nothing: the launcher is shutting.
function M.finish(line)
  if not picking then return end
  local done = picking.done
  picking = nil
  if done then done(line) end
end

local function dmenu_rows(query)
  if not picking then return {} end
  local out = {}
  for i, line in ipairs(fuzzy(picking.rows, query, "name")) do
    out[i] = { kind = "menu", id = line.id, name = line.name, material = line.material,
      run = function() M.finish(line.name) return "close" end }
  end
  return out
end

--- The rows for `query` in the menu on show, best first.
function M.search(query, limit)
  local source = M.source:get()
  local found
  if source == "apps" then
    local shown, pool = M.shown_group(), {}
    for _, r in ipairs(app_rows:get()) do
      if r.group == shown then pool[#pool + 1] = r end
    end
    local list = fuzzy(pool, query)
    local out = {}
    for i = 1, math.min(#list, limit or #list) do
      local r = list[i]
      out[i] = { kind = "menu", id = r.id, name = r.name, description = r.description,
        icon = r.icon, material = r.material,
        run = function() start(r.argv) return "close" end }
    end
    return out, "apps"
  elseif source == "dmenu" then
    found = dmenu_rows(query)
  else
    found = web_page(query)
  end
  local out = {}
  for i = 1, math.min(#found, limit or #found) do out[i] = found[i] end
  return out, "apps"
end

--- Opens `source` ("apps", "web" or "dmenu") from its top.
function M.open(source)
  M.page:set("")
  local before = M.source:get()
  if before == "dmenu" and source ~= "dmenu" then M.finish(nil) end
  M.source:set((source == "web" or source == "apps" or source == "dmenu") and source or "")
  if M.source:get() == "apps" then
    M.group:set(M.GROUPS[1].id)
    M.refresh_apps()
  end
end

--- Escape: back to the menu from a page (true), or nothing to go back to.
function M.back()
  if M.source:get() ~= "" and M.page:get() ~= "" then
    local page = M.page:get()
    M.page:set(page:match("^search:") and "search" or "")
    return true
  end
  return false
end

return M
