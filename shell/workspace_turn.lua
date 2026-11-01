-- A wheel over a workspace control, the bar's or the rail's. A touchpad turns
-- in fractions: a workspace goes by for each whole notch.
local morf = require("morf")
local services = require("services")
local turned = 0
return function(steps)
  turned = turned + steps
  if math.abs(turned) < 1 then return end
  local delta = turned > 0 and 1 or -1
  turned = 0
  local dry = morf.env("EVA_DRY_RUN")
  if dry and dry ~= "" and dry ~= "0" then
    morf.log("info", "eva: workspace " .. delta .. " (dry run)")
    return
  end
  services.workspace.step(delta)
end
