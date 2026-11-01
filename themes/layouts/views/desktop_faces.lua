-- What each of StandBy's widgets shows. A face is built once, for a tile that is
-- `ctx.w()` x `ctx.h()`, and reads `ctx.small()` for its size, `ctx.ink()` for
-- ink that stands out from the picture behind it and `ctx.soft()` for its second
-- ink. Data comes from the same models the panels read.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local config = require("config")
local C, S = theme.color, theme.space
local F = {}

local function line(ctx, props)
  props.color = props.color or ctx.ink
  props.font_size = props.font_size or theme.size.normal
  return kit.text(props)
end

-- ------------------------------------------------------------------ clock --

-- A digit that melts into the next: an outline in a field, walked between two
-- glyphs by the engine.
local function digit(ctx, id, width, height, weight)
  local shape = ui.SdfShape { id = id, glyph = "0", glyph_morph_to = "0", font_family = theme.font, font_weight = weight,
    anchors = { fill = true } }
  local field = ui.Sdf { width = width, height = height, fill_color = ctx.ink, shape }
  local shown = "0"
  local running
  local function set(value)
    if value == shown then return end
    if running then running:stop() end
    shape.glyph, shape.glyph_morph_to, shape.morph_progress = shown, value, 0
    shown = value
    if config.get("appearance.reduce_motion") == true then
      shape.glyph, shape.morph_progress = value, 0
      return
    end
    local bounce = theme.bounce.spatial
    running = morf.animation.play {
      { node = shape, property = "morph_progress", to = 1, duration = bounce.duration, easing = bounce.easing },
      on_finished = function()
        running = nil
        shape.glyph, shape.morph_progress = value, 0
      end,
    }
  end
  return field, set
end

local function hand(ctx, length, thick, turn, color)
  return ui.Item { anchors = { center_in = true }, width = thick, height = 2 * length,
    rotation = turn, behavior = { rotation = theme.spring.spatial },
    ui.Rect { width = thick, height = length, radius = thick / 2, color = color } }
end

function F.clock(ctx, model)
  local S_W, S_H = 56, 96
  local digits, setters = {}, {}
  local row = { anchors = { center_in = true }, gap = S.xs, align = "center", visible = function() return not ctx.small() end }
  for i = 1, 4 do
    local field, set = digit(ctx, "desktop-clock-digit-" .. i, S_W, S_H, 300)
    digits[i], setters[i] = field, set
    if i == 3 then
      row[#row + 1] = line(ctx, { id = "desktop-clock-colon", text = ":", font_size = 64, font_weight = 300 })
    end
    row[#row + 1] = field
  end
  local node = ui.Item { anchors = { fill = true } }
  morf.effect("eva.desktop.clock", function()
    morf.time.minute_clock:get()
    local text = model.clock_text():gsub(":", "")
    for i = 1, 4 do setters[i](text:sub(i, i)) end
  end, { owner = node })
  local function minutes()
    morf.time.minute_clock:get()
    return tonumber(morf.time.format("%M")) or 0
  end
  local function hour_turn() return ((tonumber(morf.time.format("%H")) or 0) % 12 + minutes() / 60) * 30 end
  local function minute_turn() return minutes() * 6 end
  ui.reparent(ui.Row(row), node)
  ui.reparent(ui.Item { anchors = { center_in = true }, width = 144, height = 144, visible = ctx.small,
    ui.Path { anchors = { fill = true }, view_box = { 0, 0, 144, 144 }, fill_color = "transparent", stroke_width = 2,
      stroke_color = ctx.soft, stroke_cap = "round",
      d = morf.geometry.ticks(72, 72, 62, 70, { count = 60, major = 5, major_r0 = 56 }) },
    hand(ctx, 40, 6, hour_turn, ctx.ink),
    hand(ctx, 58, 4, minute_turn, function() return C.primary end),
  }, node)
  return node
end

-- ---------------------------------------------------------------- weather --

function F.weather(ctx)
  local weather = require("weather_model").new { opened = function() return true end }
  return ui.Item { anchors = { fill = true },
    ui.Column { gap = S.xs,
      kit.icon(function() local w = weather.now() return weather.symbol(w.code, w.is_day) end, 44, ctx.ink),
      line(ctx, { id = "desktop-weather-now", font_size = 32, font_weight = 500,
        text = function() return weather.temperature(weather.now().temperature, true) end }),
      line(ctx, { text = function() return weather.place() end, color = ctx.soft, font_size = theme.size.small,
        width = function() return ctx.w() end, elide = "right" }),
    },
    ui.Column { anchors = { right = true, top = true }, gap = S.xs, visible = function() return not ctx.small() end,
      line(ctx, { text = function() return "Humidity " .. weather.humidity() end, color = ctx.soft, font_size = theme.size.small }),
      line(ctx, { text = function() return "Wind " .. weather.wind() end, color = ctx.soft, font_size = theme.size.small }),
      line(ctx, { font_size = theme.size.small, color = ctx.soft, text = function()
        local today = weather.today()
        return weather.temperature(today.low, true) .. " / " .. weather.temperature(today.high, true)
      end }),
    },
  }
end

-- ----------------------------------------------------------------- system --

local function meter(ctx, id, name, value, history)
  return ui.Item { width = function() return ctx.small() and ctx.w() or (ctx.w() - S.m) / 2 end, height = function() return ctx.h() end,
    ui.Path { id = id .. "-history", anchors = { left = true, right = true, bottom = true }, height = function() return ctx.h() - 56 end,
      view_box = { 0, 0, 160, 80 }, series = history, plot = { kind = "area", smooth = true, width = 160, height = 80, bottom = 0, top = 100 },
      fill_color = function() return C.primary:alpha(0.35) end, stroke_color = function() return C.primary end, stroke_width = 2 },
    ui.Column { gap = 0,
      line(ctx, { id = id, font_size = 28, font_weight = 600, text = function() return ("%d%%"):format(math.floor(value() + 0.5)) end }),
      line(ctx, { text = name, color = ctx.soft, font_size = theme.size.small }),
    },
  }
end

function F.system(ctx)
  local sysinfo = require("lib.services.sysinfo")
  local function cpu() return tonumber(sysinfo.cpu().usage) or 0 end
  local function memory() return tonumber(sysinfo.memory().percent) or 0 end
  return ui.Row { anchors = { fill = true }, gap = S.m,
    meter(ctx, "desktop-system-cpu", "Processor", cpu, sysinfo.channel("cpu").id),
    ui.Item { visible = function() return not ctx.small() end, width = function() return ctx.small() and 1e-3 or (ctx.w() - S.m) / 2 end,
      height = function() return ctx.h() end,
      meter(ctx, "desktop-system-memory", "Memory", memory, sysinfo.channel("memory").id) },
  }
end

-- ------------------------------------------------------------------ media --

local function transport(ctx, media, id, icon, action)
  local press = kit.action { id = id, accessible_name = id, width = S.TARGET, height = S.TARGET, cursor = "pointer",
    on_clicked = function() media.control(action) end,
    kit.icon(icon, 24, ctx.ink, { anchors = { center_in = true }, fill = true }) }
  return press
end

function F.media(ctx)
  local media = require("media_state")
  local art = function() return require("lib.util.remote").file(media.active().art_url) end
  local side = function() return ctx.small() and ctx.w() or ctx.h() end
  return ui.Item { anchors = { fill = true },
    ui.ClipRect { width = side, height = function() return ctx.small() and ctx.h() - S.TARGET - S.xs or ctx.h() end, radius = kit.round(S.m),
      color = function() return C.surfaceContainerHigh end,
      ui.Image { id = "desktop-media-art", anchors = { fill = true }, fill_mode = "preserve_aspect_crop", source = art,
        visible = function() return art() ~= "" end },
      kit.icon("music_note", 40, kit.ink("lo"), { anchors = { center_in = true }, visible = function() return art() == "" end }),
    },
    ui.Column { x = function() return ctx.small() and 0 or ctx.h() + S.m end, y = 0, gap = S.xxs,
      visible = function() return not ctx.small() end,
      line(ctx, { id = "desktop-media-title", font_weight = 600, width = function() return math.max(1, ctx.w() - ctx.h() - S.m) end, elide = "right",
        text = function() local t = media.field("title")() return t ~= "" and t or "Nothing playing" end }),
      line(ctx, { color = ctx.soft, font_size = theme.size.small, width = function() return math.max(1, ctx.w() - ctx.h() - S.m) end, elide = "right",
        text = media.field("artist") }),
    },
    ui.Row { anchors = { right = true, bottom = true }, gap = S.xs,
      transport(ctx, media, "desktop-media-previous", "skip_previous", "previous"),
      transport(ctx, media, "desktop-media-toggle", function() return media.playing() and "pause" or "play_arrow" end, "play_pause"),
      transport(ctx, media, "desktop-media-next", "skip_next", "next"),
    },
  }
end

-- --------------------------------------------------------------- calendar --

function F.calendar(ctx)
  local today = function()
    morf.time.minute_clock:get()
    return morf.time.format("%Y-%m-%d")
  end
  local small = ui.Column { anchors = { center_in = true }, gap = 0, align = "center", visible = ctx.small,
    line(ctx, { text = function() morf.time.minute_clock:get() return morf.time.format("%a") end, color = function() return C.primary end, font_weight = 600 }),
    line(ctx, { id = "desktop-calendar-day", font_size = 64, font_weight = 300, text = function() morf.time.minute_clock:get() return morf.time.format("%-d") end }),
    line(ctx, { text = function() morf.time.minute_clock:get() return morf.time.format("%B") end, color = ctx.soft, font_size = theme.size.small }),
  }
  local large = ui.Item { anchors = { fill = true }, visible = function() return not ctx.small() end,
    (require("themes.kit.composites").calendar { id = "desktop-calendar", width = 328, value = today, cell_height = 36 }) }
  return ui.Item { anchors = { fill = true }, small, large }
end

return F
