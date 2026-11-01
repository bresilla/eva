-- The wallpaper picker: Lule's pictures as a grid, and what the shell does with
-- them. The selection, the folder and the colours stay in the Lule studio.
local M = {}

function M.build(w, h)
  return require("themes").view("wallpaper_page").build(require("lule_page").model, require("wallpaper_model"), w, h)
end

return M
