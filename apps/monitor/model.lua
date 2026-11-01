-- eva-monitor's state: lib.services.sysinfo's samples through shell/performance_model,
-- the processes filtered and sorted, what is asked only of the chosen process,
-- and the signals sent. No nodes.
local morf = require("morf")
local poll = require("lib.util.poll")
local sysinfo = require("lib.services.sysinfo")
local performance = require("performance_model")
local sys = require("common.sys")
local procfs = require("procfs")

local M = {
  tab = morf.signal("monitor.tab", 1),
  query = morf.signal("monitor.query", ""),
  sort = morf.signal("monitor.sort", "cpu"),
  selected = morf.signal("monitor.selected", 0),
  detail = morf.signal("monitor.detail", {}),
  ended = morf.signal("monitor.ended", {}),
  sent = morf.signal("monitor.sent", {}),
  message = morf.signal("monitor.message", ""),
  paused = morf.signal("monitor.paused", false),
  away = morf.signal("monitor.away", false),
  speed = morf.signal("monitor.speed", 2000),
  count = morf.signal("monitor.count", 0),
  shown = morf.signal("monitor.shown", 0),
  rows = morf.list_model({}),
  sensors = morf.list_model({}),
  devices = morf.list_model({}),
}

M.TABS = { "processes", "resources", "sensors" }
M.SORTS = { "cpu", "memory", "name", "pid" }
M.SPEEDS = { 1000, 2000, 5000 }
-- The most processes the sampler ranks.
M.LIMIT = 4096
-- The most descriptors, connections and fdinfo files asked of one process.
M.FDS = 1024
M.CONNECTIONS = 64
M.FDINFO = 64

M.root = morf.env("EVA_MONITOR_ROOT") or ""

local function saved() return sys.state("monitor", "settings.json") end

--- Whether the window is minimised, as the compositor says.
function M.minimized()
  local list = morf.toplevels and morf.toplevels.list and morf.toplevels.list() or {}
  for _, row in ipairs(list) do
    if row.app_id == "eva.monitor" then return row.minimized == true end
  end
  return false
end

--- Whether anything is sampled at all.
function M.live() return not M.paused:get() and not M.away:get() and not M.minimized() end

--- Whether the page of `name` is showing and live.
function M.showing(name) return M.live() and M.TABS[M.tab:get()] == name end

M.perf = nil

local function read_files(paths, done)
  if M.root ~= "" then
    local out = {}
    for index, path in ipairs(paths) do
      local ok, text = pcall(morf.fs.read, path)
      out[index] = ok and type(text) == "string" and text or false
    end
    morf.time.timer(1, function() done(out) end, false)
    return
  end
  local out, at = {}, 1
  local function step()
    local batch = {}
    for index = at, math.min(at + 255, #paths) do batch[#batch + 1] = paths[index] end
    if #batch == 0 then done(out) return end
    local started = morf.fs.read_async(batch, function(ok, contents)
      for index = 1, #batch do out[at + index - 1] = ok and contents[index] or false end
      at = at + #batch
      step()
    end, 1048576)
    if not started then done(out) end
  end
  step()
end

-- ------------------------------------------------------------- processes --

local known = {}
local users
local learning = false
local learned = morf.signal("monitor.learned", 0)
local rank = {}

local function user_name(uid)
  if not users then
    local ok, text = pcall(morf.fs.read, M.root .. "/etc/passwd")
    users = procfs.users(ok and text or "")
  end
  return uid and (users[uid] or tostring(uid)) or ""
end

-- What the sampler's rows lack, read once for each process that is new.
local function learn(list)
  if learning then return end
  local fresh = {}
  for _, process in ipairs(list) do
    local kept = known[process.pid]
    if not kept or kept.name ~= process.name then fresh[#fresh + 1] = process end
  end
  if #fresh == 0 then return end
  learning = true
  local paths = {}
  for _, process in ipairs(fresh) do
    local base = M.root .. "/proc/" .. math.floor(process.pid)
    paths[#paths + 1] = base .. "/cmdline"
    paths[#paths + 1] = base .. "/status"
  end
  read_files(paths, function(texts)
    learning = false
    for index, process in ipairs(fresh) do
      local command = procfs.command(texts[index * 2 - 1] or nil)
      local status = procfs.status(texts[index * 2] or nil)
      local user = user_name(status.uid)
      known[process.pid] = { name = process.name, command = command or ("[" .. process.name .. "]"), kernel = command == nil,
        user = user, threads = status.threads, words = (process.name .. " " .. (command or "") .. " " .. user .. " "
        .. math.floor(process.pid)):lower() }
    end
    learned:set(learned:get() + 1)
  end)
end

local function matches(process, words)
  local kept = known[process.pid]
  local text = kept and kept.words or process.name:lower()
  for _, word in ipairs(words) do
    if not text:find(word, 1, true) then return false end
  end
  return true
end

local function by_name(a, b)
  local x, y = a.name:lower(), b.name:lower()
  if x == y then return a.pid < b.pid end
  return x < y
end

--- The processes to show, of what the sampler gave, by the sort and the query.
function M.arrange(list, query, sort)
  local words = {}
  for word in query:lower():gmatch("%S+") do words[#words + 1] = word end
  local out = {}
  for _, process in ipairs(list) do
    if #words == 0 or matches(process, words) then
      local kept = known[process.pid]
      out[#out + 1] = { pid = process.pid, name = process.name, state = process.state, cpu = process.cpu,
        memory = process.memory, percent = process.memory_percent, command = kept and kept.command or "",
        user = kept and kept.user or "", threads = kept and kept.threads or nil }
    end
  end
  if sort == "name" then table.sort(out, by_name)
  elseif sort == "pid" then table.sort(out, function(a, b) return a.pid < b.pid end) end
  return out
end

--- The list as sampled, for `sort`.
function M.sampled(sort)
  local all = sysinfo.processes()
  return sort == "memory" and all.by_memory or all.by_cpu
end

--- The row of `pid` among those shown.
function M.row_of(pid)
  for index = 1, M.rows:len() do
    local row = M.rows:get(index)
    if row.pid == pid then return row, index end
  end
  return nil, 0
end

--- Which row the chosen process is in now, from 1; 0 for none. A tracked read.
function M.selected_index()
  local _, index = M.row_of(M.selected:get())
  return index
end

--- Follows the sampler while the Processes page shows: the list stops with it.
local function follow_processes()
  morf.effect("monitor.processes", function()
    if not M.showing("processes") then return end
    sysinfo.cpu()
    local sort, query = M.sort:get(), M.query:get()
    learned:get()
    local all = sysinfo.processes()
    local list = sort == "memory" and all.by_memory or all.by_cpu
    local seen = {}
    for _, process in ipairs(list) do seen[process.pid] = true end
    for pid in pairs(known) do
      if not seen[pid] then known[pid] = nil end
    end
    learn(list)
    local shown = M.arrange(list, query, sort)
    M.rows:replace(shown, "pid")
    M.count:set(all.count or #list)
    M.shown:set(#shown)
  end)
end

-- ------------------------------------------------------- the chosen process --

local before = {}
local sampling

-- A process's descriptors, as its sockets and its DRM files.
local function descriptors(pid, spend)
  local base = M.root .. "/proc/" .. pid .. "/fd"
  local ok, list = pcall(morf.fs.list, base)
  if not ok or type(list) ~= "table" then return nil end
  local inodes, drm, sockets = {}, {}, 0
  for index, entry in ipairs(list) do
    if index > M.FDS then break end
    spend(3)
    local link = morf.fs.read_link(base .. "/" .. entry.name)
    if type(link) == "string" then
      local inode = link:match("^socket:%[(%d+)%]$")
      if inode then
        inodes[inode] = true
        sockets = sockets + 1
      elseif link:find("/dev/dri/", 1, true) == 1 and #drm < M.FDINFO then
        drm[#drm + 1] = entry.name
      end
    end
  end
  return { inodes = inodes, drm = drm, sockets = sockets }
end

local function reading(pid, seen, texts)
  local index = 2
  local now = morf.time.now()
  local status = procfs.status(texts[1] or nil)
  local counters = procfs.io(texts[2] or nil)
  local out = { pid = pid, threads = status.threads, swap = status.swap, parent = status.parent, hidden = seen == nil }
  local last = before[pid]
  local seconds = last and now - last.at or 0
  if counters then
    out.read_total, out.write_total = counters.read, counters.write
    if last and last.io and seconds > 0 then
      out.read_rate = math.max(0, counters.read - last.io.read) / seconds
      out.write_rate = math.max(0, counters.write - last.io.write) / seconds
    end
  end
  if seen then
    out.sockets = seen.sockets
    local connections = {}
    for offset, protocol in ipairs(procfs.PATHS) do
      procfs.sockets(protocol, texts[index + offset] or nil, seen.inodes, connections)
    end
    while #connections > M.CONNECTIONS do connections[#connections] = nil end
    out.connections = connections
    local files = {}
    for offset = 1, #seen.drm do files[offset] = texts[index + #procfs.PATHS + offset] end
    local gpu = procfs.gpu(files)
    if gpu then
      out.gpu = { clients = gpu.clients, memory = gpu.memory, driver = gpu.driver,
        busy = procfs.gpu_busy(last and last.gpu, gpu, seconds) }
    end
    before[pid] = { at = now, io = counters, gpu = gpu }
  else
    before[pid] = { at = now, io = counters }
  end
  return out
end

--- Reads `pid`'s descriptors, disk counters and sockets, off the loop.
function M.sample(pid)
  if sampling then sampling.cancel() end
  sampling = poll.job(function(spend) return descriptors(pid, spend) end, function(seen)
    sampling = nil
    local base = M.root .. "/proc/" .. pid
    local paths = { base .. "/status", base .. "/io" }
    if seen then
      for _, protocol in ipairs(procfs.PATHS) do paths[#paths + 1] = base .. "/net/" .. protocol end
      for _, fd in ipairs(seen.drm) do paths[#paths + 1] = base .. "/fdinfo/" .. fd end
    end
    read_files(paths, function(texts)
      if M.selected:get() == pid then M.detail:set(reading(pid, seen, texts)) end
    end)
  end)
end

local function follow_selected()
  morf.effect("monitor.selected", function()
    local pid = M.selected:get()
    if pid == 0 or not M.showing("processes") then return end
    sysinfo.processes()
    local whole = math.floor(pid)
    morf.time.timer(1, function() M.sample(whole) end, false)
  end)
end

--- Chooses a process, or none (0).
function M.select(pid)
  pid = tonumber(pid) or 0
  if pid == M.selected:get() then return end
  before = {}
  M.detail:set({})
  M.selected:set(pid)
end

--- Chooses the row at `index`, as a press or the arrow keys do.
function M.select_row(index)
  local row = M.rows:get(index)
  if row then M.select(row.pid) end
end

--- Sends `signal` to `pid`: dry, it is written down and nothing is sent.
function M.send(pid, signal)
  pid = math.floor(tonumber(pid) or 0)
  local row = M.row_of(pid)
  local name = row and row.name or tostring(pid)
  if pid <= 1 then
    M.message:set("Process " .. pid .. " cannot be signalled")
    return false
  end
  local log = M.sent:get()
  local entries = { { pid = pid, signal = signal } }
  for _, entry in ipairs(log) do entries[#entries + 1] = entry end
  M.sent:set(entries)
  if sys.dry() then
    morf.log("info", ("eva: kill -%s %d (dry run)"):format(signal, pid))
    M.message:set(("Would send %s to %s (dry run)"):format(signal, name))
    return true
  end
  local ok, why = morf.process.kill(pid, signal)
  if ok then
    M.message:set(("Sent %s to %s"):format(signal, name))
  else
    M.message:set(("%s not sent to %s: %s"):format(signal, name, tostring(why)))
  end
  return ok == true
end

--- Asks `pid` to end.
function M.term(pid)
  pid = math.floor(tonumber(pid) or 0)
  local ok = M.send(pid, "TERM")
  if ok then
    local ended = {}
    for key, value in pairs(M.ended:get()) do ended[key] = value end
    ended[tostring(pid)] = true
    M.ended:set(ended)
  end
  return ok
end

--- Kills `pid`, once it has been asked to end.
function M.force(pid)
  pid = math.floor(tonumber(pid) or 0)
  if not M.ended:get()[tostring(pid)] then
    M.message:set("End it first")
    return false
  end
  return M.send(pid, "KILL")
end

--- Whether the chosen process has been asked to end.
function M.may_force() return M.ended:get()[tostring(math.floor(M.selected:get()))] == true end

-- ------------------------------------------------------------- resources --

--- One sensor by its row's key, as sampled now.
function M.sensor(key)
  local kind, rest = key:match("^(%a+):(.*)$")
  if kind == "fan" then
    for _, fan in ipairs(M.perf.fans().fans or {}) do
      if fan.chip .. "/" .. fan.label == rest then return fan end
    end
  else
    for _, sensor in ipairs(M.perf.temps().sensors or {}) do
      if sensor.chip .. "/" .. sensor.label == rest then return sensor end
    end
  end
  return nil
end

-- Rows hold only names: the readings are bindings on the sample, so a row is
-- rebuilt only when a sensor comes or goes.
local function follow_sensors()
  morf.effect("monitor.sensors", function()
    if not M.showing("sensors") then return end
    local rows, seen = {}, {}
    for _, sensor in ipairs(M.perf.temps().sensors or {}) do
      local key = "temp:" .. sensor.chip .. "/" .. sensor.label
      if not seen[key] then
        seen[key] = true
        rows[#rows + 1] = { key = key, kind = "temperature", label = sensor.label, chip = sensor.chip }
      end
    end
    for _, fan in ipairs(M.perf.fans().fans or {}) do
      local key = "fan:" .. fan.chip .. "/" .. fan.label
      if not seen[key] then
        seen[key] = true
        rows[#rows + 1] = { key = key, kind = "fan", label = fan.label, chip = fan.chip }
      end
    end
    M.sensors:replace(rows, "key")
  end)
end

local function follow_devices()
  morf.effect("monitor.devices", function()
    if not M.showing("resources") then return end
    local rows = {}
    for _, row in ipairs(M.perf.list.devices) do
      if row.kind == "gpu" or row.kind == "drive" or row.kind == "net" then
        rows[#rows + 1] = { key = row.key, kind = row.kind, ref = row.ref, index = row.index }
      end
    end
    M.devices:replace(rows, "key")
  end)
end

--- GPU, disk and network added up over the devices, as sampled now.
function M.totals()
  local perf = M.perf
  local out = { read = 0, write = 0, read_total = 0, write_total = 0, rx = 0, tx = 0, rx_total = 0, tx_total = 0,
    vram_used = 0, vram_total = 0, cards = 0, drives = 0, interfaces = 0 }
  for _, drive in ipairs(perf.drives().drives or {}) do
    out.drives = out.drives + 1
    out.read, out.write = out.read + (drive.read_rate or 0), out.write + (drive.write_rate or 0)
    out.read_total = out.read_total + (drive.read_total or 0)
    out.write_total = out.write_total + (drive.write_total or 0)
  end
  for _, interface in ipairs(perf.network().interfaces or {}) do
    if not interface.virtual then
      out.interfaces = out.interfaces + 1
      out.rx, out.tx = out.rx + (interface.rx_rate or 0), out.tx + (interface.tx_rate or 0)
      out.rx_total = out.rx_total + (interface.rx_bytes or 0)
      out.tx_total = out.tx_total + (interface.tx_bytes or 0)
    end
  end
  local busy, read = 0, 0
  for _, card in ipairs(perf.gpus().cards or {}) do
    out.cards = out.cards + 1
    if card.busy then busy, read = busy + card.busy, read + 1 end
    out.vram_used = out.vram_used + (card.vram_used or 0)
    out.vram_total = out.vram_total + (card.vram_total or 0)
  end
  out.busy = read > 0 and busy / read or nil
  return out
end

-- ------------------------------------------------------------- the controls --

local function pace(ms)
  local intervals = {}
  for _, name in ipairs { "cpu", "memory", "drives", "fans", "gpu", "network", "processes" } do intervals[name] = ms end
  intervals.temperatures = math.max(ms, 2000)
  sysinfo.configure { intervals = intervals }
end

--- How often the machine is sampled, in milliseconds.
function M.set_speed(ms)
  ms = tonumber(ms) or 2000
  M.speed:set(ms)
  pace(ms)
  sys.save(saved(), { speed = ms })
end

function M.select_tab(name)
  for index, key in ipairs(M.TABS) do
    if key == name then M.tab:set(index) return true end
  end
  return false
end

function M.select_sort(name)
  for _, key in ipairs(M.SORTS) do
    if key == name then M.sort:set(name) return true end
  end
  return false
end

--- Starts following the sampler; nothing is read until a page asks.
function M.start()
  if M.root ~= "" then sysinfo.configure { root = M.root, blocking = true } end
  sysinfo.configure { top = M.LIMIT }
  M.speed:set(sys.load(saved(), {}).speed or 2000)
  pace(M.speed:get())
  M.perf = performance.new { opened = function() return M.live() and M.tab:get() ~= 1 end }
  follow_processes()
  follow_selected()
  follow_sensors()
  follow_devices()
  morf.effect("monitor.rest", function()
    if M.live() then return end
    for _, source in pairs(sysinfo.sources) do source:stop() end
  end)
end

return M
