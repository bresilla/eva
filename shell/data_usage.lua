-- Bytes through each network interface this calendar month, from the kernel's
-- counters, added up in a file beside the phone's other state. No nodes.
--
--   local usage = require("data_usage").start { limit = fn, notify = fn }
--   usage.rows:get()     -- { { name, kind, bytes }, ... }, busiest first
--   usage.mobile()       -- bytes over mobile interfaces this month
--
-- `options.dir` is the seam for /sys/class/net; EVA_FAKE_NET names a fixture.
local morf = require("morf")

local M = { rows = morf.signal("eva.data.rows", {}) }
function M.reset() end

local EVERY = 60000
local MEGABYTE = 1000000
-- Warned at these shares of the limit.
local STEPS = { 80, 100 }
local KINDS = { { "^wwan", "mobile" }, { "^rmnet", "mobile" }, { "^ccmni", "mobile" }, { "^wl", "wifi" },
  { "^en", "wired" }, { "^eth", "wired" }, { "^usb", "wired" } }

--- What kind of interface `name` is, or nil for one nobody counts.
function M.kind(name)
  for _, entry in ipairs(KINDS) do
    if name:match(entry[1]) then return entry[2] end
  end
end

--- `bytes` as a person reads it.
function M.size(bytes)
  bytes = tonumber(bytes) or 0
  if bytes >= 1e9 then return ("%.2f GB"):format(bytes / 1e9) end
  if bytes >= 1e6 then return ("%.1f MB"):format(bytes / 1e6) end
  if bytes >= 1e3 then return ("%d kB"):format(bytes // 1000) end
  return ("%d B"):format(math.floor(bytes))
end

local function number_at(path)
  local ok, text = pcall(morf.fs.read, path)
  return ok and type(text) == "string" and tonumber(text:match("%d+")) or nil
end

local function state_file()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/phone/usage.json"
end

--- Starts counting. `options`: `dir`, `limit()` (megabytes a month, 0 for
--- none), `notify(entry)`, `every` (ms).
function M.start(options)
  options = options or {}
  local dir = options.dir or morf.env("EVA_FAKE_NET") or "/sys/class/net"
  local kept = { month = "", totals = {}, last = {}, warned = 0 }
  do
    local ok, text = pcall(morf.fs.read, state_file())
    local fine, value = pcall(morf.json.decode, ok and text or "")
    if fine and type(value) == "table" then
      kept.month, kept.warned = value.month or "", value.warned or 0
      kept.totals, kept.last = value.totals or {}, value.last or {}
    end
  end

  local function publish()
    local rows = {}
    for name, bytes in pairs(kept.totals) do
      rows[#rows + 1] = { name = name, kind = M.kind(name) or "other", bytes = bytes }
    end
    table.sort(rows, function(a, b)
      if a.bytes ~= b.bytes then return a.bytes > b.bytes end
      return a.name < b.name
    end)
    M.rows:set(rows)
  end

  --- Bytes over mobile interfaces this month.
  function M.mobile()
    local total = 0
    for _, row in ipairs(M.rows:get()) do
      if row.kind == "mobile" then total = total + row.bytes end
    end
    return total
  end

  local function warn()
    local limit = options.limit and tonumber(options.limit()) or 0
    if limit <= 0 then return end
    local share = M.mobile() / (limit * MEGABYTE) * 100
    for _, step in ipairs(STEPS) do
      if share >= step and kept.warned < step then
        kept.warned = step
        if options.notify then
          options.notify { app = "Mobile data", urgency = step >= 100 and 2 or 1,
            summary = step >= 100 and "Mobile data limit reached" or ("%d%% of your mobile data used"):format(step),
            body = ("%s of %s this month"):format(M.size(M.mobile()), M.size(limit * MEGABYTE)) }
        end
      end
    end
  end

  --- Reads the counters, once.
  function M.sample()
    local month = morf.time.format("%Y-%m")
    if month ~= kept.month then
      kept.month, kept.totals, kept.warned = month, {}, 0
    end
    local ok, entries = pcall(morf.fs.list, dir, { follow = true })
    for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
      local name = entry.name
      if M.kind(name) then
        local base = dir .. "/" .. name .. "/statistics/"
        local now = (number_at(base .. "rx_bytes") or 0) + (number_at(base .. "tx_bytes") or 0)
        local before = kept.last[name]
        -- A count lower than the last means the counters started over.
        local added = before and now >= before and now - before or (before and now or 0)
        kept.last[name] = now
        if added > 0 or kept.totals[name] then kept.totals[name] = (kept.totals[name] or 0) + added end
      end
    end
    pcall(morf.fs.write, state_file(), morf.json.encode(kept), { atomic = true, parents = true, mode = 384 })
    publish()
    warn()
  end

  --- Starts this month's count over.
  function M.reset()
    kept.totals, kept.warned = {}, 0
    pcall(morf.fs.write, state_file(), morf.json.encode(kept), { atomic = true, parents = true, mode = 384 })
    publish()
  end

  M.sample()
  M.timer = morf.time.timer(options.every or EVERY, M.sample, true)
  return M
end

return M
