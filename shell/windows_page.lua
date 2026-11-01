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
  model.scopes = { { "all", "public", "Everywhere" }, { "workspace", "workspaces", "This workspace" },
    { "output", "monitor", "This screen" } }
  model.scrubs = { { "apps", "apps", "Apps" }, { "workspaces", "workspaces", "Workspaces" } }
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

return M
