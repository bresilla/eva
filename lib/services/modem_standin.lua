-- ModemManager on a bus of Lua tables: what EVA_FAKE_MODEM runs and what the
-- specs drive. `lib.services.modem` connects to it through its `dbus` seam, so
-- everything above the wire runs as it would on a phone; only the far end is
-- made up.
--
--   local standin = require("lib.services.modem_standin")
--   local mobile = require("lib.services.modem").connect { dbus = standin.dbus }
--   standin.ring("+31612345678")     -- a call comes in
--   standin.text("+316...", "hello") -- a message comes in
--   standin.alert(4370, "Flood warning")
--   standin.lock("sim-pin")
--
-- Every member here is one ModemManager's XML declares
-- (tests/fixtures/phone-bus.txt), checked by tests/phone_bus_spec.lua. It speaks
-- only for the shape of the bus: timing, errors and audio are not a modem's.
local morf = require("morf")
local fake = require("lib.testing.dbus")

local M = { dbus = fake.dbus, fake = fake }

local MM = "org.freedesktop.ModemManager1"
local ROOT = "/org/freedesktop/ModemManager1"
local MODEM = MM .. ".Modem"
local GPP = MODEM .. ".Modem3gpp"
local VOICE = MODEM .. ".Voice"
local MESSAGING = MODEM .. ".Messaging"
local CELL = MODEM .. ".CellBroadcast"
local SIGNAL = MODEM .. ".Signal"
local CALL = MM .. ".Call"
local SMS = MM .. ".Sms"
local CBM = MM .. ".Cbm"
local SIM = MM .. ".Sim"
local OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
local PROPERTIES = "org.freedesktop.DBus.Properties"
local NM = "org.freedesktop.NetworkManager"
local NM_PATH = "/org/freedesktop/NetworkManager"
local AUDIO = "org.mobian_project.CallAudio"
local AUDIO_PATH = "/org/mobian_project/CallAudio"
local PATH = ROOT .. "/Modem/0"
local SIM_PATH = ROOT .. "/SIM/0"
local LOCKED, CONNECTED = 2, 11
local LOCK_NONE, LOCK_PIN, LOCK_PUK = 1, 2, 4
local PIN = "1234"

local ids = { call = 0, sms = 0, cbm = 0 }
local calls = {}

local function changed(path, interface, values)
  local held = fake.props("system", MM, path, interface)
  for key, value in pairs(values) do held[key] = value end
  fake.emit("system", MM, path, PROPERTIES, "PropertiesChanged", { interface, values, {} })
end

local function set_call(path, state, reason)
  local held = fake.props("system", MM, path, CALL)
  local old = held.State
  changed(path, CALL, { State = state, StateReason = reason })
  fake.emit("system", MM, path, CALL, "StateChanged", { old, state, reason })
end

local function others(path)
  local out = {}
  for _, each in ipairs(calls) do
    if each ~= path then out[#out + 1] = each end
  end
  return out
end

-- One call's object. MMCallState: 1 dialing, 3 ringing-in, 4 active, 5 held,
-- 6 waiting, 7 terminated. MMCallStateReason: 3 accepted, 4 terminated.
local function add_call(number, direction, state, reason)
  ids.call = ids.call + 1
  local path = ROOT .. "/Call/" .. ids.call
  fake.object("system", MM, path, CALL,
    { State = state, StateReason = reason, Direction = direction, Number = number, Multiparty = false,
      AudioPort = "", DtmfToneDuration = 0 },
    {
      Start = function()
        morf.time.timer(40, function() set_call(path, 2, 1) end, false)
        morf.time.timer(90, function() set_call(path, 4, 3) end, false)
      end,
      Accept = function() set_call(path, 4, 3) end,
      Hangup = function() set_call(path, 7, 4) end,
      Deflect = function() set_call(path, 7, 9) end,
      JoinMultiparty = function()
        for _, each in ipairs(calls) do
          local p = fake.props("system", MM, each, CALL)
          if p.State == 4 or p.State == 5 then
            changed(each, CALL, { Multiparty = true })
            if p.State == 5 then set_call(each, 4, 3) end
          end
        end
      end,
      LeaveMultiparty = function() changed(path, CALL, { Multiparty = false }) end,
      SendDtmf = function() end,
    })
  calls[#calls + 1] = path
  changed(PATH, VOICE, { Calls = calls })
  fake.emit("system", MM, PATH, VOICE, "CallAdded", { path })
  return path
end

local function add_sms(number, text, state, pdu)
  ids.sms = ids.sms + 1
  local path = ROOT .. "/SMS/" .. ids.sms
  fake.object("system", MM, path, SMS,
    { State = state, PduType = pdu, Number = number, Text = text,
      Timestamp = morf.time.format("%Y-%m-%dT%H:%M:%S%:z"),
      DeliveryState = 0x100, MessageReference = ids.sms, Storage = 2 },
    {
      Send = function()
        changed(path, SMS, { State = 4 })
        changed(path, SMS, { State = 5 })
      end,
      Store = function() end,
    })
  return path
end

local function next_call()
  for _, want in ipairs { 6, 5 } do
    for _, path in ipairs(calls) do
      if fake.props("system", MM, path, CALL).State == want then return path end
    end
  end
end

local function fill()
  fake.object("session", AUDIO, AUDIO_PATH, AUDIO, { AudioMode = 0, SpeakerState = 0, MicState = 1 }, {
    SelectMode = function(args)
      fake.emit("session", AUDIO, AUDIO_PATH, PROPERTIES, "PropertiesChanged",
        { AUDIO, { AudioMode = fake.plain(args[1]) }, {} })
      return { true }
    end,
    EnableSpeaker = function(args)
      fake.emit("session", AUDIO, AUDIO_PATH, PROPERTIES, "PropertiesChanged",
        { AUDIO, { SpeakerState = fake.plain(args[1]) and 1 or 0 }, {} })
      return { true }
    end,
    MuteMic = function(args)
      fake.emit("session", AUDIO, AUDIO_PATH, PROPERTIES, "PropertiesChanged",
        { AUDIO, { MicState = fake.plain(args[1]) and 0 or 1 }, {} })
      return { true }
    end,
  })
  fake.object("system", NM, NM_PATH, NM, { WwanEnabled = true }, {})
  fake.object("system", MM, ROOT, OBJECT_MANAGER, {}, {})
  fake.object("system", MM, PATH, MODEM, {
    State = CONNECTED, Sim = SIM_PATH, SignalQuality = { 72, true }, AccessTechnologies = 1 << 15,
    UnlockRequired = LOCK_NONE, UnlockRetries = { [LOCK_PIN] = 3, [LOCK_PUK] = 10 }, OwnNumbers = { "+31600000001" },
  }, {})
  fake.object("system", MM, PATH, GPP, { OperatorName = "Vodafone NL", OperatorCode = "20404", RegistrationState = 1 }, {})
  fake.object("system", MM, PATH, VOICE, { Calls = {}, EmergencyOnly = false }, {
    ListCalls = function() return { calls } end,
    CreateCall = function(args)
      local number = fake.plain(args[1]).number
      return { add_call(number, 2, 0, 0) }
    end,
    DeleteCall = function(args)
      local path = fake.plain(args[1])
      calls = others(path)
      fake.remove("system", MM, path)
      changed(PATH, VOICE, { Calls = calls })
      fake.emit("system", MM, PATH, VOICE, "CallDeleted", { path })
    end,
    HoldAndAccept = function()
      local resume = next_call()
      for _, path in ipairs(calls) do
        if fake.props("system", MM, path, CALL).State == 4 then set_call(path, 5, 3) end
      end
      if resume then set_call(resume, 4, 3) end
    end,
    HangupAndAccept = function()
      local resume = next_call()
      for _, path in ipairs(calls) do
        if fake.props("system", MM, path, CALL).State == 4 then set_call(path, 7, 4) end
      end
      if resume then set_call(resume, 4, 3) end
    end,
    HangupAll = function()
      for _, path in ipairs(calls) do
        if fake.props("system", MM, path, CALL).State ~= 7 then set_call(path, 7, 4) end
      end
    end,
    Transfer = function()
      for _, path in ipairs(calls) do set_call(path, 7, 8) end
    end,
    CallWaitingSetup = function() end,
    CallWaitingQuery = function() return { true } end,
  })
  fake.object("system", MM, PATH, MESSAGING, { Messages = {}, SupportedStorages = { 1, 2 }, DefaultStorage = 2 }, {
    List = function() return { fake.props("system", MM, PATH, MESSAGING).Messages } end,
    Create = function(args)
      local p = fake.plain(args[1])
      local path = add_sms(p.number, p.text, 1, 2)
      local held = fake.props("system", MM, PATH, MESSAGING)
      held.Messages[#held.Messages + 1] = path
      fake.emit("system", MM, PATH, MESSAGING, "Added", { path, false })
      return { path }
    end,
    Delete = function(args)
      local path = fake.plain(args[1])
      local held = fake.props("system", MM, PATH, MESSAGING)
      for index, each in ipairs(held.Messages) do
        if each == path then table.remove(held.Messages, index) break end
      end
      fake.remove("system", MM, path)
      fake.emit("system", MM, PATH, MESSAGING, "Deleted", { path })
    end,
    SetDefaultStorage = function() end,
  })
  fake.object("system", MM, PATH, CELL, { CellBroadcasts = {}, Channels = {} }, {
    List = function() return { fake.props("system", MM, PATH, CELL).CellBroadcasts } end,
    Delete = function(args) fake.remove("system", MM, fake.plain(args[1])) end,
    SetChannels = function(args) fake.props("system", MM, PATH, CELL).Channels = fake.plain(args[1]) end,
  })
  fake.object("system", MM, PATH, SIGNAL, { Rate = 0, Nr5g = { rsrp = -92.0, rsrq = -11.0, snr = 18.5 },
    Lte = { rssi = -67.0, rsrp = -96.0, rsrq = -12.0, snr = 14.0 }, Umts = {}, Gsm = {} }, {
    Setup = function(args) fake.props("system", MM, PATH, SIGNAL).Rate = fake.plain(args[1]) end,
    SetupThresholds = function() end,
  })
  local function unlocked()
    changed(PATH, MODEM, { State = CONNECTED, UnlockRequired = LOCK_NONE,
      UnlockRetries = { [LOCK_PIN] = 3, [LOCK_PUK] = 10 } })
  end
  local function missed(lock)
    local retries = fake.props("system", MM, PATH, MODEM).UnlockRetries
    retries[lock] = math.max(0, (retries[lock] or 1) - 1)
    local blocked = lock == LOCK_PIN and retries[lock] == 0
    changed(PATH, MODEM, { UnlockRetries = retries, UnlockRequired = blocked and LOCK_PUK or lock })
    error("org.freedesktop.ModemManager1.Error.MobileEquipment.IncorrectPassword: Incorrect password", 0)
  end
  fake.object("system", MM, SIM_PATH, SIM, { Active = true, SimIdentifier = "8931000000000000001",
    OperatorName = "Vodafone NL", OperatorIdentifier = "20404", EmergencyNumbers = { "112", "911" } }, {
    SendPin = function(args) if fake.plain(args[1]) ~= PIN then missed(LOCK_PIN) end unlocked() end,
    SendPuk = function(args) if #tostring(fake.plain(args[1])) ~= 8 then missed(LOCK_PUK) end unlocked() end,
    EnablePin = function(args) if fake.plain(args[1]) ~= PIN then missed(LOCK_PIN) end end,
    ChangePin = function(args) if fake.plain(args[1]) ~= PIN then missed(LOCK_PIN) end end,
  })
end

--- Puts the modem on the bus: `options.plain` leaves out what a data-only
--- modem has no use for.
function M.start(options)
  options = options or {}
  fill()
  if options.plain then
    local objects = fake.objects.system[MM][PATH]
    objects[VOICE], objects[MESSAGING], objects[CELL], objects[SIGNAL] = nil, nil, nil, nil
  end
  return M
end

--- A call comes in from `number`: waiting, when one is already up.
function M.ring(number)
  for _, path in ipairs(calls) do
    local state = fake.props("system", MM, path, CALL).State
    if state == 4 or state == 5 then return add_call(number, 1, 6, 2) end
  end
  return add_call(number, 1, 3, 2)
end

--- The other side hangs up the call at `path`, or every call.
function M.hang_up(path)
  for _, each in ipairs(path and { path } or calls) do
    if fake.props("system", MM, each, CALL).State ~= 7 then set_call(each, 7, 4) end
  end
end

--- A message arrives; `parts` above 1 reads as receiving until `finish`.
function M.text(number, text, parts)
  local path = add_sms(number, text, (parts or 1) > 1 and 2 or 3, 1)
  local held = fake.props("system", MM, PATH, MESSAGING)
  held.Messages[#held.Messages + 1] = path
  fake.emit("system", MM, PATH, MESSAGING, "Added", { path, true })
  return path
end

--- The last part of a long message arrives.
function M.finish(path, text) changed(path, SMS, { State = 3, Text = text }) end

--- The network reports on a sent message: 0 delivered, 0x40.. failed.
function M.report(path, delivery) changed(path, SMS, { DeliveryState = delivery }) end

--- An alert arrives on `channel`.
function M.alert(channel, text, code)
  ids.cbm = ids.cbm + 1
  local path = ROOT .. "/Cbm/" .. ids.cbm
  fake.object("system", MM, path, CBM, { State = 2, Text = text, Channel = channel,
    MessageCode = code or ids.cbm, Update = 0, Language = "en" }, {})
  fake.emit("system", MM, PATH, CELL, "Added", { path })
  return path
end

--- The SIM asks: "sim-pin", "sim-puk" or "" for neither.
function M.lock(what)
  local lock = ({ ["sim-pin"] = LOCK_PIN, ["sim-puk"] = LOCK_PUK })[what]
  changed(PATH, MODEM, { State = lock and LOCKED or CONNECTED, UnlockRequired = lock or LOCK_NONE })
end

--- Every call made so far that the contract in `names` does not know:
--- `names[interface.." "..member]` must be true.
function M.unknown_calls(names)
  local out = {}
  for _, call in ipairs(fake.calls) do
    local standard = call.iface:match("^org%.freedesktop%.DBus") ~= nil
    if not standard and not names[call.iface .. " " .. call.method] then
      out[#out + 1] = call.iface .. " " .. call.method
    end
  end
  return out
end

return M
