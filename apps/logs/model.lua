-- eva-logs' state: journalctl as a child that lives on, its lines kept to a bounded
-- number, narrowed by priority, boot, unit and words. No nodes.
local morf = require("morf")
local sys = require("common.sys")

local M = {
  rows = morf.list_model({}),
  priority = morf.signal("logs.priority", 1),
  boot = morf.signal("logs.boot", 1),
  unit = morf.signal("logs.unit", ""),
  query = morf.signal("logs.query", ""),
  grep = morf.signal("logs.grep", ""),
  follow = morf.signal("logs.follow", true),
  selected = morf.signal("logs.selected", ""),
  shown = morf.signal("logs.shown", 0),
  kept = morf.signal("logs.kept", 0),
  running = morf.signal("logs.running", false),
  missing = morf.signal("logs.missing", false),
  message = morf.signal("logs.message", ""),
}

-- The most entries kept, what is asked for at the start, and how long lines
-- wait to land on the list together.
M.LIMIT = 2000
M.FIRST = 1000
M.FLUSH = 200
-- Priorities, by the choice's place: the most that is shown, nil for all.
M.PRIORITIES = { false, 6, 4, 3 }
M.BOOTS = { "0", "-1" }
M.LEVELS = { [0] = "Emergency", "Alert", "Critical", "Error", "Warning", "Notice", "Info", "Debug" }

local entries = {}
local waiting = {}
local generation = 0
local child, flush_timer

local function program() return morf.env("EVA_JOURNALCTL") or "journalctl" end

--- The argv for what is chosen. `follow` adds --follow.
function M.argv(follow)
  local argv = { program(), "--no-pager", "--output=json", "-n" .. M.FIRST, "-b" .. M.BOOTS[M.boot:get()] }
  local level = M.PRIORITIES[M.priority:get()]
  if level then argv[#argv + 1] = "-p" .. level end
  if M.unit:get() ~= "" then argv[#argv + 1] = "-u" .. M.unit:get() end
  if M.grep:get() ~= "" then argv[#argv + 1] = "--grep=" .. M.grep:get() end
  if follow then argv[#argv + 1] = "--follow" end
  return argv
end

-- A MESSAGE the journal holds as bytes comes as a list of numbers.
local function text_of(message)
  if type(message) == "string" then return message end
  if type(message) ~= "table" then return "" end
  local out = {}
  for index, byte in ipairs(message) do
    if index > 4096 then break end
    out[index] = string.char(math.floor(byte) % 256)
  end
  return table.concat(out)
end

--- One line of `journalctl --output=json` as an entry, or nil.
function M.parse(line)
  local ok, data = pcall(morf.json.decode, line)
  if not ok or type(data) ~= "table" or not data.__CURSOR then return nil end
  local at = (tonumber(data.__REALTIME_TIMESTAMP) or 0) / 1e6
  local unit = data._SYSTEMD_UNIT or data.UNIT or ""
  return {
    key = data.__CURSOR, at = at, priority = tonumber(data.PRIORITY) or 6, unit = unit,
    name = data.SYSLOG_IDENTIFIER or unit:gsub("%.service$", "") or "kernel", pid = data._PID or "",
    text = text_of(data.MESSAGE), hostname = data._HOSTNAME or "",
  }
end

local function matches(entry, words)
  local text = (entry.name .. " " .. entry.unit .. " " .. entry.text):lower()
  for _, word in ipairs(words) do
    if not text:find(word, 1, true) then return false end
  end
  return true
end

local function arrange()
  local words = {}
  for word in M.query:get():lower():gmatch("%S+") do words[#words + 1] = word end
  local out = {}
  for index = #entries, 1, -1 do
    if #words == 0 or matches(entries[index], words) then out[#out + 1] = entries[index] end
  end
  M.rows:replace(out, "key")
  M.shown:set(#out)
  M.kept:set(#entries)
end

local function flush()
  flush_timer = nil
  if #waiting == 0 then return end
  for _, entry in ipairs(waiting) do entries[#entries + 1] = entry end
  waiting = {}
  local over = #entries - M.LIMIT
  if over > 0 then table.move(entries, over + 1, #entries + over, 1) end
  arrange()
end

--- Takes one line of the journal; the list hears of it a moment later, with
--- the others that came.
function M.feed(line)
  local entry = M.parse(line)
  if not entry then return end
  waiting[#waiting + 1] = entry
  if not flush_timer then flush_timer = morf.time.timer(M.FLUSH, flush, false) end
end

--- Stops the child, if one runs.
function M.stop()
  generation = generation + 1
  if child then child:kill("TERM") end
  child = nil
  M.running:set(false)
end

--- Asks the journal again for what is chosen, following it while `follow`.
function M.load()
  M.stop()
  entries, waiting = {}, {}
  M.select("")
  M.missing:set(false)
  arrange()
  local own = generation
  local following = M.follow:get()
  local started, why = morf.process.spawn {
    command = M.argv(following), max_line = 65536,
    on_stdout = function(line)
      if own == generation then M.feed(line) end
    end,
    on_stderr = function(line)
      if own == generation and line ~= "" then M.message:set(line) end
    end,
    on_exit = function(code)
      if own ~= generation then return end
      child = nil
      M.running:set(false)
      if flush_timer then flush_timer:cancel() end
      flush()
      if code ~= 0 and #entries == 0 and M.message:get() == "" then M.message:set("journalctl ended with " .. tostring(code)) end
    end,
  }
  if not started then
    M.missing:set(true)
    M.message:set(tostring(why))
    return false
  end
  child = started
  M.running:set(following)
  M.message:set("")
  return true
end

--- Chooses an entry, by its key, or none ("").
function M.select(key) M.selected:set(key or "") end

function M.select_row(index)
  local row = M.rows:get(index)
  if row then M.select(row.key) end
end

--- The chosen entry, a tracked read.
function M.chosen()
  local key = M.selected:get()
  if key == "" then return nil end
  for index = 1, M.rows:len() do
    local row = M.rows:get(index)
    if row.key == key then return row, index end
  end
  return nil
end

--- Which row the chosen entry is in, from 1; 0 for none.
function M.selected_index()
  local _, index = M.chosen()
  return index or 0
end

--- The local time of an entry.
function M.time(entry, format) return morf.time.format(format or "%H:%M:%S", entry.at) end

--- The chosen entry as a line for a paste.
function M.line(entry)
  return ("%s %s[%s] %s: %s"):format(M.time(entry, "%Y-%m-%d %H:%M:%S"), entry.name, entry.pid,
    M.LEVELS[math.floor(entry.priority)] or "", entry.text)
end

--- The chosen entry on the clipboard.
function M.copy()
  local entry = M.chosen()
  if not entry then return false end
  sys.copy(M.line(entry))
  M.message:set(sys.dry() and "Would copy the entry (dry run)" or "Copied the entry")
  return true
end

function M.set_priority(index)
  M.priority:set(index)
  M.load()
end

function M.set_boot(index)
  M.boot:set(index)
  M.follow:set(index == 1)
  M.load()
end

--- Narrows to one unit, "" for all of them.
function M.set_unit(name)
  M.unit:set(name or "")
  M.load()
end

--- Asks the journal itself for words, past what is kept.
function M.search(words)
  M.grep:set(words or "")
  M.load()
end

--- Follows the journal, or stops at what has come.
function M.set_follow(on)
  M.follow:set(on and M.boot:get() == 1)
  M.load()
end

--- Starts following; `unit` narrows it from the start. The list follows the
--- words typed over what is kept, and rests when nothing comes.
function M.start(unit)
  if unit and unit ~= "" then M.unit:set(unit) end
  morf.effect("logs.query", function()
    M.query:get()
    morf.time.timer(1, arrange, false)
  end)
  M.load()
end

return M
