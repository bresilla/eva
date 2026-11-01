-- The mobile network: a phone's modem, through ModemManager, and mobile
-- data on or off through NetworkManager -- what postmarketOS, Mobian and
-- every other Linux phone run.
--
--   local modem = require("lib.services.modem")
--   local mobile = modem.connect()
--   mobile.state.available      -- a modem is there
--   mobile.state.signal         -- 0..100
--   mobile.state.technology     -- "5G", "LTE", "3G", "2G", ""
--   mobile.state.operator       -- "Vodafone NL"
--   mobile.state.registered, .connected, .enabled, .locked
--   mobile.state.data           -- mobile data on (NetworkManager's WwanEnabled)
--   mobile.state.unlock         -- "sim-pin", "sim-puk" or ""
--   mobile.state.tries_pin, .tries_puk   -- what is left, -1 where unknown
--   mobile.state.number         -- the SIM's own number, where it knows it
--   mobile.set_data(true)
--   mobile.voice                -- calls (lib/services/modem_voice.lua)
--   mobile.messaging            -- SMS (lib/services/modem_messaging.lua)
--   mobile.cell                 -- cell broadcast (lib/services/modem_cell.lua)
--   mobile.levels()             -- dBm and dB by radio, while `watch_levels` runs
--
-- A machine without ModemManager, or without a modem, reads as not
-- available and costs one look at the bus: a laptop is not asked twice.
--
-- `options.dbus` is the bus seam: lib/services/modem_standin.lua is ModemManager
-- on one. EVA_DRY_RUN stops every action before the real modem, not a stand-in.

local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local modem = {}

local MM = "org.freedesktop.ModemManager1"
local ROOT = "/org/freedesktop/ModemManager1"
local MODEM = "org.freedesktop.ModemManager1.Modem"
local GPP = "org.freedesktop.ModemManager1.Modem.Modem3gpp"
local VOICE = "org.freedesktop.ModemManager1.Modem.Voice"
local MESSAGING = "org.freedesktop.ModemManager1.Modem.Messaging"
local CELL = "org.freedesktop.ModemManager1.Modem.CellBroadcast"
local SIGNAL = "org.freedesktop.ModemManager1.Modem.Signal"
local SIM = "org.freedesktop.ModemManager1.Sim"
local OBJECT_MANAGER = "org.freedesktop.DBus.ObjectManager"
local NM = "org.freedesktop.NetworkManager"
local NM_PATH = "/org/freedesktop/NetworkManager"

-- MMModemAccessTechnology, best first: the generation a person reads.
local TECHNOLOGIES = {
  { 1 << 15, "5G" }, { 1 << 14, "LTE" }, { 1 << 16, "LTE" }, { 1 << 17, "LTE" },
  { 1 << 9, "H+" }, { 1 << 8, "H" }, { 1 << 7, "H" }, { 1 << 6, "H" }, { 1 << 5, "3G" },
  { 1 << 13, "3G" }, { 1 << 12, "3G" }, { 1 << 11, "3G" }, { 1 << 10, "2G" },
  { 1 << 4, "E" }, { 1 << 3, "G" }, { 1 << 1, "2G" }, { 1 << 2, "2G" },
}

--- The generation a technology mask stands for ("5G", "LTE", ... or "").
function modem.technology(mask)
  mask = tonumber(mask) or 0
  for _, t in ipairs(TECHNOLOGIES) do
    if mask & t[1] ~= 0 then return t[2] end
  end
  return ""
end

-- MMModemState.
local LOCKED, DISABLED, ENABLED, REGISTERED, CONNECTED = 2, 3, 6, 8, 11
-- MMModemLock.
local LOCK_PIN, LOCK_PUK = 2, 4
local UNLOCK = { [LOCK_PIN] = "sim-pin", [LOCK_PUK] = "sim-puk" }

local function first(value)
  if type(value) == "table" then return value[1] end
  return value
end

local function tries(retries, lock)
  return tonumber(type(retries) == "table" and retries[lock]) or -1
end

function modem.connect(options)
  options = options or {}
  local client = dbus_client.new({ dbus = options.dbus, bus = "system" })
  local state = morf.state {
    available = false, signal = 0, technology = "", operator = "",
    registered = false, connected = false, enabled = false, locked = false,
    data = false, path = "", sim_present = false, roaming = false,
    unlock = "", tries_pin = -1, tries_puk = -1, number = "",
  }
  local mobile = { state = state }
  local objects = {}
  local watching = {}
  local legacy_dictionary = false
  local function dry()
    if options.dbus then return false end
    local v = morf.env and morf.env("EVA_DRY_RUN")
    return v ~= nil and v ~= "" and v ~= "0"
  end
  mobile.voice = require("lib.services.modem_voice").attach(client, { dry = dry })
  mobile.messaging = require("lib.services.modem_messaging").attach(client, { dry = dry })
  mobile.cell = require("lib.services.modem_cell").attach(client, { dry = dry })

  local function publish()
    local chosen
    for path, interfaces in pairs(objects) do
      if interfaces[MODEM] and (not chosen or path < chosen) then chosen = path end
    end
    local held = chosen and objects[chosen] or {}
    mobile.voice.bind(held[VOICE] and chosen or nil, held[VOICE])
    mobile.messaging.bind(held[MESSAGING] and chosen or nil)
    mobile.cell.bind(held[CELL] and chosen or nil)
    if not chosen then
      state.available = false
      state.path = ""
      state.sim_present = false
      state.roaming = false
      state.unlock = ""
      state.number = ""
      return
    end
    local m = objects[chosen][MODEM] or {}
    local gpp = objects[chosen][GPP] or {}
    local s = tonumber(m.State) or 0
    state.available = true
    state.path = chosen
    state.signal = tonumber(first(m.SignalQuality)) or 0
    state.technology = modem.technology(m.AccessTechnologies)
    state.operator = tostring(gpp.OperatorName or "")
    state.locked = s == LOCKED
    state.enabled = s >= ENABLED
    state.registered = s >= REGISTERED
    state.connected = s == CONNECTED
    state.sim_present = type(m.Sim) == "string" and m.Sim ~= "/" and m.Sim ~= ""
    state.roaming = tonumber(gpp.RegistrationState) == 5
    state.unlock = UNLOCK[tonumber(m.UnlockRequired)] or ""
    state.tries_pin = tries(m.UnlockRetries, LOCK_PIN)
    state.tries_puk = tries(m.UnlockRetries, LOCK_PUK)
    state.number = tostring(first(m.OwnNumbers) or "")
  end

  local function watch(path)
    if watching[path] then return end
    watching[path] = client.on_properties(MM, path, function(interface, changed, invalidated)
      local held = objects[path] and objects[path][interface]
      if held then
        dbus_client.merge(held, changed, invalidated)
        publish()
      end
    end) or true
  end

  local function read_all()
    objects = {}
    if not client.has_owner(MM) then
      publish()
      return
    end
    local tree, err = client.call1(MM, ROOT, OBJECT_MANAGER, "GetManagedObjects")
    legacy_dictionary = tree == nil and tostring(err):find("dictionary keys must be strings", 1, true) ~= nil
    if legacy_dictionary then
      -- Cached engines before numeric D-Bus dictionary support cannot decode
      -- UnlockRetries (a{uu}), so the entire ObjectManager reply fails. Read
      -- only this service's properties until those engines are upgraded.
      tree = {}
      local folder = ROOT .. "/Modem"
      local xml = client.call1(MM, folder, "org.freedesktop.DBus.Introspectable", "Introspect")
      for id in (type(xml) == "string" and xml or ""):gmatch([[<node%s+name=["'](%d+)["']%s*/>]]) do
        local path = folder .. "/" .. id
        local m, gpp = {}, {}
        for _, property in ipairs {"State", "Sim", "SignalQuality", "AccessTechnologies"} do
          m[property] = client.get(MM, path, MODEM, property)
        end
        for _, property in ipairs {"OperatorName", "RegistrationState"} do
          gpp[property] = client.get(MM, path, GPP, property)
        end
        if m.State ~= nil then tree[path] = {[MODEM] = m, [GPP] = gpp} end
      end
    end
    for path, interfaces in pairs(type(tree) == "table" and tree or {}) do
      if type(interfaces) == "table" and interfaces[MODEM] then
        objects[path] = interfaces
        watch(path)
      end
    end
    publish()
  end

  local function read_data()
    if not client.has_owner(NM) then state.data = false return end
    local nm = client.get_all(NM, NM_PATH, NM) or {}
    state.data = nm.WwanEnabled == true
  end

  --- `method` on the SIM at `path`, over the system bus so a PIN is on no
  --- command line: SendPin, ChangePin or EnablePin. `done(ok, why)`.
  function mobile.sim_call(path, method, arguments, done)
    return client.call_async(MM, path, SIM, method, arguments, 30000, function(_, err) done(err == nil, err) end)
  end

  --- The SIM in use, as its object path, or nil.
  function mobile.sim_path()
    local held = objects[state.path]
    local sim = held and held[MODEM] and held[MODEM].Sim
    if type(sim) == "string" and sim ~= "/" and sim ~= "" then return sim end
  end

  --- The numbers the SIM says reach the emergency services, or an empty list.
  function mobile.emergency_numbers()
    local sim = mobile.sim_path()
    local numbers = sim and client.get(MM, sim, SIM, "EmergencyNumbers")
    return type(numbers) == "table" and numbers or {}
  end

  --- Whether the modem reports extended signal levels at all.
  function mobile.has_levels()
    local held = objects[state.path]
    return held ~= nil and held[SIGNAL] ~= nil
  end

  --- Asks the modem for extended levels every `seconds`; 0 stops it.
  function mobile.watch_levels(seconds, done)
    done = done or function() end
    if not mobile.has_levels() then done(false, "no signal interface") return false end
    if dry() then done(false, "dry run") return false end
    return client.call_async(MM, state.path, SIGNAL, "Setup", { dbus_client.u(seconds) }, 10000,
      function(reply, err) done(reply ~= nil, err) end) == true
  end

  --- The strongest radio's levels: `{ radio, rssi, rsrp, rsrq, snr, rscp,
  --- ecio }` in dBm and dB, with only what it measures; nil without any.
  function mobile.levels()
    local held = objects[state.path]
    local levels = held and held[SIGNAL]
    if not levels then return nil end
    for _, entry in ipairs { { "Nr5g", "5G" }, { "Lte", "LTE" }, { "Umts", "3G" }, { "Gsm", "2G" } } do
      local radio = levels[entry[1]]
      if type(radio) == "table" and next(radio) ~= nil then
        return { radio = entry[2], rssi = radio.rssi, rsrp = radio.rsrp, rsrq = radio.rsrq,
          snr = radio.snr, rscp = radio.rscp, ecio = radio.ecio }
      end
    end
  end

  --- Mobile data on or off: NetworkManager's WWAN switch.
  function mobile.set_data(on)
    local ok, err = client.set(NM, NM_PATH, NM, "WwanEnabled", on == true)
    read_data()
    return ok, err
  end

  client.watch_name(MM, read_all)
  client.watch_name(NM, read_data)
  client.on_signal(MM, ROOT, OBJECT_MANAGER, "InterfacesAdded", function() read_all() end)
  client.on_signal(MM, ROOT, OBJECT_MANAGER, "InterfacesRemoved", function() read_all() end)
  client.on_properties(NM, NM_PATH, function(_, changed)
    if changed.WwanEnabled ~= nil then state.data = changed.WwanEnabled == true end
  end)
  read_all()
  read_data()
  -- InterfacesAdded also contains UnlockRetries on older engines. Keep
  -- discovery live there when that signal cannot be decoded. New engines
  -- use the ObjectManager signals and do no periodic bus reads.
  morf.time.timer(10000, function() if legacy_dictionary then read_all() end end, true)
  return mobile
end

return modem
