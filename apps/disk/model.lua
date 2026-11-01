-- eva-disk's state: what is under a folder, from `du` runs off the main loop, the
-- boxes of the treemap, the way back up, and each mount's use from
-- lib.services.sysinfo. No nodes.
local morf = require("morf")
local sysinfo = require("lib.services.sysinfo")
local performance = require("performance_model")
local sys = require("common.sys")
local treemap = require("treemap")

local M = {
  tab = morf.signal("disk.tab", 1),
  path = morf.signal("disk.path", ""),
  draft = morf.signal("disk.draft", ""),
  entries = morf.signal("disk.entries", {}),
  total = morf.signal("disk.total", 0),
  scanning = morf.signal("disk.scanning", false),
  message = morf.signal("disk.message", ""),
  boxes = morf.signal("disk.boxes", {}),
  area = morf.signal("disk.area", { 0, 0 }),
  moving = morf.signal("disk.moving", false),
  chosen = morf.signal("disk.chosen", ""),
}

M.TABS = { "folder", "mounts" }
-- The boxes a field holds, the most entries kept of a folder, how many folders
-- are remembered, how long lines wait to land together, and how long a change
-- of boxes counts as moving.
M.BOXES = 16
M.KEEP = 2048
M.REMEMBERED = 32
M.FLUSH = 200
M.SETTLE = 600
M.GAP = 4
-- What a crumb takes: per character, beside its text, and the crumb of what is cut.
M.CRUMB_CHAR = 10
M.CRUMB_EDGE = 44
M.CRUMB_CUT = 56

M.root = morf.env("EVA_DISK_ROOT") or ""

local remembered, order = {}, {}
local child, flush_timer, settle_timer
local generation = 0
local incoming = {}

--- `bytes` in words.
function M.size(bytes)
  local number, unit = performance.bytes(bytes)
  return number .. " " .. unit
end

--- What `du -x -a -k --max-depth=1` says of one entry: its path and bytes.
function M.parse(line)
  local size, path = line:match("^(%d+)%s+(.+)$")
  if not size then return nil end
  return { path = path, size = tonumber(size) * 1024 }
end

--- The folders from `/` down to `path`, each `{ label, path }`.
function M.crumbs(path)
  local out = { { label = "/", path = "/" } }
  local at = ""
  for part in path:gmatch("[^/]+") do
    at = at .. "/" .. part
    out[#out + 1] = { label = part, path = at }
  end
  return out
end

--- As many of `crumbs`, from the end, as fit `width`; what is cut goes behind a
--- first crumb that leads to the folder above the ones shown.
function M.tail(crumbs, width)
  local room, first = width - M.CRUMB_CUT, #crumbs + 1
  for index = #crumbs, 1, -1 do
    room = room - #crumbs[index].label * M.CRUMB_CHAR - M.CRUMB_EDGE
    if room < 0 then break end
    first = index
  end
  first = math.min(first, #crumbs)
  if first <= 1 then return crumbs end
  local out = { { label = "…", path = crumbs[first - 1].path } }
  for index = first, #crumbs do out[#out + 1] = crumbs[index] end
  return out
end

--- The folder above `path`, or nil at the top.
function M.parent(path)
  if path == "/" or path == "" then return nil end
  local up = path:match("^(.*)/[^/]+/?$")
  return (up == nil or up == "") and "/" or up
end

local function is_dir(path)
  local ok, value = pcall(morf.fs.is_dir, path)
  return ok and value == true
end

-- The treemap's boxes for the entries and the room there is. The last box stands
-- for what does not fit.
local function layout()
  local entries, total = M.entries:get(), M.total:get()
  local room = M.area:get()
  local shown, rest = {}, 0
  for index, entry in ipairs(entries) do
    if index < M.BOXES or #entries == M.BOXES then
      shown[#shown + 1] = entry
    else
      rest = rest + entry.size
    end
  end
  local sizes = {}
  for index, entry in ipairs(shown) do sizes[index] = entry.size end
  if rest > 0 then sizes[#sizes + 1] = rest end
  local rects = treemap.layout(sizes, 0, 0, room[1], room[2])
  local boxes = {}
  for index, rect in ipairs(rects) do
    local entry = shown[index]
    local inset = M.GAP / 2
    boxes[index] = {
      x = rect.x + inset, y = rect.y + inset, w = math.max(0, rect.w - M.GAP), h = math.max(0, rect.h - M.GAP),
      name = entry and entry.name or ("%d others"):format(#entries - #shown),
      size = sizes[index], path = entry and entry.path or "", dir = entry and entry.dir or false, others = entry == nil,
      share = total > 0 and sizes[index] / total or 0,
    }
  end
  M.boxes:set(boxes)
  M.moving:set(true)
  if settle_timer then settle_timer:cancel() end
  settle_timer = morf.time.timer(M.SETTLE, function()
    settle_timer = nil
    M.moving:set(false)
  end, false)
end

local function remember(path, entries, total)
  if not remembered[path] then order[#order + 1] = path end
  remembered[path] = { entries = entries, total = total }
  while #order > M.REMEMBERED do
    remembered[table.remove(order, 1)] = nil
  end
end

local function publish(entries, total)
  table.sort(entries, function(a, b)
    if a.size == b.size then return a.name < b.name end
    return a.size > b.size
  end)
  while #entries > M.KEEP do entries[#entries] = nil end
  for index = 1, math.min(M.BOXES, #entries) do
    local entry = entries[index]
    if entry.dir == nil then entry.dir = is_dir(entry.path) end
  end
  local sum = 0
  for _, entry in ipairs(entries) do sum = sum + entry.size end
  M.entries:set(entries)
  M.total:set(total or sum)
  layout()
end

local function flush(path)
  flush_timer = nil
  if #incoming == 0 then return end
  local entries = M.entries:get()
  local merged = {}
  for _, entry in ipairs(entries) do merged[#merged + 1] = entry end
  local total
  for _, found in ipairs(incoming) do
    if found.path == path then
      total = found.size
    else
      found.name = found.path:match("([^/]+)/?$") or found.path
      merged[#merged + 1] = found
    end
  end
  incoming = {}
  publish(merged, total)
end

--- Stops a scan under way.
function M.stop()
  generation = generation + 1
  if child then child:kill("TERM") end
  child = nil
  M.scanning:set(false)
end

--- What `du` is asked for `path`.
function M.argv(path) return { morf.env("EVA_DU") or "du", "-x", "-a", "-k", "--max-depth=1", path } end

local function scan(path)
  M.stop()
  local own = generation
  incoming = {}
  M.scanning:set(true)
  M.entries:set({})
  M.total:set(0)
  local started, why = morf.process.spawn {
    command = M.argv(path), max_line = 8192,
    on_stdout = function(line)
      if own ~= generation then return end
      local found = M.parse(line)
      if not found then return end
      incoming[#incoming + 1] = found
      if not flush_timer then flush_timer = morf.time.timer(M.FLUSH, function() flush(path) end, false) end
    end,
    on_stderr = function() end,
    on_exit = function()
      if own ~= generation then return end
      child = nil
      if flush_timer then flush_timer:cancel() end
      flush(path)
      M.scanning:set(false)
      remember(path, M.entries:get(), M.total:get())
    end,
  }
  if not started then
    M.scanning:set(false)
    M.message:set(tostring(why))
    return false
  end
  child = started
  return true
end

--- Goes to `path`: what is remembered of it at once, else a scan.
function M.open(path)
  path = morf.fs.expand and morf.fs.expand(path) or path
  if #path > 1 then path = path:gsub("/+$", "") end
  if not is_dir(path) then
    M.message:set("No such folder: " .. path)
    return false
  end
  M.message:set("")
  M.chosen:set("")
  M.path:set(path)
  M.draft:set(path)
  local kept = remembered[path]
  if kept then
    M.stop()
    M.entries:set(kept.entries)
    M.total:set(kept.total)
    layout()
    return true
  end
  layout()
  return scan(path)
end

--- Scans the folder again.
function M.refresh()
  local path = M.path:get()
  remembered[path] = nil
  return M.open(path)
end

--- Goes up a folder.
function M.up()
  local above = M.parent(M.path:get())
  if not above then return false end
  return M.open(above)
end

--- A press on box `index`: a folder opens, a file is named.
function M.press(index)
  local box = M.boxes:get()[index]
  if not box or box.others then return false end
  if box.dir then return M.open(box.path) end
  M.chosen:set(box.path)
  M.message:set(("%s, %s"):format(box.name, M.size(box.size)))
  return true
end

--- The folder in the file manager.
function M.reveal(path)
  sys.detach { "xdg-open", path or M.path:get() }
  M.message:set(sys.dry() and "Would open it (dry run)" or "")
  return true
end

--- The room the boxes have.
function M.set_area(w, h)
  local now = M.area:get()
  if now[1] == w and now[2] == h then return end
  M.area:set({ w, h })
  layout()
end

--- Every mount as sysinfo samples it, while its page shows.
function M.mounts()
  if M.tab:get() ~= 2 then return {} end
  return sysinfo.disks()
end

function M.select_tab(name)
  for index, key in ipairs(M.TABS) do
    if key == name then M.tab:set(index) return true end
  end
  return false
end

--- Starts at `path`, or at home.
function M.start(path)
  if M.root ~= "" then sysinfo.configure { root = M.root, blocking = true } end
  M.open(path and path ~= "" and path or morf.fs.home())
end

return M
