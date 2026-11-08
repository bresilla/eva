-- eva-breaks as Settings' Breaks page: the reminders to look away and to get
-- up, and the day so far. `eva-breaks --watch` keeps the count; the page reads
-- what it writes, and is built only while it is on show.
local ui = require("morf.ui")
local model = require("apps.breaks.model")

local M = {}

local followed = false
local function follow()
  if followed then return end
  followed = true
  model.follow()
end

--- The page, `w` by `h`.
function M.build(w, h)
  follow()
  local shown = require("presentation").active("settings.breaks")
  return ui.Item { width = w, height = h,
    ui.Loader { anchors = { fill = true }, active = shown,
      source = function()
        return require("apps.breaks.view").build(function() return w end, function() return h end)
      end } }
end

-- What the specs and scenarios ask of it, as the tool's window answered.
M.verbs = {
  state = function()
    follow()
    return { status = model.status:get(), settings = model.settings:get(), watching = model.watching(model.status:get()) }
  end,
  set = function(kind, field, value)
    follow()
    if field == "on" then value = value == "true" else value = tonumber(value) end
    model.change(function(settings) settings[kind][field] = value end)
    return true
  end,
  pause = function(minutes) follow() model.pause(tonumber(minutes)) return true end,
}

return M
