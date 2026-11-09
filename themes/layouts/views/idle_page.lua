-- The right panel's Idle and sleep page, behind Eva's row: keeping awake, the
-- stages, what holds them back, and what happens around sleep. In the page
-- template (themes/layouts/page.lua).
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.option_rows")

local V = {}
local APPS, HOLDERS = 8, 5

local function spans(model, list)
  local out = {}
  for _, seconds in ipairs(list) do out[#out + 1] = { seconds, seconds == 0 and "Off" or model.span(seconds) } end
  return out
end

function V.build(model, w, h)
  local inner = P.inner(w)
  local function free(stage) return function() return not model.managed(stage) end end

  -- Keeping awake: off, for a while, or on.
  local awake = { { false, "Off" } }
  for _, choice in ipairs(model.AWAKE_CHOICES) do awake[#awake + 1] = { choice.seconds, choice.label } end
  awake[#awake + 1] = { true, "On" }
  local keep = P.section { id = "idle-keep", width = w,
    F.choices { id = "idle-awake", width = inner, icon = "coffee", title = "Keep awake", choices = awake,
      subtitle = model.awake_note,
      read = function()
        if not model.awake() then return false end
        local ends = model.awake_until()
        if ends == 0 then return true end
        return nil
      end,
      set = model.set_awake },
  }

  -- The stages, in the order they come.
  local stages = { id = "idle-stages", width = w, title = "When idle" }
  stages[#stages + 1] = F.choices { id = "idle-dim", width = inner, icon = "brightness_6", title = "Warn before locking",
    subtitle = "The screen closes in, and moving stops it", choices = spans(model, model.DIM_CHOICES),
    read = model.dim, set = model.set_dim }
  for _, stage in ipairs(model.STAGES) do
    stages[#stages + 1] = F.choices { id = "idle-stage-" .. stage.id, width = inner, icon = stage.icon, title = stage.name,
      subtitle = function()
        local seconds = model.seconds(stage.id)
        local said = seconds > 0 and ("After " .. model.span(seconds)) or "Never"
        return model.managed(stage.id) and (said .. ", set by the system") or said
      end,
      choices = spans(model, stage.choices), enabled = free(stage.id),
      read = function() return model.chosen(stage.id) end,
      set = function(seconds) model.set_stage(stage.id, seconds) end }
  end

  local battery = { id = "idle-battery", width = w, title = "On battery", visible = model.has_battery }
  for _, stage in ipairs(model.STAGES) do
    local choices = spans(model, stage.choices)
    choices[1] = { 0, "Same" }
    battery[#battery + 1] = F.choices { id = "idle-battery-" .. stage.id, width = inner, icon = stage.icon, title = stage.name,
      choices = choices, enabled = free(stage.id),
      read = function() return model.battery_stage(stage.id) end,
      set = function(seconds) model.set_battery_stage(stage.id, seconds) end }
  end

  -- What keeps it awake: situations, then windows by name.
  local reasons = { id = "idle-reasons", width = w, title = "Stay awake for" }
  for _, flag in ipairs {
    { "fullscreen", "fullscreen", "Fullscreen windows" }, { "media", "play_circle", "Playing media" },
    { "charging", "power", "While plugged in" } } do
    reasons[#reasons + 1] = F.switch { id = "idle-flag-" .. flag[1], width = inner, icon = flag[2], title = flag[3],
      on = function() return model.flag(flag[1]) end, set = function(on) model.set_flag(flag[1], on) end }
  end
  for index = 1, APPS do
    local function class() return model.apps()[index] end
    reasons[#reasons + 1] = F.switch { id = "idle-app-" .. index, width = inner, icon = "apps",
      title = function() return class() or "" end, visible = function() return class() ~= nil end,
      on = function() local c = class() return c ~= nil and model.app_on(c) end,
      set = function(on) local c = class() if c then model.set_app(c, on) end end }
  end

  local holders = { id = "idle-holding", width = w, title = "Holding it awake now",
    visible = function() return #model.holding() > 0 end }
  for index = 1, HOLDERS do
    holders[#holders + 1] = kit.subtitle { id = "idle-holder-" .. index, width = inner, elide = "right",
      font_size = theme.size.small, color = kit.ink("lo"),
      visible = function() return model.holding()[index] ~= nil end,
      text = function() return model.holding()[index] or "" end }
  end

  local function lock_flag(id, icon, title, subtitle)
    return F.switch { id = "idle-lock-" .. id, width = inner, icon = icon, title = title, subtitle = subtitle,
      on = function() return model.lock_flag(id) end, set = function(on) model.set_lock_flag(id, on) end,
      enabled = function() return not model.lock_managed(id) end }
  end
  local sleep = P.section { id = "idle-sleep", width = w, title = "Sleep",
    lock_flag("on_suspend", "bedtime", "Lock on suspend", "Locked before the machine sleeps"),
    lock_flag("on_lid", "laptop", "Lock when the lid closes"),
    lock_flag("at_startup", "login", "Lock at the session's start", "For a machine that logs in by itself"),
    kit.subtitle { width = inner, font_size = theme.size.small, color = kit.ink("lo"), text = "Commands, words split by spaces" },
    F.text { id = "idle-command-before", width = inner, title = "Run before sleep", value = function() return model.command("before_sleep") end,
      set = function(text) model.set_command("before_sleep", text) end },
    F.text { id = "idle-command-after", width = inner, title = "Run after waking", value = function() return model.command("after_sleep") end,
      set = function(text) model.set_command("after_sleep", text) end },
    F.text { id = "idle-command-resume", width = inner, title = "Run when input returns", value = function() return model.command("resume_command") end,
      set = function(text) model.set_command("resume_command", text) end },
  }

  return P.page { id = "settings-idle-scroll", width = w, height = h,
    keep, P.section(stages), P.section(battery), P.section(reasons), P.section(holders), sleep }
end

return V
