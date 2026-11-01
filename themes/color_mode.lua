-- Dark or light, one answer for the shell, the lock and the greeter: the
-- choice saved with the theme, and under "auto" what the colour tool made.
-- EVA_THEME_MODE overrides it for a preview.
local morf = require("morf")
local themes = require("themes")
local M = { CHOICES = { "auto", "dark", "light" } }

local function explicit(value) return value == "dark" or value == "light" end

--- "auto", "dark" or "light"; tracked in a binding.
function M.chosen()
  local forced = morf.env("EVA_THEME_MODE")
  if explicit(forced) then return forced end
  local saved = themes.preferences.get("mode")
  return explicit(saved) and saved or "auto"
end

--- "dark" or "light", given what the colour tool made (nil without one).
function M.resolve(tool_mode)
  local chosen = M.chosen()
  if chosen ~= "auto" then return chosen end
  return tool_mode == "light" and "light" or "dark"
end

function M.set(mode)
  themes.preferences.set("mode", mode)
  themes.preferences.flush()
end

return M
