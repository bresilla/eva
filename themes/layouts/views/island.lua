-- The island's look: a box tracked by a layer of the frame's field, so its seam
-- is the frame's, and everything it does is that box changing size on a spring.
-- A press opens it; a right press walks its faces.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local S = theme.space
local V = {}

local REST_W, REST_H = S.xxl * 5, S.xxl
local OPEN_W, OPEN_H = S.xxl * 13, S.xxl * 3

local function line(props)
  props.color = props.color or kit.ink("hi")
  props.font_size = props.font_size or theme.size.small
  return kit.text(props)
end

--- `model` is shell/island.lua, `desk` the frame's desk box. Returns
--- `{ node, shape, panel }`.
function V.build(model, desk)
  local media = require("media_state")
  local weather = require("weather_model").new { opened = function() return model.enabled() end }
  local function opened() return model.open:get() end
  local function width() return opened() and OPEN_W or REST_W end
  local function height() return opened() and OPEN_H or REST_H end
  media.hear(function() return model.showing() == "media" and opened() end)

  local function clock_text()
    morf.time.minute_clock:get()
    return morf.time.format("%H:%M")
  end
  local function words()
    local face = model.showing()
    if face == "media" then
      local title = media.field("title")()
      return title ~= "" and title or "Nothing playing"
    elseif face == "weather" then
      return weather.temperature(weather.now().temperature, true) .. " " .. weather.place()
    end
    return clock_text()
  end
  local function icon()
    local face = model.showing()
    if face == "media" then return media.playing() and "graphic_eq" or "music_note" end
    if face == "weather" then local w = weather.now() return weather.symbol(w.code, w.is_day) end
    return "schedule"
  end

  -- Its resting line and its opened face cross over as the box springs between
  -- them; only the face on show takes a press.
  local fade = { duration = theme.duration.small, easing = theme.ease.standard }
  local rest = ui.Row { anchors = { center_in = true }, gap = S.xs, align = "center",
    opacity = function() return opened() and 0 or 1 end, behavior = { opacity = fade },
    kit.icon(icon, 18, kit.ink("accent")),
    line { id = "island-words", text = words, width = REST_W - S.xxl - S.l, elide = "right" } }

  local function step(id, glyph, action)
    return kit.action { id = id, accessible_name = id, width = S.TARGET, height = S.TARGET, cursor = "pointer",
      enabled = opened, on_clicked = function() media.control(action) end,
      kit.icon(glyph, 24, kit.ink("hi"), { anchors = { center_in = true }, fill = true }) }
  end
  local wide = ui.Item { anchors = { fill = true, margins = S.s },
    opacity = function() return opened() and 1 or 0 end, behavior = { opacity = fade },
    ui.Column { anchors = { vertical_center = true }, gap = S.xxs,
      line { id = "island-title", text = words, font_size = theme.size.normal, font_weight = 600,
        width = OPEN_W - S.TARGET * 3 - S.xl, elide = "right" },
      line { text = function()
        if model.showing() == "media" then return media.field("artist")() end
        return morf.time.format("%A, %B %-d")
      end, color = kit.ink("lo"), width = OPEN_W - S.TARGET * 3 - S.xl, elide = "right" } },
    ui.Row { anchors = { right = true, vertical_center = true }, visible = function() return model.showing() == "media" end,
      step("island-previous", "skip_previous", "previous"),
      step("island-toggle", function() return media.playing() and "pause" or "play_arrow" end, "play_pause"),
      step("island-next", "skip_next", "next") },
  }

  local panel = ui.Item { id = "island",
    width = width, height = height,
    x = function() local _, _, w = desk() return (w - width()) / 2 end,
    y = theme.BORDER - S.xxs,
    behavior = { width = theme.spring.spatial, height = theme.spring.spatial, x = theme.spring.spatial },
    stretch = theme.stretch and theme.stretch.blob or nil,
    ui.MouseArea { id = "island-press", anchors = { fill = true }, z = -1, accepted_buttons = { "left", "right" },
      on_clicked = function(_, _, _, _, button)
        if button == "right" then model.cycle() else model.toggle() end
      end },
    rest, wide,
  }
  -- A finger down opens it, up shuts it, and across walks its faces; it leans
  -- with the finger and springs home.
  panel.on_panned = require("themes.swipe_dismiss").new { id = "island", node = panel, axes = { x = true, y = true },
    stays = true, distance = S.xl,
    ways = function() return { left = true, right = true, [opened() and "up" or "down"] = true } end,
    on_dismiss = function(way)
      if way == "left" or way == "right" then model.cycle() else model.toggle() end
    end }.on_panned
  local shape = ui.SdfShape { id = "island-background", shape = "box", operation = "smooth_union", blend_group = 900,
    track = panel, radius = function() return kit.round(opened() and S.xl or S.m) end,
    behavior = { radius = theme.spring.spatial } }
  return { node = panel, shape = shape, panel = panel }
end

return V
