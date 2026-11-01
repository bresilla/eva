-- A board of tiles: which of a catalogue are shown, in what order and at what
-- size. The quick settings keep one list per form factor (`quick.tiles.<form>`
-- and `quick.small.<form>`); the bar keeps one per zone. State and actions only.
local morf = require("morf")
local config = require("config")
local M = {}

local function index_of(list, id)
  for i, v in ipairs(list) do if v == id then return i end end
end

-- Where the quick settings keep their lists. `form()` names the form factor,
-- asked the first time and then kept.
local function quick_store(form)
  local order_key, small_key
  local function keys()
    if order_key then return end
    order_key, small_key = "quick.tiles." .. form(), "quick.small." .. form()
  end
  return {
    order = function() keys() return config.get(order_key) end,
    set_order = function(_, list) keys() config.set(order_key, list) end,
    small = function() keys() return config.get(small_key) end,
    set_small = function(list) keys() config.set(small_key, list) end,
    reset = function() keys() config.reset(order_key) config.reset(small_key) end,
  }
end

--- A board over `catalogue` (tiles with `id`, optional `present()`). `form()`
--- names the form factor whose lists it keeps. `opts`: `zones` (names of the
--- lists it holds: one nameless list without), `store` (`order(zone)`,
--- `set_order(zone, list)`, `small()`, `set_small(list)`, `reset()`) and
--- `editing` (the signal saying it is being arranged).
function M.new(catalogue, form, opts)
  opts = opts or {}
  local store = opts.store or quick_store(form)
  local zones = opts.zones or { "" }
  local board = { zones = zones, editing = opts.editing or morf.signal("eva.quick.editing", false) }
  local by_id = {}
  for _, tile in ipairs(catalogue) do by_id[tile.id] = tile end

  local function here(id)
    local tile = by_id[id]
    return tile ~= nil and (tile.present == nil or tile.present() == true)
  end

  local function small_set()
    local set = {}
    for _, id in ipairs(store.small() or {}) do set[id] = true end
    return set
  end

  local function saved_order(zone) return store.order(zone) or {} end

  --- The zone `id` is saved in, or nil.
  function board.zone_of(id)
    for _, zone in ipairs(zones) do
      if index_of(saved_order(zone), id) then return zone end
    end
  end

  --- The tiles shown in `zone` (the first without), in order: `{ id, small }`.
  function board.shown(zone)
    local out, small, seen = {}, small_set(), {}
    for _, id in ipairs(saved_order(zone or zones[1])) do
      if here(id) and not seen[id] then
        seen[id] = true
        out[#out + 1] = { id = id, small = small[id] == true }
      end
    end
    return out
  end

  --- The tiles this machine has that are not shown: `{ id, small }`.
  function board.spare()
    local small, out = small_set(), {}
    for _, tile in ipairs(catalogue) do
      if not board.zone_of(tile.id) and here(tile.id) then
        out[#out + 1] = { id = tile.id, small = small[tile.id] == true }
      end
    end
    return out
  end

  local function copy(list)
    local out = {}
    for i, v in ipairs(list) do out[i] = v end
    return out
  end

  -- `id` out of the zone it is in, and in before the tile at `index` of `zone`.
  local function cross(id, index, zone)
    local from = board.zone_of(id)
    if not from then return false end
    local target = board.shown(zone)[index]
    local out = copy(saved_order(zone))
    table.insert(out, target and index_of(out, target.id) or #out + 1, id)
    local rest = {}
    for _, v in ipairs(saved_order(from)) do if v ~= id then rest[#rest + 1] = v end end
    store.set_order(from, rest)
    store.set_order(zone, out)
    return true
  end

  --- `id` moved to `index` among the tiles shown in `zone` (its own without);
  --- a tile the saved list holds that this machine lacks keeps its place
  --- behind those it stood behind.
  function board.move(id, index, zone)
    zone = zone or board.zone_of(id) or zones[1]
    if board.zone_of(id) ~= zone then return cross(id, index, zone) end
    local saved = saved_order(zone)
    local shown = board.shown(zone)
    local target = shown[math.max(1, math.min(index, #shown))]
    if not target or target.id == id then return false end
    local from, to = index_of(saved, id), index_of(saved, target.id)
    if not from or not to then return false end
    local out = copy(saved)
    table.remove(out, from)
    table.insert(out, to, id)
    store.set_order(zone, out)
    return true
  end

  --- `id` one step along its zone, across into the next zone at the end.
  function board.step(id, step)
    local zone = board.zone_of(id)
    if not zone then return false end
    local shown = board.shown(zone)
    for index, item in ipairs(shown) do
      if item.id == id then
        if shown[index + step] then return board.move(id, index + step, zone) end
        local next_zone = zones[(index_of(zones, zone) or 0) + step]
        if not next_zone then return false end
        return cross(id, step > 0 and 1 or #board.shown(next_zone) + 1, next_zone)
      end
    end
    return false
  end

  --- `id` taken off the board, to the Available tiles.
  function board.hide(id)
    for _, zone in ipairs(zones) do
      local saved, out = saved_order(zone), {}
      for _, v in ipairs(saved) do if v ~= id then out[#out + 1] = v end end
      if #out ~= #saved then store.set_order(zone, out) end
    end
  end

  --- `id` back on the board, at the end of `zone` (the board's last without).
  function board.add(id, zone)
    if not by_id[id] or board.zone_of(id) then return false end
    zone = zone or zones[#zones]
    local out = copy(saved_order(zone))
    out[#out + 1] = id
    store.set_order(zone, out)
    return true
  end

  --- Whether `id` is drawn small.
  function board.small(id) return small_set()[id] == true end

  --- `id` between its full and its small size.
  function board.toggle_size(id)
    local out, had = {}, false
    for _, v in ipairs(store.small() or {}) do
      if v == id then had = true else out[#out + 1] = v end
    end
    if not had then out[#out + 1] = id end
    store.set_small(out)
  end

  --- The form factor's own tiles and sizes again.
  function board.reset() store.reset() end

  return board
end

return M
