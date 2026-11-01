-- The phone in the shell: the owner of calls (models/phone_calls.lua), the
-- surface they appear on, what a call does to the machine, and the verbs.
--
-- The surface is a layer of its own in the compositor's overlay layer, above
-- fullscreen windows. A locked session shows only the lock's surfaces: the lock
-- hosts the same screen (themes/phone_lock.lua) and the shell keeps ringing.
--
-- `phone answer|decline|hangup|mute|speaker|hold|silence|state`, `phone dial N`.
-- With EVA_FAKE_MODEM: `phone ring N`, `phone text N WORDS`, `phone alert CHANNEL
-- WORDS`, `phone lock sim-pin`, `phone near on`.
local morf = require("morf")
local config = require("config")
local services = require("services")
local M = { near = morf.signal("eva.phone.near", false), rung = morf.signal("eva.phone.rung", ""),
  ready = morf.signal("eva.phone.ready", false) }

local function flag(name)
  local v = morf.env and morf.env(name)
  return v ~= nil and v ~= "" and v ~= "0"
end
local function dry() return flag("EVA_DRY_RUN") end

--- The address book: EVA_CONTACTS, or `phone.contacts`.
function M.book()
  if not M.contacts then
    M.contacts = require("lib.services.contacts").open {
      folder = morf.env("EVA_CONTACTS") or config.get("phone.contacts"), country = config.get("phone.country"),
    }
  end
  return M.contacts
end

--- The call history.
function M.history()
  if not M.log then M.log = require("lib.services.journal").open { name = "calls" } end
  return M.log
end

-- Without feedbackd, or standing in, ringing is only recorded here.
local function ringer()
  local ring = services.ringer
  if ring and ring.state.feedbackd and not services.modem_standin then return ring end
  return {
    trigger = function(event, _, done) M.rung:set(event) if done then done(1) end return true end,
    stop = function() M.rung:set("") end,
  }
end

local function screen(action)
  local ok, raw = pcall(morf.fs.read, morf.env("EVA_PHONE_SCREEN_CONFIG") or "/etc/eva/phone-screen.json")
  local fine, value = pcall(morf.json.decode, ok and raw or "")
  local command = fine and type(value) == "table" and value.command
  if dry() then morf.log("info", "eva: phone screen " .. action .. " (dry run)") return true end
  if type(command) == "string" then morf.process.run({ command, action }, {}, function() end) return true end
  return false
end

local function start()
  local mobile = services.modem
  M.audio = require("lib.services.callaudio").connect {
    dbus = services.modem_standin and services.modem_standin.dbus or nil,
  }
  M.model = require("models.phone_calls").new {
    mobile = mobile, book = M.book(), owner = true, ring = ringer(), audio = M.audio, log = M.history(),
    notify = function(entry) require("notifs").push(entry) end,
    quiet = function(row)
      local person = M.book().person(row.number)
      if not person and config.get("phone.silence_unknown") == true then return true end
      if not require("notifs").dnd:get() then return false end
      return not (person and person.favourite)
    end,
  }
  M.sim = require("models.phone_sim").new { mobile = mobile }
  M.messages = require("models.phone_messages").new {
    mobile = mobile, book = M.book(), owner = true, ring = ringer(),
    log = require("lib.services.journal").open { name = "messages" },
    report = config.get("phone.delivery_reports") == true,
    notify = function(entry) require("notifs").push(entry) end,
  }
  M.alerts = require("models.phone_alerts").new {
    mobile = mobile, ring = ringer(), log = require("lib.services.journal").open { name = "alerts" },
    wake = function() screen("wake") end,
    enabled = function(id) return (config.get("phone.alerts") or {})[id] ~= false end,
  }
  require("data_usage").start {
    limit = function() return config.get("phone.data_limit") end,
    notify = function(entry) require("notifs").push(entry) end,
  }
  require("call_surface").start(M)
  require("call_posture").start(M, { screen = screen, dry = dry, flag = flag })
  M.ready:set(true)
end

-- Calls are owned by the primary output's runtime alone.
local function primary() return not morf.window.primary or morf.window.primary() end
local is_primary = morf.signal("eva.phone.primary", primary())
if morf.window.on_primary then morf.window.on_primary(function(now) is_primary:set(now == true) end) end

morf.effect("eva.phone.start", function()
  local mobile = services.modem
  if M.model or not is_primary:get() then return end
  if not (mobile and mobile.voice and mobile.voice.present:get()) then return end
  start()
end)

-- What the lock reads, it having no way to the settings.
morf.effect("eva.phone.lock-settings", function()
  local saved = { contacts = config.get("phone.contacts"), country = config.get("phone.country"),
    medical = config.get("phone.medical") }
  local state = morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")
  pcall(morf.fs.write, state .. "/eva/phone/lock.json", morf.json.encode(saved),
    { atomic = true, parents = true, mode = 384 })
end)

local function need()
  if not M.model then error("no voice modem") end
  return M.model
end

local VERBS = {
  answer = function(p) return p.answer() end,
  decline = function(p) return p.decline() end,
  hangup = function(p) return p.hangup() end,
  hold = function(p) return p.hold() end,
  silence = function(p) p.silence() return true end,
  mute = function(p) return p.set_muted(not p.muted()) end,
  speaker = function(p) return p.set_speaker(not p.on_speaker()) end,
  keypad = function(p) p.keypad:set(not p.keypad:get()) return p.keypad:get() end,
  minimise = function(p) p.minimised:set(not p.minimised:get()) return p.minimised:get() end,
  dial = function(p, number) return p.dial(number) end,
  reply = function(_, number, text) return M.reply(number, text) end,
  ok = function() M.alerts.dismiss() return true end,
  block = function(_, number, how) M.book().block(number, how ~= "off") return true end,
  state = function(p)
    return { stage = p.stage:get(), calls = p.rows:get(), seconds = p.seconds:get(), near = M.near:get(),
      rung = M.rung:get(), muted = p.muted(), speaker = p.on_speaker(), unread = M.messages.unread(),
      threads = M.messages.threads(), alert = M.alerts.showing:get().text or "", sim = M.sim.asking(),
      on_modem = #services.modem.messaging.list:get(), held = require("call_posture").held:get() }
  end,
}

--- Answers the thread with `number` from wherever: a notification's inline
--- reply takes this and the `reply` field of what `notify` pushed.
function M.reply(number, text)
  if not M.messages then return false end
  M.messages.read(number)
  return M.messages.send(number, text)
end

local FAKES = {
  ring = function(s, number) return s.ring(number) end,
  text = function(s, number, words) return s.text(number, words) end,
  alert = function(s, channel, words) return s.alert(tonumber(channel), words) end,
  lock = function(s, what) s.lock(what or "") return true end,
  report = function(s, path, delivery) s.report(path, tonumber(delivery)) return true end,
  hangup = function(s) s.hang_up() return true end,
  near = function(_, how) M.near:set(how == "on") return true end,
}

--- `phone VERB ARGS`, over IPC.
function M.ipc(verb, ...)
  if not is_primary:get() then return nil end
  if verb == "key" then return require("hardware_keys").press(M, (...)) end
  if verb == "sos-cancel" then require("hardware_keys").cancel() return true end
  if verb == "fake" then
    local what = ...
    local act = FAKES[what]
    local standin = services.modem_standin
    if not act or not standin then error("no stand-in: `" .. tostring(what) .. "`") end
    return act(standin, select(2, ...))
  end
  local act = VERBS[verb or "state"]
  if not act then error("`" .. tostring(verb) .. "`: no such phone verb") end
  return act(need(), ...)
end

return M
