-- Material's dock: a pill, round bubbles rising out of it on a wide soft seam.
local V = {}
function V.build(model)
  return require("themes.layouts.dock").build(model, { bubble = "circle", seam = 14 })
end
return V
