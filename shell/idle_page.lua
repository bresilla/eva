-- The Settings page behind Eva's "Idle and sleep": the model; the view is the
-- selected theme's. A stage the system fixes reads as set and does not move.
local morf = require("morf")
local config = require("config")
local idle = require("idle_model")
local M = {}

--- Seconds in few words.
function M.span(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return "Never" end
  if seconds % 3600 == 0 then return ("%d h"):format(seconds // 3600) end
  if seconds >= 3600 then return ("%d h %d min"):format(seconds // 3600, (seconds % 3600) // 60) end
  if seconds % 60 == 0 then return ("%d min"):format(seconds // 60) end
  if seconds >= 60 then return ("%d min %d s"):format(seconds // 60, seconds % 60) end
  return ("%d s"):format(seconds)
end

function M.model(active)
  local model = { active = active, STAGES = idle.STAGES, DIM_CHOICES = idle.DIM_CHOICES,
    AWAKE_CHOICES = idle.AWAKE_CHOICES, span = M.span }
  local function set(key, value) if active() then config.set(key, value) end end

  function model.managed(stage) return idle.managed(stage) ~= nil end
  function model.seconds(stage) return idle.seconds(stage) end
  function model.chosen(stage)
    if model.managed(stage) then return idle.seconds(stage) end
    return tonumber(config.get("idle." .. stage)) or 0
  end
  function model.set_stage(stage, seconds) if not model.managed(stage) then set("idle." .. stage, seconds) end end
  function model.dim() return tonumber(config.get("idle.dim")) or 0 end
  function model.set_dim(seconds) set("idle.dim", seconds) end
  function model.battery_stage(stage) return tonumber(config.get("idle.battery." .. stage)) or 0 end
  function model.set_battery_stage(stage, seconds) if not model.managed(stage) then set("idle.battery." .. stage, seconds) end end
  function model.has_battery()
    local ok, present = pcall(function() return require("services").upower.state.display.present end)
    return ok and present == true or morf.env("EVA_FAKE_BATTERY") ~= nil
  end

  function model.awake() return idle.awake:get() end
  function model.awake_until() return idle.awake_until() end
  --- Keeps the session awake for `seconds`, or for good with true, or not with false.
  function model.set_awake(value)
    if not active() then return end
    local settings = require("settings_model")
    if value == false then settings.set_awake(false)
    elseif value == true then settings.set_awake(true)
    else settings.set_awake(true, value) end
  end
  function model.awake_note()
    if not idle.awake:get() then return "The session follows the timers" end
    local ends = idle.awake_until()
    if ends > 0 then return "Until " .. morf.time.format("%H:%M", ends) end
    return "Until turned off"
  end

  function model.flag(key) return config.get("idle." .. key) == true end
  function model.set_flag(key, on) set("idle." .. key, on == true) end
  function model.lock_flag(key) return config.get("lock." .. key) == true end
  local policy = require("models.lock_settings").policy()
  function model.lock_managed(key) return policy[key] ~= nil end
  function model.set_lock_flag(key, on) if not model.lock_managed(key) then set("lock." .. key, on == true) end end

  --- The windows open now and the ones listed, each once.
  function model.apps()
    local seen, out = {}, {}
    for _, class in ipairs(config.get("idle.apps") or {}) do
      if not seen[class] then seen[class] = true out[#out + 1] = class end
    end
    for _, class in ipairs(idle.open_classes()) do
      if not seen[class] then seen[class] = true out[#out + 1] = class end
    end
    return out
  end
  function model.app_on(class)
    for _, listed in ipairs(config.get("idle.apps") or {}) do if listed == class then return true end end
    return false
  end
  function model.set_app(class, on)
    local out = {}
    for _, listed in ipairs(config.get("idle.apps") or {}) do
      if listed ~= class then out[#out + 1] = listed end
    end
    if on then out[#out + 1] = class end
    set("idle.apps", out)
  end

  -- Who holds it awake or blocks sleep, asked as the page opens and as its own
  -- reasons move: logind is a bus call, and a binding may run often.
  local holding = morf.signal("eva.idle.holding", {})
  morf.effect("eva.idle.holding", function()
    local reasons = idle.reasons()
    if not active() then return end
    local out = {}
    for _, row in ipairs(reasons) do
      out[#out + 1] = row.name .. (row.why ~= "" and (": " .. row.why) or "")
    end
    for _, row in ipairs(idle.inhibitors()) do
      out[#out + 1] = row.who .. (row.why ~= "" and (": " .. row.why) or "")
    end
    holding:set(out)
  end)
  --- What holds it now, as lines.
  function model.holding() return holding:get() end

  function model.command(key) return table.concat(config.get("idle." .. key) or {}, " ") end
  function model.set_command(key, text)
    set("idle." .. key, require("themes.layouts.option_rows").words(text))
  end
  return model
end

function M.page(w, h)
  local model = M.model(require("presentation").active("settings.idle"))
  return require("themes").view("idle_page").build(model, w, h)
end

return M
