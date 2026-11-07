-- eva-breaks: the window that configures it and shows the day, and the overlay
-- of a break, a dial of the time left.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local controls = require("apps.common.controls")
local alarm = require("lib.services.alarm")
local model = require("apps.breaks.model")
local C, S = theme.color, theme.space

local M = {}

local DIAL = 200
local CARD = 340
local DAYS = 7
local DAY_W = 40
local VALUE_W = 88
local FULL_DAY_S = 8 * 3600

local function state() return model.status:get() end
local function today() return model.seconds(state(), model.day(model.now())) end

local function counts()
  return (state().counts or {})[model.day(model.now())] or { taken = 0, skipped = 0 }
end

local function next_words()
  morf.time.clock:get()
  if model.settings:get().pause_until > model.now() then
    return "Paused until " .. morf.time.format("%H:%M", model.settings:get().pause_until)
  end
  if not model.watching(state()) then return "Not watching" end
  if state().idle then return "Away" end
  local kind, left = model.next_break(state())
  if not kind then return "No reminders on" end
  return ("%s in %s"):format(model.WORDS[kind].name, alarm.running(math.floor(left)))
end

local function today_section(w)
  local inner = function() return P.inner(w) end
  return P.section {
    id = "breaks-today", width = w, title = "Today",
    P.row {
      id = "breaks-screen", width = inner, icon = "schedule",
      title = function() return alarm.span(math.floor(today())) .. " of screen time" end,
      subtitle = function()
        local day = counts()
        return ("%d taken, %d skipped"):format(day.taken, day.skipped)
      end,
    },
    P.row {
      id = "breaks-next", width = inner, icon = "visibility", title = next_words,
      subtitle = function()
        return model.watching(state()) and "Idle time counts as rest" or "Reminders need the watcher running"
      end,
      trailing = P.button {
        id = "breaks-start", label = "Start", tone = "primary", on_clicked = function() model.start_watching() end,
        visible = function() return not model.watching(state()) end,
      },
    },
  }
end

-- The day `back` days ago.
local function day_of(back) return model.now() - back * 86400 end

local function week_section(w)
  local inner = function() return P.inner(w) end
  local rows = { id = "breaks-week", width = w, title = "This week" }
  for back = DAYS - 1, 0, -1 do
    local function seconds() return model.seconds(state(), model.day(day_of(back))) end
    rows[#rows + 1] = ui.Item {
      width = inner, height = S.xl,
      kit.text {
        width = DAY_W, anchors = { vertical_center = true }, font_size = theme.size.small, color = kit.ink("lo"),
        text = function() return morf.time.format("%a", day_of(back)) end,
      },
      ui.Rect {
        x = DAY_W, y = S.s, height = S.s, radius = kit.round(S.xs), color = function() return C.surfaceContainerHighest end,
        width = function() return math.max(1, inner() - DAY_W - VALUE_W) end,
        ui.Rect {
          height = S.s, radius = kit.round(S.xs), color = kit.signal("accent"),
          width = function() return math.max(1, inner() - DAY_W - VALUE_W) * math.min(1, seconds() / FULL_DAY_S) end,
          behavior = { width = theme.spring.spatial },
        },
      },
      kit.text {
        id = "breaks-day-" .. back, anchors = { right = true, vertical_center = true }, width = VALUE_W,
        horizontal_alignment = "right", font_size = theme.size.small, color = kit.ink("lo"),
        text = function() return seconds() > 0 and alarm.span(math.floor(seconds())) or "" end,
      },
    }
  end
  return P.section(rows)
end

local function reminder_section(w, kind)
  local inner = function() return P.inner(w) end
  local function setting() return model.settings:get()[kind] end
  local function choices(field, list, words)
    local items = {}
    for index, value in ipairs(list) do items[index] = words(value) end
    return controls.segments {
      id = "breaks-" .. kind .. "-" .. field, width = inner, items = items,
      current = function()
        for index, value in ipairs(list) do
          if setting()[field] == value then return index end
        end
        return 0
      end,
      on_changed = function(index) model.change(function(value) value[kind][field] = list[index] end) end,
    }
  end
  return P.section {
    id = "breaks-" .. kind, width = w,
    P.row {
      width = inner, icon = kind == "eyes" and "visibility" or "self_improvement",
      title = model.WORDS[kind].title,
      subtitle = model.WORDS[kind].body,
      on = function() return setting().on end,
      trailing = P.switch {
        id = "breaks-" .. kind .. "-on", name = model.WORDS[kind].title, on = function() return setting().on end,
        on_toggled = function(now) model.change(function(value) value[kind].on = now end) end,
      },
    },
    controls.note { id = "breaks-" .. kind .. "-every-note", width = inner, text = "Every" },
    choices("every", model.EVERY[kind], function(value) return value .. " min" end),
    controls.note { id = "breaks-" .. kind .. "-length-note", width = inner, text = "For" },
    choices("length", model.LENGTH[kind], function(value) return alarm.span(value) end),
  }
end

local function pause_section(w)
  return P.section {
    id = "breaks-pause", width = w, title = "Pause",
    P.buttons {
      width = function() return P.inner(w) end,
      { id = "breaks-pause-30", label = "30 min", on_clicked = function() model.pause(30) end },
      { id = "breaks-pause-60", label = "1 h", on_clicked = function() model.pause(60) end },
      { id = "breaks-resume", label = "Resume", enabled = function() return model.settings:get().pause_until > model.now() end,
        on_clicked = function() model.pause(0) end },
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  return P.page {
    id = "breaks-page", width = w, height = h,
    today_section(w), week_section(w), reminder_section(w, "eyes"), reminder_section(w, "rest"), pause_section(w),
  }
end

local function break_screen()
  local function current() return model.current:get() end
  local function left()
    morf.time.clock:get()
    local now = current()
    return now and math.max(0, now.ends - model.now()) or 0
  end
  local column = ui.Column {
    x = S.xl, y = S.xl, width = CARD - 2 * S.xl, gap = S.m, align = "center",
    ui.Item {
      width = DIAL, height = DIAL,
      kit.dial {
        id = "breaks-dial", size = DIAL,
        value = function() local now = current() return now and left() / now.length or 0 end,
      },
    },
    kit.text {
      id = "breaks-left", width = CARD - 2 * S.xl, horizontal_alignment = "center", font_size = theme.size.extra,
      font_weight = 300, color = kit.ink("hi"), text = function() return alarm.running(math.ceil(left())) end,
    },
    kit.text {
      id = "breaks-title", width = CARD - 2 * S.xl, horizontal_alignment = "center", wrap = true,
      font_size = theme.size.normal, color = kit.ink("lo"),
      text = function() local now = current() return now and model.WORDS[now.kind].body or "" end,
    },
    P.buttons {
      width = CARD - 2 * S.xl,
      { id = "breaks-skip", label = "Skip", on_clicked = function() model.skip() end },
      { id = "breaks-postpone", label = "Later", tone = "primary", on_clicked = function() model.postpone() end },
    },
  }
  local card = kit.card {
    id = "breaks-card", width = CARD, height = function() return (column.layout_height or 0) + 2 * S.xl end,
    anchors = { center_in = true }, radius = kit.round(S.xl),
    scale = 1, opacity = 1, enter = { scale = 0.92, opacity = 0 },
    behavior = { scale = theme.spring.spatial, opacity = theme.spring.effects },
    column,
  }
  local root = ui.Rect {
    id = "breaks-overlay", anchors = { fill = true }, color = function() return C.surface:alpha(0.86) end,
    ui.MouseArea {
      id = "breaks-area", anchors = { fill = true }, focus = function() return current() ~= nil end,
      on_key_pressed = function(_, _, _, _, name)
        if name == "Escape" then
          model.skip()
          return true
        end
      end,
    },
    card,
  }
  return require("common.frame").overlay { id = "breaks", root = root, close = model.skip }
end

--- The overlay, for as long as a break runs.
function M.overlay()
  local layer
  morf.effect("eva.breaks.overlay", function()
    local shown = model.current:get() ~= nil
    if shown and not layer then layer = break_screen()
    elseif not shown and layer then
      require("common.frame").dismiss(layer)
      layer = nil
    end
  end)
end

return M
