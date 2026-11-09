-- The detail pages of the hardware tiles. Hotspot keeps its password in a
-- local of the page, never in a signal, and hands it over once on saving.
local morf = require("morf")
local ui = require("morf.ui")
local unicase = require("lib.util.unicase")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local C = theme.color

local V = {}

--- A one-line text field the card's width. Returns its box and its handle.
local function field(id, w, placeholder, kind, on_changed, on_accept)
  return P.field { id = id, width = w, placeholder = placeholder, kind = kind, on_changed = on_changed,
    on_accepted = on_accept }
end
V.field = field

--- A slider under its name, shown while `visible` holds.
local function named(width, name, slider, visible)
  return ui.Column { width = width, gap = theme.space.xs, visible = visible, F.note(width, name), slider }
end

--- `node` dimmed while its feature's switch `on` is off: it still sets
--- what the feature takes up once on.
local function waiting(node, on)
  return ui.Column { opacity = function() return on() and 1 or 0.45 end,
    behavior = { opacity = { duration = theme.duration.small } }, node }
end

--- What a switch row says: what it does while off, how it stands while on.
local function says(status, off)
  return function() local now = status() return now == "Off" and off or now end
end

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
        subtitle = says(hotspot.status, "Shares this connection over Wi-Fi"),
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
      P.button { id = "settings-hotspot-save", width = inner, label = "Save", tone = "primary", on_clicked = save },
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
    P.section { id = "settings-nightlight", width = w,
      P.row { id = "settings-nightlight-state", width = inner, icon = "nightlight", on = on, title = "Night light",
        subtitle = function() return on() and "Warmer colours on the screen" or "Colours as they are" end,
        trailing = P.switch { id = "settings-nightlight-switch", name = "Night light", on = on,
          on_toggled = function(now) night.set(now) end } },
      waiting(named(inner, "Warmth", kit.slider { id = "settings-nightlight-temperature", accessible_name = "Temperature", width = inner,
        icon = "thermostat", value = position,
        set = function(value) night.set_temperature(night.WARMEST + value * span) end,
        reading = function(value)
          local kelvin = night.WARMEST + value * span
          return ("%d K"):format(math.floor(kelvin / night.STEP + 0.5) * night.STEP)
        end }), on),
      P.row { id = "settings-nightlight-follow", width = inner, icon = "wb_twilight", on = night.follow,
        title = "Follow the sun", subtitle = "On at sunset, off at sunrise",
        visible = night.placed,
        trailing = P.switch { id = "settings-nightlight-follow-switch", name = "Follow the sun", on = night.follow,
          on_toggled = function(now) night.set_follow(now) end } },
    },
  }
end

--- The Flashlight page: on or off, and how bright, where the LED has steps.
function V.flashlight_page(model, w, h)
  local inner = P.inner(w)
  local torch = require("quick_hardware").torch()
  local function on() return torch.on() end
  local strength = kit.slider { id = "settings-flashlight-level", accessible_name = "Strength", width = inner,
    icon = "flashlight_on", value = torch.level,
    set = function(value) torch.set_level(value) end,
    reading = function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end }
  strength.visible = torch.dims
  return P.page { id = "settings-flashlight-scroll", width = w, height = h,
    P.section { id = "settings-flashlight", width = w,
      P.row { id = "settings-flashlight-state", width = inner, icon = "flashlight_on", on = on, title = "Flashlight",
        subtitle = says(torch.status, "The camera's light, as a torch"),
        trailing = P.switch { id = "settings-flashlight-switch", name = "Flashlight", on = on,
          on_toggled = function(now) torch.set(now) end } },
      named(inner, "Strength", strength, torch.dims),
      kit.subtitle { id = "settings-flashlight-note", width = inner, wrap = true, font_size = P.SUB,
        visible = function() return not torch.dims() end, text = "This light has one strength." },
    },
  }
end

local FILTERS = {
  { id = "grayscale", name = "Greyscale", icon = "filter_b_and_w", on = "Takes the colour out of the screen" },
  { id = "invert", name = "Invert colours", icon = "invert_colors", on = "Light turns dark and dark turns light" },
  { id = "reading", name = "Reading mode", icon = "menu_book", on = "Paper tones, little colour" },
  { id = "extradim", name = "Extra dim", icon = "brightness_low", on = "Darker than the lowest brightness" },
  { id = "correction", name = "Colour correction", icon = "palette", on = "For colour blindness" },
}

local KINDS = { protanopia = "Protan", deuteranopia = "Deutan", tritanopia = "Tritan" }

--- The Colour filters page: a switch for each, how dim extra dim is, and which
--- colours the correction is for.
function V.filters_page(model, w, h)
  local inner = P.inner(w)
  local filters = require("quick_hardware").filters()
  local list = { id = "settings-filters", width = w, title = "The whole screen" }
  for _, item in ipairs(FILTERS) do
    local function on() return filters.on(item.id) end
    list[#list + 1] = P.row { id = "settings-filters-" .. item.id, width = inner, icon = item.icon, on = on, title = item.name,
      subtitle = item.on,
      trailing = P.switch { id = "settings-filters-" .. item.id .. "-switch", name = item.name, on = on,
        on_toggled = function(now) filters.set(item.id, now) end } }
  end
  local dim = kit.slider { id = "settings-filters-dim", accessible_name = "How much light is left", width = inner,
    icon = "brightness_low", value = filters.dim, set = function(value) filters.set_dim(value) end,
    reading = function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end }
  local function dimmed() return filters.on("extradim") end
  dim.visible = dimmed
  list[#list + 1] = named(inner, "Light left", dim, dimmed)
  local kinds = { id = "settings-filters-kind", width = inner, visible = function() return filters.on("correction") end }
  for _, kind in ipairs(filters.CORRECTIONS) do
    kinds[#kinds + 1] = { id = "settings-filters-kind-" .. kind, label = KINDS[kind] or unicase.capitalise(kind),
      accessible_name = kind, group = "settings-filters-kind",
      visible = function() return filters.on("correction") end,
      selected = function() return filters.correction() == kind end,
      on_clicked = function() filters.set_correction(kind) end }
  end
  list[#list + 1] = P.buttons(kinds)
  return P.page { id = "settings-filters-scroll", width = w, height = h, P.section(list) }
end

--- The Background sounds page: on or off, which, and how loud.
function V.sounds_page(model, w, h)
  local inner = P.inner(w)
  local sounds = require("quick_hardware").sounds()
  local function on() return sounds.on() end
  local choices = { id = "settings-sounds-kind", width = inner }
  for _, kind in ipairs(sounds.KINDS) do
    choices[#choices + 1] = { id = "settings-sounds-" .. kind.id, label = kind.name, icon = kind.icon, group = "settings-sounds",
      selected = function() return sounds.kind() == kind.id end,
      on_clicked = function() sounds.set_kind(kind.id) end }
  end
  return P.page { id = "settings-sounds-scroll", width = w, height = h,
    P.section { id = "settings-sounds", width = w,
      P.row { id = "settings-sounds-state", width = inner, icon = "waves", on = on, title = "Background sounds",
        subtitle = says(sounds.status, "Rain, ocean or noise under everything"),
        trailing = P.switch { id = "settings-sounds-switch", name = "Background sounds", on = on,
          on_toggled = function(now) sounds.set(now) end } },
      waiting(P.buttons(choices), on),
      waiting(named(inner, "Volume", kit.slider { id = "settings-sounds-level", accessible_name = "Volume", width = inner, icon = "volume_up",
        value = sounds.level, set = function(value) sounds.set_level(value) end, live = false,
        reading = function(value) return ("%d%%"):format(math.floor(value * 100 + 0.5)) end }), on),
    },
  }
end

return V
