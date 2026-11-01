-- Glass as a material: an appearance setting that frames, panels and displays of
-- both themes read. What a panel lets through is the plate (themes/glass_plate.lua),
-- the picture blurred and drawn under the frame's field on the shell's own surface,
-- so it looks the same on any compositor; where the compositor can blur what is
-- behind the shell, it does that too.
local morf = require("morf")
local config = require("config")
local M = {}

--- Whether panels are glass; tracked in a binding.
function M.on() return config.get("appearance.glass") == true end

--- How much a surface lets through, 0 to 1.
function M.clarity() return config.get("appearance.glass_clarity") end

--- `color` as a surface of the current material; `weight` thickens it.
function M.fill(color, weight)
  if not M.on() then return color end
  return color:alpha(math.min(1, (1 - M.clarity()) * (weight or 1)))
end

--- How bright a card's edge is lit.
function M.rim() return M.on() and 0.45 or 0 end

--- Whether the compositor blurs behind the shell's translucent surfaces.
function M.compositor()
  return M.on() and morf.capabilities ~= nil and morf.capabilities.backdrop_blur == true
end

return M
