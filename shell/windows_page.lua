-- The Windows and Dock pages of Settings: what they read and set. The view is
-- the theme's.
local config = require("config")
local M = {}

local function model_of(key)
  local active = require("presentation").active("settings." .. key)
  local function set(path) return function(value) if active() then config.set(path, value) end end end
  local function get(path) return function() return config.get(path) end end
  return { active = active, set = set, get = get, key = key }
end

function M.page(w, h)
  local model = model_of("windows")
  local corners = require("hot_corners")
  local responsive = require("responsive")
  model.corners, model.touch, model.phone = corners, responsive.touch(), responsive.phone()
  model.scopes = { { "all", "public", "All" }, { "workspace", "workspaces", "Space" },
    { "output", "monitor", "Screen" } }
  model.scrubs = { { "apps", "apps", "Apps" }, { "workspaces", "workspaces", "Workspaces" } }
  model.dim_min, model.dim_max = require("window_rules_model").DIM_MIN, require("window_rules_model").DIM_MAX
  return require("themes").view("windows_page").build_windows(model, w, h)
end

function M.dock_page(w, h)
  local model = model_of("dock")
  local dock = require("dock")
  model.dock = dock
  model.taskbar = dock.mode() == "taskbar"
  model.shows = { { "auto", "smart_toy", "Auto" }, { "on", "visibility", "On" }, { "off", "visibility_off", "Off" } }
  model.edges = { { "bottom", "vertical_align_bottom", "Bottom" }, { "left", "align_horizontal_left", "Left" },
    { "right", "align_horizontal_right", "Right" } }
  model.hides = { { "off", "visibility", "Never" }, { "windows", "select_window", "Under windows" }, { "on", "visibility_off", "Always" } }
  model.sizes = { { 40, "photo_size_select_small", "Small" }, { 48, "crop_square", "Medium" }, { 64, "photo_size_select_large", "Large" } }
  return require("themes").view("windows_page").build_dock(model, w, h)
end

--- The rules' list, and the running windows to start one from.
function M.rules_page(w, h)
  local model = model_of("windows/rules")
  local rules = require("window_rules_model")
  local windows = require("windows_model")
  model.rules, model.windows = rules, windows
  function model.rule(index) return rules.list()[index] end
  function model.running() return windows.list() end
  return require("themes").view("windows_page").build_rules(model, w, h)
end

--- The saved layouts.
function M.layouts_page(w, h)
  local model = model_of("windows/layouts")
  model.layouts = require("layouts_model")
  model.message = require("morf").signal("eva.layouts.message", "")
  function model.saved(index) return model.layouts.list()[index] end
  --- What a saved layout is, in a line: how many, and how many cannot be started.
  function model.count(layout)
    local rows, stuck = layout.windows or {}, 0
    for _, row in ipairs(rows) do if row.startable == false then stuck = stuck + 1 end end
    if stuck == 0 then return ("%d windows"):format(#rows) end
    return ("%d windows, %d cannot be started again"):format(#rows, stuck)
  end
  function model.save(name)
    model.layouts.save(name, function(count, why)
      model.message:set(count and ("Saved %d windows as %s"):format(count, name) or why)
    end)
  end
  return require("themes").view("windows_page").build_layouts(model, w, h)
end

--- One rule, as the draft.
function M.rule_page(w, h)
  local model = model_of("windows/rule")
  model.rules = require("window_rules_model")
  model.layouts = { { "", "tab_unselected", "As it comes" }, { "float", "picture_in_picture", "Float" }, { "tile", "view_quilt", "Tile" } }
  return require("themes").view("windows_page").build_rule(model, w, h)
end

return M
