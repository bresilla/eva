-- The keyboard as a login screen needs it: which layouts there are, which is
-- active, and whether Caps Lock is on. One per controller, shared by lock and
-- greeter. The layouts are the compositor's; EVA_FAKE_LAYOUTS (a comma list)
-- stands in where there is none.
local morf = require("morf")
local lights = require("lib.services.key_lights")
local M = {}

local function compositor()
  local ok, hyprland = pcall(require, "lib.compositor.hyprland")
  return ok and hyprland or nil
end

local function words(text)
  local out = {}
  for word in tostring(text or ""):gmatch("[^,%s]+") do out[#out + 1] = word end
  return out
end

function M.new(prefix)
  local names = morf.signal(prefix .. ".keyboard.layouts", {})
  local active = morf.signal(prefix .. ".keyboard.layout", 1)
  local caps = morf.signal(prefix .. ".keyboard.caps", false)
  local leds = lights.scan()
  local fake = words(morf.env("EVA_FAKE_LAYOUTS"))
  local hyprland = #fake == 0 and compositor() or nil
  local self = { caps = function() return caps:get() end }

  local function read()
    if not hyprland then return end
    pcall(function()
      hyprland.json("devices", function(devices)
        for _, keyboard in ipairs(type(devices) == "table" and devices.keyboards or {}) do
          if keyboard.main then
            names:set(words(keyboard.layout))
            active:set((tonumber(keyboard.active_layout_index) or 0) + 1)
            if self.wanted then self.force(self.wanted) end
            return
          end
        end
      end)
    end)
  end
  if #fake > 0 then names:set(fake) else read() end

  --- Reads the light again; a key may have moved it.
  function self.look() caps:set(lights.lit(leds.caps)) end
  self.look()

  function self.list() return names:get() end
  --- The active layout's short name, or "" with a single one.
  function self.current()
    local list = names:get()
    if #list < 2 then return "" end
    return (list[active:get()] or list[1]):upper()
  end

  local function apply(index)
    active:set(index)
    if hyprland and morf.env("EVA_DRY_RUN") ~= "1" then
      pcall(function() hyprland.request(("switchxkblayout all %d"):format(index - 1), function() end) end)
    end
  end

  --- On to the next layout, round to the first.
  function self.step()
    local count = #names:get()
    if count < 2 then return false end
    apply(active:get() % count + 1)
    return true
  end

  --- The layout called `name`, now or as soon as the layouts are known. The one
  --- it left is given back by `restore`.
  function self.force(name)
    self.wanted = name
    for index, candidate in ipairs(names:get()) do
      if candidate == name then
        self.wanted = nil
        if index == active:get() then return false end
        self.saved = active:get()
        apply(index)
        return true
      end
    end
    return false
  end
  function self.restore()
    if self.saved then apply(self.saved) self.saved = nil end
  end
  return self
end

return M
