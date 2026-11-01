-- termworks/drop through its command line: people, machines, topics, what is
-- nearby, files and chat. The CLI prints for people, so the parsers here follow
-- the formats of drop 0.6.2.
--
-- Every drop subcommand mints this machine's key on its first run, listing
-- commands included. `identified()` reads the disk and runs nothing; nothing
-- here starts a process on a machine that has not been `set_up()`.
local morf = require("morf")
local poll = require("lib.util.poll")
local M = { LIST_MS = 8000, REACH_MS = 12000, SEND_MS = 600000, NO_DAEMON = "nothing is running here to reach the network",
  -- Added to what drop's processes inherit.
  env = nil }

local function env(name)
  local value = morf.env and morf.env(name)
  return value ~= "" and value or nil
end

--- The folder drop keeps its things in, profile included.
function M.config_dir()
  local home = env("XDG_CONFIG_HOME") or (morf.fs.home() .. "/.config")
  local dir = home .. "/drop"
  local profile = env("DROP_PROFILE")
  return profile and (dir .. "/profiles/" .. profile) or dir
end

--- The program, or nil.
function M.program() return poll.which("drop") end

--- Whether this machine has been through drop's first run.
function M.identified() return morf.fs.exists(M.config_dir() .. "/badge") end

--- Runs `drop ...`, handing `done` the result. `options.timeout_ms` bounds it.
function M.run(words, options, done)
  local program = M.program()
  if not program then done { ok = false, error = "drop is not installed" } return nil end
  local argv = { program }
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  local ok, handle = pcall(morf.process.run, argv, { env = M.env, timeout_ms = options.timeout_ms or M.LIST_MS }, done)
  if not ok then done { ok = false, error = tostring(handle) } return nil end
  return handle
end

--- Starts `drop ...` to stay, handing back the child: `spec` is that of
--- morf.process.spawn, its `command` the words after `drop`.
function M.spawn(words, spec)
  local program = M.program()
  if not program then return nil end
  local argv = { program }
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  spec.command, spec.env = argv, M.env
  return morf.process.spawn(spec)
end

--- What a failed run said, without drop's own prefix.
function M.why(result)
  if not result then return "drop did not answer." end
  if result.timed_out then return "It took too long." end
  local said = tostring(result.error or result.stderr or ""):gsub("^%s*drop:%s*", ""):gsub("%s+$", "")
  return said ~= "" and said:sub(1, 240) or "drop did not say why."
end

-- ---------------------------------------------------------------- parsers --

--- `drop person ls`: `{ { name, me, trusted, machines = { names } } }`.
function M.parse_people(text)
  local people = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local machine = line:match("^      (.+)$")
    local who = line:match("^  (%S.*)$")
    if machine and #people > 0 then
      local list = people[#people].machines
      local name = machine:gsub("%s+%(this one%)$", "")
      list[#list + 1] = name
    elseif who then
      local name, trusted = who:match("^(.-)%s%s+trusted$")
      people[#people + 1] = { name = name or who, me = (name or who) == "me", trusted = trusted ~= nil or name ~= nil, machines = {} }
    end
  end
  return people
end

--- `drop machine ls`: `{ { name, state, id, here } }`.
function M.parse_machines(text)
  local machines = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local name, state, id = line:match("^  (.-)%s%s+(%S.-)%s%s+(%x+)%s*$")
    if name then
      machines[#machines + 1] = { name = name, state = state, id = id, here = state == "this one" }
    end
  end
  return machines
end

--- `drop topic ls` here: `{ { path, kind, source, access, detail } }`, and
--- the config file (nil while it serves the defaults).
function M.parse_own_topics(text)
  local topics, config = {}, nil
  for line in tostring(text):gmatch("[^\n]+") do
    local path, rest = line:match("^  (/%S*)%s+(.+)$")
    if path then
      local kind, source, tail = rest:match("^(%S+)%s+(%S+)%s+(.*)$")
      local access, detail = tostring(tail or ""):match("^(.-)%s%s+(.*)$")
      topics[#topics + 1] = { path = path, kind = kind or rest, source = source or "",
        access = access or tail or "", detail = detail or "" }
    elseif line:match("^/") and not config then
      config = line
    end
  end
  return topics, config
end

--- `drop topic ls <machine>`: `{ { path, kind, about } }`.
function M.parse_topics(text)
  local topics = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local path, kind, about = line:match("^  (/%S*)%s+(%S+)%s*(.*)$")
    if path then topics[#topics + 1] = { path = path, kind = kind, about = about } end
  end
  return topics
end

--- `drop nearby`: `{ devices = { { name, id } }, asking = { { name, says, check } } }`.
function M.parse_nearby(text)
  local devices, asking = {}, {}
  for line in tostring(text):gmatch("[^\n]+") do
    local who, says, check = line:match("^  (.-) asks (.-) — check (%S+)%s*$")
    local name, id = line:match("^  (%S.-)%s%s+(%x+)%s*$")
    if who then asking[#asking + 1] = { name = who, says = says, check = check }
    elseif name then devices[#devices + 1] = { name = name, id = id } end
  end
  return { devices = devices, asking = asking }
end

--- `drop file ls`: `{ { name, size, when, folder } }`.
function M.parse_files(text)
  local files = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local head, when = line:match("^  (.-)%s%s+(%d%d%d%d%-%d%d%-%d%d %d%d:%d%d)%s*$")
    if head then
      local name, size = head:match("^(.-)%s%s+(%S.*)$")
      name = name or head
      local folder = name:sub(-1) == "/"
      files[#files + 1] = { name = folder and name:sub(1, -2) or name, size = size or "", when = when, folder = folder }
    end
  end
  return files
end

--- `drop me log`: `{ { name, count, last, waiting } }`.
function M.parse_conversations(text)
  local out = {}
  for line in tostring(text):gmatch("[^\n]+") do
    local name, count, last = line:match("^  (%S+)%s+(%d+)  (.*)$")
    if name then
      local tail, waiting = last:match("^(.-)%s%s%((%d+) waiting%)$")
      out[#out + 1] = { name = name, count = tonumber(count), last = tail or last, waiting = tonumber(waiting) or 0 }
    end
  end
  return out
end

--- `drop me log <name>`: the lines as printed, and how many wait.
function M.parse_log(text)
  local lines, waiting = {}, 0
  for line in tostring(text):gmatch("[^\n]+") do
    local count = line:match("^(%d+) message%(s%) still waiting")
    if count then waiting = tonumber(count)
    elseif not line:match("^nothing said to ") then lines[#lines + 1] = line end
  end
  return lines, waiting
end

return M
