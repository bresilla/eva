-- The Settings pages behind Touch gestures: the model; the view is the selected
-- theme's. Which form is being edited, what each gesture does there, a way to
-- try one with the fingers on show, and what the reader is doing, plainly.
local morf = require("morf")
local config = require("config")
local bindings = require("touch_bindings")
local actions = require("touch_actions")
local driver = require("touch_driver")
local M = {}

-- What the reader says, for a person: a title and what to do about it.
local WORDS = {
  running = { "Reading the touchscreen", "Gestures work everywhere on this screen" },
  starting = { "Starting", "Opening the touchscreen" },
  none = { "No touchscreen", "Gestures begin when one is plugged in" },
  missing = { "libinput is not installed", "Install libinput, or libinput-tools on Debian and Ubuntu" },
  denied = { "This session may not read the touchscreen",
    "It needs a udev rule, which on NixOS is programs.eva.touch.enable; the README has the rule" },
}

--- Why it is not reading, once the reader says "off".
local function stopped()
  if config.get("gestures.enabled") == false then return "Off", "Apps keep every touch, and the edges still pull panels" end
  if morf.env("EVA_GESTURE_DRIVER") == "lisgd" then return "Off", "The phone's lisgd driver has the gestures" end
  if driver.locked() then return "Stopped", "It stays stopped while the session is locked" end
  if driver.away() then return "Stopped", "Another session has the screen" end
  local gesture = require("phone_gestures")
  if gesture.blocked() or not gesture.global_allowed() then
    return "Stopped", "It stays stopped while a password or the capture editor is on screen"
  end
  if #(morf.screens or {}) > 1 and not driver.panel() then
    return "Which screen is it on?", "Choose the screen the touchscreen sits on"
  end
  return "Off", "Another screen has the touchscreen"
end

--- What the page says the reader is doing: a title, then a line about it.
function M.status()
  local state = driver.state:get()
  local words = WORDS[state]
  if words then return words[1], words[2] end
  return stopped()
end

local COUNTS = { "One finger", "Two fingers", "Three fingers", "Four fingers", "Five fingers" }

local chosen = morf.signal("eva.touch.settings.gesture", "two_up_bottom")
local editing = morf.signal("eva.touch.settings.form", "")

-- Leaving the page ends a try: gestures go back to doing what they do.
local function watch_leaving(active)
  if M.watched then return end
  M.watched = true
  morf.effect("eva.touch.settings.left", function()
    if active() or not driver.trying:get() then return end
    driver.trying:set(false)
    driver.watching:set(false)
    driver.fingers:set({})
  end)
end

function M.model()
  local presentation = require("presentation")
  local model = { active = presentation.active("settings.touch"), GROUPS = bindings.GROUPS, FORMS = bindings.FORMS,
    ACTIONS = actions.ACTIONS, status = M.status, BY_ACTION = actions.BY_KEY }
  watch_leaving(model.active)
  local function form()
    local picked = editing:get()
    return picked ~= "" and picked or require("responsive").form()
  end
  model.form = form
  function model.pick_form(name) if model.active() then editing:set(name) end end
  function model.on() return config.get("gestures.enabled") ~= false end
  function model.set_on(on) if model.active() then config.set("gestures.enabled", on == true) end end
  function model.gestures(group)
    local out = {}
    for _, gesture in ipairs(bindings.GESTURES) do
      if gesture.group == group then out[#out + 1] = gesture end
    end
    return out
  end
  function model.does(key) return actions.name(bindings.action(key, form())) end
  function model.open(key)
    if not model.active() then return end
    chosen:set(key)
    require("utilities").request("touch/gesture")
  end
  function model.reset() if model.active() then bindings.reset(form()) end end

  -- Trying: the fingers shown, and each gesture named instead of run.
  function model.trying() return driver.trying:get() end
  function model.set_trying(on)
    if not model.active() then return end
    driver.trying:set(on == true)
    driver.watching:set(on == true)
    if on ~= true then driver.fingers:set({}) end
  end
  function model.can_try() return driver.owns() end
  function model.finger(index) return driver.fingers:get()[index] end
  function model.screen() return require("responsive").size() end
  --- What the last gesture was.
  function model.heard()
    local heard = driver.heard:get()
    if not model.trying() then return "See your fingers" end
    if not heard.key then return "Put fingers on the screen" end
    if bindings.BY_KEY[heard.key] then return heard.name end
    return COUNTS[heard.fingers] or "Fingers"
  end
  --- What it would do.
  function model.would()
    local heard = driver.heard:get()
    if not model.trying() then return "Named here, and nothing runs" end
    if not heard.key then return "Then swipe, pinch or tap" end
    if not bindings.BY_KEY[heard.key] then return "Apps and the edges keep this one" end
    return actions.name(heard.action)
  end
  --- The screens to choose from, past one.
  function model.outputs()
    local out = {}
    for _, screen in ipairs(morf.screens or {}) do out[#out + 1] = screen.name end
    return out
  end
  function model.output() return config.get("gestures.output") end
  function model.set_output(name) if model.active() then config.set("gestures.output", name) end end
  return model
end

--- The model of a gesture's page.
function M.gesture_model()
  local presentation = require("presentation")
  local parent = M.model()
  local model = { active = presentation.active("settings.touch/gesture"), ACTIONS = actions.ACTIONS }
  local function key() return chosen:get() end
  model.key = key
  function model.name() return (bindings.BY_KEY[key()] or {}).name or "" end
  function model.action() return bindings.action(key(), parent.form()) end
  function model.pick(action) if model.active() then bindings.set(key(), parent.form(), action) end end
  function model.command() return table.concat(bindings.command(key()), " ") end
  function model.set_command(text)
    if not model.active() then return end
    local words = {}
    for word in tostring(text or ""):gmatch("%S+") do words[#words + 1] = word end
    bindings.set_command(key(), words)
  end
  function model.is_command() return model.action() == "command" end
  function model.is_default() return bindings.is_default(key(), parent.form()) end
  function model.reset()
    if model.active() then bindings.set(key(), parent.form(), bindings.defaults(parent.form())[key()]) end
  end
  return model
end

local function view() return require("themes").view("touch_page") end
function M.page(w, h) return view().build(M.model(), w, h) end
function M.gesture_page(w, h) return view().gesture(M.gesture_model(), w, h) end

return M
