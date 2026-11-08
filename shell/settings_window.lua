-- The Settings window: every page of shell/settings_registry.lua in one shell
-- surface over everything (shell/window_host.lua). Its pages are utilities.lua's
-- builders and its state is shell/settings_model.lua's.
local morf = require("morf")
local settings = require("utilities")

local M = require("window_host").new(settings)

-- The Lule studio works while its page is on show.
morf.effect("eva.settings.window.lule", function()
  local on = settings.opened:get() and settings.displayed:get() == "theme/lule"
  local studio = package.loaded.lule_studio or (on and require("lule_studio"))
  if studio and studio.active then studio.active:set(on) end
end)

return M
