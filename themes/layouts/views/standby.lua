-- StandBy's face: a great clock, the folder's pictures changing through the
-- shell's transitions, two stacks of widgets, eva-clock's cities, or the next
-- thing to ring. A swipe turns the view; a touch shows the way out. At night the
-- ink is a dim red, and everything drifts a little so nothing burns in.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local config = require("config")
local P = require("themes.layouts.page")
local S = theme.space

local V = {}
local SWIPE = 64
local PHOTO_MS = 20000

--- The whole-screen node; `model` is shell/standby_model.lua.
function V.build(model)
  local faces = require("themes").view("desktop_faces")
  local function size()
    morf.window.screens_revision()
    local s = (morf.screens or {})[1] or {}
    return s.width or 1280, s.height or 800
  end
  local function ink()
    if model.night() then return morf.color("#b3261e") end
    return morf.color("#f4f4f6")
  end
  local function soft() return ink():alpha(0.62) end
  local function ctx(w, h, small)
    return { small = function() return small end, ink = ink, soft = soft,
      w = function() return w end, h = function() return h end }
  end

  -- ---------------------------------------------------------------- clock --
  local function clock_view()
    local sw, sh = size()
    local scale = math.min(3.6, math.max(1.6, math.min(sw / 400, sh / 240)))
    return ui.Item { id = "standby-clock", anchors = { fill = true }, visible = function() return model.view:get() == "clock" end,
      ui.Item { anchors = { center_in = true }, width = 360, height = 176, scale = scale,
        faces.clock(ctx(360, 176, false), model) },
      kit.text { id = "standby-date", anchors = { bottom = true, horizontal_center = true, bottom_margin = S.xxl },
        color = soft, font_size = theme.size.large,
        text = function() morf.time.minute_clock:get() return morf.time.format("%A, %B %-d") end },
    }
  end

  -- --------------------------------------------------------------- photos --
  local photos = require("themes.wallpaper_swap").new { id = "standby-photo" }
  local index = 0
  local function next_photo()
    local list = require("wallpaper_model").pictures()
    if #list == 0 then return end
    index = index % #list + 1
    local sw, sh = size()
    photos.show(list[index], { kind = "random", width = sw, height = sh, time = 1600, soft = 40,
      ease = theme.ease.emphasized, instant = config.get("appearance.reduce_motion") == true })
  end
  local photo_view = ui.Item { id = "standby-photos", anchors = { fill = true },
    visible = function() return model.view:get() == "photos" end,
    photos.node,
    ui.Rect { anchors = { fill = true }, color = function() return model.night() and morf.color("#2a0000"):alpha(0.7) or "transparent" end },
  }

  -- -------------------------------------------------------------- widgets --
  local function stack(id, w, h, kinds)
    local cards = { id = id, width = w, height = h, clip = true }
    local shown = morf.signal("eva.standby.stack." .. id, 1)
    for i, kind in ipairs(kinds) do
      local spec = { id = id .. "-" .. kind, width = w, height = h,
        visible = function() return shown:get() == i end,
        ui.Item { x = S.l, y = S.l, width = w - 2 * S.l, height = h - 2 * S.l,
          faces[kind](ctx(w - 2 * S.l, h - 2 * S.l, false), model, function() return model.showing() end) } }
      cards[#cards + 1] = ui.Item(spec)
    end
    cards[#cards + 1] = ui.MouseArea { anchors = { fill = true }, on_wheel = function(_, _, _, _, _, dy)
      shown:set((shown:get() - 1 + (dy > 0 and 1 or -1)) % #kinds + 1)
    end }
    return ui.Item(cards)
  end
  local sw, sh = size()
  local half = math.floor((sw - 3 * S.xl) / 2)
  local widget_view = ui.Row { id = "standby-widgets", anchors = { center_in = true }, gap = S.xl,
    visible = function() return model.view:get() == "widgets" end,
    stack("standby-left", half, math.min(sh - 2 * S.xl, 348), { "calendar", "weather" }),
    stack("standby-right", half, math.min(sh - 2 * S.xl, 348), { "media", "system" }),
  }

  -- ---------------------------------------------------------------- world --
  local CITIES = 6
  local list_w = math.floor(sw * 0.6)
  local world_rows = { id = "standby-world-rows", anchors = { center_in = true }, width = list_w, gap = S.m }
  for index = 1, CITIES do
    local function city() return model.cities()[index] end
    local function reading()
      local entry = city()
      if not entry then return "", "" end
      return model.city_time(entry)
    end
    world_rows[#world_rows + 1] = ui.Item { width = list_w, height = 2 * S.xxl, visible = function() return city() ~= nil end,
      ui.Column { anchors = { vertical_center = true }, gap = S.xxs,
        kit.text { id = "standby-city-name-" .. index, color = ink, font_size = theme.size.large,
          text = function() local entry = city() return entry and entry.name or "" end },
        kit.text { id = "standby-city-apart-" .. index, color = soft, font_size = theme.size.small,
          text = function() local _, apart = reading() return apart end } },
      kit.text { id = "standby-city-time-" .. index, anchors = { right = true, vertical_center = true }, color = ink,
        font_size = theme.size.extra * 1.6, font_weight = 200, text = function() local time = reading() return time end },
    }
  end
  local world_view = ui.Item { id = "standby-world", anchors = { fill = true },
    visible = function() return model.view:get() == "world" end,
    ui.Column(world_rows),
    kit.text { id = "standby-world-empty", anchors = { center_in = true }, color = soft, font_size = theme.size.large,
      text = "Add cities in Clock", visible = function() return #model.cities() == 0 end },
  }

  -- ---------------------------------------------------------------- alarm --
  local function next_one() return model.next_alarm() end
  local alarm_view = ui.Item { id = "standby-alarm", anchors = { fill = true },
    visible = function() return model.view:get() == "alarm" end,
    kit.text { id = "standby-alarm-empty", anchors = { center_in = true }, color = soft, font_size = theme.size.large,
      text = "Nothing set to ring", visible = function() return next_one() == nil end },
    ui.Column { anchors = { center_in = true }, gap = S.s, align = "center", visible = function() return next_one() ~= nil end,
      kit.icon("alarm", S.xxl, ink),
      kit.text { id = "standby-alarm-time", color = ink, font_size = math.floor(math.min(sh * 0.3, sw * 0.2)), font_weight = 200,
        text = function() local one = next_one() return one and one.time or "" end },
      kit.text { id = "standby-alarm-label", color = soft, font_size = theme.size.large,
        text = function()
          local one = next_one()
          return one and (one.label .. " · " .. one.left) or ""
        end },
    },
  }

  -- ----------------------------------------------------------- the way out --
  local chrome = morf.signal("eva.standby.chrome", false)
  local hide
  local function show_chrome()
    chrome:set(true)
    if hide then hide:cancel() end
    hide = morf.time.timer(4000, function() hide = nil chrome:set(false) end, false)
  end
  local buttons = { id = "standby-buttons", width = #model.VIEWS * S.xxl * 3 + (#model.VIEWS - 1) * S.s }
  for _, view in ipairs(model.VIEWS) do
    buttons[#buttons + 1] = { id = "standby-view-" .. view[1], label = view[2], icon = view[3], group = "standby-view",
      selected = function() return model.view:get() == view[1] end, on_clicked = function() model.view:set(view[1]) show_chrome() end }
  end
  local tray = ui.Row { anchors = { top = true, horizontal_center = true, top_margin = S.xl }, gap = S.s, z = 5,
    visible = function() return chrome:get() end,
    P.buttons(buttons),
    P.button { id = "standby-close", label = "Close", icon = "close", on_clicked = model.dismiss },
  }

  -- The views slide under a finger, and the next comes as it lets go.
  local views = ui.Item { anchors = { fill = true },
    photo_view,
    ui.Item { id = "standby-drift", anchors = { fill = true },
      loop = function()
        if not model.showing() or config.get("appearance.reduce_motion") == true then return nil end
        return { translate_x = { from = -S.s, to = S.s, duration = 90000, easing = "in_out_sine", alternate = true } }
      end,
      clock_view(), widget_view, world_view, alarm_view } }
  local swipe = require("themes.swipe_dismiss").new { id = "standby", node = views, ways = { left = true, right = true },
    stays = true, distance = SWIPE, on_dismiss = function(way) model.step(way == "left" and 1 or -1) end }
  local moved = false
  local root = ui.Rect { id = "standby", anchors = { fill = true }, color = "#000000",
    views,
    ui.MouseArea { anchors = { fill = true }, z = 1,
      on_panned = swipe.on_panned,
      on_pressed = function(x, y) moved = false swipe.press(x, y) end,
      on_touch_pressed = function() swipe.touched() end,
      on_dragged = function(x, y) swipe.drag(x, y) end,
      on_released = function() moved = swipe.release() end,
      on_clicked = function() if not moved then show_chrome() end end },
    tray,
  }
  morf.effect("eva.standby.photos", function()
    if model.view:get() ~= "photos" then return end
    next_photo()
    local timer = morf.time.timer(PHOTO_MS, next_photo, true)
    return function() timer:cancel() end
  end, { owner = root })
  return root
end

return V
