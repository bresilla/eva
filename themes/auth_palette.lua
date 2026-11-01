-- The lock and greeter consume the same wallpaper palette regardless of
-- visual theme. A greeter account without a readable Lule cache falls back
-- to its administrator-provided accent, then the built-in blue.
local morf = require("morf")
local lule = require("lib.integrations.lule")
local material = require("lib.theme.material")
local shared_watches={}
-- `contrast` (a tracked fn, optional): the quiet roles take the loud ones.
local LOUDER={onSurfaceVariant="onSurface",onSecondaryContainer="onSurface",outline="onSurface",
  surfaceContainer="surfaceContainerLowest",surfaceContainerHigh="surfaceContainerLowest"}
return function(name,contrast)
  local accent = "#9ccbfb"
  local ok, words = pcall(morf.fs.read, "/etc/eva/accent")
  local wanted = ok and type(words) == "string" and words:match("#%x%x%x%x%x%x")
  if wanted then accent = wanted end
  local shared=require("themes.wallpaper_handoff").palette(name)
  local current
  if shared then
    current=morf.signal("eva."..name..".palette",(lule.read(shared)))
    shared_watches[name]=morf.fs.watch(shared,function()
      local value=lule.read(shared)
      if value then current:set(value) end
    end)
  else
    current=lule.watch("eva." .. name .. ".palette")
  end
  local function scheme()
    local tool = current:get()
    return material.scheme(tool and tool.accent or accent,
      { variant = "tonal_spot", mode = require("themes.color_mode").resolve(tool and tool.theme) })
  end
  local roles = {}
  for key, value in pairs(scheme()) do
    local valid, red = pcall(function() return value.r end)
    if type(value) ~= "string" and valid and type(red) == "number" then roles[key] = value end
  end
  local colors = morf.theme(roles, { transition = { duration = 400 } })
  morf.effect("eva." .. name .. ".colors", function()
    local values=scheme()
    local loud=contrast and contrast()
    for key, value in pairs(values) do
      if roles[key] then colors[key] = loud and LOUDER[key] and values[LOUDER[key]] or value end
    end
  end)
  return colors, current
end
