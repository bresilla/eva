-- The two sound pages, Sound (the output) and Microphone (the input), in the
-- quick controls' panel and the Settings window, in the page template
-- (themes/layouts/page.lua), and Sound's second page, which ends with the sound
-- server's restart:
--
--   Output         the default output, its mute, volume, and each of its
--                  channels under a Channels expander that remembers
--                  being shut; then the equalizer, one page in
--   Output device  every output, the default one chosen; a click makes
--                  another the default
--   Apps           what is playing: each app's volume and mute, and a
--                  button for each output to send it to
--   Input          the default input's volume, mute and channels, and
--                  every input
--   Recording      what records: each app's volume and mute, and a button
--                  for each input to take it from
--
-- Readings and actions come from the shared audio model.

local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local rows = require("themes.layouts.rows")
local P = require("themes.layouts.page")
local disclosure = require("lib.kit.archetypes.disclosure")

local M = {}

--- Sound's second page: the devices wanted first, codecs and card profiles,
--- and the sound theme.
function M.more(model, w, h)
  return M.build(model, w, h, true)
end

function M.build(model, w, h, more)
local INNER = P.inner(w)
local MAX_CHANNELS = 16
local available = model.available
local sink, source = model.default, model.default

--- A mute toggle at a row's right: the theme's alert tone when on.
local function mute_button(id, target, icon_on, icon_off, name)
  local function muted() local t = target() return t and t.muted end
  return rows.toggle { id = id, accessible_name = name, width = 40, height = 36,
    on = function() return muted() == true end, icon_on = icon_on, icon_off = icon_off,
    on_clicked = function()
      local t = target()
      if t then model.toggle_device(t) end
    end,
  }
end

--- A line inside a card saying what is missing, centred in it.
local function nothing(icon, text, visible)
  return P.row { width = INNER, icon = icon, on = function() return false end, title = text, visible = visible }
end

local function name_of(d) return d and (d.description or d.name) or "?" end

--- A row to choose a device by: its name, a mark when it is the default.
local function device_row(id_prefix, row, icon)
  local function live() return model.device(row) end
  local function chosen() local d = live() return d ~= nil and d.default == true end
  return rows.choice {
    id = id_prefix .. "-" .. math.floor(row.id), group = id_prefix,
    width = INNER, height = P.ROW_H, on = chosen, enter = kit.enter(), exit = kit.leave(),
    on_clicked = function() model.select_device(row) end,
    P.row { width = INNER, on = chosen, icon = icon,
      title = function() return name_of(live()) end,
      subtitle = function() return chosen() and "In use" or "Not in use" end,
      trailing = kit.icon(function() return chosen() and "radio_button_checked" or "radio_button_unchecked" end, 22,
        rows.ink(chosen, false, theme.color.onSurfaceVariant)) },
  }
end

local function volume_icon()
  local s = sink()
  if not s or s.muted or s.volume <= 0 then return "volume_mute" end
  return s.volume < 0.5 and "volume_down" or "volume_up"
end

-- ------------------------------------------------------------------ output --

local channels_open = require("themes.session").keep("eva.sound.channels_open", true)

--- The default device's channels, each its own slider, under an expander that
--- remembers being shut: `prefix` names them.
local function channels_expander(prefix)
  local channels = {}
  for i = 1, MAX_CHANNELS do
    local function count() local s = sink() return s and s.channels or 0 end
    local function name()
      if count() == 2 then return i == 1 and "L" or "R" end
      return tostring(i)
    end
    channels[i] = ui.Row {
      gap = 8, align = "center",
      visible = function() return count() > 1 and i <= count() end,
      kit.text { width = 18, text = name, horizontal_alignment = "center",
        font_size = theme.size.small, font_weight = 600, color = kit.ink("lo") },
      kit.slider {
        id = prefix .. "-channel-" .. i, width = INNER - 26, height = 26,
        accessible_name = function() return "Channel " .. name() end,
        value = function() local s = sink() return s and s.volumes and s.volumes[i] or 0 end,
        set = function(v) model.set_channel(i, v) end,
      },
    }
  end
  return (disclosure.make("expander", {
    id = prefix .. "-channels", title = "Channels", width = INNER, header_height = 34,
    visible = function() local s = sink() return s ~= nil and (s.channels or 0) > 1 end,
    expanded = function() return channels_open:get() end,
    on_toggled = function(open) if open ~= channels_open:get() then channels_open:set(open) end end,
    content = ui.Column { gap = P.ROW_GAP, table.unpack(channels) },
  }))
end

local function output_section()
  return P.section { id = "sound-output", caption_id = "sound-title-output", width = w, title = "Output",
    P.row { id = "sound-output-device", width = INNER, icon = volume_icon,
      on = function() local s = sink() return s ~= nil and not s.muted end,
      title = function()
        if not available() then return "No sound server" end
        local s = sink() return s and name_of(s) or "No output selected"
      end,
      subtitle = function() local s = sink() return s and ("%d%%"):format(math.floor(s.volume * 100 + 0.5)) or "" end,
      trailing = mute_button("sound-output-mute", sink, "volume_off", "volume_up", "Mute output") },
    ui.Column { width = INNER, gap = 4, visible = available,
      kit.slider {
        id = "sound-output-volume", width = INNER, accessible_name = "Output volume",
        value = function() local s = sink() return s and s.volume or 0 end,
        set = function(v) local s = sink() if s then model.set_device_volume(s, v) end end,
        icon = volume_icon,
      },
      channels_expander("sound"),
    },
    P.row { id = "sound-input", width = INNER, icon = "mic", title = "Microphone",
      subtitle = "Inputs, level and test", trailing = P.chevron(), visible = function() return model.open_input ~= nil end,
      on_clicked = function() model.open_input() end },
    P.row { id = "sound-equalizer", width = INNER, icon = "equalizer", title = "Equalizer",
      subtitle = "Tone, presets and audiogram compensation", trailing = P.chevron(),
      on_clicked = model.open_equalizer },
    P.row { id = "sound-more", width = INNER, icon = "tune", title = "More sound settings",
      subtitle = "Preferred devices, codec, sound theme", trailing = P.chevron(),
      on_clicked = model.open_more },
  }
end

local function devices_section()
  return P.section { id = "sound-devices", caption_id = "sound-title-output-device", width = w, title = "Output device",
    ui.Repeater { as = "column", gap = P.ROW_GAP, width = INNER, model = model.devices,
      visible = function() return available() and model.devices:len() > 0 end,
      delegate = function(row) return device_row("sound-sink", row, "speaker") end },
    nothing("speaker", function() return available() and "No outputs available" or "No sound server" end,
      function() return not available() or model.devices:len() == 0 end),
  }
end

-- -------------------------------------------------------------------- apps --

local PLAYS = model.kind == "output"
local DIRECTION = PLAYS and "playback" or "record"

--- One app playing or recording: its name and what it plays with its mute, its
--- volume, and a button for each device to send it to or take it from.
local function app_row(row)
  if row.direction ~= DIRECTION then return ui.Item { width = 0, height = 0, visible = false } end
  local id = row.id
  local function live() return model.stream(row) end
  local function app_name() local s = live() return s and (s.app_name or s.binary) or "App" end
  -- Where it plays: one choice per output, one under the other, so any
  -- number of them fits the card's width.
  local routes = ui.Repeater {
    as = "column", gap = 2, width = INNER,
    model = model.devices,
    delegate = function(device)
      local function on() local s = live() return s ~= nil and s.device == device.id end
      return rows.choice {
        id = "sound-app-" .. math.floor(id) .. "-to-" .. math.floor(device.id),
        group = "sound-app-" .. math.floor(id), width = INNER, height = 36, on = on,
        on_clicked = function() model.route(row, device) end,
        kit.icon(function() return on() and "radio_button_checked" or "radio_button_unchecked" end, 18,
          rows.ink(on, false, theme.color.onSurfaceVariant), { x = 14, anchors = { vertical_center = true } }),
        kit.text { x = 44, width = INNER - 56, elide = "right", anchors = { vertical_center = true },
          text = function() return name_of(model.device(device)) end, font_size = theme.size.small,
          color = rows.ink(on, false, theme.color.onSurface) },
      }
    end,
  }
  local function muted() local s = live() return s and s.muted end
  local mute = rows.toggle {
    id = "sound-app-" .. math.floor(id) .. "-mute",
    accessible_name = function() return "Mute " .. app_name() end,
    width = 40, height = 36,
    on = function() return muted() == true end, icon_on = PLAYS and "volume_off" or "mic_off",
    icon_off = PLAYS and "volume_up" or "mic",
    on_clicked = function() if live() then model.toggle_stream(row) end end,
  }
  return ui.Column { width = INNER, gap = 4,
    P.row { width = INNER, icon = PLAYS and "music_note" or "mic", title = app_name,
      on = function() return muted() ~= true end,
      subtitle = function() local s = live() return s and s.media_name or "" end,
      trailing = mute },
    kit.slider {
      id = "sound-app-" .. math.floor(id) .. "-volume", width = INNER, height = 30,
      accessible_name = function() return app_name() .. " volume" end,
      value = function() local s = live() return s and s.volume or 0 end,
      set = function(v) model.set_stream_volume(row, v) end,
    },
    kit.text { x = 0, width = INNER, text = PLAYS and "Play on" or "Record from", font_size = theme.size.small,
      color = kit.ink("lo") },
    routes,
    ui.Item { width = INNER, height = 6 },
  }
end

local function apps_section()
  local function playing()
    if not available() then return 0 end
    local n, streams = 0, model.streams
    for i = 1, streams:len() do
      if streams:get(i).direction == DIRECTION then n = n + 1 end
    end
    return n
  end
  return P.section { id = "sound-apps", caption_id = "sound-title-apps", width = w,
    title = PLAYS and "Apps" or "Recording",
    ui.Repeater { as = "column", gap = P.ROW_GAP, width = INNER, model = model.streams,
      visible = function() return playing() > 0 end, delegate = app_row },
    nothing(PLAYS and "music_off" or "mic_off", function()
      if not available() then return "No sound server" end
      return PLAYS and "Nothing playing" or "Nothing recording"
    end, function() return playing() == 0 end),
  }
end

-- ------------------------------------------------------------------ extras --

--- The devices wanted first: each with a way up and off the list, and a way
--- to add the one in use.
local function preferred_section()
  local F = require("themes.layouts.form")
  local function count() return #model.preferred() end
  local list = F.list(INNER, "sound-preferred-" .. model.kind .. "-", count, function(index, width)
    local function name() return model.preferred()[index] or "" end
    return P.row { id = "sound-prefer-" .. model.kind .. "-" .. index, width = width, icon = "star",
      title = function() return model.device_name(name()) end,
      subtitle = function() return index == 1 and "Wanted most" or ("Choice %d"):format(index) end,
      trailing = ui.Row { gap = theme.space.xs, align = "center",
        P.button { id = "sound-prefer-up-" .. model.kind .. "-" .. index, label = "Up", accessible_name = "Move this device up",
          visible = function() return index > 1 end, on_clicked = function() model.raise_preferred(index) end },
        P.button { id = "sound-prefer-drop-" .. model.kind .. "-" .. index, label = "Remove", accessible_name = "Stop preferring this device",
          on_clicked = function() model.drop_preferred(index) end } } }
  end, "None: the system decides", 6)
  return P.section { id = "sound-preferred-" .. model.kind, width = w, title = "Preferred devices",
    list,
    F.note(INNER, "When one of these appears and outranks the device in use, sound moves to it."),
    P.button { id = "sound-prefer-add-" .. model.kind, icon = "add", label = "Prefer the device in use", width = INNER,
      on_clicked = model.prefer_current },
  }
end

--- A card's profile choices: a Bluetooth headset's codec, or a sound card's
--- mode.
local function card_block(card_of, prefix, index)
  local rows = {}
  for slot = 1, 6 do
    local function profile() local card = card_of() return card and card.profiles[slot] end
    rows[#rows + 1] = P.row { id = prefix .. "-" .. index .. "-" .. slot, width = INNER,
      visible = function() return profile() ~= nil end,
      icon = function() local card, p = card_of(), profile() return (card and p and card.active == p.key) and "radio_button_checked" or "radio_button_unchecked" end,
      on = function() local card, p = card_of(), profile() return card ~= nil and p ~= nil and card.active == p.key end,
      title = function() local p = profile() return p and (p.codec or p.name) or "" end,
      subtitle = function() local p = profile() return p and p.codec and p.name or "" end,
      on_clicked = function() local card, p = card_of(), profile() if card and p then model.set_profile(card, p) end end }
  end
  return ui.Column { width = INNER, gap = P.ROW_GAP, visible = function() return card_of() ~= nil end,
    kit.subtitle { width = INNER, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
      text = function() local card = card_of() return card and card.title or "" end },
    table.unpack(rows) }
end

local function cards_section(title, id, list, prefix)
  local spec = { id = id, width = w, title = title, visible = function() return #list() > 0 end }
  for index = 1, 3 do spec[#spec + 1] = card_block(function() return list()[index] end, prefix, index) end
  return P.section(spec)
end

local function theme_section()
  local F = require("themes.layouts.form")
  return P.section { id = "sound-theme", width = w, title = "Sound theme", visible = function() return #model.themes() > 0 end,
    (F.picker { id = "sound-theme-list", width = INNER, placeholder = "Search sound themes", max = 5, items = model.themes,
      row = function(item)
        return { icon = "music_note", title = item.name, on = item.key == model.theme(),
          subtitle = item.key == model.theme() and "In use, press to hear it" or "Press to use it",
          pick = function()
            if item.key == model.theme() then model.preview(item) else model.set_theme(item) end
          end }
      end }),
    require("themes.layouts.form").status("sound-theme-status", INNER, model),
  }
end

--- The sound server itself, restarted for what only that fixes.
local function server_section()
  return P.section { id = "sound-server", width = w, title = "Sound server",
    P.row { id = "sound-restart", width = INNER, icon = "restart_alt", title = "Restart the sound server",
      subtitle = function()
        local said = model.restarted()
        return said ~= "" and said or "PipeWire and WirePlumber, started again"
      end,
      trailing = P.button { id = "sound-restart-button", label = "Restart", on_clicked = model.restart } },
  }
end

-- ------------------------------------------------------------------- input --

--- The level as the microphone hears it, while a test runs.
local function test_section()
  local F = require("themes.layouts.form")
  local testing = function() return model.testing:get() end
  return P.section { id = "sound-test", width = w, title = "Test", visible = available,
    P.row { id = "sound-test-row", width = INNER, icon = "graphic_eq", on = testing,
      title = function() return testing() and model.verdict() or "Test the microphone" end,
      subtitle = function() return testing() and "Speak as you normally would" or "Shows how loud it hears you" end,
      trailing = P.button { id = "sound-test-button", label = function() return testing() and "Stop" or "Start" end,
        tone = function() return testing() and "primary" or nil end, on_clicked = function() model.test(not testing()) end } },
    ui.Item { id = "sound-test-level", width = INNER, height = theme.space.m, visible = testing,
      kit.fill { width = INNER, height = theme.space.m, color = kit.signal("accent"),
        value = function() return model.level:get() end } },
    model.message and F.status("sound-test-status", INNER, model) or nil,
  }
end

local function input_section()
  return P.section { id = "sound-input", caption_id = "sound-title-input", width = w, title = "Input",
    P.row { id = "sound-input-device", width = INNER,
      icon = function() local s = source() return (s and s.muted) and "mic_off" or "mic" end,
      on = function() local s = source() return s ~= nil and not s.muted end,
      title = function()
        if not available() then return "No sound server" end
        local s = source() return s and name_of(s) or "No input selected"
      end,
      subtitle = function() local s = source() return s and ("%d%%"):format(math.floor(s.volume * 100 + 0.5)) or "" end,
      trailing = mute_button("sound-input-mute", source, "mic_off", "mic", "Mute input") },
    kit.slider {
      id = "sound-input-volume", width = INNER, height = 36, accessible_name = "Input volume", visible = available,
      value = function() local s = source() return s and s.volume or 0 end,
      set = function(v) local s = source() if s then model.set_device_volume(s, v) end end,
      icon = function() local s = source() return (s and s.muted) and "mic_off" or "mic" end,
    },
    channels_expander("sound-input"),
  }
end

local function inputs_section()
  return P.section { id = "sound-sources", width = w, title = "Input device",
    ui.Repeater { as = "column", gap = P.ROW_GAP, width = INNER, model = model.devices,
      visible = function() return available() and model.devices:len() > 0 end,
      delegate = function(row)
        -- A monitor is an output's echo, not a microphone.
        if tostring(row.name or ""):match("%.monitor$") then
          return ui.Item { width = 0, height = 0, visible = false }
        end
        return device_row("sound-source", row, "mic")
      end },
    nothing("mic_off", function() return available() and "No inputs available" or "No sound server" end,
      function() return not available() or model.devices:len() == 0 end),
  }
end

if more then
  return ui.Item { id = "sound-more-page", width = w, height = h, clip = true,
    P.page { id = "sound-more-scroll", width = w, height = h, preferred_section(),
      cards_section("Bluetooth codec", "sound-codec", model.bluetooth_cards, "sound-codec"),
      cards_section("Card profile", "sound-profile", model.other_cards, "sound-profile"), theme_section(),
      model.restart and server_section() or nil } }
end

local function touch_section()
  local haptics = require("haptics")
  return P.section { id = "sound-touch", width = w, title = "Touch", visible = haptics.present,
    P.row { id = "sound-haptics", width = INNER, icon = "vibration", title = "Touch feedback",
      subtitle = "A buzz on keys, gestures and tiles", on = haptics.on,
      trailing = P.switch { id = "sound-haptics-switch", name = "Touch feedback", on = haptics.on,
        on_toggled = haptics.set } },
  }
end

if model.kind == "output" then
  return ui.Item { id = "sound-page", width = w, height = h, clip = true,
    P.page { id = "sound-scroll", width = w, height = h, output_section(), devices_section(), apps_section(),
      touch_section() } }
end
return ui.Item { id = "microphone-page", width = w, height = h, clip = true,
  P.page { id = "microphone-scroll", width = w, height = h, input_section(), test_section(), inputs_section(),
    apps_section(), model.preferred and preferred_section() or nil } }
end

return M
