-- Looks saved by name: the colours, the shape and the wallpaper as one set, to
-- come back to. State and actions only.
local morf = require("morf")
local config = require("config")
local M = {}

-- What a look is.
M.KEYS = { "theme.source", "theme.variant", "theme.hue", "theme.follow_song",
  "appearance.density", "appearance.corners", "appearance.glass", "appearance.glass_clarity", "appearance.pure_black",
  "wallpaper.path", "wallpaper.pin", "wallpaper.fit", "wallpaper.parallax", "wallpaper.transition.kind" }

--- The saved looks: `{ name, values }`.
function M.list() return config.get("appearance.profiles") end

--- Saves the look on show as `name`, over one of that name.
function M.save(name)
  name = (name or ""):match("^%s*(.-)%s*$")
  if name == "" then return false end
  local values = {}
  for i, key in ipairs(M.KEYS) do values[i] = { key = key, value = config.get(key) } end
  local out = {}
  for _, profile in ipairs(M.list()) do
    if profile.name ~= name then out[#out + 1] = profile end
  end
  out[#out + 1] = { name = name, values = values }
  config.set("appearance.profiles", out)
  return true
end

--- Puts a saved look back.
function M.load(name)
  for _, profile in ipairs(M.list()) do
    if profile.name == name then
      for _, entry in ipairs(profile.values) do config.set(entry.key, entry.value) end
      return true
    end
  end
  return false
end

function M.remove(name)
  local out, found = {}, false
  for _, profile in ipairs(M.list()) do
    if profile.name == name then found = true else out[#out + 1] = profile end
  end
  config.set("appearance.profiles", out)
  return found
end

return M
