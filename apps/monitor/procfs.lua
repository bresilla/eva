-- What /proc says about one process that lib.services.sysinfo does not sample:
-- its command line and owner, disk counters, GPU clients and sockets. Plain
-- functions from text to tables. No nodes, nothing read here.
local M = {}

M.PATHS = { "tcp", "tcp6", "udp", "udp6" }

--- The argv of a /proc/PID/cmdline, its NULs as spaces, or nil for a kernel
--- thread, which has none.
function M.command(text)
  if not text or text == "" then return nil end
  local words = text:gsub("\0+$", ""):gsub("\0", " ")
  if words == "" then return nil end
  return words
end

--- The fields of a /proc/PID/status that matter here.
function M.status(text)
  text = text or ""
  return {
    uid = tonumber(text:match("\nUid:%s+(%d+)")),
    threads = tonumber(text:match("\nThreads:%s+(%d+)")),
    swap = (tonumber(text:match("\nVmSwap:%s+(%d+)")) or 0) * 1024,
    parent = tonumber(text:match("\nPPid:%s+(%d+)")),
  }
end

--- uid to name, from /etc/passwd.
function M.users(text)
  local out = {}
  for name, uid in (text or ""):gmatch("([^:\n]+):[^:\n]*:(%d+):") do out[tonumber(uid)] = name end
  return out
end

--- The counters of a /proc/PID/io, or nil where it could not be read.
function M.io(text)
  if not text then return nil end
  local read, written = text:match("read_bytes:%s*(%d+)"), text:match("\nwrite_bytes:%s*(%d+)")
  if not read or not written then return nil end
  return { read = tonumber(read), write = tonumber(written) }
end

local UNIT = { KiB = 1024, MiB = 1048576, GiB = 1073741824, B = 1 }

-- One client of one /proc/PID/fdinfo/N, or nil where that fd is no DRM client.
local function client(text)
  local driver = text:match("drm%-driver:%s*(%S+)")
  if not driver then return nil end
  local out = { driver = driver, id = text:match("drm%-client%-id:%s*(%d+)") or "", pdev = text:match("drm%-pdev:%s*(%S+)") or "",
    engines = {}, cycles = {}, totals = {}, memory = 0 }
  for name, value in text:gmatch("drm%-engine%-([%w_-]+):%s*(%d+) ns") do out.engines[name] = tonumber(value) end
  for name, value in text:gmatch("drm%-cycles%-([%w_-]+):%s*(%d+)") do out.cycles[name] = tonumber(value) end
  for name, value in text:gmatch("drm%-total%-cycles%-([%w_-]+):%s*(%d+)") do out.totals[name] = tonumber(value) end
  for kind, region, value, unit in text:gmatch("drm%-(%a+)%-([%w_-]+):%s*(%d+) (%a+)") do
    if (kind == "memory" or kind == "total") and UNIT[unit] then
      out.memory = out.memory + tonumber(value) * UNIT[unit]
    end
    if kind == "memory" and region == "vram" and UNIT[unit] then out.vram = tonumber(value) * UNIT[unit] end
  end
  return out
end

--- Every DRM client among fdinfo texts, each once: a process holding one
--- context through two fds counts it once. `{ clients, engines, cycles, totals,
--- memory, driver }`, or nil when none of them is a client.
function M.gpu(texts)
  local seen, out = {}, nil
  for _, text in ipairs(texts) do
    local found = type(text) == "string" and client(text)
    if found and not seen[found.pdev .. "/" .. found.id] then
      seen[found.pdev .. "/" .. found.id] = true
      out = out or { clients = 0, engines = {}, cycles = {}, totals = {}, memory = 0, driver = found.driver }
      out.clients = out.clients + 1
      out.memory = out.memory + found.memory
      for _, field in ipairs { "engines", "cycles", "totals" } do
        for name, value in pairs(found[field]) do out[field][name] = (out[field][name] or 0) + value end
      end
    end
  end
  return out
end

--- How busy the busiest engine was between two readings of M.gpu, in percent,
--- `seconds` apart.
function M.gpu_busy(before, now, seconds)
  if not before or not now or seconds <= 0 then return nil end
  local busiest = 0
  for name, value in pairs(now.engines) do
    local was = before.engines[name]
    if was and value >= was then busiest = math.max(busiest, (value - was) / (seconds * 1e9) * 100) end
  end
  for name, value in pairs(now.cycles) do
    local was, total, total_was = before.cycles[name], now.totals[name], before.totals[name]
    if was and total and total_was and total > total_was then
      busiest = math.max(busiest, (value - was) / (total - total_was) * 100)
    end
  end
  return math.min(100, busiest)
end

local function ipv4(hex)
  local a, b, c, d = hex:match("^(%x%x)(%x%x)(%x%x)(%x%x)$")
  return ("%d.%d.%d.%d"):format(tonumber(d, 16), tonumber(c, 16), tonumber(b, 16), tonumber(a, 16))
end

local function ipv6(hex)
  local groups = {}
  for word in hex:gmatch("%x%x%x%x%x%x%x%x") do
    local a, b, c, d = word:match("^(%x%x)(%x%x)(%x%x)(%x%x)$")
    groups[#groups + 1] = tonumber(d .. c, 16)
    groups[#groups + 1] = tonumber(b .. a, 16)
  end
  local mapped = groups[6] == 0xffff
  for index = 1, 5 do mapped = mapped and groups[index] == 0 end
  if mapped then
    return ("::ffff:%d.%d.%d.%d"):format(groups[7] // 256, groups[7] % 256, groups[8] // 256, groups[8] % 256)
  end
  local best, length, run, at = 0, 0, 0, 0
  for index = 1, 9 do
    if groups[index] == 0 then
      if run == 0 then at = index end
      run = run + 1
      if run > length then best, length = at, run end
    else
      run = 0
    end
  end
  local out = {}
  for index = 1, 8 do
    if length < 2 or index < best or index >= best + length then out[#out + 1] = ("%x"):format(groups[index]) end
    if length >= 2 and index == best then out[#out + 1] = "" end
  end
  local text = table.concat(out, ":")
  if best == 1 and length >= 2 then text = ":" .. text end
  if best + length == 9 and length >= 2 then text = text .. ":" end
  return text
end

local function address(hex)
  local host, port = hex:match("^(%x+):(%x+)$")
  if not host then return "" end
  local name = #host == 8 and ipv4(host) or ipv6(host)
  return (#host == 8 and name or "[" .. name .. "]") .. ":" .. tostring(tonumber(port, 16))
end

M.STATES = { ["01"] = "Established", ["02"] = "Syn sent", ["03"] = "Syn received", ["04"] = "Fin wait", ["05"] = "Fin wait",
  ["06"] = "Time wait", ["07"] = "Closed", ["08"] = "Close wait", ["09"] = "Last ack", ["0A"] = "Listening", ["0B"] = "Closing" }

--- The rows of one /proc/PID/net/{tcp,tcp6,udp,udp6} whose inode is in `inodes`
--- (a set), appended to `out`, each `{ protocol, here, there, state }`.
function M.sockets(protocol, text, inodes, out)
  for line in (text or ""):gmatch("[^\n]+") do
    local here, there, state, inode = line:match("^%s*%d+:%s+(%S+)%s+(%S+)%s+(%x%x)%s+%S+%s+%S+%s+%S+%s+%S+%s+%S+%s+(%d+)")
    if inode and inodes[inode] then
      out[#out + 1] = { protocol = protocol:gsub("6$", ""), here = address(here), there = address(there),
        state = protocol:match("^udp") and "Open" or M.STATES[state] or state }
    end
  end
  return out
end

return M
