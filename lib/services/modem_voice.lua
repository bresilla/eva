-- Phone calls on the modem `lib.services.modem` watches: the Voice interface
-- for dialling and for what acts on every call, one Call object per call.
--
--   local voice = mobile.voice
--   voice.calls:get()        -- { { path, number, state, direction, reason, multiparty }, ... }
--   voice.dial("+31...", done)
--   voice.accept(path)  voice.hangup(path)  voice.tones(path, "12#")
--   voice.hold()             -- active calls held, a held or waiting one back
--   voice.forget(path)       -- a finished call off ModemManager's list
--
-- `state` is dialing, ringing-out, ringing-in, active, held, waiting or
-- terminated. `done(ok, why)` hears each action.
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = {}

local MM = "org.freedesktop.ModemManager1"
local VOICE = MM .. ".Modem.Voice"
local CALL = MM .. ".Call"
local PROPERTIES = "org.freedesktop.DBus.Properties"
local QUICK, DIALLING = 10000, 60000

-- MMCallState, MMCallStateReason, MMCallDirection.
M.STATES = { [0] = "unknown", "dialing", "ringing-out", "ringing-in", "active", "held", "waiting", "terminated" }
M.REASONS = { [0] = "unknown", "outgoing-started", "incoming-new", "accepted", "terminated", "refused-or-busy",
  "error", "audio-setup-failed", "transferred", "deflected" }
M.DIRECTIONS = { [0] = "unknown", "incoming", "outgoing" }

-- One tone a call, this far apart; a comma waits the longer time here.
local TONE_GAP, TONE_PAUSE = 200, 2000

local serial = 0

--- `options.dry()` says whether actions stop short of the modem.
function M.attach(client, options)
  serial = serial + 1
  local name = "eva.modem." .. serial .. "."
  local dry = options.dry
  local voice = {
    present = morf.signal(name .. "voice", false),
    calls = morf.signal(name .. "calls", {}),
    emergency_only = morf.signal(name .. "emergency", false),
  }
  local bound
  local rows, order, watching, modem_handles = {}, {}, {}, {}

  local function publish()
    local list = {}
    for _, path in ipairs(order) do
      if rows[path].ready then list[#list + 1] = rows[path] end
    end
    voice.calls:set(list)
  end

  local function apply(row, p)
    if p.State ~= nil then row.state = M.STATES[tonumber(p.State)] or "unknown" end
    if p.StateReason ~= nil then row.reason = M.REASONS[tonumber(p.StateReason)] or "unknown" end
    if p.Direction ~= nil then row.direction = M.DIRECTIONS[tonumber(p.Direction)] or "unknown" end
    if p.Number ~= nil then row.number = tostring(p.Number) end
    if p.Multiparty ~= nil then row.multiparty = p.Multiparty == true end
  end

  local function follow(path)
    if watching[path] or type(path) ~= "string" then return end
    order[#order + 1] = path
    local row = { path = path, number = "", state = "unknown", reason = "unknown", direction = "unknown",
      multiparty = false, ready = false }
    rows[path] = row
    watching[path] = {
      client.on_signal(MM, path, CALL, "StateChanged", function(body)
        row.state = M.STATES[tonumber(body[2])] or row.state
        row.reason = M.REASONS[tonumber(body[3])] or row.reason
        publish()
      end),
      client.on_properties(MM, path, function(interface, changed)
        if interface == CALL then apply(row, changed) publish() end
      end),
    }
    client.call1_async(MM, path, PROPERTIES, "GetAll", { CALL }, QUICK, function(properties)
      if not rows[path] then return end
      if type(properties) == "table" then apply(row, properties) end
      row.ready = true
      publish()
    end)
  end

  local function unfollow(path)
    local handles = watching[path]
    if not handles then return end
    for _, handle in pairs(handles) do pcall(handle.close) end
    watching[path], rows[path] = nil, nil
    for index, each in ipairs(order) do
      if each == path then table.remove(order, index) break end
    end
    client.forget(path, MM)
    publish()
  end

  local function clear()
    for _, handle in pairs(modem_handles) do pcall(handle.close) end
    modem_handles = {}
    local all = {}
    for path in pairs(watching) do all[#all + 1] = path end
    for _, path in ipairs(all) do unfollow(path) end
    bound = nil
    voice.present:set(false)
    voice.emergency_only:set(false)
  end

  --- The modem to follow, with its Voice properties; nil lets go of it.
  function voice.bind(path, properties)
    if path ~= bound then
      clear()
      if path then
        bound = path
        voice.present:set(true)
        modem_handles = {
          client.on_signal(MM, path, VOICE, "CallAdded", function(body) follow(dbus_client.first(body)) end),
          client.on_signal(MM, path, VOICE, "CallDeleted", function(body) unfollow(dbus_client.first(body)) end),
        }
        client.call1_async(MM, path, VOICE, "ListCalls", nil, QUICK, function(list)
          for _, each in ipairs(type(list) == "table" and list or {}) do follow(each) end
        end)
      end
    end
    if path then voice.emergency_only:set((properties or {}).EmergencyOnly == true) end
  end

  local function act(what, send, done)
    done = done or function() end
    if not bound then done(false, "no voice modem") return false end
    if dry() then
      morf.log("info", "eva: phone " .. what .. " (dry run)")
      done(false, "dry run")
      return false
    end
    local sent, why = send(function(reply, err) done(reply ~= nil, err) end)
    if not sent then done(false, why) return false end
    return true
  end
  local function on_call(method, path, arguments, timeout, done)
    return act(method, function(answer)
      return client.call_async(MM, path, CALL, method, arguments, timeout or QUICK, answer)
    end, done)
  end
  local function on_voice(method, arguments, done)
    return act(method, function(answer)
      return client.call_async(MM, bound, VOICE, method, arguments, QUICK, answer)
    end, done)
  end

  --- Starts a call to `number`.
  function voice.dial(number, done)
    done = done or function() end
    return act("dial", function(answer)
      return client.call1_async(MM, bound, VOICE, "CreateCall",
        { dbus_client.typed("a{sv}", { number = number }) }, QUICK, function(path, err)
          if type(path) ~= "string" then return answer(nil, err) end
          client.call_async(MM, path, CALL, "Start", nil, DIALLING, answer)
        end)
    end, done)
  end

  function voice.accept(path, done) return on_call("Accept", path, nil, DIALLING, done) end
  function voice.hangup(path, done) return on_call("Hangup", path, nil, nil, done) end
  --- Turns an incoming or waiting call away to `number`.
  function voice.deflect(path, number, done) return on_call("Deflect", path, { number }, nil, done) end
  --- The held call into the call that is active, as a conference.
  function voice.join(path, done) return on_call("JoinMultiparty", path, nil, nil, done) end
  --- This call out of the conference, the rest held.
  function voice.leave(path, done) return on_call("LeaveMultiparty", path, nil, nil, done) end

  --- Holds what is active and takes up a waiting or held call: hold, swap
  --- and resume are all this one request.
  function voice.hold(done) return on_voice("HoldAndAccept", nil, done) end
  function voice.hangup_and_accept(done) return on_voice("HangupAndAccept", nil, done) end
  function voice.hangup_all(done) return on_voice("HangupAll", nil, done) end
  --- Joins the active and the held call to each other and leaves them.
  function voice.transfer(done) return on_voice("Transfer", nil, done) end
  function voice.waiting(enable, done) return on_voice("CallWaitingSetup", { enable == true }, done) end

  --- Sends `tones` ("0-9", "A-D", "*", "#", and "," for a pause) in order.
  function voice.tones(path, tones, done)
    done = done or function() end
    local at = 0
    local function next_tone()
      at = at + 1
      local tone = tones:sub(at, at)
      if tone == "" then return done(true) end
      if tone == "," then return morf.time.timer(TONE_PAUSE, next_tone, false) end
      on_call("SendDtmf", path, { tone }, nil, function(ok, why)
        if not ok then return done(false, why) end
        morf.time.timer(TONE_GAP, next_tone, false)
      end)
    end
    next_tone()
  end

  --- Takes a finished call off ModemManager's list.
  function voice.forget(path, done)
    return act("forget", function(answer)
      return client.call_async(MM, bound, VOICE, "DeleteCall", { dbus_client.o(path) }, QUICK, answer)
    end, done)
  end

  return voice
end

return M
