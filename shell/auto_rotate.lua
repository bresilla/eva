-- Turning the screen as the machine turns: while the rotation is not locked
-- the accelerometer is claimed and its orientation becomes the built-in
-- output's transform (and the touchscreen's), through Hyprland's own socket.
-- Every screen runs the shell once; only the one the sensor belongs to acts.
local morf = require("morf")
local hyprland = require("lib.compositor.hyprland")
local hypr = require("lib.util.hypr")
local M = {}

M.TRANSFORMS = { normal = 0, ["left-up"] = 1, ["bottom-up"] = 2, ["right-up"] = 3 }

local function dry()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

local function screen_name() return (morf.screens and morf.screens[1] and morf.screens[1].name) or "" end

--- Whether `name` is an output built into the machine.
function M.built_in(name)
  return name:match("^eDP") ~= nil or name:match("^DSI") ~= nil or name:match("^LVDS") ~= nil
end

local function legacy(name, transform)
  local row = hyprland.monitor(name)
  if not row then return false end
  hyprland.keyword("monitor", ("%s,%dx%d@%.3f,%dx%d,%s,transform,%d"):format(name, row.width, row.height,
    row.refresh_rate, row.x, row.y, tostring(row.scale), transform))
  hyprland.keyword("input:touchdevice:transform", transform)
  hyprland.keyword("input:tablet:transform", transform)
  return true
end

--- Turns the output to `orientation`; false for one that names no turn.
function M.apply(orientation, name)
  local transform = M.TRANSFORMS[orientation]
  if not transform then return false end
  name = name or screen_name()
  if dry() then
    morf.log("info", ("eva: rotate %s to %d (dry run)"):format(name, transform))
    return true
  end
  if not hyprland.available() then return false end
  hypr.eval_or(hyprland, ("hl.monitor({output=%q, transform=%d})"):format(name, transform),
    function() legacy(name, transform) end,
    function()
      hyprland.eval(("hl.config({input={touchdevice={transform=%d},tablet={transform=%d}}})"):format(transform, transform))
    end)
  return true
end

--- Follows the accelerometer from here on. `options`: `rotation`
--- (quick_hardware's, by default), `name` (the output, this screen's).
function M.start(options)
  options = options or {}
  local rotation = options.rotation or require("quick_hardware").rotation()
  local sensors = rotation.sensors
  local name = options.name or screen_name()
  if not M.built_in(name) then return false end
  local claimed = false
  morf.effect("eva.rotate.claim", function()
    local wanted = rotation.present() and not rotation.on()
    if wanted ~= claimed then
      claimed = wanted
      if wanted then sensors.claim() else sensors.release() end
      -- A convertible opened back into a laptop stands upright again.
      if not wanted and rotation.hinged and rotation.hinged() then M.apply("normal", name) end
    end
    if wanted then M.apply(sensors.state.orientation, name) end
  end)
  return true
end

return M
