-- eva-clock's window: a line that takes what you say, over the pages for alarms,
-- timers, the stopwatch and the world.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("apps.common.controls")
local lib = require("lib.services.alarm")
local model = require("apps.clock.model")
local S = theme.space

local M = {}

local ROWS = 24
local DIAL = 56
local BIG = theme.size.extra * 2
local TIME = theme.size.extra

local function get(v) if type(v) == "function" then return v() end return v end
local function tick() return morf.time.clock:get() end

local function delete_button(id, name, action)
  return L.icon_button { id = id, icon = "delete", name = name, width = S.TARGET, height = S.TARGET, on_clicked = action }
end

-- ----------------------------------------------------------------- alarms --

local function alarm_row(index, item, w)
  local function title()
    local it = item()
    if not it then return "" end
    if it.hour then return ("%02d:%02d"):format(it.hour, it.minute) end
    return morf.time.format("%H:%M", it.at)
  end
  local function subtitle()
    local it = item()
    if not it then return "" end
    local days = lib.days_words(it.days)
    local parts = {}
    if it.label ~= "" then parts[#parts + 1] = it.label end
    parts[#parts + 1] = days ~= "" and days or morf.time.format("%a %-d %b", it.at)
    return table.concat(parts, " · ")
  end
  local function right() return S.TARGET * 2 + S.xl end
  return ui.Item {
    width = w, height = controls.ROW_H,
    kit.text {
      id = "clock-alarm-time-" .. index, anchors = { vertical_center = true }, font_size = TIME, font_weight = 300,
      color = function() local it = item() return (it and it.on) and kit.ink("hi")() or kit.ink("lo")() end,
      text = title,
    },
    kit.text {
      id = "clock-alarm-note-" .. index, x = TIME * 3.4, anchors = { vertical_center = true }, elide = "right",
      width = function() return math.max(1, get(w) - TIME * 3.4 - right()) end,
      font_size = theme.size.normal, color = kit.ink("lo"), text = subtitle,
    },
    ui.Row {
      anchors = { right = true, vertical_center = true }, gap = S.s, align = "center",
      P.switch {
        id = "clock-alarm-switch-" .. index, name = "Alarm on",
        on = function() local it = item() return it ~= nil and it.on == true end,
        on_toggled = function(on) local it = item() if it then model.alarm.set(it.id, on) end end,
      },
      delete_button("clock-alarm-delete-" .. index, "Delete alarm",
        function() local it = item() if it then model.alarm.remove(it.id) end end),
    },
  }
end

local function alarms_page(w, h)
  local function items() return model.entries("alarm") end
  return ui.Item {
    id = "clock-alarms", width = w, height = h,
    P.empty {
      id = "clock-alarms-empty", icon = "alarm", title = "No alarms", width = w,
      text = 'Say one above: "at 7am", "every weekday 6:30 gym".',
      visible = function() return #items() == 0 end,
    },
    controls.list {
      id = "clock-alarm-list", width = w, height = h, count = ROWS, items = items,
      build = function(index, item) return alarm_row(index, item, w) end,
    },
  }
end

-- ----------------------------------------------------------------- timers --

local function timer_row(index, item, w)
  local function left()
    tick()
    local it = item()
    return it and math.max(0, it.at - lib.now()) or 0
  end
  local dial = kit.gauge {
    id = "clock-timer-dial-" .. index, size = DIAL, stroke = S.xs,
    value = function() local it = item() return it and it.seconds > 0 and left() / it.seconds or 0 end,
    color = kit.signal("accent"),
  }
  return ui.Item {
    width = w, height = DIAL + S.s,
    ui.Item { width = DIAL, height = DIAL, anchors = { vertical_center = true }, dial },
    ui.Column {
      x = DIAL + S.m, anchors = { vertical_center = true }, gap = S.xxs,
      kit.text {
        id = "clock-timer-left-" .. index, font_size = TIME, font_weight = 300, color = kit.ink("hi"),
        text = function() return lib.running(left()) end,
      },
      kit.text {
        id = "clock-timer-label-" .. index, font_size = theme.size.small, color = kit.ink("lo"), elide = "right",
        width = function() return math.max(1, get(w) - DIAL - S.TARGET * 3 - S.xl) end,
        text = function()
          local it = item()
          if not it then return "" end
          return it.label ~= "" and it.label or lib.span(it.seconds)
        end,
      },
    },
    ui.Row {
      anchors = { right = true, vertical_center = true }, gap = S.s, align = "center",
      P.button {
        id = "clock-timer-more-" .. index, label = "+1 min",
        on_clicked = function() local it = item() if it then model.alarm.extend(it.id, 60) end end,
      },
      delete_button("clock-timer-delete-" .. index, "Cancel timer",
        function() local it = item() if it then model.alarm.remove(it.id) end end),
    },
  }
end

local function timers_page(w, h)
  local function items() return model.entries("timer") end
  local presets = { width = w }
  for index, minutes in ipairs(model.PRESETS) do
    presets[index] = {
      id = "clock-preset-" .. minutes, label = minutes .. " min", icon = "timer",
      on_clicked = function() model.add("timer " .. minutes .. " min") end,
    }
  end
  local foot = P.BUTTON_H + S.m
  local function body() return math.max(1, get(h) - foot) end
  return ui.Item {
    id = "clock-timers", width = w, height = h,
    P.buttons(presets),
    ui.Item {
      y = foot, width = w, height = body,
      P.empty {
        id = "clock-timers-empty", icon = "timer", title = "No timers", width = w,
        text = 'Pick one, or say "timer 12 min pasta".',
        visible = function() return #items() == 0 end,
      },
      controls.list {
        id = "clock-timer-list", width = w, height = body, count = ROWS, row_height = DIAL + S.s, items = items,
        build = function(index, item) return timer_row(index, item, w) end,
      },
    },
  }
end

-- -------------------------------------------------------------- stopwatch --

local function stopwatch_page(w, h)
  local function laps() return model.laps:get() end
  local top = BIG * 2 + P.BUTTON_H + S.xl
  local function body() return math.max(1, get(h) - top) end
  return ui.Item {
    id = "clock-stopwatch", width = w, height = h,
    kit.text {
      id = "clock-watch", width = w, y = S.l, horizontal_alignment = "center", font_size = BIG, font_weight = 200,
      color = kit.ink("hi"), text = function() return model.watch_words(model.shown:get()) end,
    },
    ui.Item {
      y = BIG * 2, width = w, height = P.BUTTON_H,
      P.buttons {
        width = w,
        { id = "clock-watch-go", tone = "primary", icon = function() return model.running:get() and "pause" or "play_arrow" end,
          label = function() return model.running:get() and "Stop" or "Start" end,
          on_clicked = function() model.stopwatch(model.running:get() and "stop" or "start") end },
        { id = "clock-watch-lap", icon = "flag", label = "Lap", enabled = function() return model.running:get() end,
          on_clicked = function() model.stopwatch("lap") end },
        { id = "clock-watch-reset", icon = "restart_alt", label = "Reset", on_clicked = function() model.stopwatch("reset") end },
      },
    },
    ui.Item {
      y = top, width = w, height = body,
      controls.list {
        id = "clock-lap-list", width = w, height = body, count = 60, row_height = S.TARGET, items = laps,
        build = function(index, item)
          return ui.Item {
            width = w, height = S.TARGET,
            kit.text {
              anchors = { vertical_center = true }, font_size = theme.size.normal, color = kit.ink("lo"),
              text = function() return ("Lap %d"):format(#laps() - index + 1) end,
            },
            kit.text {
              id = "clock-lap-" .. index, anchors = { right = true, vertical_center = true }, color = kit.ink("hi"),
              font_size = theme.size.normal,
              text = function() local lap = item() return lap and model.watch_words(lap) or "" end,
            },
          }
        end,
      },
    },
  }
end

-- ------------------------------------------------------------------ world --

local function world_page(w, h)
  local function cities() return model.world:get() end
  local add = 120
  local foot = S.TARGET + S.xl
  local function body() return math.max(1, get(h) - foot) end
  return ui.Item {
    id = "clock-world", width = w, height = h,
    ui.Row {
      gap = S.s, align = "center",
      controls.entry {
        id = "clock-city", width = function() return math.max(1, get(w) - add - S.s) end, value = model.city,
        placeholder = "Add a city or a zone", on_accepted = function(value) model.add_city(value) end,
      },
      P.button { id = "clock-city-add", label = "Add", width = add, on_clicked = function() model.add_city(model.city:get()) end },
    },
    controls.note { id = "clock-world-note", y = S.TARGET + S.xs, width = w, text = function() return model.message:get() end },
    ui.Item {
      y = foot, width = w, height = body,
      P.empty {
        id = "clock-world-empty", icon = "public", title = "No other cities", width = w,
        text = "Add one to see its time here.",
        visible = function() return #cities() == 0 end,
      },
      controls.list {
        id = "clock-world-list", width = w, height = body, count = ROWS, items = cities,
        build = function(index, item)
          local function reading()
            tick()
            local entry = item()
            if not entry then return "", "" end
            return model.city_time(entry)
          end
          return ui.Item {
            width = w, height = controls.ROW_H,
            ui.Column {
              anchors = { vertical_center = true }, gap = S.xxs,
              kit.text {
                id = "clock-city-name-" .. index, font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi"),
                text = function() local entry = item() return entry and entry.name or "" end,
              },
              kit.text {
                id = "clock-city-apart-" .. index, font_size = theme.size.small, color = kit.ink("lo"),
                text = function() local _, apart = reading() return apart end,
              },
            },
            kit.text {
              id = "clock-city-time-" .. index, anchors = { right = true, right_margin = S.TARGET + S.s, vertical_center = true },
              font_size = TIME, font_weight = 300, color = kit.ink("hi"),
              text = function() local time = reading() return time end,
            },
            ui.Item {
              anchors = { right = true, vertical_center = true }, width = S.TARGET, height = S.TARGET,
              delete_button("clock-city-delete-" .. index, "Remove city", function() model.remove_city(index) end),
            },
          }
        end,
      },
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local add = 120
  local top = S.TARGET + L.lh(theme.size.small) + S.m
  local pages = controls.pages {
    id = "clock", width = w, tab = model.tab,
    height = function() return math.max(1, h() - top) end,
    tabs = {
      { key = "alarms", name = "Alarms", icon = "alarm", build = alarms_page },
      { key = "timers", name = "Timers", icon = "timer", build = timers_page },
      { key = "stopwatch", name = "Stopwatch", icon = "avg_pace", build = stopwatch_page },
      { key = "world", name = "World", icon = "public", build = world_page },
    },
  }
  return ui.Item {
    id = "clock-root", width = w, height = h,
    ui.Row {
      gap = S.s, align = "center",
      controls.entry {
        id = "clock-add", width = function() return math.max(1, w() - add - S.s) end, value = model.draft, focus = true,
        placeholder = "timer 12 min pasta, at 6pm, every weekday 7:30",
        on_accepted = function(value) model.add(value) end,
      },
      P.button { id = "clock-add-go", label = "Add", tone = "primary", width = add, on_clicked = function() model.add(model.draft:get()) end },
    },
    controls.note {
      id = "clock-hint", y = S.TARGET + S.xs, width = w,
      text = function() return model.hint() or model.alarm.message:get() end,
    },
    ui.Item { y = top, width = w, height = function() return math.max(1, h() - top) end, pages },
  }
end

return M
