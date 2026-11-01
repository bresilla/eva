-- Settings in the launcher's search: every page of `settings_model.DETAILS` and
-- every tile of `TOGGLES` is an entry without being asked, and what else finds a
-- page, or a control inside one, is written here. A page or a tile added to those
-- lists is searchable as it stands.
local index = require("lib.shell.launcher.search_index")

local M = {}

-- The words that find each page, beside its name.
M.KEYWORDS = {
  network = "wifi wi-fi wireless internet ssid connect", bluetooth = "bt pair headphones devices",
  mobile = "cellular sim modem lte 5g data apn", sound = "audio volume speakers output headphones",
  microphone = "mic input recording", power = "battery charge limit profile performance saver sleep",
  eva = "shell panels hover motion animation", bar = "panel status taskbar edge tray clock",
  wired = "ethernet lan cable", osd = "on-screen display popup volume indicator overlay",
  mesh = "tailscale zerotier netbird vpn", tunnel = "vpn wireguard openvpn proton tor", focus = "do not disturb dnd awake caffeine ringer silent",
  hotspot = "tethering share internet", nightlight = "blue light warm sunset redshift temperature",
  theme = "dark light mode appearance colours colors", ["theme/lule"] = "wallpaper colours palette font scheme",
  ["sound/equalizer"] = "eq bass treble presets autoeq", ["sound/equalizer/audiogram"] = "hearing test",
}

-- Controls inside a page, each its own result: { name, page, words, icon }.
M.CONTROLS = {
  { "Reduce motion", "eva", "animations accessibility", "animation" },
  { "Motion style", "eva", "calm balanced playful bounce spring", "animation" },
  { "Open panels on hover", "eva", "edge reach pointer", "near_me" },
  { "Bar position", "bar", "top bottom left right edge side", "toolbar" },
  { "System tray", "bar", "tray indicators", "toolbar" },
  { "Clock format", "bar", "12 hour 24 hour time", "schedule" },
  { "Charge limit", "power", "battery threshold health 80", "battery_charging_full" },
  { "Power profile", "power", "performance balanced saver", "bolt" },
  { "Output device", "sound", "speakers headphones sink", "speaker" },
  { "App volumes", "sound", "streams mixer per application", "tune" },
  { "Input device", "microphone", "mic source", "mic" },
  { "Equalizer presets", "sound/equalizer", "eq bass treble autoeq", "equalizer" },
  { "Night light temperature", "nightlight", "warm kelvin", "thermostat" },
  { "Hotspot password", "hotspot", "share wifi name", "wifi_tethering" },
  { "Wallpaper", "theme/lule", "background picture image", "image" },
  { "Colour scheme", "theme/lule", "palette accent", "palette" },
  { "Summary times", "notifications", "digest schedule when held", "schedule" },
  { "Notification buttons keep working", "notifications", "actions expired how long", "smart_button" },
  { "Dark mode", "theme", "night appearance", "dark_mode" },
  { "Light mode", "theme", "day appearance", "light_mode" },
  { "On-screen display position", "osd", "corner where", "picture_in_picture" },
}

local function opener(key)
  return function()
    if not require("utilities").request(key) then return "keep" end
    require("pages").open("settings")
    return "close"
  end
end

local function read(value)
  return function()
    if type(value) ~= "function" then return value end
    local ok, result = pcall(value)
    return ok and result or nil
  end
end

--- Registers `model`'s pages, tiles and controls.
function M.register(model)
  local page_names = {}
  local listed = {}
  for _, entry in ipairs(require("settings_registry").list()) do listed[entry.key] = entry end
  for _, page in ipairs(model.DETAILS) do
    page_names[page.key] = page.name
    local entry = listed[page.key] or {}
    index.register { id = "setting:" .. page.key, name = page.name, tag = "Setting",
      keywords = (M.KEYWORDS[page.key] or "") .. " " .. (entry.keywords or ""),
      description = "Settings", material = entry.icon or "settings", kind = "menu", run = opener(page.key) }
  end
  for _, control in ipairs(M.CONTROLS) do
    if page_names[control[2]] then
      index.register { id = "setting:" .. control[2] .. ":" .. control[1], name = control[1], keywords = control[3], tag = "Setting",
        description = "Settings  ·  " .. page_names[control[2]], material = control[4], kind = "menu", run = opener(control[2]) }
    end
  end
  for _, tile in ipairs(model.TOGGLES) do
    local live = model.CONTROLS[tile.id] or tile
    local status = read(live.status)
    index.register {
      id = "tile:" .. tile.id, name = tile.name or tile.id, tag = "Tile", kind = "menu",
      keywords = tile.detail and M.KEYWORDS[tile.detail] or nil,
      material = type(live.icon) == "function" and read(live.icon) or live.icon,
      on = live.on, present = live.present,
      description = function()
        local said = status()
        if said and said ~= "" then return said end
        return (live.on and read(live.on)()) and "On" or "Off"
      end,
      run = function()
        live.set(not (live.on and read(live.on)()))
        return "keep"
      end,
      actions = tile.detail and { { name = "Open its page", material = "open_in_new", run = opener(tile.detail) } } or nil,
    }
  end
end

return M
