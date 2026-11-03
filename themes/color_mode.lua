-- Dark or light, one answer for the shell, the lock and the greeter: the
-- choice saved with the theme, or what the colour tool made until there is
-- one. EVA_THEME_MODE overrides it for a preview.
local morf = require("morf")
local themes = require("themes")
local M = {}

local function explicit(value) return value == "dark" or value == "light" end
local preferences = themes.preferences

--- "dark" or "light", or "auto" before a choice; tracked in a binding.
function M.chosen()
  local forced = morf.env("EVA_THEME_MODE")
  if explicit(forced) then return forced end
  local saved = preferences.get("mode")
  return explicit(saved) and saved or "auto"
end

--- "dark" or "light", given what the colour tool made (nil without one).
function M.resolve(tool_mode)
  local chosen = M.chosen()
  if explicit(chosen) then return chosen end
  return tool_mode == "light" and "light" or "dark"
end

function M.set(mode)
  preferences.set("mode", mode)
  preferences.flush()
  require("themes.ui_scale").share { mode = mode }
end

return M
