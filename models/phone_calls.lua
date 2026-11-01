-- What a phone call is to the person holding the phone, on top of the modem's
-- call objects. No nodes. The shell runs one as the owner: it rings, routes
-- the sound, writes the history and clears finished calls. The lock runs
-- another with `owner` false, which only shows and acts, so a call can be
-- taken over the lock without the two ringing or logging twice.
--
--   local phone = require("models.phone_calls").new { mobile = m, book = contacts, owner = true,
--     ring = ringer, audio = callaudio, log = journal, notify = fn }
--   phone.stage:get()     -- idle, incoming, dialing, talking or ended
--   phone.current()       -- the call the screen is about, or nil
--   phone.waiting()       -- a second call asking, while one is up
--   phone.answer()  phone.decline()  phone.hangup()  phone.hold()  phone.tone("5")
--
-- `quiet(row)` keeps a call from ringing.
local morf = require("morf")

local M = {}

-- What 3GPP TS 22.101 has every phone place with no list from the network:
-- two numbers always, and six more with no SIM.
M.EMERGENCY = { "112", "911" }
M.EMERGENCY_NO_SIM = { "000", "08", "110", "118", "119", "999" }

local LIVE = { dialing = true, ["ringing-out"] = true, ["ringing-in"] = true, active = true, held = true, waiting = true }
local ENDED_FOR = 1800

local serial = 0

--- What became of a finished call: answered, missed, declined, outgoing,
--- unanswered or failed.
function M.outcome(memory, reason)
  if memory.direction == "incoming" then
    if memory.talked then return "answered" end
    if memory.declined then return "declined" end
    return "missed"
  end
  if memory.talked then return "outgoing" end
  if reason == "error" or reason == "audio-setup-failed" then return "failed" end
  return "unanswered"
end

function M.new(options)
  serial = serial + 1
  local name = "eva.phone." .. serial .. "."
  local mobile, book = options.mobile, options.book
  local voice = mobile.voice
  local owner = options.owner == true
  local phone = {
    rows = morf.signal(name .. "rows", {}),
    stage = morf.signal(name .. "stage", "idle"),
    seconds = morf.signal(name .. "seconds", 0),
    keypad = morf.signal(name .. "keypad", false),
    ended = morf.signal(name .. "ended", ""),
    message = morf.signal(name .. "message", ""),
  }
  local memory = {}
  local ring_id, ringing, clock, ended_timer
  local was_talking = false

  local function hook(fn, ...) if fn then return fn(...) end end

  local function stop_ring()
    if ringing and options.ring then options.ring.stop(ring_id) end
    ringing, ring_id = false, nil
  end

  local function start_ring(row)
    if not owner or ringing or not options.ring then return end
    if options.quiet and options.quiet(row) then return end
    ringing = true
    options.ring.trigger("phone-incoming-call", { timeout = 0 }, function(id)
      if ringing then ring_id = id else options.ring.stop(id) end
    end)
  end

  local function stop_clock()
    if clock then clock:cancel() clock = nil end
  end
  local function start_clock(started)
    if clock then return end
    phone.seconds:set(0)
    clock = morf.time.timer(1000, function()
      phone.seconds:set((morf.time.now_ms() - started) // 1000)
    end, true)
  end

  local function record(mem, row)
    if not owner or not options.log then return end
    local now = morf.time.now()
    local outcome = mem.outcome or M.outcome(mem, row.reason)
    options.log.put { id = row.path .. "@" .. tostring(mem.time), number = row.number, direction = mem.direction,
      outcome = outcome, time = mem.time, duration = mem.talked and math.max(0, now - mem.talked) or 0,
      seen = outcome ~= "missed" }
    if outcome == "missed" then
      hook(options.notify, { summary = "Missed call", body = book.label(row.number), app = "Phone",
        urgency = 1, number = row.number })
    end
  end

  local function finish(row, mem)
    if mem.finished then return end
    mem.finished = true
    if owner then
      record(mem, row)
      voice.forget(row.path)
    end
    phone.ended:set(mem.outcome == "blocked" and "" or (mem.talked and "Call ended" or
      (mem.direction == "incoming" and "Missed call" or "Call ended")))
  end

  local function observe(row)
    local mem = memory[row.path]
    if not mem then
      mem = { direction = row.direction, time = morf.time.now(), number = row.number }
      memory[row.path] = mem
      if row.direction == "incoming" and owner and book.blocked(row.number) then
        mem.outcome = "blocked"
        voice.hangup(row.path)
      end
    end
    if row.state == "active" and not mem.talked then
      mem.talked = morf.time.now()
      mem.started_ms = morf.time.now_ms()
    end
    if row.state == "terminated" then finish(row, mem) end
    return mem
  end

  morf.effect(name .. "follow", function()
    local rows, present = {}, {}
    local talking, incoming, dialing
    for _, row in ipairs(voice.calls:get()) do
      present[row.path] = true
      local mem = observe(row)
      if LIVE[row.state] and mem.outcome ~= "blocked" then
        row.name = book.person(row.number) ~= nil and book.label(row.number) or ""
        row.label = book.label(row.number)
        rows[#rows + 1] = row
        if row.state == "active" or row.state == "held" then talking = true
        elseif row.state == "ringing-in" then incoming = row
        elseif row.state == "dialing" or row.state == "ringing-out" then dialing = true end
      end
    end
    for path in pairs(memory) do
      if not present[path] then memory[path] = nil end
    end
    phone.rows:set(rows)

    if incoming and not talking then start_ring(incoming) else stop_ring() end

    local stage = talking and "talking" or incoming and "incoming" or dialing and "dialing" or "idle"
    local before = phone.stage:get()
    if stage == "idle" and before ~= "idle" and before ~= "ended" and phone.ended:get() ~= "" then stage = "ended" end
    if stage ~= "idle" and stage ~= "ended" and ended_timer then
      ended_timer:cancel()
      ended_timer = nil
    end
    if stage == "ended" and not ended_timer then
      ended_timer = morf.time.timer(ENDED_FOR, function()
        ended_timer = nil
        phone.ended:set("")
        phone.keypad:set(false)
        phone.stage:set("idle")
      end, false)
    end
    if stage ~= before and not (before == "ended" and stage == "idle") then phone.stage:set(stage) end

    if talking then
      local started
      for _, row in ipairs(rows) do
        local mem = memory[row.path]
        if mem and mem.started_ms and (not started or mem.started_ms < started) then started = mem.started_ms end
      end
      if started then start_clock(started) end
    else
      stop_clock()
    end
    local live = #rows > 0 and (talking or dialing or incoming ~= nil) and stage ~= "incoming"
    if owner and options.audio and live ~= was_talking then
      was_talking = live
      options.audio.call(live)
      if not live then
        options.audio.speaker(false)
        options.audio.mute(false)
      end
    end
  end)

  local function by_state(...)
    local wanted = {}
    for _, state in ipairs { ... } do wanted[state] = true end
    for _, row in ipairs(phone.rows:get()) do
      if wanted[row.state] then return row end
    end
  end

  --- The call the screen is about.
  function phone.current()
    return by_state("active") or by_state("ringing-in") or by_state("dialing", "ringing-out") or by_state("held")
  end
  --- A second call asking while one is up.
  function phone.waiting() return by_state("waiting") end
  --- A call on hold beside the one that is active.
  function phone.held() return by_state("active") and by_state("held") or nil end
  --- Whether two calls are joined.
  function phone.conference()
    local row = by_state("active")
    return row ~= nil and row.multiparty == true
  end
  --- Whether the only call up is on hold.
  function phone.on_hold() return by_state("held") ~= nil and by_state("active") == nil end

  --- Takes the call that is ringing; the one up is held for a waiting one.
  function phone.answer()
    stop_ring()
    local waiting = by_state("waiting")
    if waiting then return voice.hold() end
    local row = by_state("ringing-in")
    return row ~= nil and voice.accept(row.path)
  end
  --- Ends the call that is up and takes the waiting one.
  function phone.answer_ending() return voice.hangup_and_accept() end

  --- Turns the ringing or waiting call away.
  function phone.decline()
    stop_ring()
    local row = by_state("ringing-in") or by_state("waiting")
    if not row then return false end
    if memory[row.path] then memory[row.path].declined = true end
    return voice.hangup(row.path)
  end

  --- Ends the call that is up, or a conference whole.
  function phone.hangup()
    if phone.conference() then return voice.hangup_all() end
    local row = phone.current()
    return row ~= nil and voice.hangup(row.path)
  end

  --- Holds the call that is up, brings a held one back: hold and swap.
  function phone.hold() return voice.hold() end
  --- Joins the held call to the active one.
  function phone.merge()
    local row = by_state("held")
    return row ~= nil and voice.join(row.path)
  end
  --- Stops the ringing and leaves the call asking.
  function phone.silence() stop_ring() end

  --- Sends a keypad tone into the call that is up.
  function phone.tone(digit)
    local row = by_state("active")
    return row ~= nil and voice.tones(row.path, digit)
  end

  --- Starts a call to `number`.
  function phone.dial(number, done) return voice.dial(number, done) end

  --- Numbers that reach the emergency services here.
  function phone.emergency_numbers()
    local out, seen = {}, {}
    local function add(number)
      if not seen[number] then seen[number] = true out[#out + 1] = number end
    end
    for _, number in ipairs(mobile.emergency_numbers and mobile.emergency_numbers() or {}) do add(number) end
    for _, number in ipairs(M.EMERGENCY) do add(number) end
    if not mobile.state.sim_present then
      for _, number in ipairs(M.EMERGENCY_NO_SIM) do add(number) end
    end
    return out
  end

  --- Whether `number` reaches the emergency services.
  function phone.is_emergency(number)
    for _, each in ipairs(phone.emergency_numbers()) do
      if each == number then return true end
    end
    return false
  end

  --- Starts a call that needs no unlocking: only an emergency number does.
  function phone.emergency(number, done)
    if not phone.is_emergency(number) then return false end
    return voice.dial(number, done)
  end

  function phone.muted() return options.audio ~= nil and options.audio.state.muted end
  function phone.on_speaker() return options.audio ~= nil and options.audio.state.speaker end
  function phone.audio_ready() return options.audio ~= nil end
  function phone.set_muted(on) return options.audio ~= nil and options.audio.mute(on) end
  function phone.set_speaker(on) return options.audio ~= nil and options.audio.speaker(on) end

  return phone
end

return M
