-- The one way the shell buzzes. Callers name a moment, never a feedback event:
--
--   require("haptics").fire("commit")
--
-- Every press of a kit control reaches it through `attach`, so a view needs no
-- line of its own; the keyboard, tiles and gestures name their moments. The
-- one setting is `haptics.on`. Strength and silence are feedbackd's profile's.
-- EVA_FAKE_HAPTICS=1 reads as a machine that can buzz, for sealed sessions.
local morf = require("morf")
local config = require("config")

local M = {}

-- What each moment plays: feedbackd's default theme gives `button-pressed`
-- and `key-pressed` 7 ms and `button-released` a firmer 12 ms.
M.EVENTS = {
  tap = "button-pressed", toggle = "button-pressed", key = "key-pressed",
  long = "button-released", commit = "button-released", error = "phone-failure",
}
-- Two moments of a kind closer than this are one: a press and its toggle.
local GAP = 30

M.last = morf.signal("eva.haptics.last", "")
M.count = morf.signal("eva.haptics.count", 0)

local function flag(name)
  local v = morf.env and morf.env(name)
  return v ~= nil and v ~= "" and v ~= "0"
end

local own
local function feedback()
  local services = package.loaded.services
  if services and services.ringer then return services.ringer end
  if own == nil then
    local ok, ring = pcall(function()
      return require("lib.shell.audio.ringer").connect { mode = config.get("ringer.mode") }
    end)
    own = ok and ring or false
  end
  return own or nil
end

--- Whether anything here can buzz.
function M.present()
  if flag("EVA_FAKE_HAPTICS") then return true end
  local ring = feedback()
  return ring ~= nil and ring.state.feedbackd == true
end

function M.on() return config.get("haptics.on") ~= false end
function M.set(on) config.set("haptics.on", on == true) end

local settling = {}
--- Plays `kind`: tap, toggle, key, long, commit or error.
function M.fire(kind)
  local event = M.EVENTS[kind]
  if not event or not M.on() or settling[kind] then return false end
  settling[kind] = true
  morf.time.timer(GAP, function() settling[kind] = nil end, false)
  M.last:set(kind)
  M.count:set(M.count:get() + 1)
  if flag("EVA_DRY_RUN") or flag("EVA_FAKE_HAPTICS") then return true end
  local ring = feedback()
  return ring ~= nil and ring.trigger(event)
end

--- Plays every press of a kit control: `control` is lib.kit.control.
function M.attach(control)
  if M.attached then return end
  M.attached = true
  local make = control.make
  local KINDS = { on_clicked = "tap", on_toggled = "toggle", on_long_pressed = "long" }
  function control.make(archetype, widget, spec, extra)
    if type(spec) == "table" then
      for handler, kind in pairs(KINDS) do
        local run = spec[handler]
        if run then
          spec[handler] = function(...)
            M.fire(kind)
            return run(...)
          end
        end
      end
    end
    return make(archetype, widget, spec, extra)
  end
end

return M
