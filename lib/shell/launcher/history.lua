-- What was typed into the launcher and what it led to: the queries Up walks back
-- through, and the query that last picked each result, so a short word goes on
-- finding what it found.
--
--   local history = require("lib.shell.launcher.history")
--   local kept = history.open { path = morf.paths.state("eva-launcher-history.json") }
--   kept.add("fire", "app:firefox.desktop", "Firefox")
--   kept.older(); kept.newer(); kept.reset()     -- walking the queries
--   kept.learned("fire")                         -- "app:firefox.desktop"
--   kept.picks()                                 -- what was chosen, newest first

local morf = require("morf")

local M = {}

local QUERIES, PICKS, LEARNED = 200, 200, 400

--- Opens a store. Options: `path`, `debounce_ms` (500).
function M.open(opts)
  assert(type(opts) == "table" and opts.path, "history.open needs a path")
  local data = { queries = {}, picks = {}, learned = {} }
  local ok, text = pcall(morf.fs.read, opts.path)
  if ok and type(text) == "string" then
    local fine, decoded = pcall(morf.json.decode, text)
    if fine and type(decoded) == "table" then
      for _, key in ipairs { "queries", "picks", "learned" } do
        if type(decoded[key]) == "table" then data[key] = decoded[key] end
      end
    end
  end

  local store = {}
  local at, pending = 0, nil

  local function save()
    pending = nil
    morf.fs.write(opts.path, morf.json.encode(data), { atomic = true, parents = true, mode = 384 })
  end
  local function soon()
    if not pending then pending = morf.time.timer(opts.debounce_ms or 500, save, false) end
  end

  local function push(list, value, same, limit)
    for i = #list, 1, -1 do
      if same(list[i]) then table.remove(list, i) end
    end
    table.insert(list, 1, value)
    while #list > limit do list[#list] = nil end
  end

  --- Remembers that `query` led to the result `id`, named `name`.
  function store.add(query, id, name)
    query = tostring(query or "")
    if query:match("%S") then
      push(data.queries, query, function(other) return other == query end, QUERIES)
      if id then
        data.learned[query:lower()] = id
        local count = 0
        for key in pairs(data.learned) do
          count = count + 1
          if count > LEARNED then data.learned[key] = nil end
        end
      end
    end
    if id then
      push(data.picks, { id = id, name = name or id, query = query, at = morf.time.now() },
        function(other) return other.id == id end, PICKS)
    end
    at = 0
    soon()
  end

  --- The query one older than the one walked to, or nil at the far end.
  function store.older()
    if at >= #data.queries then return nil end
    at = at + 1
    return data.queries[at]
  end

  --- The query one newer, or "" past the newest.
  function store.newer()
    if at <= 0 then return nil end
    at = at - 1
    return at == 0 and "" or data.queries[at]
  end

  --- Whether a walk is under way.
  function store.walking() return at > 0 end

  --- Ends the walk.
  function store.reset() at = 0 end

  --- The result `query` picked last, or nil.
  function store.learned(query) return data.learned[tostring(query or ""):lower()] end

  --- What was picked, newest first: `{ id, name, query, at }` each.
  function store.picks() return data.picks end

  --- The queries, newest first.
  function store.queries() return data.queries end

  --- Forgets everything.
  function store.clear()
    data.queries, data.picks, data.learned = {}, {}, {}
    at = 0
    soon()
  end

  --- Writes now instead of a moment later.
  function store.flush()
    if pending then pending:cancel() save() end
  end

  return store
end

return M
