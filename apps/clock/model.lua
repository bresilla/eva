-- eva-clock's window: the alarms and timers of lib/services/alarm.lua, the
-- stopwatch, the world clocks. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local lib = require("lib.services.alarm")

local M = {
  alarm = lib.new { ring = true, delay = 1500 },
  draft = morf.signal("clock.draft", ""),
  tab = morf.signal("clock.tab", 1),
  world = morf.signal("clock.world", {}),
  city = morf.signal("clock.city", ""),
  message = morf.signal("clock.message", ""),
  laps = morf.signal("clock.laps", {}),
  running = morf.signal("clock.running", false),
  shown = morf.signal("clock.shown", 0),
}

M.TABS = { "alarms", "timers", "stopwatch", "world" }
M.PRESETS = { 1, 5, 10, 25 }

-- Cities a person names, with the zone each is in.
M.CITIES = {
  amsterdam = "Europe/Amsterdam", athens = "Europe/Athens", auckland = "Pacific/Auckland", bangkok = "Asia/Bangkok",
  beijing = "Asia/Shanghai", berlin = "Europe/Berlin", bogota = "America/Bogota", boston = "America/New_York",
  cairo = "Africa/Cairo", chicago = "America/Chicago", delhi = "Asia/Kolkata", denver = "America/Denver",
  dubai = "Asia/Dubai", dublin = "Europe/Dublin", helsinki = "Europe/Helsinki", hongkong = "Asia/Hong_Kong",
  istanbul = "Europe/Istanbul", jakarta = "Asia/Jakarta", johannesburg = "Africa/Johannesburg",
  lagos = "Africa/Lagos", lisbon = "Europe/Lisbon", london = "Europe/London", losangeles = "America/Los_Angeles",
  madrid = "Europe/Madrid", melbourne = "Australia/Melbourne", mexico = "America/Mexico_City",
  moscow = "Europe/Moscow", mumbai = "Asia/Kolkata", nairobi = "Africa/Nairobi", newyork = "America/New_York",
  oslo = "Europe/Oslo", paris = "Europe/Paris", prague = "Europe/Prague", pristina = "Europe/Belgrade",
  reykjavik = "Atlantic/Reykjavik", rome = "Europe/Rome", sanfrancisco = "America/Los_Angeles",
  santiago = "America/Santiago", saopaulo = "America/Sao_Paulo", seattle = "America/Los_Angeles",
  seoul = "Asia/Seoul", shanghai = "Asia/Shanghai", singapore = "Asia/Singapore", stockholm = "Europe/Stockholm",
  sydney = "Australia/Sydney", taipei = "Asia/Taipei", tirana = "Europe/Tirane", tokyo = "Asia/Tokyo",
  toronto = "America/Toronto", vancouver = "America/Vancouver", vienna = "Europe/Vienna", warsaw = "Europe/Warsaw",
  zurich = "Europe/Zurich",
}

local function saved(name) return sys.state("clock", name) end

-- ---------------------------------------------------------------- alarms --

function M.start()
  M.alarm.load()
  M.world:set(sys.load(saved("world.json"), {}))
  local held = sys.load(saved("stopwatch.json"), {})
  if held.since then
    M.since, M.banked = held.since, held.banked or 0
    M.laps:set(held.laps or {})
    M.running:set(held.running == true)
    M.banked = held.banked or 0
  end
  M.tick()
end

--- What the draft would make, in words, or nil.
function M.hint()
  local words = M.draft:get()
  if words:match("^%s*$") then return nil end
  local item, why = lib.parse(words)
  if not item then return why end
  return lib.describe(item)
end

--- Adds what `words` ask for: the entry, or nil.
function M.add(words)
  local item = M.alarm.add(words)
  if item then
    M.draft:set("")
    M.tab:set(item.kind == "timer" and 2 or 1)
  end
  return item
end

--- The entries of `kind`, soonest first. A tracked read.
function M.entries(kind)
  local out = {}
  for _, item in ipairs(M.alarm.items:get()) do
    if item.kind == kind then out[#out + 1] = item end
  end
  table.sort(out, function(a, b) return a.at < b.at end)
  return out
end

function M.select(name)
  for index, key in ipairs(M.TABS) do
    if key == name then M.tab:set(index) return true end
  end
  return false
end

-- ------------------------------------------------------------- stopwatch --

M.banked = 0

local ticker

local function keep()
  sys.save(saved("stopwatch.json"), { since = M.since, banked = M.banked, laps = M.laps:get(),
    running = M.running:get() })
end

--- Milliseconds on the stopwatch.
function M.elapsed()
  if M.running:get() and M.since then return M.banked + morf.time.now_ms() - M.since end
  return M.banked
end

--- Follows the stopwatch on screen, only while it runs.
function M.tick()
  if ticker then ticker:cancel() ticker = nil end
  M.shown:set(M.elapsed())
  if not M.running:get() then return end
  ticker = morf.time.timer(50, function() M.shown:set(M.elapsed()) end, true)
end

--- "start", "stop", "lap" or "reset".
function M.stopwatch(how)
  if how == "start" and not M.running:get() then
    M.since = morf.time.now_ms()
    M.running:set(true)
  elseif how == "stop" and M.running:get() then
    M.banked = M.elapsed()
    M.since = nil
    M.running:set(false)
  elseif how == "lap" and M.running:get() then
    local laps = { M.elapsed() }
    for _, lap in ipairs(M.laps:get()) do laps[#laps + 1] = lap end
    M.laps:set(laps)
  elseif how == "reset" then
    M.banked, M.since = 0, nil
    M.running:set(false)
    M.laps:set({})
  end
  keep()
  M.tick()
end

--- Milliseconds as a stopwatch reads, "1:02.45".
function M.watch_words(ms)
  local total = math.floor(ms / 10)
  local cents, seconds = total % 100, (total // 100) % 60
  local minutes, hours = (total // 6000) % 60, total // 360000
  if hours > 0 then return ("%d:%02d:%02d.%02d"):format(hours, minutes, seconds, cents) end
  return ("%d:%02d.%02d"):format(minutes, seconds, cents)
end

-- ----------------------------------------------------------- world clocks --

-- The zone `name` means: a city this knows, or a zone's own name.
local function zone_of(name)
  local key = name:lower():gsub("[%s%-_']", "")
  if M.CITIES[key] then return M.CITIES[key] end
  local ok = pcall(morf.time.date, nil, { tz = name })
  if ok then return name end
end

--- Adds a city or a zone: whether it was known.
function M.add_city(name)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  if name == "" then return false end
  local zone = zone_of(name)
  if not zone then
    M.message:set("No time zone for " .. name)
    return false
  end
  local list = {}
  for _, entry in ipairs(M.world:get()) do list[#list + 1] = entry end
  list[#list + 1] = { name = name:gsub("^%l", string.upper), zone = zone }
  M.world:set(list)
  sys.save(saved("world.json"), list)
  M.city:set("")
  M.message:set("")
  return true
end

function M.remove_city(index)
  local list = {}
  for i, entry in ipairs(M.world:get()) do
    if i ~= index then list[#list + 1] = entry end
  end
  M.world:set(list)
  sys.save(saved("world.json"), list)
end

--- A city's time and how it stands to here: "14:05", "+6 h, tomorrow".
function M.city_time(entry)
  local now = morf.time.now()
  local there, here = morf.time.date(now, { tz = entry.zone }), morf.time.date(now)
  local hours = (there.offset - here.offset) / 3600
  local apart = hours == 0 and "Same time" or (("%+g h"):format(hours))
  local day = ""
  if there.yearday ~= here.yearday or there.year ~= here.year then
    local ahead = there.year > here.year or (there.year == here.year and there.yearday > here.yearday)
    day = ahead and ", tomorrow" or ", yesterday"
  end
  return ("%02d:%02d"):format(there.hour, there.minute), apart .. day
end

return M
