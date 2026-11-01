-- Glass as a material, read by the frames, cards and displays of both themes.
local morf = require("morf")
local config = require("config")
local M = {}

function M.on() return config.get("appearance.glass") == true end

--- How much a surface lets through, 0 to 1.
function M.clarity() return config.get("appearance.glass_clarity") end

--- `color` as a surface of the current material; `weight` thickens it.
function M.fill(color, weight)
  if not M.on() then return color end
  return color:alpha(math.min(1, (1 - M.clarity()) * (weight or 1)))
end

function M.rim() return M.on() and 0.45 or 0 end

--- Whether the compositor blurs behind the shell's translucent surfaces.
function M.compositor()
  return M.on() and morf.capabilities ~= nil and morf.capabilities.backdrop_blur == true
end

return M
