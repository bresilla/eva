-- The detail pages of the hardware tiles. Hotspot keeps its password in a
-- local of the page, never in a signal, and hands it over once on saving.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local C = theme.color

local V = {}

--- A one-line text field the card's width. Returns its box and its handle.
local function field(id, w, placeholder, kind, on_changed, on_accept)
  return P.field { id = id, width = w, placeholder = placeholder, kind = kind, on_changed = on_changed,
    on_accepted = on_accept }
end
V.field = field

--- The Hotspot page: on or off, and the network's name and password.
function V.hotspot_page(model, w, h)
  local inner = P.inner(w)
  local hotspot = require("quick_hardware").hotspot()
  local stamp = tostring({})
  local name = morf.signal("eva.hotspot.draft." .. stamp, hotspot.ssid())
  local typed = morf.signal("eva.hotspot.typed." .. stamp, false)
  local failure = morf.signal("eva.hotspot.failure." .. stamp, "")
  local password = ""
  local password_handle

  local function say_status()
    local said = failure:get()
    if said ~= "" then return said end
    return hotspot.message:get()
  end
  local function save()
    failure:set("")
    local given = password
    hotspot.save(name:get(), given, function(ok, why)
      if not ok then failure:set(tostring(why or "It could not be saved")) return end
      password, given = "", ""
      if password_handle then password_handle.text = "" end
      typed:set(false)
    end)
  end
  local function on() return hotspot.on() end
  local name_box, name_handle = field("settings-hotspot-ssid", inner, "Network name", "entry",
    function(value) name:set(value) end, save)
  name_handle.text = name:get()
  local pass_box
  pass_box, password_handle = field("settings-hotspot-password", inner,
    function() return hotspot.saved() and "Password (unchanged)" or "Password, at least 8 characters" end, "password",
    function(value) password = value typed:set(value ~= "") end, save)

  return P.page { id = "settings-hotspot-scroll", width = w, height = h,
    P.section { id = "settings-hotspot", width = w, title = "Sharing",
      P.row { id = "settings-hotspot-state", width = inner, icon = "wifi_tethering", on = on, title = "Hotspot",
        subtitle = function() return hotspot.status() end,
        trailing = P.switch { id = "settings-hotspot-switch", name = "Hotspot", on = on,
          enabled = function() return hotspot.saved() end,
          on_toggled = function(now) hotspot.set(now) end } },
      kit.subtitle { id = "settings-hotspot-note", width = inner, wrap = true, font_size = P.SUB,
        text = "It uses the Wi-Fi radio: it drops the Wi-Fi network you are on, and turning Wi-Fi off stops it." },
    },
    P.section { id = "settings-hotspot-network", width = w, title = "Network",
      name_box, pass_box,
      kit.subtitle { id = "settings-hotspot-message", width = inner, wrap = true, font_size = P.SUB, text = say_status,
        visible = function() return say_status() ~= "" end, color = function() return C.error end },
      P.button { id = "settings-hotspot-save", label = "Save", tone = "primary", on_clicked = save },
    },
  }
end

--- The Night light page: on or off, and how warm.
function V.nightlight_page(model, w, h)
  local inner = P.inner(w)
  local night = require("quick_hardware").nightlight()
  local span = night.COOLEST - night.WARMEST
  local function on() return night.on() end
  local function position() return (night.temperature() - night.WARMEST) / span end
  return P.page { id = "settings-nightlight-scroll", width = w, height = h,
    P.section { id = "settings-nightlight", width = w, title = "Night light",
      P.row { id = "settings-nightlight-state", width = inner, icon = "nightlight", on = on, title = "Night light",
        subtitle = function() return on() and "Warmer colours on the screen" or "Colours as they are" end,
        trailing = P.switch { id = "settings-nightlight-switch", name = "Night light", on = on,
          on_toggled = function(now) night.set(now) end } },
      kit.slider { id = "settings-nightlight-temperature", accessible_name = "Temperature", width = inner,
        icon = "thermostat", value = position,
        set = function(value) night.set_temperature(night.WARMEST + value * span) end,
        reading = function(value)
          local kelvin = night.WARMEST + value * span
          return ("%d K"):format(math.floor(kelvin / night.STEP + 0.5) * night.STEP)
        end },
    },
  }
end

return V
