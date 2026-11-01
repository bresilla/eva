-- The system tray: a StatusNotifier watcher where no other panel runs one, the
-- engine's host, and a row per item. No nodes.
--
-- A row: `{ address, id, service, path, title, icon, file, pixmap, passive }`.
-- `id` is the item's own name, the same each run; `icon` is a theme icon's
-- name, `file` a picture on disk, `pixmap` a source for `ui.Image`: whichever the
-- item gave. Rows are read from the item without waiting on it, and again when
-- it says it changed.
--
-- `edgebar.tray_items` keeps a person's arrangement, `{ id, title, place }` in
-- their order: `bar`, `more` (behind the overflow arrow) or `hide`. What arrives
-- unknown goes last, on the bar; a passive item stays away, as it asks.
local morf = require("morf")

local M = {}

M.PLACES = { { "bar", "On the bar" }, { "more", "Tucked away" }, { "hide", "Hidden" } }
-- As many as a bar will ever hold: no limit at all.
M.ROOMY = 1024

--- How many of `count` icons, each `step` along, stand in `given`: the arrow
--- takes one's place where they do not all fit.
function M.room_for(given, step, count)
  local fits = math.floor(given / step)
  if fits >= count then return M.ROOMY end
  return math.max(1, fits - 1)
end

--- The arrangement kept.
local function kept()
  local list = require("config").get("edgebar.tray_items")
  return type(list) == "table" and list or {}
end

--- `rows` in a person's order, split into what goes on the bar and behind the
--- arrow; `room` is how many the bar has space for.
function M.arrange(rows, list, room)
  local order, by_id = {}, {}
  for index, row in ipairs(list or {}) do by_id[row.id] = { index = index, place = row.place } end
  local ranked = {}
  for index, row in ipairs(rows) do
    local keep = by_id[row.id]
    if not row.passive and not (keep and keep.place == "hide") then
      ranked[#ranked + 1] = { row = row, rank = keep and keep.index or (#(list or {}) + index), more = keep and keep.place == "more" }
    end
  end
  table.sort(ranked, function(a, b) return a.rank < b.rank end)
  local bar, more = {}, {}
  for _, entry in ipairs(ranked) do
    order[#order + 1] = entry.row
    if entry.more or #bar >= room then more[#more + 1] = entry.row else bar[#bar + 1] = entry.row end
  end
  return order, bar, more
end

local ITEM = "org.kde.StatusNotifierItem"
local PROPERTIES = "org.freedesktop.DBus.Properties"
local CHANGES = { "NewIcon", "NewAttentionIcon", "NewTitle", "NewStatus", "NewToolTip" }
-- The size a pixmap is chosen nearest to.
local WANTED = 44
local TIMEOUT = 2000

local function dry_run()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= false and v ~= "" and v ~= "0"
end

--- ARGB bytes, as a tray item sends them, as RGBA.
function M.rgba(data)
  local out = {}
  for i = 1, #data - 3, 4 do
    local a, r, g, b = data:byte(i, i + 3)
    out[#out + 1] = string.char(r, g, b, a)
  end
  return table.concat(out)
end

--- The pixmap of `list` (each `{ width, height, data }`) nearest `size`.
function M.nearest(list, size)
  local best
  for _, entry in ipairs(list or {}) do
    local w, h, data = entry[1], entry[2], entry[3]
    if type(w) == "number" and w > 0 and type(h) == "number" and h > 0 and type(data) == "string"
      and #data >= w * h * 4 and (not best or math.abs(w - size) < math.abs(best[1] - size)) then
      best = entry
    end
  end
  return best
end

-- A name on disk under the item's own theme path, or an absolute one.
local function file_of(name, folder)
  if name:sub(1, 1) == "/" then return name end
  if folder == "" then return nil end
  for _, extension in ipairs { ".svg", ".png" } do
    local path = folder .. "/" .. name .. extension
    if morf.fs.exists(path) then return path end
  end
end

local function publish(address, list)
  local entry = M.nearest(list, WANTED)
  if not (entry and morf.image and morf.image.from_dbus) then return nil end
  local w, h = entry[1], entry[2]
  local ok, source = pcall(morf.image.from_dbus, { width = w, height = h, rowstride = 4 * w, has_alpha = true,
    bits_per_sample = 8, channels = 4, data = M.rgba(entry[3]) }, { name = "tray-" .. address })
  return ok and source or nil
end

--- A row from an item's properties.
function M.row(address, service, path, props)
  local attention = props.Status == "NeedsAttention"
  local name = attention and props.AttentionIconName or nil
  if not name or name == "" then name = props.IconName or "" end
  local list = attention and props.AttentionIconPixmap or nil
  if type(list) ~= "table" or #list == 0 then list = props.IconPixmap end
  local title = props.Title
  if not title or title == "" then title = props.Id or "" end
  local folder = props.IconThemePath or ""
  local file = name ~= "" and file_of(name, folder) or nil
  local id = props.Id
  if not id or id == "" then id = title ~= "" and title or address end
  return { address = address, id = id, service = service, path = path, title = title,
    icon = not file and name or "", file = file or "", passive = props.Status == "Passive",
    pixmap = (name == "" or (not file and morf.image and morf.image.has_icon and not morf.image.has_icon(name)))
      and publish(address, list) or nil }
end

-- A click on an item's menu goes nowhere in a dry run.
local function hold_menus()
  local menus = require("lib.services.tray_menu")
  local for_item = menus.for_item
  menus.for_item = function(address, options)
    local menu, why = for_item(address, options)
    if menu then menu.click = function(id) morf.log("info", "eva: tray menu " .. tostring(id) .. " (dry run)") end end
    return menu, why
  end
end

--- The tray. `opts.dbus` stands in for `morf.dbus`, `opts.host` for
--- `morf.status_notifier`, `opts.watcher` for lib.services.tray.
function M.new(opts)
  opts = opts or {}
  local client = require("lib.services.dbus").new { bus = "session", dbus = opts.dbus }
  -- `rows` is all that shows, `bar` and `more` where.
  local model = { rows = morf.list_model({}), bar = morf.list_model({}), more = morf.list_model({}),
    -- How many icons the bar's slot has room for.
    room = morf.signal("eva.tray.room", M.ROOMY), ROOMY = M.ROOMY }
  local order, known, listening = {}, {}, {}

  local function present()
    local rows = {}
    for _, address in ipairs(order) do
      if known[address] then rows[#rows + 1] = known[address] end
    end
    return rows
  end

  local function limit()
    local value = tonumber(require("config").get("edgebar.tray_limit"))
    return math.min(model.room:get(), value and value > 0 and value or model.ROOMY)
  end

  local function publish_rows()
    local all, bar, more = M.arrange(present(), kept(), limit())
    model.rows:replace(all, "address")
    model.bar:replace(bar, "address")
    model.more:replace(more, "address")
  end

  morf.effect("eva.tray.arrange", function()
    kept()
    limit()
    publish_rows()
  end)

  --- Every item a person can arrange: those here and those kept, in order, each
  --- `{ id, title, place, here }`.
  function model.items()
    local out, seen = {}, {}
    for _, row in ipairs(kept()) do
      seen[row.id] = #out + 1
      out[#out + 1] = { id = row.id, title = row.title, place = row.place or "bar", here = false }
    end
    for _, row in ipairs(present()) do
      local at = seen[row.id]
      if at then
        out[at].here, out[at].title = true, row.title
      elseif not row.passive then
        out[#out + 1] = { id = row.id, title = row.title, place = "bar", here = true }
      end
    end
    return out
  end

  local function store(items)
    local list = {}
    for index, item in ipairs(items) do list[index] = { id = item.id, title = item.title, place = item.place } end
    require("config").set("edgebar.tray_items", list)
  end

  --- Puts an item on the bar, behind the arrow, or nowhere.
  function model.place(id, place)
    local items = model.items()
    for _, item in ipairs(items) do if item.id == id then item.place = place end end
    store(items)
  end

  --- The next place for an item, round the three.
  function model.next_place(id)
    for _, item in ipairs(model.items()) do
      if item.id == id then
        for index, place in ipairs(M.PLACES) do
          if place[1] == item.place then return model.place(id, M.PLACES[index % #M.PLACES + 1][1]) end
        end
      end
    end
  end

  --- Moves an item `by` places along.
  function model.move(id, by)
    local items = model.items()
    for index, item in ipairs(items) do
      if item.id == id then
        local to = math.max(1, math.min(#items, index + by))
        table.remove(items, index)
        table.insert(items, to, item)
        break
      end
    end
    store(items)
  end

  local function read(address, service, path)
    client.call_async(service, path, PROPERTIES, "GetAll", { ITEM }, TIMEOUT, function(reply)
      if not listening[address] then return end
      local props = reply and reply[1] or nil
      if type(props) ~= "table" then return end
      known[address] = M.row(address, service, path, props)
      publish_rows()
    end)
  end

  local function follow(item)
    local address = item.service .. item.path
    local handles = {}
    for _, member in ipairs(CHANGES) do
      local ok, handle = pcall(client.on_signal, item.service, item.path, ITEM, member,
        function() read(address, item.service, item.path) end)
      if ok then handles[#handles + 1] = handle end
    end
    listening[address] = handles
    read(address, item.service, item.path)
  end

  local function drop(address)
    for _, handle in ipairs(listening[address] or {}) do pcall(handle.close, handle) end
    listening[address], known[address] = nil, nil
    if morf.image and morf.image.release then pcall(morf.image.release, "tray-" .. address) end
  end

  --- The engine's list of items, as it changes.
  function model.update(items)
    local here = {}
    order = {}
    for _, item in ipairs(items) do
      local address = item.service .. item.path
      here[address] = true
      order[#order + 1] = address
      if not listening[address] then follow(item) end
    end
    for address in pairs(listening) do if not here[address] then drop(address) end end
    publish_rows()
  end

  --- Activates an item, as a click on it means. A dry run only says so.
  function model.activate(address)
    local row = known[address]
    if not row then return false end
    if dry_run() then
      morf.log("info", "eva: tray activate " .. address .. " (dry run)")
      return true
    end
    local dbus = require("lib.services.dbus")
    return client.call_async(row.service, row.path, ITEM, "Activate", { dbus.i(0), dbus.i(0) }, TIMEOUT)
  end

  if dry_run() then pcall(hold_menus) end
  local running, watching, subscribed = false, nil, false

  --- Puts the tray up: the watcher, unless another panel has it, and the host.
  function model.start()
    if running then return end
    running = true
    local ok, watcher = pcall((opts.watcher or require("lib.services.tray")).serve, { replace = false })
    watching = ok and watcher or nil
    local host = opts.host or morf.status_notifier
    if host and not subscribed then
      subscribed = pcall(host.subscribe, function(items) if running then model.update(items) end end)
    end
  end

  --- Takes it down: its rows go, and the watcher's name with them.
  function model.stop()
    if not running then return end
    running = false
    if watching and watching.close then pcall(watching.close) end
    watching = nil
    model.update({})
  end

  return model
end

return M
