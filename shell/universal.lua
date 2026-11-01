-- One box for everything: a plain search reaches apps, Settings pages, quick tiles,
-- open windows, files and actions, ranked together. Each source hands in rows; one
-- fuzzy pass over the lot ranks them, a source's weight and what was picked before
-- deciding between matches about as good.
--
-- The setting `launcher.sources` says which sources join, by name.
local config = require("config")
local index = require("lib.shell.launcher.search_index")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local pins = require("lib.shell.launcher.pins")

local M = {}

local KEYS = { "name", { "keywords", 0.4 }, { "description", 0.2 } }
-- The best matches ranked in Lua; the fuzzy pass over everything is native.
local CONSIDERED = 120

local function providers() return require("providers") end
local function apps() return require("apps") end

--- `entry` of the search index, as a row. A description that is a function is
--- read now.
function M.entry_row(entry)
  local description = entry.description
  if type(description) == "function" then
    local ok, value = pcall(description)
    description = ok and value or ""
  end
  local material = entry.material
  if type(material) == "function" then
    local ok, value = pcall(material)
    material = ok and value or nil
  end
  local current = false
  if entry.on then
    local ok, value = pcall(entry.on)
    current = ok and value == true
  end
  return rows.row {
    id = entry.id, name = entry.name, description = description or "", keywords = entry.keywords, tag = entry.tag,
    material = material, icon = entry.icon, current = current, pin = entry.pin or entry.id, run = entry.run,
    actions = entry.actions, kind = entry.kind,
  }
end

-- Rows are built once for what they are built from, not for each letter.
local built = {}
local function cached(name, from, make)
  local slot = built[name]
  if not slot or slot.from ~= from then
    slot = { from = from, rows = make(from) }
    built[name] = slot
  end
  return slot.rows
end

-- The index's rows, without what they say of themselves now.
local function index_rows()
  return cached("index", index.revision:get(), function()
    local out = {}
    for _, entry in ipairs(index.all()) do
      out[#out + 1] = rows.row {
        id = entry.id, name = entry.name, keywords = entry.keywords, tag = entry.tag, icon = entry.icon, kind = entry.kind,
        pin = entry.pin or entry.id, run = entry.run, actions = entry.actions, entry = entry,
        description = type(entry.description) == "string" and entry.description or "",
        material = type(entry.material) == "string" and entry.material or nil,
      }
    end
    return out
  end)
end

--- `row` with what its entry says now; nil when the machine lacks what it is for.
local function freshened(row)
  local entry = row.entry
  if not entry then return row end
  if entry.present then
    local ok, there = pcall(entry.present)
    if ok and not there then return nil end
  end
  local now = M.entry_row(entry)
  row.description, row.material, row.current = now.description, now.material, now.current
  return row
end

-- Each source: what it hands in, and how much a match in it counts.
local SOURCES = {
  apps = { 1, function() return apps().rows() end },
  settings = { 0.97, index_rows },
  windows = { 0.95, function() return (require("launcher_modes.windows").window_rows()) end },
  system = { 0.9, function() return providers().system_rows("") end },
  actions = { 0.9, function() return apps().ACTIONS end },
  app_actions = { 0.82, function() return apps().action_rows() end },
  places = { 0.85, function() return require("launcher_modes.files").place_rows() end },
  modes = { 0.8, function() return providers().mode_rows() end },
  snippets = { 0.8, function()
    local library = require("lib.shell.launcher.snippets")
    return cached("snippets", library.revision:get(), function()
      local out = {}
      local text = require("launcher_modes.text")
      for _, item in ipairs(library.all()) do out[#out + 1] = text.snippet_row(item) end
      return out
    end)
  end },
  recent = { 0.8, function()
    local files = require("launcher_modes.files")
    return cached("recent", files.recent_list(), files.recent_rows)
  end },
  bookmarks = { 0.76, function()
    local web = require("launcher_modes.web")
    return cached("bookmarks", web.bookmarks(), function(list)
      local out = {}
      for i, mark in ipairs(list) do out[i] = web.mark_row(mark) end
      return out
    end)
  end },
  files = { 0.78, nil },
}

local function pool(q)
  local items = {}
  local sources = config.get("launcher.sources")
  for _, name in ipairs(sources) do
    local source = SOURCES[name]
    local list
    if name == "files" then list = require("launcher_modes.files").universal(q)
    elseif source then list = source[2]() end
    for _, item in ipairs(list or {}) do
      item.weight = source and source[1] or 1
      item.kind = item.kind or "menu"
      items[#items + 1] = item
    end
  end
  return items
end

local function rank_id(item) return item.pin or item.id end

--- The alias `q` is, as a row, or nil.
local function alias_row(q)
  for _, alias in ipairs(pins.aliases()) do
    if alias.name == q then
      local target = alias.target
      local resolved = target:match("^%a+:") and providers().resolve(target)
      if resolved then return resolved end
      return rows.row { id = "alias:" .. alias.name, name = target, description = "Alias “" .. alias.name .. "”", material = "label",
        complete = target, run = function() return target end }
    end
  end
end

--- What a mode says of a query whose first word names it: its first few rows.
local function mode_rows(q)
  local word, rest = q:match("^(%S+)%s+(.+)$")
  local mode = word and registry.by_word(word)
  if not mode or mode.bare == false then return {}, nil end
  local found = mode.search(rest, q)
  local out = {}
  for i, r in ipairs(found or {}) do
    if i > 3 then break end
    r.kind = r.kind or "menu"
    r.id = r.id or (mode.id .. ":" .. i)
    r.tag = r.tag or mode.name
    out[#out + 1] = r
  end
  return out, mode
end

--- What `q` finds, best first: an answer, what a mode says, every source's matches
--- ranked together, then the fallbacks.
function M.search(q, limit)
  local prov = providers()
  prov.revision:get()
  index.revision:get()
  local app = apps()
  local hits = app.used.rank(q, pool(q), { key = KEYS, id = rank_id, best = CONSIDERED,
    boost = function(item) return item.weight or 1 end })
  hits = app.strict(q, hits)
  local out, seen = {}, {}
  local listed = 0
  local function add(r)
    local key = (r.kind or "menu") .. ":" .. tostring(r.id)
    if seen[key] then return end
    seen[key] = true
    if listed >= (limit or math.huge) then return end
    r = freshened(r)
    if not r then return end
    listed = listed + 1
    out[#out + 1] = r
  end
  local answer = prov.inline(q)
  if answer then add(answer) end
  local alias = alias_row(q)
  if alias then add(alias) end
  local learned = app.history.learned(q)
  if learned then
    for _, hit in ipairs(hits) do
      if rank_id(hit.item) == learned then add(hit.item) break end
    end
  end
  local exact = hits[1] and tostring(hits[1].item.name):lower() == q:lower()
  if exact then add(hits[1].item) end
  local said = mode_rows(q)
  for _, r in ipairs(said) do add(r) end
  for _, hit in ipairs(hits) do
    hit.item.positions = hit.key == "name" and hit.positions or nil
    add(hit.item)
  end
  listed = 0
  for _, f in ipairs(prov.fallbacks(q)) do add(f) end
  out.cap = limit and limit + 2 or nil
  return out
end

--- What the launcher shows before anything is typed: the favourites, then what
--- is used most.
function M.home(limit)
  local app = apps()
  local out = {}
  local prov = providers()
  local seen = {}
  for _, name in ipairs(pins.favourites()) do
    local r = prov.resolve(name)
    if r then
      if #out == 0 then out[1] = rows.row { kind = "header", id = "favourites", name = "Favourites" } end
      r.pinned = true
      seen[rank_id(r)] = true
      out[#out + 1] = r
    end
  end
  local had_pins = #out > 0
  local first = true
  for _, hit in ipairs(app.used.rank("", app.rows(), { key = KEYS, id = "id" })) do
    if not seen[rank_id(hit.item)] and not seen[hit.item.id] then
      if had_pins and first then
        out[#out + 1] = rows.row { kind = "header", id = "apps", name = "Apps" }
        first = false
      end
      hit.item.positions = nil
      out[#out + 1] = hit.item
    end
  end
  out.cap = limit
  return out
end

return M
