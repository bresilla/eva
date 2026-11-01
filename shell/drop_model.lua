-- The Drop page's state, over lib/integrations/drop.lua: who this machine is,
-- the people and machines it knows, what they offer, what is nearby, and what
-- is on its way. One model, whichever panel shows the page. No nodes.
--
-- Nothing runs while `stage()` is not `ready`. `set_up`, on a press, is what
-- does drop's first run and makes this machine's key.
local morf = require("morf")
local drop = require("lib.integrations.drop")
local M = {
  people = morf.list_model({}),
  machines = morf.list_model({}),
  targets = morf.list_model({}),
  topics = morf.list_model({}),
  nearby = morf.list_model({}),
  asking = morf.list_model({}),
  remote = morf.list_model({}),
  files = morf.list_model({}),
  log = morf.list_model({}),
  transfers = morf.list_model({}),
  received = morf.list_model({}),
  conversations = morf.list_model({}),
  identity = morf.signal("eva.drop.identity", ""),
  serving = morf.signal("eva.drop.serving", "unknown"),
  selected = morf.signal("eva.drop.selected", ""),
  reach = morf.signal("eva.drop.reach", {}),
  folder = morf.signal("eva.drop.folder", ""),
  pending = morf.signal("eva.drop.pending", ""),
  said = morf.signal("eva.drop.said", ""),
  code = morf.signal("eva.drop.code", ""),
  revision = morf.signal("eva.drop.revision", 0),
  loaded = morf.signal("eva.drop.loaded", false),
  KINDS = { "chat", "inbox", "folder", "note", "terminal", "links", "stream" },
  LEVELS = { "me", "trusted", "paired", "anyone" },
}
local NAMES = { share = "inbox", files = "folder", tty = "terminal", link = "links" }
local timer, watcher, offering
local held = {}
local inbox_path
local transfer_count = 0

local function dry_run()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

--- Where things stand: `missing`, `first-run` or `ready`. Reads the disk only.
function M.stage()
  M.revision:get()
  if not drop.program() then return "missing" end
  if not drop.identified() then return "first-run" end
  return "ready"
end

--- A word for what a topic is, however drop spells it.
function M.kind_name(kind) return NAMES[kind] or kind or "" end

local function say(text) M.said:set(text or "") end

-- ----------------------------------------------------------------- reading --

local function refresh_targets()
  local rows = {}
  for i = 1, M.machines:len() do
    local machine = M.machines:get(i)
    if not machine.here then
      rows[#rows + 1] = { id = machine.name, address = machine.name, title = machine.name,
        detail = "Yours", machine = machine.name }
    end
  end
  for i = 1, M.people:len() do
    local person = M.people:get(i)
    if not person.me then
      for _, machine in ipairs(person.machines) do
        rows[#rows + 1] = { id = person.name .. ":" .. machine, address = person.name .. ":" .. machine,
          title = person.name, detail = machine .. (person.trusted and " · trusted" or ""), machine = machine }
      end
    end
  end
  M.targets:replace(rows, "id")
end

local function read_received()
  local rows = {}
  if inbox_path then
    local ok, entries = pcall(morf.fs.list, inbox_path)
    for _, entry in ipairs(ok and entries or {}) do
      if entry.is_file then
        rows[#rows + 1] = { id = entry.name, name = entry.name, path = entry.path, modified = entry.modified or 0,
          when = entry.modified and morf.time.format("%-d %b %H:%M", entry.modified) or "" }
      end
    end
  end
  table.sort(rows, function(a, b) return a.modified > b.modified end)
  for i = #rows, 13, -1 do rows[i] = nil end
  M.received:replace(rows, "id")
end

local function follow_inbox()
  if watcher then watcher:close() watcher = nil end
  if inbox_path then watcher = morf.fs.watch(inbox_path, read_received) end
  read_received()
end

-- Hears whether `drop serve` is up, and what is nearby. The wording is drop's.
local function read_nearby()
  drop.run({ "nearby" }, {}, function(result)
    if result.ok then
      M.serving:set("yes")
      local found = drop.parse_nearby(result.stdout)
      local rows, asks = {}, {}
      for _, device in ipairs(found.devices) do rows[#rows + 1] = { id = device.id, name = device.name } end
      for _, ask in ipairs(found.asking) do
        asks[#asks + 1] = { id = ask.name, name = ask.name, says = ask.says, check = ask.check }
      end
      M.nearby:replace(rows, "id")
      M.asking:replace(asks, "id")
    elseif tostring(result.stderr or ""):find(drop.NO_DAEMON, 1, true) then
      M.serving:set("no")
      M.nearby:replace({}, "id")
      M.asking:replace({}, "id")
    else
      M.serving:set("unknown")
    end
  end)
end

local function read_own_topics()
  drop.run({ "topic", "ls" }, {}, function(result)
    if not result.ok then return end
    local topics = drop.parse_own_topics(result.stdout)
    local rows = {}
    inbox_path = nil
    for _, topic in ipairs(topics) do
      local kind = M.kind_name(topic.kind)
      rows[#rows + 1] = { id = topic.path, path = topic.path, kind = kind, access = topic.access, detail = topic.detail }
      if kind == "inbox" and not inbox_path then
        local dir = topic.detail:match("(~?/%S+)")
        if dir then inbox_path = morf.fs.expand(dir) end
      end
    end
    M.topics:replace(rows, "id")
    follow_inbox()
  end)
end

local function read_conversations()
  drop.run({ "me", "log" }, {}, function(result)
    local rows = {}
    for _, row in ipairs(drop.parse_conversations(result.ok and result.stdout or "")) do
      row.id = row.name
      rows[#rows + 1] = row
    end
    M.conversations:replace(rows, "id")
  end)
end

--- Reads everything again. Runs nothing before the first run is done.
function M.refresh()
  if M.stage() ~= "ready" then return false end
  drop.run({ "machine", "ls" }, {}, function(result)
    if not result.ok then say(drop.why(result)) return end
    local rows = {}
    for _, machine in ipairs(drop.parse_machines(result.stdout)) do
      if machine.here then M.identity:set(machine.name .. "  ·  " .. machine.id:sub(-12)) end
      machine.id = machine.name
      rows[#rows + 1] = machine
    end
    M.machines:replace(rows, "id")
    drop.run({ "person", "ls" }, {}, function(people)
      if not people.ok then say(drop.why(people)) return end
      local list = {}
      for _, person in ipairs(drop.parse_people(people.stdout)) do
        person.id = person.name
        list[#list + 1] = person
      end
      M.people:replace(list, "id")
      refresh_targets()
      M.loaded:set(true)
    end)
  end)
  read_own_topics()
  read_nearby()
  read_conversations()
  return true
end

--- Polls while the page is on show.
function M.watch(on)
  if timer then timer:cancel() timer = nil end
  if watcher then watcher:close() watcher = nil end
  M.revision:set(M.revision:get() + 1)
  if on and M.refresh() then timer = morf.time.timer(10000, read_nearby, true) end
end

-- ---------------------------------------------------------------- settling --

--- Does drop's first run, which makes this machine's key. Only on a press.
function M.set_up()
  if M.stage() ~= "first-run" then return false end
  if dry_run() then morf.log("info", "eva: drop set up (dry run)") return false end
  say("Making this machine's identity…")
  drop.run({ "me", "id" }, {}, function(result)
    say(result.ok and "" or drop.why(result))
    M.revision:set(M.revision:get() + 1)
    if result.ok then M.watch(true) end
  end)
  return true
end

--- Starts `drop serve`, left running past the shell.
function M.start_serve()
  if M.stage() ~= "ready" then return false end
  if dry_run() then morf.log("info", "eva: drop serve (dry run)") return false end
  say("Starting drop serve…")
  drop.spawn({ "serve", "--quiet" }, { detached = true })
  morf.time.timer(1500, function()
    read_nearby()
    say("")
  end, false)
  return true
end

-- ----------------------------------------------------------------- a target --

--- The target on show, or nil.
function M.target()
  local id = M.selected:get()
  for i = 1, M.targets:len() do
    local row = M.targets:get(i)
    if row.id == id then return row end
  end
end

--- A word for how `id` stands: `checking`, `yes`, `no` or nil.
function M.reachable(id) return M.reach:get()[id] end

local function set_reach(id, state)
  local all = M.reach:get()
  all[id] = state
  M.reach:set(all)
end

local function target_with(id)
  for i = 1, M.targets:len() do
    if M.targets:get(i).id == id then return M.targets:get(i) end
  end
end

-- Asks a machine what it offers; that it answers at all is what reachable is.
local function check(target, done)
  set_reach(target.id, "checking")
  drop.run({ "topic", "ls", target.address }, { timeout_ms = drop.REACH_MS }, function(result)
    set_reach(target.id, result.ok and "yes" or "no")
    if result.ok and M.selected:get() == target.id then
      local rows = {}
      for _, topic in ipairs(drop.parse_topics(result.stdout)) do
        rows[#rows + 1] = { id = topic.path, path = topic.path, kind = M.kind_name(topic.kind), about = topic.about }
      end
      M.remote:replace(rows, "id")
    end
    if done then done(result.ok) end
  end)
end

--- Asks every target in turn whether it answers.
function M.check_all()
  local index = 0
  local function step()
    index = index + 1
    local row = M.targets:get(index)
    if row then check(row, step) end
  end
  step()
end

--- Shows a target: what it offers, and what was said with it.
function M.select(id)
  local target = target_with(id)
  if not target then return end
  M.selected:set(id)
  M.remote:replace({}, "id")
  M.files:replace({}, "id")
  M.folder:set("")
  M.log:replace({}, "id")
  check(target)
  M.read_log()
  local waiting = held
  if #waiting > 0 then
    held = {}
    M.pending:set("")
    M.send(waiting)
  end
end

function M.read_log()
  local target = M.target()
  if not target then return end
  drop.run({ "me", "log", target.machine }, {}, function(result)
    if M.selected:get() ~= target.id then return end
    local rows = {}
    for i, line in ipairs((drop.parse_log(result.ok and result.stdout or ""))) do rows[i] = { id = tostring(i), text = line } end
    M.log:replace(rows, "id")
  end)
end

--- Opens a shared folder of the target, at `path`.
function M.browse(path)
  local target = M.target()
  if not target then return end
  M.folder:set(path)
  say("Asking " .. target.title .. "…")
  drop.run({ "file", "ls", target.address .. ":" .. path }, { timeout_ms = drop.REACH_MS }, function(result)
    if not result.ok then say(drop.why(result)) return end
    say("")
    local rows = {}
    for _, file in ipairs(drop.parse_files(result.stdout)) do
      file.id = file.name
      rows[#rows + 1] = file
    end
    M.files:replace(rows, "id")
  end)
end

--- A step into a folder, or the file fetched.
function M.open_file(row)
  local folder = M.folder:get()
  if row.folder then M.browse(folder .. "/" .. row.name) return end
  M.fetch(folder .. "/" .. row.name, row.name)
end

--- Up one folder, back to the topics at the top.
function M.up()
  local folder = M.folder:get()
  local parent = folder:match("^(/[^/]+)/.+$") and folder:match("^(.*)/[^/]+$")
  if parent then M.browse(parent) else
    M.folder:set("")
    M.files:replace({}, "id")
  end
end

-- ---------------------------------------------------------------- moving --

local function transfer(name, to)
  transfer_count = transfer_count + 1
  local id = tostring(transfer_count)
  M.transfers:insert(1, { id = id, name = name, to = to, state = "Sending…" })
  return function(state)
    for i = 1, M.transfers:len() do
      local row = M.transfers:get(i)
      if row.id == id then
        row.state = state
        M.transfers:set(i, row)
        return
      end
    end
  end
end

--- Sends `paths` to the target on show; with none, they wait for a press.
function M.send(paths)
  local list = {}
  for _, path in ipairs(paths or {}) do
    if type(path) == "string" and path ~= "" then list[#list + 1] = (morf.fs.expand(path)) end
  end
  if #list == 0 then return false end
  local target = M.target()
  if not target then
    for _, path in ipairs(list) do held[#held + 1] = path end
    M.pending:set(#held == 1 and (held[1]:match("([^/]+)$") or held[1]) or (#held .. " files"))
    return false
  end
  local words = { "connect", target.address .. ":/inbox" }
  for _, path in ipairs(list) do words[#words + 1] = path end
  local name = #list == 1 and (list[1]:match("([^/]+)$") or list[1]) or (#list .. " files")
  local mark = transfer(name, target.title)
  if dry_run() then mark("Not sent: dry run") return false end
  drop.run(words, { timeout_ms = drop.SEND_MS }, function(result)
    mark(result.ok and "Sent" or drop.why(result))
    M.read_log()
  end)
  return true
end

--- Forgets files waiting for somewhere to go.
function M.cancel_pending()
  held = {}
  M.pending:set("")
end

--- Fetches a file of the target into the inbox folder or the home folder.
function M.fetch(path, name)
  local target = M.target()
  if not target then return false end
  local into = inbox_path or morf.fs.home()
  local mark = transfer(name, "this machine")
  if dry_run() then mark("Not fetched: dry run") return false end
  drop.run({ "file", "get", target.address .. ":" .. path, into }, { timeout_ms = drop.SEND_MS }, function(result)
    mark(result.ok and "Fetched" or drop.why(result))
    read_received()
  end)
  return true
end

--- Says `text` in the target's chat.
function M.message(text)
  text = tostring(text or ""):match("^%s*(.-)%s*$")
  local target = M.target()
  if text == "" or not target then return false end
  if dry_run() then say("Not sent: dry run") return false end
  drop.run({ "connect", target.address .. ":/chat", text }, { timeout_ms = drop.REACH_MS }, function(result)
    say(result.ok and "" or drop.why(result))
    M.read_log()
  end)
  return true
end

-- ------------------------------------------------------------------ people --

--- Asks a nearby device to pair; it says yes on its own screen.
function M.pair(name)
  if dry_run() then say("Not asked: dry run") return false end
  say("Asking " .. name .. ": check the number on its screen.")
  drop.run({ "nearby", "pair", name }, { timeout_ms = drop.SEND_MS }, function(result)
    say(result.ok and ("Paired with " .. name) or drop.why(result))
    M.refresh()
  end)
  return true
end

--- Answers a device asking this one.
function M.decide(name, yes)
  if dry_run() then return false end
  drop.run({ "nearby", yes and "yes" or "no", name }, {}, function(result)
    if not result.ok then say(drop.why(result)) end
    M.refresh()
  end)
  return true
end

--- Takes a code somebody shows.
function M.take_code(code)
  code = tostring(code or ""):match("^%s*(.-)%s*$")
  if code == "" or dry_run() then return false end
  say("Taking the code…")
  drop.run({ "person", "add", code }, { timeout_ms = drop.SEND_MS }, function(result)
    say(result.ok and "Paired." or drop.why(result))
    M.refresh()
  end)
  return true
end

--- Shows this machine's code until it is taken or given up on.
function M.offer_code()
  if offering or dry_run() or M.stage() ~= "ready" then return false end
  local child = drop.spawn({ "person", "add" }, { timeout_ms = 300000,
    on_stdout = function(line)
      local code = line:match("^%s+code:%s+(%S+)")
      if code then M.code:set(code) end
    end,
    on_stderr = function() end,
    on_exit = function()
      offering = nil
      M.code:set("")
      M.refresh()
    end,
  })
  offering = child
  return child ~= nil
end

--- Stops showing the code.
function M.stop_offer()
  if offering then offering:kill("TERM") end
end

-- ------------------------------------------------------------------ topics --

--- Adds a topic to this machine.
function M.add_topic(name, kind, level)
  name = tostring(name or ""):match("^/*%s*(.-)%s*/*$")
  if name == "" or not name:match("^[%w_%-]+$") then say("A topic's name is one word.") return false end
  if dry_run() then say("Not added: dry run") return false end
  drop.run({ "topic", "add", name, kind, "--for", level or "me" }, {}, function(result)
    say(result.ok and "" or drop.why(result))
    read_own_topics()
  end)
  return true
end

--- Takes a topic off this machine.
function M.remove_topic(path)
  if dry_run() then return false end
  drop.run({ "topic", "rm", (path:gsub("^/", "")) }, {}, function(result)
    say(result.ok and "" or drop.why(result))
    read_own_topics()
  end)
  return true
end

return M
