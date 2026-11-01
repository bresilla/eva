-- How things move and how the shell is proportioned, for every part of eva. The
-- shell, the lock, the greeter and the tools run apart and share one file, the
-- appearance preferences, so a choice made in one reaches them all. The shell's
-- `appearance.*` settings read and write through here.
local morf = require("morf")
local themes = require("themes")
local M = { STYLES = { calm = true, balanced = true, playful = true } }
local preferences = themes.preferences

-- Setting, and its name in the shared file.
local SHARED = { ["appearance.motion"] = "motion", ["appearance.reduce_motion"] = "reduce_motion",
  ["appearance.density"] = "density", ["appearance.corners"] = "corners" }

--- "calm", "balanced" or "playful"; tracked in a binding.
function M.style()
  local style = preferences.get("motion")
  return M.STYLES[style] and style or "balanced"
end

--- Whether everything lands at once: chosen here, or asked for by the desktop.
function M.reduced()
  return preferences.get("reduce_motion") == true or (morf.prefers ~= nil and morf.prefers.reduced_motion == true)
end

--- Links the shell's settings to the shared file, bringing a value set before
--- it existed across once.
function M.link(config)
  local get, set, reset = config.get, config.set, config.reset
  for key, name in pairs(SHARED) do
    local old, default = get(key), config.defaults.appearance[name]
    if old ~= default and preferences.get(name) == default then preferences.set(name, old) end
  end
  config.get = function(key)
    local name = SHARED[key]
    if name then return preferences.get(name) end
    return get(key)
  end
  config.set = function(key, value)
    local name = SHARED[key]
    if not name then return set(key, value) end
    local ok, why = preferences.set(name, value)
    if ok then
      preferences.flush()
      require("themes.ui_scale").share { [name] = value }
    end
    return ok, why
  end
  config.reset = function(key)
    if SHARED[key] then return config.set(key, config.defaults.appearance[SHARED[key]]) end
    return reset(key)
  end
  return config
end

--- For a role built without the shell's theme facade, the lock and the greeter:
--- springs take the style, and under Reduce motion everything lands. Runs
--- before anything is built to move.
function M.install()
  if M.reduced() then
    require("themes.motion_landing").install()
    return
  end
  local style = M.style()
  if style == "balanced" then return end
  local ui, styled = require("morf.ui"), require("themes.spring")
  local make = ui.spring
  ui.spring = function(spec)
    if type(spec) == "table" and spec.stiffness and spec.damping then
      local ratio = spec.damping / (2 * math.sqrt(spec.stiffness))
      local changed = styled.styled({ stiffness = spec.stiffness, ratio = ratio }, style)
      spec.damping = styled.damping(changed)
    end
    return make(spec)
  end
end

return M
