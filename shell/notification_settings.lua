-- The Settings pages behind Notifications: how they behave, and each app's
-- rules. The views are the selected theme's; this is their model.
local morf = require("morf")
local config = require("config")
local rules = require("notification_rules")
local unicase = require("lib.util.unicase")
local M = {}

M.TIMES = { { 0, "Auto" }, { 3000, "3 s" }, { 5000, "5 s" }, { 10000, "10 s" } }
M.COUNTS = { { 1, "1" }, { 3, "3" }, { 5, "5" } }
M.LOCK = { { "all", "Everything" }, { "app", "App name" }, { "count", "Count" }, { "none", "Nothing" } }
M.LIMITS = { { 50, "50" }, { 200, "200" }, { 500, "500" }, { 1000, "1000" } }
M.DAYS = { { 1, "1 day" }, { 7, "7 days" }, { 30, "30 days" }, { 0, "Always" } }
M.PREVIEWS = { { 1, "1" }, { 2, "2" }, { 3, "3" }, { 4, "4" } }
M.URGENCY = { { -1, "App's" }, { 0, "Low" }, { 1, "Normal" }, { 2, "Critical" } }
M.APP_TIMES = { { -1, "Auto" }, { 3000, "3 s" }, { 10000, "10 s" }, { 0, "Stays" } }
M.APP_SOUND = { { "default", "Default" }, { "off", "Off" } }
M.KEEP = { { 0, "Off" }, { 60000, "1 m" }, { 300000, "5 m" }, { 900000, "15 m" }, { 3600000, "1 h" } }
M.DIGEST = { key = "notifications.digest_times", kind = "list", title = "Summary times", icon = "schedule",
  note = "24-hour, as 08:00 18:00", clean = require("settings_forms").times }

function M.model()
  local notifs = require("notifs")
  local model = { active = require("presentation").active("settings.notifications") }
  function model.get(key) return config.get("notifications." .. key) end
  function model.set(key, value) config.set("notifications." .. key, value) end
  function model.ring()
    local ringer = require("services").ringer
    local mode = ringer and ringer.state.mode or config.get("ringer.mode")
    return unicase.capitalise(mode)
  end
  --- Plays the sound a notification would make now.
  function model.try()
    local sound = require("lib.services.notification_sound")
    local chosen = model.get("sound")
    return sound.play { event = chosen ~= "" and not chosen:find("/", 1, true) and chosen or sound.event(1),
      file = chosen:find("/", 1, true) and chosen or "", volume = model.get("volume"),
      ring = require("services").ringer and require("services").ringer.state.mode or config.get("ringer.mode") }
  end
  model.apps = rules.apps
  --- What an app's rule says, in a word.
  function model.summary(key)
    local rule = rules.of(key)
    if rule.mute then return "Muted" end
    if rule.mute_until > require("focus_model").now() then
      return "Muted until " .. morf.time.format("%H:%M", rule.mute_until)
    end
    if not rule.popup then return "No popups" end
    if rule.priority then return "Priority" end
    if rule.digest then return "In the summary" end
    if rules.custom(key) then return "Custom" end
    return "Default"
  end
  function model.open_app(key)
    local utilities = require("utilities")
    utilities.rules_app:set(key)
    utilities.request("notifications/app")
  end
  function model.open_position() require("utilities").request("osd") end
  --- The screens popups can keep to, and the one in use.
  function model.outputs()
    local out = { { "", "In use" } }
    for _, screen in ipairs(morf.screens or {}) do out[#out + 1] = { screen.name, screen.name } end
    return out
  end
  function model.clear_history() notifs.clear() end
  model.content = rules.content
  model.remove_rule = rules.remove_at
  function model.add_rule(pattern, field)
    if pattern == "" then return false end
    local fields = {}
    if field == "mute" then fields.mute = true elseif field == "priority" then fields.priority = true
    else fields.highlight = true end
    return rules.add_content(pattern, fields)
  end
  function model.describe(rule)
    if rule.mute then return "Muted" end
    if rule.priority then return "Priority" end
    if rule.highlight then return "Highlighted" end
    return "Custom"
  end
  return model
end

--- The model of the app page: `key()` names the app chosen.
function M.app_model()
  local utilities = require("utilities")
  local model = { active = require("presentation").active("settings.notifications/app") }
  local function key() return utilities.rules_app:get() end
  model.key = key
  function model.name() return rules.name(key()) end
  function model.get(field, category) return rules.of(key(), category)[field] end
  function model.set(field, value, category) rules.set(key(), field, value, category) end
  function model.muted()
    local rule = rules.of(key())
    return rule.mute or rule.mute_until > require("focus_model").now()
  end
  function model.mute(seconds) rules.mute(key(), seconds, require("focus_model").now()) end
  function model.unmute() rules.unmute(key()) end
  function model.categories() return rules.categories(key()) end
  function model.reset() rules.reset(key()) end
  return model
end

function M.page(w, h) return require("themes").view("notification_settings").build(M.model(), w, h) end
function M.app_page(w, h) return require("themes").view("notification_settings").app(M.app_model(), w, h) end

return M
