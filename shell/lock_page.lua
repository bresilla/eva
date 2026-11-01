-- The Settings page behind Eva's "Lock screen": the model; the view is the
-- selected theme's. What the system's policy sets reads as set and does not move.
local config = require("config")
local M = {}

local function walk(tree, key)
  local node = tree
  for part in key:gmatch("[^.]+") do
    if type(node) ~= "table" then return nil end
    node = node[part]
  end
  return node
end

function M.model(active)
  local policy = require("models.lock_settings").policy()
  local model = { active = active, LEVELS = {
    { "all", "All" }, { "senders", "Senders" }, { "count", "Count" }, { "none", "None" } },
    GRACE = { { 0, "Always" }, { 5, "5 s" }, { 15, "15 s" }, { 30, "30 s" }, { 60, "60 s" } } }

  function model.get(key)
    local fixed = walk(policy, key)
    if fixed ~= nil then return fixed end
    return config.get("lock." .. key)
  end
  function model.managed(key) return walk(policy, key) ~= nil end
  function model.free(key) return function() return not model.managed(key) end end
  function model.set(key, value)
    if active() and not model.managed(key) then config.set("lock." .. key, value) end
  end

  -- One level: where the Notifications page keeps it, both pages move it.
  local bridge = require("lock_bridge")
  local view = require("models.lock_notifications")
  function model.level() return bridge.level() end
  function model.set_level(level)
    if model.managed("notifications.level") or not active() then return end
    if bridge.previews() ~= nil then config.set("notifications.lock_previews", view.preview_of(level))
    else config.set("lock.notifications.level", level) end
  end

  --- Whether a shortcut stands at the corners.
  function model.shortcut_on(id)
    for _, listed in ipairs(model.get("shortcuts") or {}) do if listed == id then return true end end
    return false
  end
  function model.set_shortcut(id, on)
    local out = {}
    for _, listed in ipairs(model.get("shortcuts") or {}) do
      if listed ~= id then out[#out + 1] = listed end
    end
    if on then out[#out + 1] = id end
    model.set("shortcuts", out)
  end

  --- The widgets that may stand on a lock.
  function model.widgets()
    local out = {}
    for _, widget in ipairs(require("models.desktop_widgets").list()) do
      if widget.lock_safe == true then out[#out + 1] = widget end
    end
    return out
  end
  function model.widget_on(id)
    for _, listed in ipairs(model.get("widgets") or {}) do if listed == id then return true end end
    return false
  end
  function model.set_widget(id, on)
    local out = {}
    for _, listed in ipairs(model.get("widgets") or {}) do
      if listed ~= id then out[#out + 1] = listed end
    end
    if on then out[#out + 1] = id end
    model.set("widgets", out)
  end
  function model.argv() return table.concat(model.get("command.argv") or {}, " ") end
  function model.set_argv(text) model.set("command.argv", require("themes.layouts.form").words(text)) end
  return model
end

function M.page(w, h)
  local model = M.model(require("presentation").active("settings.lock"))
  return require("themes").view("lock_page").build(model, w, h)
end

return M
