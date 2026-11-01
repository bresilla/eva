-- Notification service, history and actions; theme builders own popups.
--
-- Every screen runs this file. The primary one serves the bus and keeps the
-- clocks, the history and its file; the others read the shared signals and ask
-- it through `ask`.
local morf = require("morf")
local drawer = require("drawer")
local config = require("config")
local rules = require("notification_rules")
local focus = require("focus_model")

local M = {}

local shared = morf.shared or morf.signal
local function primary() return not morf.window.primary or morf.window.primary() end

-- Moves with every change to the lists below. `records`, `asleep`, `recent` and
-- `on_show` read them through it: one table until the next change.
M.revision = shared("eva.notifications.revision", 0)
local function listing(name)
  local signal, list, at, value = shared(name, {}), {}, nil, nil
  function list:get() return signal:get() end
  function list:set(new)
    signal:set(new)
    M.revision:set(M.revision:get() + 1)
  end
  function list.read()
    local revision = M.revision:get()
    if revision ~= at then at, value = revision, signal:get() end
    return value
  end
  return list
end

-- The popups on show, oldest first.
M.list = listing("eva.notifications")
-- Every notification that came in, oldest first, until it is dismissed from
-- the sidebar or cleared there: the popups go when they expire, the history
-- stays. Each entry is a copy with `time` (seconds, when it came).
M.history = listing("eva.notifications.history")
-- Hidden until `wake_at`, and what was cleared lately.
M.snoozed = listing("eva.notifications.snoozed")
M.dismissed = listing("eva.notifications.dismissed")
M.records, M.asleep, M.recent, M.on_show = M.history.read, M.snoozed.read, M.dismissed.read, M.list.read
-- What a clear can still take back: `{ count, label }`, or false.
M.undo = shared("eva.notifications.undo", false)
-- The ids whose sender still hears actions, as `{ ["id"] = true }`.
M.answers = shared("eva.notifications.answers", {})
-- What a bar or a dock reads: `count`, `unread`, `critical`, `missed`, `hidden`
-- (a Focus mode hides badges), `apps` (key -> count) and `icons` (one per app
-- with anything but low urgency, newest first: `{ key, app, icon }`).
M.badge = shared("eva.notifications.badge",
  { count = 0, unread = 0, critical = 0, missed = 0, hidden = false, apps = {}, icons = {} })
-- Do not disturb: Focus's "dnd" mode as a switch.
M.dnd = require("themes.session").keep("eva.notifications.dnd", false)
-- True while the sidebar is open (sidebar.lua sets it).
M.covered = morf.signal("eva.notifications.covered", false)
-- Which card is taking a reply, and which shows its tools (this screen's).
M.replying = morf.signal("eva.notifications.replying", false)
M.tools = morf.signal("eva.notifications.tools", false)
-- A count that rises with each arrival a screen should light for.
M.pulse = shared("eva.notifications.pulse", 0)

--- The snooze presets: seconds, and "tomorrow" for the next 8:00.
M.SNOOZE = { { 900, "15 min" }, { 3600, "1 hour" }, { 10800, "3 hours" }, { "tomorrow", "Tomorrow" } }
--- The timed mutes offered, in seconds; 0 is until turned back on.
M.MUTES = { { 3600, "1 hour" }, { 28800, "8 hours" }, { 0, "Forever" } }

local UNDO_MS, DISMISSED_CAP, TICK_MS, COOLDOWN_S, COOLDOWN_N = 8000, 20, 30000, 60, 3
local FOLD_FROM = 3

-- What the primary knows about each open notification, by id: `entry`, `out`
-- (its rule), `urgency`, `key`, `time`, `popup`, `gone` and its timers.
local live, order, handlers = {}, {}, {}
local server
local missed, last_read = 0, 0
local stale = 0

local function now() return focus.now() end

local function scalars(hints)
  local out = {}
  for key, value in pairs(hints or {}) do
    local kind = type(value)
    if kind == "string" or kind == "number" or kind == "boolean" then out[key] = value end
  end
  return out
end

-- The action keys a sender offered, less what its rule leaves out.
local function offered(n, out)
  local list = {}
  for _, action in ipairs(n.actions or {}) do
    local hidden = false
    for _, word in ipairs(out.hidden_actions or {}) do
      hidden = hidden or word == action.key or word == action.label
    end
    if not hidden then list[#list + 1] = { key = action.key, label = action.label } end
  end
  return list
end

-- What every screen may read of an open notification.
local function public(n, m)
  return { id = n.id, key = m.key, app = n.app or "", summary = n.summary or "", body = n.body or "",
    urgency = m.urgency, icon = n.icon or "", image = n.image_path or "", image_source = n.image_source,
    category = n.category or "", desktop_entry = n.desktop_entry or "", actions = offered(n, m.out),
    hints = scalars(n.hints), resident = n.resident == true, transient = n.transient == true, own = n.own,
    time = m.time, hide = m.out.hide or nil, highlight = m.out.highlight or nil, eta = m.eta,
    no_buttons = (m.out.actions == false) or nil }
end

-- How long a job has left, by how fast its `value` hint moved.
local function pace(n, m, at)
  local value = type(n.hints) == "table" and tonumber(n.hints.value) or nil
  if not value then m.eta = nil return end
  if m.value and value > m.value and at > m.value_at then
    m.eta = (100 - value) / ((value - m.value) / (at - m.value_at))
  end
  if value ~= m.value then m.value, m.value_at = value, at end
end

local function answers()
  local ids = {}
  for id in pairs(live) do ids[tostring(id)] = true end
  M.answers:set(ids)
end

local function publish()
  local list = {}
  for _, id in ipairs(order) do
    local m = live[id]
    if m and m.popup and not m.gone then list[#list + 1] = public(m.entry, m) end
  end
  M.list:set(list)
  answers()
end

-- ------------------------------------------------------------- the store --

local function store_path()
  local chosen = morf.env and morf.env("EVA_NOTIFICATION_STORE")
  if chosen and chosen ~= "" then return chosen end
  if morf.capabilities and morf.capabilities.headless then return nil end
  return morf.paths.state("notifications/history.json")
end

-- The store's folder, for its owner alone.
local function private_folder()
  local chosen = morf.env and morf.env("EVA_NOTIFICATION_STORE")
  if (chosen and chosen ~= "") or not store_path() then return end
  local folder = morf.paths.state("notifications")
  pcall(morf.fs.mkdir, folder)
  morf.process.run({ "chmod", "700", folder }, {}, function() end)
end

local function bare(record)
  local out = {}
  for key, value in pairs(record) do
    if key ~= "image_source" and key ~= "actions" then out[key] = value end
  end
  return out
end

-- What may reach the disk: a one-time code never does.
local function filed(list)
  local text = require("themes.notification_text")
  local out = {}
  for i, record in ipairs(list) do
    out[i] = bare(record)
    if text.otp(record) then out[i].summary, out[i].body = "One-time code", "Not kept" end
  end
  return out
end

local saving
local function save()
  saving = nil
  local path = store_path()
  if not path then return end
  local text = morf.json.encode { version = 1, read = last_read, history = filed(M.history:get()),
    snoozed = filed(M.snoozed:get()), dismissed = filed(M.dismissed:get()) }
  local ok, err = morf.fs.write(path .. ".new", text)
  if ok then ok, err = pcall(morf.fs.rename, path .. ".new", path) end
  if not ok then morf.log("warn", "eva: notifications not saved: " .. tostring(err)) end
end
local function dirty()
  if not primary() or saving then return end
  saving = morf.time.timer(800, save, false)
end
--- Writes the store now, instead of a moment later.
function M.flush()
  if saving then saving:cancel() save() end
end

local function within(list)
  local limit, days = config.get("notifications.history.limit"), config.get("notifications.history.days")
  local oldest = days > 0 and now() - days * 86400 or nil
  local out = {}
  for _, record in ipairs(list) do
    if not oldest or (record.time or 0) >= oldest then out[#out + 1] = record end
  end
  while limit > 0 and #out > limit do table.remove(out, 1) end
  return out
end

local function set_history(list)
  M.history:set(within(list))
  dirty()
end

local function renumber(list)
  local out = {}
  for i, record in ipairs(list) do
    stale = stale - 1
    out[i] = bare(record)
    out[i].id = stale
  end
  return out
end

-- A reload finds the shared signals as they were, under ids a new server will
-- reuse. A headless run starts from its store alone.
local function load_store()
  local headless = morf.capabilities and morf.capabilities.headless
  if not headless and (#M.history:get() > 0 or #M.snoozed:get() > 0) then
    set_history(renumber(M.history:get()))
    M.snoozed:set(renumber(M.snoozed:get()))
    M.dismissed:set(renumber(M.dismissed:get()))
    return
  end
  M.history:set({})
  M.snoozed:set({})
  M.dismissed:set({})
  M.undo:set(false)
  local path = store_path()
  if not path or not morf.fs.exists(path) then return end
  local ok, text = pcall(morf.fs.read, path)
  if not ok or type(text) ~= "string" then return end
  local fine, stored = pcall(morf.json.decode, text)
  if not fine or type(stored) ~= "table" then
    morf.log("warn", "eva: " .. path .. " is not a notification store")
    return
  end
  last_read = tonumber(stored.read) or 0
  set_history(renumber(stored.history or {}))
  M.snoozed:set(renumber(stored.snoozed or {}))
  M.dismissed:set(renumber(stored.dismissed or {}))
end

-- ----------------------------------------------------------------- history --

local function record_of(n, m)
  return { id = n.id, key = m.key, app = n.app or "", summary = n.summary or "", body = n.body or "",
    urgency = m.urgency, icon = n.icon or "", image = n.image_path or "", image_source = n.image_source,
    category = n.category or "", desktop_entry = n.desktop_entry or "", actions = offered(n, m.out),
    hints = scalars(n.hints), resident = n.resident == true, time = m.time, digest = m.out.digest or nil,
    hide = m.out.hide or nil, highlight = m.out.highlight or nil, priority = m.out.priority or nil,
    no_buttons = (m.out.actions == false) or nil }
end

local function remember(record)
  local list, out, replaced = M.history:get(), {}, false
  for i, e in ipairs(list) do
    if e.id == record.id then
      out[i] = record
      replaced = true
    else
      out[i] = e
    end
  end
  if not replaced then out[#out + 1] = record end
  set_history(out)
end

local function recorded(id)
  for _, e in ipairs(M.history:get()) do
    if e.id == id then return e end
  end
end

--- Whether a notification stays until it finishes: resident, or a job part-way.
function M.ongoing(n)
  if n.resident then return true end
  local value = type(n.hints) == "table" and tonumber(n.hints.value) or nil
  return value ~= nil and value < 100 and M.answers:get()[tostring(n.id)] == true
end

-- ------------------------------------------------------------------ sound --

local heard = {}
local function cooled(key, at)
  if not config.get("notifications.cooldown") then return false end
  local kept = {}
  for _, t in ipairs(heard[key] or {}) do
    if at - t < COOLDOWN_S then kept[#kept + 1] = t end
  end
  kept[#kept + 1] = at
  heard[key] = kept
  return #kept > COOLDOWN_N
end

local function ring_mode()
  local ringer = require("services").ringer
  return ringer and ringer.state.mode or config.get("ringer.mode")
end

local function hear(n, m)
  local sound = require("lib.services.notification_sound")
  local hints = n.hints or {}
  if m.out.announce then sound.say((n.app ~= "" and n.app .. ". " or "") .. tostring(n.summary or "")) end
  if m.out.sound == "off" or hints["suppress-sound"] == true then return end
  local wanted = config.get("notifications.sounds") or m.out.sound ~= "default" or m.out.ring
  if not wanted or cooled(m.key, m.time) then return end
  local chosen = m.out.sound ~= "default" and m.out.sound or config.get("notifications.sound")
  local file = type(hints["sound-file"]) == "string" and hints["sound-file"] or ""
  local event = type(hints["sound-name"]) == "string" and hints["sound-name"] or sound.event(m.urgency)
  if file == "" and chosen ~= "" then
    if chosen:find("/", 1, true) then file = chosen else event = chosen end
  end
  sound.play { event = event, file = file, volume = config.get("notifications.volume"), ring = ring_mode(),
    through_silent = m.out.ring == true or (m.urgency >= 2 and (n.category or ""):match("alarm") ~= nil) }
end

--- A word of a rule's command, with `$APP`, `$SUMMARY` and `$BODY` filled in.
function M.rule_word(word, n)
  local words = { APP = n.app or "", SUMMARY = n.summary or "", BODY = n.body or "" }
  return (tostring(word):gsub("%$(%u+)", function(name) return words[name] end))
end

local function run(out, n)
  if #(out.run or {}) == 0 then return end
  local dry = morf.env and morf.env("EVA_DRY_RUN")
  if dry and dry ~= "" and dry ~= "0" then
    morf.log("info", "eva: notification rule (dry run): " .. table.concat(out.run, " "))
    return
  end
  local argv = {}
  for i, word in ipairs(out.run) do argv[i] = M.rule_word(word, n) end
  morf.process.run(argv, {}, function() end)
end

-- ------------------------------------------------------------------ clocks --

local function popup_ms(m)
  if m.out.timeout >= 0 then return m.out.timeout end
  if m.urgency >= 2 or (m.entry.category or ""):match("^call%.incoming") then return 0 end
  local chosen, sent = config.get("notifications.timeout"), m.entry.timeout_ms
  if sent == nil or sent < 0 or config.get("notifications.ignore_app_timeouts") then
    return chosen > 0 and chosen or 5000
  end
  return sent
end

local function stop(m)
  if m.timer then m.timer:cancel() m.timer = nil end
end
local function stop_all(m)
  stop(m)
  if m.retire then m.retire:cancel() m.retire = nil end
end

local function drop(id)
  local m = live[id]
  if not m then return end
  stop_all(m)
  live[id] = nil
  for i, candidate in ipairs(order) do
    if candidate == id then table.remove(order, i) break end
  end
end

local function close(id)
  if server and server.open(id) then
    if server.expire then server.expire(id) else server.dismiss(id) end
  else
    drop(id)
    handlers[id] = nil
    publish()
  end
end

-- Off the screen, it stays open for its buttons a while, then closes.
local function retain(id)
  local m = live[id]
  if not m then return end
  m.gone = true
  local keep = config.get("notifications.keep_actions")
  if not m.retire then m.retire = morf.time.timer(math.max(1, keep), function() close(id) end, false) end
end

-- Its time on screen is up. A sender that left the time to us keeps its buttons
-- for a while; the rest are told it expired.
local function lapse(id)
  local m = live[id]
  if not m then return end
  m.timer = nil
  local keep = config.get("notifications.keep_actions")
  if #(m.entry.actions or {}) > 0 and (m.entry.timeout_ms or -1) < 0 and keep > 0 then
    retain(id)
    publish()
  else
    close(id)
  end
end

local function arm(id)
  local m = live[id]
  if not m then return end
  stop(m)
  if m.held then return end
  local ms = popup_ms(m)
  if ms > 0 then m.timer = morf.time.timer(ms, function() lapse(id) end, false) end
end

-- ---------------------------------------------------------------- arrivals --

local function pop(m) return m.popup and not m.gone end

local function admit(n, was)
  local at = now()
  local out = rules.outcome(n)
  local urgency = out.urgency >= 0 and out.urgency or (n.urgency or 1)
  local through = focus.allows(setmetatable({ urgency = urgency }, { __index = n }), out)
  local muted = rules.muted(out, at)
  local digest = out.digest == true and urgency < 2
  local m = was or { time = at }
  stop_all(m)
  m.entry, m.out, m.urgency, m.key = n, out, urgency, rules.key(n)
  m.popup = through and not muted and not digest and out.popup
  m.gone = false
  pace(n, m, at)
  if not was then
    live[n.id] = m
    order[#order + 1] = n.id
    if not n.own then rules.saw(n, at) end
    if not through and not muted then missed = missed + 1 end
    if out.history and config.get("notifications.history.enabled") and not n.transient then remember(record_of(n, m)) end
    if through and not muted and not digest then
      hear(n, m)
      if config.get("notifications.flash") or config.get("notifications.edge_light") then M.pulse:set(M.pulse:get() + 1) end
    end
    run(out, n)
  elseif recorded(n.id) then
    remember(record_of(n, m))
  end
  arm(n.id)
end

local function receive(list)
  local present = {}
  for i = #list, 1, -1 do
    local n = list[i]
    present[n.id] = true
    local m = live[n.id]
    if not m or m.entry ~= n then admit(n, m) end
  end
  local closed = {}
  for id, m in pairs(live) do
    if not m.entry.own and not present[id] then closed[#closed + 1] = id end
  end
  for _, id in ipairs(closed) do drop(id) end
  publish()
end

-- ------------------------------------------------------------- the server --

local function capabilities()
  local lib = require("lib.services.notification_server")
  local list = {}
  for i, word in ipairs(lib.CAPABILITIES) do list[i] = word end
  if config.get("notifications.sounds") then list[#list + 1] = "sound" end
  return list
end

local function serve()
  if server then return end
  local ok, lib = pcall(require, "lib.services.notification_server")
  if not ok then morf.log("warn", "eva: notification server: " .. tostring(lib)) return end
  local served, why = lib.serve { on_change = receive, capabilities = capabilities(),
    on_inhibit = function(count) focus.inhibited:set(count) end }
  if served then server = served
  else morf.log("info", "eva: not the notification server: " .. tostring(why)) end
end

local function unserve()
  if server and server.close then server.close() end
  server = nil
end

-- ---------------------------------------------------------------- asking --

-- What the primary does; `ask` reaches it from any screen.
local act = {}
local function ask(kind, ...)
  if primary() then return act[kind](...) end
  if morf.broadcast then morf.broadcast("notifs-ask", kind, ...) end
end
morf.ipc["notifs-ask"] = function(kind, ...)
  if primary() and act[kind] then return act[kind](...) end
end

-- Notifications the shell raises itself (and the tests): `{ app, summary, body,
-- urgency, icon, image, category, hints, actions, on_action, transient, resident,
-- timeout_ms }`; they expire as the server's do. `on_action(key, text)` hears
-- what is pressed, on the screen that raised it when that is the primary.
local own = 100000
function act.push(entry)
  own = own + 1
  local n = { id = own, app = entry.app or "eva", summary = entry.summary or "", body = entry.body or "",
    urgency = entry.urgency or 1, icon = entry.icon or "", image_path = entry.image or "", own = true,
    category = entry.category or "", desktop_entry = "", actions = entry.actions or {}, hints = entry.hints or {},
    transient = entry.transient == true, resident = entry.resident == true, timeout_ms = entry.timeout_ms }
  handlers[n.id] = entry.on_action
  admit(n)
  publish()
  return n.id
end
function M.push(entry)
  if primary() then return act.push(entry) end
  if morf.broadcast then morf.broadcast("notifs-ask", "push_json", morf.json.encode(entry)) end
end
function act.push_json(text)
  local ok, entry = pcall(morf.json.decode, text)
  if ok and type(entry) == "table" then act.push(entry) end
end

function act.dismiss(id)
  if server and server.open(id) then server.dismiss(id) return end
  drop(id)
  handlers[id] = nil
  publish()
end
function M.dismiss(id) ask("dismiss", id) end

--- Presses action `key` of notification `id`; false when nobody is listening.
function act.invoke(id, key)
  local m = live[id]
  if m and m.entry.own then
    local handler = handlers[id]
    if handler then handler(key) end
    if not m.entry.resident then act.dismiss(id) end
    return handler ~= nil
  end
  if server and server.open(id) then
    if server.invoke then return server.invoke(id, key) end
    return true
  end
  return false
end
function M.invoke(id, key) return ask("invoke", id, key) end

--- Sends what was typed to the notification's sender.
function act.reply(id, text)
  local m = live[id]
  if m and m.entry.own then
    local handler = handlers[id]
    if handler then handler("inline-reply", text) end
    act.dismiss(id)
    return true
  end
  if server and server.reply and server.reply(id, text) then
    if not (m and m.entry.resident) then server.dismiss(id) end
    return true
  end
  return false
end
function M.reply(id, text)
  M.cancel_reply()
  return ask("reply", id, text)
end

--- Stops a popup's clock while it is held, and starts it afresh after.
function act.hold(id, on)
  local m = live[id]
  if not m then return end
  m.held = on == true
  if m.held then stop(m) elseif pop(m) then arm(id) end
end
function M.hold(id, on) ask("hold", id, on) end

-- Where a finger is the main input, the on-screen keyboard comes with the field.
local function typing(on)
  local responsive, keyboard = package.loaded.responsive, package.loaded.keyboard
  if responsive and keyboard and responsive.touch() then keyboard.set(on) end
end
function M.begin_reply(id)
  M.replying:set(id)
  typing(true)
end
function M.cancel_reply()
  M.replying:set(false)
  typing(false)
end

--- A card's own tools (snooze, mute, its rules) out or back.
function M.toggle_tools(id) M.tools:set(M.tools:get() ~= id and id or false) end

--- Whether cards draw their senders' buttons, and their code and link chips.
function M.buttons_on() return config.get("notifications.actions") end
function M.smart_on() return config.get("notifications.smart") end
--- How many cards stand on screen.
function M.max_popups() return config.get("notifications.max_popups") end
--- Whether an arrival lights the edge, and flashes the screen.
function M.edge_light() return config.get("notifications.edge_light") end
function M.flash() return config.get("notifications.flash") end

--- Whether `n`'s content stays hidden until it is opened.
function M.redacted(n)
  if n.hide or config.get("notifications.previews") == "hide" then return true end
  return focus.auto:get() == "sharing"
end

--- Silences sender `key` for `seconds`, for good with 0.
function M.mute_app(key, seconds) rules.mute(key, seconds or 0, now()) end
--- Opens sender `key`'s rules, in Settings.
function M.rules_of(key) require("notification_history").rules_of(key) end

-- ------------------------------------------------------------ taken away --

local pending

local function commit()
  local batch = pending
  if not batch then return end
  pending = nil
  if batch.timer then batch.timer:cancel() end
  M.undo:set(false)
  for _, id in ipairs(batch.ids) do
    if live[id] then act.dismiss(id) end
  end
end

local function hide(id)
  local m = live[id]
  if m then
    m.gone = true
    stop(m)
  end
end

local function sorted(list)
  table.sort(list, function(a, b) return (a.time or 0) < (b.time or 0) end)
  return list
end

-- Takes records out of the history; their senders hear when the undo lapses.
local function take(ids, label)
  commit()
  local gone, kept = {}, {}
  for _, e in ipairs(M.history:get()) do
    if ids[e.id] then gone[#gone + 1] = e else kept[#kept + 1] = e end
  end
  local closing = {}
  for id in pairs(ids) do
    closing[#closing + 1] = id
    hide(id)
  end
  publish()
  if #gone == 0 then
    for _, id in ipairs(closing) do if live[id] then act.dismiss(id) end end
    return 0
  end
  set_history(kept)
  local recent = {}
  for _, e in ipairs(M.dismissed:get()) do recent[#recent + 1] = e end
  for _, e in ipairs(gone) do recent[#recent + 1] = bare(e) end
  while #recent > DISMISSED_CAP do table.remove(recent, 1) end
  M.dismissed:set(recent)
  pending = { records = gone, ids = closing, timer = morf.time.timer(UNDO_MS, commit, false) }
  M.undo:set({ count = #gone, label = label })
  return #gone
end

local function words(ids)
  local set = {}
  for id in tostring(ids):gmatch("[^,]+") do set[tonumber(id)] = true end
  return set
end

function act.forget(id) return take({ [id] = true }, "Dismissed") end
--- Takes notification `id` out of the history (and its popup with it).
function M.forget(id) return ask("forget", id) end

--- The ids given as "1,2,3", as one batch to undo.
function act.forget_ids(ids, label) return take(words(ids), label or "Cleared") end
function M.forget_ids(list, label) return ask("forget_ids", table.concat(list, ","), label) end

--- Empties the history, but for what is still running, and shuts every popup.
function act.clear()
  local ids = {}
  for _, e in ipairs(M.history:get()) do
    if not M.ongoing(e) then ids[e.id] = true end
  end
  for _, e in ipairs(M.list:get()) do
    if not M.ongoing(e) then ids[e.id] = true end
  end
  return take(ids, "Cleared")
end
function M.clear() return ask("clear") end

--- Clears one sender.
function act.clear_app(key)
  local ids = {}
  for _, e in ipairs(M.history:get()) do
    if (e.key or e.app) == key and not M.ongoing(e) then ids[e.id] = true end
  end
  for _, e in ipairs(M.list:get()) do
    if e.key == key and not M.ongoing(e) then ids[e.id] = true end
  end
  return take(ids, "Cleared " .. rules.name(key))
end
function M.clear_app(key) return ask("clear_app", key) end

--- Clears everything low urgency.
function act.clear_silent()
  local ids = {}
  for _, e in ipairs(M.history:get()) do
    if (e.urgency or 1) == 0 and not M.ongoing(e) then ids[e.id] = true end
  end
  return take(ids, "Cleared silent")
end
function M.clear_silent() return ask("clear_silent") end

--- Takes the last clear back.
function act.restore()
  local batch = pending
  if not batch then return false end
  pending = nil
  batch.timer:cancel()
  M.undo:set(false)
  local list = {}
  for _, e in ipairs(M.history:get()) do list[#list + 1] = e end
  for _, e in ipairs(batch.records) do list[#list + 1] = e end
  set_history(sorted(list))
  for _, id in ipairs(batch.ids) do retain(id) end
  local recent = {}
  for _, e in ipairs(M.dismissed:get()) do
    local back = false
    for _, r in ipairs(batch.records) do back = back or r.id == e.id end
    if not back then recent[#recent + 1] = e end
  end
  M.dismissed:set(recent)
  return true
end
function M.restore() return ask("restore") end

--- Brings a recently dismissed entry back to the history.
function act.bring_back(id)
  local kept, found = {}, nil
  for _, e in ipairs(M.dismissed:get()) do
    if e.id == id then found = e else kept[#kept + 1] = e end
  end
  if not found then return false end
  M.dismissed:set(kept)
  local list = {}
  for _, e in ipairs(M.history:get()) do list[#list + 1] = e end
  list[#list + 1] = found
  set_history(sorted(list))
  return true
end
function M.bring_back(id) return ask("bring_back", id) end

-- ---------------------------------------------------------------- snooze --

local waking = {}

local function wake(id)
  waking[id] = nil
  local kept, record = {}, nil
  for _, e in ipairs(M.snoozed:get()) do
    if e.id == id then record = e else kept[#kept + 1] = e end
  end
  if not record then return end
  M.snoozed:set(kept)
  record.wake_at = nil
  local m = live[id]
  if m then
    m.gone, m.popup = false, true
    m.time = now()
    record.time = m.time
    remember(record)
    arm(id)
    publish()
  else
    local n = act.push { app = record.app, summary = record.summary, body = record.body, urgency = record.urgency,
      icon = record.icon, image = record.image, category = record.category, hints = record.hints }
    if live[n] then live[n].key = record.key or live[n].key end
  end
  dirty()
end

local function watch_snooze(record)
  local left = (record.wake_at or 0) - now()
  if waking[record.id] then waking[record.id]:cancel() end
  waking[record.id] = morf.time.timer(math.max(1, math.floor(left * 1000)), function() wake(record.id) end, false)
end

--- Seconds until the next 8:00, or `value` as given.
function M.snooze_seconds(value)
  if value == "tomorrow" then return focus.deadline(-1, now()) - now() end
  return tonumber(value) or 0
end

--- Hides notification `id` for `seconds`.
function act.snooze(id, seconds)
  local record = recorded(id)
  local m = live[id]
  if not record and m then record = record_of(m.entry, m) end
  if not record then return false end
  local kept = {}
  for _, e in ipairs(M.history:get()) do
    if e.id ~= id then kept[#kept + 1] = e end
  end
  set_history(kept)
  record = bare(record)
  record.wake_at = now() + seconds
  local list = {}
  for _, e in ipairs(M.snoozed:get()) do list[#list + 1] = e end
  list[#list + 1] = record
  M.snoozed:set(list)
  if m then
    stop(m)
    if #(m.entry.actions or {}) > 0 then retain(id) else close(id) end
  end
  watch_snooze(record)
  publish()
  dirty()
  return true
end
function M.snooze(id, value)
  M.replying:set(false)
  M.tools:set(false)
  return ask("snooze", id, M.snooze_seconds(value))
end

--- Brings a snoozed notification back now.
function act.wake(id)
  if waking[id] then waking[id]:cancel() end
  wake(id)
end
function M.wake(id) ask("wake", id) end

-- ----------------------------------------------------------------- reading --

--- Marks everything read.
function act.read()
  last_read = now()
  missed = 0
  dirty()
  act.refresh()
end
function M.read() ask("read") end

function act.refresh()
  local list = M.history:get()
  local apps, icons, seen, unread, critical = {}, {}, {}, 0, 0
  for i = #list, 1, -1 do
    local e = list[i]
    local key = e.key or e.app
    apps[key] = (apps[key] or 0) + 1
    if (e.time or 0) > last_read then unread = unread + 1 end
    if (e.urgency or 1) >= 2 then critical = critical + 1 end
    if (e.urgency or 1) > 0 and not seen[key] then
      seen[key] = true
      icons[#icons + 1] = { key = key, app = e.app, icon = e.icon or "" }
    end
  end
  M.badge:set({ count = #list, unread = unread, critical = critical, missed = missed,
    hidden = focus.hides_badges(), apps = apps, icons = icons })
end

-- Which senders' cards stand apart: every screen's own fold.
local unfolded, unfolded_at = {}, morf.signal("eva.notifications.unfolded", 0)

--- Whether the popups of `key` stand apart.
function M.is_unfolded(key)
  unfolded_at:get()
  return unfolded[key] == true
end
function M.unfold(key)
  unfolded[key] = not unfolded[key] or nil
  unfolded_at:set(unfolded_at:get() + 1)
end

local cache_list, cache_fold, cache_open, cache_cards
local function cards()
  local list, fold, opened = M.on_show(), config.get("notifications.stack"), unfolded_at:get()
  if list == cache_list and fold == cache_fold and opened == cache_open then return cache_cards end
  local open, count, heads, out = unfolded, {}, {}, {}
  for _, n in ipairs(list) do count[n.key or n.id] = (count[n.key or n.id] or 0) + 1 end
  -- The newest on top.
  for i = #list, 1, -1 do
    local n, key = list[i], list[i].key or list[i].id
    local head = fold and count[key] >= FOLD_FROM and not open[key] and heads[key]
    if head then
      head.more = head.more + 1
      head.ids[#head.ids + 1] = n.id
    else
      local card = setmetatable({ more = 0, ids = { n.id } }, { __index = n })
      heads[key] = card
      out[#out + 1] = card
    end
  end
  cache_list, cache_fold, cache_open, cache_cards = list, fold, opened, out
  return out
end

function M.shown(limit)
  local all = cards()
  if not limit or limit >= #all then return all end
  local out = {}
  for i = 1, limit do out[i] = all[i] end
  return out
end

local open_ids = morf.signal("eva.notifications.open", {})
function M.expanded(id) return open_ids:get()[tostring(id)] == true end

M.opened = morf.signal("eva.notifications.presented", false)
function M.toggle(id)
  local key = tostring(id)
  local ids = {}
  for k, v in pairs(open_ids:get()) do ids[k] = v end
  ids[key] = not ids[key] or nil
  open_ids:set(ids)
end
-- Expanded state belongs only to live popups, never to expired history.
morf.effect("eva.notifications.expansion", function()
  local present, ids, changed = {}, {}, false
  for _, n in ipairs(M.list:get()) do present[tostring(n.id)] = true end
  for id, on in pairs(open_ids:get()) do
    if present[id] then ids[id] = on else changed = true end
  end
  if changed then open_ids:set(ids) end
end)

local visual
--- Where the popups stand: a top or bottom anchor (shell/osd_model.lua).
M.position = require("osd_model").notifications
--- Dismisses the popup at `index`, sent `direction` when a swipe says so.
function M.dismiss_at(index, direction)
  local entry = M.shown()[index]
  if not entry then return end
  local ids = entry.ids or { entry.id }
  local function go()
    for _, id in ipairs(ids) do
      M.dismiss(id)
      if not config.get("notifications.history.keep_dismissed") then M.forget(id) end
    end
  end
  local delay = visual.dismiss(index, direction) or 0
  -- Capture identity before the exit animation. A new arrival can replace
  -- this slot while it is moving; it must not be dismissed in its place.
  if delay > 0 then morf.time.timer(delay, go, false) else go() end
end

--- A press on the card at `index`: its sender's default action, else dismissal.
function M.click_at(index)
  local entry = M.shown()[index]
  if not entry then return end
  for _, action in ipairs(entry.actions or {}) do
    if action.key == "default" then
      M.invoke(entry.id, "default")
      return
    end
  end
  M.dismiss_at(index)
end

--- What a screen reader or the CLI hears as the state: a plain table.
function M.status()
  local badge = M.badge:get()
  return { count = badge.count, unread = badge.unread, critical = badge.critical, missed = badge.missed,
    shown = #M.list:get(), snoozed = #M.snoozed:get(), focus = focus.active_id(), quiet = focus.quiet() }
end

-- ------------------------------------------------------- Focus and the rest --

-- The Do not disturb switch and the mode stay one thing.
local was_dnd, focus_was_quiet = M.dnd:get(), false
morf.effect("eva.notifications.dnd", function()
  local on, active = M.dnd:get(), focus.active_id()
  if on ~= was_dnd then
    was_dnd = on
    if on and active ~= "dnd" then focus.start("dnd")
    elseif not on and active == "dnd" then focus.stop() end
  elseif (active == "dnd") ~= on then
    was_dnd = active == "dnd"
    M.dnd:set(was_dnd)
  end
end)

--- What the last quiet spell held back, as one card with a way to it.
local function report_missed()
  local count = missed
  missed = 0
  if count == 0 then return end
  act.push { app = "Eva", summary = ("You missed %d notification%s"):format(count, count == 1 and "" or "s"),
    body = "They are in your notifications.", icon = "notifications", category = "eva.missed", transient = true,
    actions = { { key = "open", label = "Open" } }, on_action = function()
      if package.loaded.sidebar then require("pages").open("notifications") end
    end }
end

-- Going quiet clears the screen of what the quiet would have held back.
local function hush()
  local changed = false
  for _, m in pairs(live) do
    local probe = setmetatable({ urgency = m.urgency }, { __index = m.entry })
    if pop(m) and not focus.allows(probe, m.out) then
      m.popup = false
      changed = true
    end
  end
  if changed then publish() end
end

local digest_fired = ""
local function digest_tick()
  local at = morf.time.format("%H:%M", now())
  local due = false
  for _, time in ipairs(config.get("notifications.digest_times") or {}) do due = due or time == at end
  if not due or digest_fired == at then return end
  digest_fired = at
  local count, apps, names = 0, {}, {}
  for _, e in ipairs(M.history:get()) do
    if e.digest and (e.time or 0) > last_read then
      count = count + 1
      if not apps[e.key or e.app] then
        apps[e.key or e.app] = true
        names[#names + 1] = e.app
      end
    end
  end
  if count == 0 then return end
  act.push { app = "Eva", summary = ("%d notification%s for you"):format(count, count == 1 and "" or "s"),
    body = table.concat(names, ", "), icon = "notifications", transient = true, category = "eva.digest" }
end

local function start_primary()
  private_folder()
  load_store()
  M.list:set({})
  if config.get("notifications.daemon") then serve() end
  for _, record in ipairs(M.snoozed:get()) do watch_snooze(record) end
  focus.on_ended = function(mode)
    act.push { app = "Eva", summary = mode.name .. " finished", body = "Time for a break.", icon = mode.icon,
      category = "eva.focus", transient = true }
  end
  require("focus_triggers").start()
  morf.time.timer(TICK_MS, digest_tick, true)
  morf.effect("eva.notifications.badge", function()
    M.history:get()
    focus.hides_badges()
    act.refresh()
  end)
  morf.effect("eva.notifications.quiet", function()
    local quiet = focus.quiet()
    if focus_was_quiet and not quiet then morf.time.timer(400, report_missed, false) end
    if quiet and not focus_was_quiet then morf.time.timer(1, hush, false) end
    focus_was_quiet = quiet
  end)
  morf.effect("eva.notifications.daemon", function()
    if config.get("notifications.daemon") then serve() else unserve() end
  end)
  morf.effect("eva.notifications.capabilities", function()
    local list = capabilities()
    if server and server.set_capabilities then server.set_capabilities(list) end
  end)
  morf.effect("eva.notifications.retention", function()
    local list = M.history:get()
    if not config.get("notifications.history.enabled") then
      if #list > 0 then M.history:set({}) dirty() end
    elseif #within(list) ~= #list then
      set_history(list)
    end
  end)
end

if primary() then start_primary() end
if morf.window.on_primary then
  morf.window.on_primary(function(now_primary)
    if now_primary then start_primary() else unserve() end
  end)
end

-- History open: what it shows counts as read.
morf.effect("eva.notifications.read", function()
  if M.covered:get() then M.read() end
end)

visual = require("themes").view("notifications").build(M)
M.drawer = drawer.new { name = "notifications", edge = visual.edge, width = visual.width, height = visual.height,
  -- Toasts: they stay until their time is up, a click or a swipe.
  close_policy = "none",
  content = visual.content, props = visual.props }
-- The screen they stand on: the one named, or the one in use.
local function on_this_screen()
  local services, chosen = require("services"), config.get("notifications.output")
  if chosen ~= "" and services.output then return services.output() == chosen end
  return services.here()
end
morf.effect("eva.notifications.shown", function()
  M.drawer.set(#M.on_show() > 0 and not M.covered:get() and on_this_screen())
end)
--- The edge light and the flash of an arrival, for the frame to lay over all.
function M.overlay() return visual.overlay() end
--- What a lock screen may say of the history: `{ count, apps = { names },
--- entries = { { app, summary, body } } }`, by `notifications.lock_previews`.
function M.lock_view()
  local level, list = config.get("notifications.lock_previews"), M.records()
  local out = { count = level ~= "none" and #list or 0, apps = {}, entries = {} }
  if level ~= "all" and level ~= "app" then return out end
  local seen = {}
  for i = #list, 1, -1 do
    local e = list[i]
    if not seen[e.app] then
      seen[e.app] = true
      out.apps[#out.apps + 1] = e.app
    end
    if level == "all" and not M.redacted(e) then
      out.entries[#out.entries + 1] = { app = e.app, summary = e.summary, body = e.body }
    end
  end
  return out
end
morf.effect("eva.notifications.presented", function() M.opened:set(M.drawer.open:get()) end)
-- A drawer's edge is fixed as it is built: the other one builds this output's
-- shell again in place. Along the edge the popups just move.
morf.effect("eva.notifications.edge", function()
  local edge = M.position():match("^bottom") and "bottom" or "top"
  if edge ~= visual.edge then morf.reload { output = true } end
end)
return M
