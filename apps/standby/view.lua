-- eva-standby's screen: always dark, a dial whose hands are layers of one distance
-- field meeting at the hub, the digits beside it, the world and the next alarm a
-- swipe away, and all of it deep red at night. Its colours are tones of the palette.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local controls = require("common.controls")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

local ROWS = 8
local DOT = S.s
local DOT_GAP = S.m
local FOOT = S.TARGET + S.l
local MOVE = theme.spring.effects

local NIGHT_CHROMA = 90

local function night() return model.night:get() end
-- The palette's red at `tone`, as strong as the screen can show it.
local function red(tone) return morf.color.hct((C.error:hct()), NIGHT_CHROMA, tone) end
local function back() return night() and red(2) or C.surface:with { t = 4 } end
local function ink() return night() and red(38) or C.onSurface:with { t = 92 } end
local function low() return night() and red(24) or C.onSurface:with { t = 62 } end
local function accent() return night() and red(45) or C.primary:with { t = 78 } end

local function words(props)
  props.behavior = { color = MOVE }
  return kit.text(props)
end

-- A hand: an arm that turns about the dial's centre, and the field's layer on it.
local function hand(side, id, length, thick, tail, angle, spring)
  local arm = ui.Item {
    id = id .. "-arm",
    x = function() return (side() - side() * thick) / 2 end,
    y = function() return side() * (0.5 - length) end,
    width = function() return side() * thick end,
    height = function() return side() * (length + tail) end,
  }
  local pivot = ui.Item { id = id, width = side, height = side, rotation = angle, behavior = { rotation = spring }, arm }
  local layer = ui.SdfShape {
    id = id .. "-layer", shape = "box", track = arm, operation = "smooth_union",
    radius = function() return kit.round(side() * thick / 2) end,
  }
  return pivot, layer
end

-- A hand's angle, starting within a turn of twelve.
local function turned(which)
  local start = select(which, model.angles(0, 0, model.seconds:get()))
  return function()
    return start % 360 + select(which, model.angles(0, 0, model.seconds:get())) - start
  end
end

local function dial(side)
  local hours, minutes, seconds = turned(1), turned(2), turned(3)
  local hour_arm, hour = hand(side, "standby-hour", 0.25, 0.034, 0, hours, theme.spring.slow)
  local minute_arm, minute = hand(side, "standby-minute", 0.38, 0.022, 0, minutes, theme.spring.slow)
  local second_arm, second = hand(side, "standby-second", 0.42, 0.008, 0.08, seconds, theme.spring.spatial)
  return ui.Item {
    id = "standby-dial", width = side, height = side,
    ui.Path {
      id = "standby-ticks", anchors = { fill = true }, view_box = { 0, 0, 100, 100 },
      d = morf.geometry.ticks(50, 50, 47, 49, { count = 60, major = 5, major_r0 = 44 }),
      fill_color = "transparent", stroke_width = 0.5, stroke_color = low, stroke_cap = "round",
    },
    hour_arm, minute_arm, second_arm,
    ui.Sdf {
      id = "standby-hands", anchors = { fill = true }, fill_color = ink, blend = S.m, behavior = { fill_color = MOVE },
      ui.SdfShape {
        shape = "box", radius = function() return kit.round(side() * 0.03) end,
        x = function() return side() * 0.47 end, y = function() return side() * 0.47 end,
        width = function() return side() * 0.06 end, height = function() return side() * 0.06 end,
      },
      hour, minute,
    },
    ui.Sdf {
      id = "standby-sweep", anchors = { fill = true }, fill_color = accent, blend = S.s, behavior = { fill_color = MOVE },
      ui.SdfShape {
        shape = "box", radius = function() return kit.round(side() * 0.014) end,
        x = function() return side() * 0.486 end, y = function() return side() * 0.486 end,
        width = function() return side() * 0.028 end, height = function() return side() * 0.028 end,
      },
      second,
    },
  }
end

local function clock_page(w, h)
  local function wide() return w() > h() end
  local function side()
    if wide() then return math.max(1, math.floor(math.min(h() * 0.82, w() * 0.46))) end
    return math.max(1, math.floor(math.min(w() * 0.8, h() * 0.5)))
  end
  local function size() return math.floor(wide() and math.min(h() * 0.26, w() * 0.15) or w() * 0.2) end
  local function text_x() return wide() and w() / 2 or 0 end
  local function text_w() return wide() and w() / 2 or w() end
  local function text_h() return size() * 1.4 + S.TARGET end
  return ui.Item {
    id = "standby-clock", width = w, height = h,
    ui.Item {
      x = function() return wide() and (w() / 2 - side()) / 2 or (w() - side()) / 2 end,
      y = function() return wide() and (h() - side()) / 2 or (h() - side() - text_h()) / 3 end,
      width = side, height = side, dial(side),
    },
    ui.Column {
      x = text_x, width = text_w, gap = S.xs, align = "center",
      y = function()
        if wide() then return (h() - text_h()) / 2 end
        return (h() - side() - text_h()) * 2 / 3 + side()
      end,
      words {
        id = "standby-time", font_size = size, font_weight = 200, color = ink,
        text = function() return morf.time.minute_clock:get() end,
      },
      words {
        id = "standby-date", font_size = theme.size.large, color = low,
        text = function()
          morf.time.minute_clock:get()
          return morf.time.format("%A %-d %B")
        end,
      },
    },
  }
end

local function world_page(w, h)
  local function cities() return model.world:get() end
  local row_h = S.TARGET * 2
  local function list_h() return math.max(1, math.min(h(), #cities() * (row_h + S.xxs))) end
  return ui.Item {
    id = "standby-world", width = w, height = h,
    words {
      id = "standby-world-empty", anchors = { center_in = true }, font_size = theme.size.large, color = low,
      visible = function() return #cities() == 0 end, text = "Add cities in Clock",
    },
    ui.Item {
      width = w, height = list_h, y = function() return (h() - list_h()) / 2 end,
      controls.list {
        id = "standby-city", width = w, height = list_h, count = ROWS, row_height = row_h, items = cities,
        build = function(index, item)
          local function reading()
            local entry = item()
            if not entry then return "", "" end
            return model.city_time(entry)
          end
          return ui.Item {
            width = w, height = row_h,
            ui.Column {
              anchors = { vertical_center = true }, gap = S.xxs,
              words {
                id = "standby-city-name-" .. index, font_size = theme.size.large, color = ink,
                text = function() local entry = item() return entry and entry.name or "" end,
              },
              words {
                id = "standby-city-apart-" .. index, font_size = theme.size.small, color = low,
                text = function() local _, apart = reading() return apart end,
              },
            },
            words {
              id = "standby-city-time-" .. index, anchors = { right = true, vertical_center = true },
              font_size = theme.size.extra * 1.6, font_weight = 200, color = ink,
              text = function() local time = reading() return time end,
            },
          }
        end,
      },
    },
  }
end

local function alarm_page(w, h)
  local function next_one() return model.next_alarm() end
  local function size() return math.floor(math.min(h() * 0.3, w() * 0.2)) end
  return ui.Item {
    id = "standby-alarm", width = w, height = h,
    words {
      id = "standby-alarm-empty", anchors = { center_in = true }, font_size = theme.size.large, color = low,
      visible = function() return next_one() == nil end, text = "Nothing set to ring",
    },
    ui.Column {
      anchors = { center_in = true }, gap = S.s, align = "center",
      visible = function() return next_one() ~= nil end,
      kit.icon("alarm", S.xxl, accent),
      words {
        id = "standby-alarm-time", font_size = size, font_weight = 200, color = ink,
        text = function() local one = next_one() return one and one.time or "" end,
      },
      words {
        id = "standby-alarm-label", font_size = theme.size.large, color = low,
        text = function()
          local one = next_one()
          return one and (one.label .. " · " .. one.left) or ""
        end,
      },
    },
  }
end

-- The views' place, a bead that runs between dots of one field.
local function dots()
  local count = #model.VIEWS
  local function at(index) return (index - 1) * (DOT + DOT_GAP) end
  local width = count * DOT + (count - 1) * DOT_GAP
  local field = { id = "standby-dots", anchors = { fill = true }, fill_color = low, blend = S.s, behavior = { fill_color = MOVE } }
  for index = 1, count do
    field[index] = ui.SdfShape { shape = "box", radius = kit.round(DOT / 2), x = at(index), y = 0, width = DOT, height = DOT }
  end
  return ui.Item {
    id = "standby-place", width = width, height = DOT,
    ui.Sdf(field),
    ui.Sdf {
      id = "standby-bead", anchors = { fill = true }, fill_color = ink, behavior = { fill_color = MOVE },
      ui.SdfShape {
        id = "standby-bead-layer", shape = "box", radius = kit.round(DOT / 2), width = DOT, height = DOT, y = 0,
        x = function() return at(model.view:get()) end, behavior = { x = theme.spring.spatial },
      },
    },
  }
end

local function foot_button(id, icon, name, action, lit)
  local area = kit.action {
    id = id, accessible_name = name, width = S.TARGET, height = S.TARGET, cursor = "pointer", on_clicked = action,
    kit.icon(icon, S.xl, function() return (lit and lit()) and accent() or low() end, { anchors = { center_in = true } }),
  }
  return area
end

--- The whole of the screen.
function M.root()
  -- The root, before what is sized from it.
  local root = ui.Rect { id = "standby-root", anchors = { fill = true }, color = back, behavior = { color = MOVE } }
  local function w() return math.max(1, root.layout_width or 1) end
  local function h() return math.max(1, root.layout_height or 1) end
  local function page_h() return math.max(1, h() - FOOT) end
  local function page_w() return math.max(1, w() - 2 * S.xl) end
  local pages = { "clock", "world", "alarm" }
  local builders = { clock = clock_page, world = world_page, alarm = alarm_page }
  local row = {
    id = "standby-pages", height = page_h,
    width = function() return page_w() * #pages end,
    x = function() return -(model.view:get() - 1) * page_w() end,
    behavior = { x = theme.spring.slow },
  }
  for index, name in ipairs(pages) do
    row[index] = ui.Item {
      x = function() return (index - 1) * page_w() end, width = page_w, height = page_h,
      opacity = function() return model.view:get() == index and 1 or 0 end,
      behavior = { opacity = theme.spring.effects },
      builders[name](page_w, page_h),
    }
  end
  -- A shift of a few pixels each minute.
  local function drift(axis)
    local minute = tonumber(morf.time.minute_clock:get():match(":(%d+)")) or 0
    return ((minute * axis) % 5 - 2) * S.xxs
  end
  ui.reparent(ui.Item {
    x = S.xl, width = page_w, height = page_h, clip = true,
    translate_x = function() return drift(3) end, translate_y = function() return drift(7) end,
    behavior = { translate_x = theme.spring.slow, translate_y = theme.spring.slow },
    ui.Item(row),
  }, root)
  ui.reparent(ui.MouseArea {
    id = "standby-area", anchors = { fill = true }, focus = true,
    on_swiped = function(direction)
      if direction == "left" then model.step(1)
      elseif direction == "right" then model.step(-1) end
    end,
    on_key_pressed = function(_, _, _, _, name)
      if name == "Right" then model.step(1)
      elseif name == "Left" then model.step(-1)
      elseif name == "n" then model.set_night(not night())
      elseif name == "Escape" or name == "q" then model.quit()
      else return false end
      return true
    end,
  }, root)
  ui.reparent(ui.Item {
    y = page_h, width = w, height = FOOT,
    ui.Item {
      x = function() return (w() - ((DOT + DOT_GAP) * #model.VIEWS - DOT_GAP)) / 2 end, y = S.s,
      width = (DOT + DOT_GAP) * #model.VIEWS - DOT_GAP, height = DOT, dots(),
    },
    ui.Item {
      x = S.l, y = S.xs, width = S.TARGET, height = S.TARGET,
      foot_button("standby-night", "bedtime", "Night mode", function() model.set_night(not night()) end, night),
    },
    ui.Item {
      anchors = { right = true, right_margin = S.l }, y = S.xs, width = S.TARGET, height = S.TARGET,
      foot_button("standby-close", "close", "Close", model.quit),
    },
    words {
      id = "standby-power", x = S.TARGET + S.xl, y = S.xl, height = S.l, elide = "right",
      width = function() return math.max(1, w() - 2 * (S.TARGET + S.xl)) end,
      horizontal_alignment = "center", font_size = theme.size.small, color = low,
      text = function() return model.message:get() ~= "" and model.message:get() or model.power:get() end,
    },
  }, root)
  return root
end

return M
