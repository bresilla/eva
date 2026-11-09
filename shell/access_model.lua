-- The Accessibility page: the shell's own settings, and what the compositor
-- holds for it (lib/services/access.lua), sent again after every reload. The
-- colour filter is a setting the screen filter follows (quick_hardware.filters).
local morf = require("morf")
local config = require("config")
local access = require("lib.services.access")
local input = require("lib.services.input_config")
local hyprconf = require("lib.compositor.hyprland_config")
local page_model = require("page_model")

local M = {}

M.TEXT = { { 1, false, "Normal" }, { 1.15, false, "Large" }, { 1.3, false, "Larger" },
  { 1.5, false, "Largest" } }

local function get(key) return config.get("accessibility." .. key) end

--- Sends the zoom.
local function push_zoom()
  hyprconf.apply(function(how)
    return input.plan({ chosen = { zoom = tonumber(get("zoom")) or 1 } }, how)
  end)
end

--- Sends the sticky keymap, or takes it away.
local function push_sticky()
  local input_model = require("input_model")
  local function send(path)
    hyprconf.apply(function(how) return { input.path_step("input:kb_file", path, how) } end)
  end
  if not get("sticky_keys") then return send("") end
  local state = input_model.state()
  access.build_sticky(state.layouts, state.options, function(path, why)
    if path then return send(path) end
    morf.log("warn", "eva: sticky keys: " .. tostring(why))
  end)
end

--- Builds the sticky keymap again, for layouts or xkb options that changed.
function M.rebuild()
  if get("sticky_keys") then push_sticky() end
end

local function push_mouse_keys(on)
  hyprconf.apply(function(how) return access.mouse_key_steps(on, how) end)
end

--- Sends everything kept on, now and after each reload, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  if not require("input_model").available() then return end
  local function push()
    if (tonumber(get("zoom")) or 1) ~= 1 then push_zoom() end
    if get("sticky_keys") then push_sticky() end
    if get("mouse_keys") then push_mouse_keys(true) end
  end
  push()
  hyprconf.on_reload(push)
end

function M.new(active, settings)
  local model = page_model.new("accessibility", active)
  model.FILTERS, model.TEXT = access.FILTERS, M.TEXT
  function model.compositor() return require("input_model").available() end
  function model.text_scale() return tonumber(config.get("appearance.text_scale")) or 1 end
  function model.set_text_scale(value) config.set("appearance.text_scale", value) end
  function model.contrast() return config.get("appearance.high_contrast") == true end
  function model.set_contrast(on) config.set("appearance.high_contrast", on == true) end
  function model.filter() return get("filter") end
  function model.set_filter(name) config.set("accessibility.filter", name) end
  -- The colour filters on, by name, for the row that leads to them.
  local NAMES = { grayscale = "Greyscale", invert = "Invert", reading = "Reading", extradim = "Extra dim",
    correction = "Correction" }
  function model.filters_now()
    local filters = require("quick_hardware").filters()
    local on = {}
    for _, id in ipairs(filters.ORDER) do
      if filters.on(id) then on[#on + 1] = NAMES[id] or id end
    end
    return #on > 0 and table.concat(on, ", ") or "Off"
  end
  function model.zoom() return tonumber(get("zoom")) or 1 end
  function model.set_zoom(value)
    config.set("accessibility.zoom", value)
    push_zoom()
  end
  function model.sticky() return get("sticky_keys") == true end
  function model.can_stick() return access.can_stick() end
  function model.set_sticky(on)
    config.set("accessibility.sticky_keys", on == true)
    push_sticky()
  end
  function model.mouse_keys() return get("mouse_keys") == true end
  function model.can_mouse_keys() return access.can_mouse_keys() end
  function model.set_mouse_keys(on)
    config.set("accessibility.mouse_keys", on == true)
    push_mouse_keys(on == true)
  end
  model.reduce_motion, model.set_reduce_motion = settings.reduce_motion, settings.set_reduce_motion
  model.request = settings.request
  return model
end

return M
