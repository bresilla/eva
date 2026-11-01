-- StandBy's face: a great clock, the folder's pictures changing through the
-- shell's transitions, or two stacks of widgets. Faces are the desktop's. A swipe
-- turns the view; a touch shows the way out. At night the ink is a dim red, and
-- everything drifts a little so nothing burns in.
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

--- The whole-screen node; `model` is shell/standby_model.lua, `desktop` the
--- desktop model.
function V.build(model, desktop)
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
        faces.clock(ctx(360, 176, false), desktop) },
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
          faces[kind](ctx(w - 2 * S.l, h - 2 * S.l, false), desktop, function() return model.showing() end) } }
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

  -- ----------------------------------------------------------- the way out --
  local chrome = morf.signal("eva.standby.chrome", false)
  local hide
  local function show_chrome()
    chrome:set(true)
    if hide then hide:cancel() end
    hide = morf.time.timer(4000, function() hide = nil chrome:set(false) end, false)
  end
  local buttons = { id = "standby-buttons", width = 3 * S.xxl * 3 + 2 * S.s }
  for _, view in ipairs(model.VIEWS) do
    buttons[#buttons + 1] = { id = "standby-view-" .. view[1], label = view[2], icon = view[3], group = "standby-view",
      selected = function() return model.view:get() == view[1] end, on_clicked = function() model.view:set(view[1]) show_chrome() end }
  end
  local tray = ui.Row { anchors = { top = true, horizontal_center = true, top_margin = S.xl }, gap = S.s, z = 5,
    visible = function() return chrome:get() end,
    P.buttons(buttons),
    P.button { id = "standby-close", label = "Close", icon = "close", on_clicked = model.dismiss },
  }

  local from
  local root = ui.Rect { id = "standby", anchors = { fill = true }, color = "#000000",
    ui.Item { id = "standby-drift", anchors = { fill = true },
      loop = function()
        if not model.showing() or config.get("appearance.reduce_motion") == true then return nil end
        return { translate_x = { from = -S.s, to = S.s, duration = 90000, easing = "in_out_sine", alternate = true } }
      end,
      clock_view(), photo_view, widget_view },
    ui.MouseArea { anchors = { fill = true }, z = 1,
      on_pressed = function(x) from = x end,
      on_released = function(x)
        local moved = from and x - from or 0
        from = nil
        if math.abs(moved) >= SWIPE then model.step(moved < 0 and 1 or -1) else show_chrome() end
      end },
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
