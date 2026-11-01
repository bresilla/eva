-- The board of quick-settings tiles: which of the catalogue are shown, in
-- what order and at what size, per form factor (`quick.tiles.<form>` and
-- `quick.small.<form>`). State and actions only.
local morf = require("morf")
local config = require("config")
local M = {}

local function index_of(list, id)
  for i, v in ipairs(list) do if v == id then return i end end
end

--- A board over `catalogue` (tiles with `id`, optional `present()`).
--- `form()` names the form factor whose list it keeps. `options`: `order` and
--- `small`, the setting prefixes it keeps them under, and `name`, its signals'.
function M.new(catalogue, form, options)
  options = options or {}
  local board = { editing = morf.signal((options.name or "eva.quick") .. ".editing", false) }
  local by_id = {}
  for _, tile in ipairs(catalogue) do by_id[tile.id] = tile end
  local order_key, small_key
  local function keys()
    if order_key then return end
    order_key, small_key = (options.order or "quick.tiles.") .. form(), (options.small or "quick.small.") .. form()
  end

  local function here(id)
    local tile = by_id[id]
    return tile ~= nil and (tile.present == nil or tile.present() == true)
  end

  local function small_set()
    keys()
    local set = {}
    for _, id in ipairs(config.get(small_key) or {}) do set[id] = true end
    return set
  end

  local function saved_order()
    keys()
    return config.get(order_key) or {}
  end

  --- The tiles shown, in order: `{ id, small }`.
  function board.shown()
    local out, small, seen = {}, small_set(), {}
    for _, id in ipairs(saved_order()) do
      if here(id) and not seen[id] then
        seen[id] = true
        out[#out + 1] = { id = id, small = small[id] == true }
      end
    end
    return out
  end

  --- The tiles this machine has that are not shown: `{ id, small }`.
  function board.spare()
    local saved, small, out = {}, small_set(), {}
    for _, id in ipairs(saved_order()) do saved[id] = true end
    for _, tile in ipairs(catalogue) do
      if not saved[tile.id] and here(tile.id) then
        out[#out + 1] = { id = tile.id, small = small[tile.id] == true }
      end
    end
    return out
  end

  --- `id` moved to `index` among the tiles shown; a tile the saved list
  --- holds that this machine lacks keeps its place behind those it stood
  --- behind.
  function board.move(id, index)
    local saved = saved_order()
    local shown = board.shown()
    local target = shown[math.max(1, math.min(index, #shown))]
    if not target or target.id == id then return false end
    local from, to = index_of(saved, id), index_of(saved, target.id)
    if not from or not to then return false end
    local out = {}
    for i, v in ipairs(saved) do out[i] = v end
    table.remove(out, from)
    table.insert(out, to, id)
    config.set(order_key, out)
    return true
  end

  --- `id` taken off the board, to the Available tiles.
  function board.hide(id)
    local out = {}
    for _, v in ipairs(saved_order()) do if v ~= id then out[#out + 1] = v end end
    config.set(order_key, out)
  end

  --- `id` back on the board, at its end.
  function board.add(id)
    if not by_id[id] then return false end
    local saved = saved_order()
    if index_of(saved, id) then return false end
    local out = {}
    for i, v in ipairs(saved) do out[i] = v end
    out[#out + 1] = id
    config.set(order_key, out)
    return true
  end

  --- Whether `id` is drawn small.
  function board.small(id) return small_set()[id] == true end

  --- `id` between its full and its small size.
  function board.toggle_size(id)
    keys()
    local out, had = {}, false
    for _, v in ipairs(config.get(small_key) or {}) do
      if v == id then had = true else out[#out + 1] = v end
    end
    if not had then out[#out + 1] = id end
    config.set(small_key, out)
  end

  --- The form factor's own tiles and sizes again.
  function board.reset()
    keys()
    config.reset(order_key)
    config.reset(small_key)
  end

  return board
end

return M
