-- eva-record's window, and the indicator shown while a recording runs.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

local function choices(w, signal, list)
  local spec = { width = w }
  for i, item in ipairs(list) do
    spec[i] = {
      id = "record-" .. item[1], label = item[2], icon = item[3],
      tone = function() return signal:get() == item[1] and "primary" or nil end,
      on_clicked = function() signal:set(item[1]) end,
    }
  end
  return P.buttons(spec)
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local inner = function() return P.inner(w) end
  return P.page {
    id = "record-page", width = w, height = h,
    P.section {
      id = "record-target", width = w, title = "Record",
      choices(inner, model.target, {
        { "region", "Region", "crop_free" }, { "window", "Window", "web_asset" },
        { "monitor", "Monitor", "desktop_windows" },
      }),
    },
    P.section {
      id = "record-audio", width = w, title = "Sound",
      choices(inner, model.audio, model.AUDIO),
    },
    P.buttons {
      width = w,
      { id = "record-start", label = "Start recording", icon = "fiber_manual_record", tone = "primary",
        visible = function() return not model.recording:get() end, on_clicked = model.start },
      { id = "record-stop", label = "Stop recording", icon = "stop",
        visible = function() return model.recording:get() end, on_clicked = function() model.stop() end },
    },
    kit.text {
      id = "record-message", width = w, font_size = theme.size.small, color = kit.ink("lo"),
      text = function() return model.message:get() end,
    },
  }
end

--- The pill at the top of the screen, until the recording ends: `done()` then.
function M.indicator(done)
  local dot = S.m
  local pill = kit.card {
    id = "record-indicator", anchors = { fill = true }, radius = kit.round(S.l),
    ui.Rect {
      x = S.m, width = dot, height = dot, radius = dot / 2, anchors = { vertical_center = true },
      color = function() return C.error end,
    },
    kit.text {
      id = "record-elapsed", x = S.m + dot + S.s, anchors = { vertical_center = true },
      color = kit.ink("hi"), font_size = theme.size.normal,
      text = function() return model.clock(model.elapsed:get()) end,
    },
    P.button {
      id = "record-indicator-stop", label = "Stop", height = S.TARGET - S.s, width = S.TARGET * 2,
      anchors = { right = true, right_margin = S.xs, vertical_center = true },
      on_clicked = function() model.stop() end,
    },
  }
  morf.window.layer {
    blend = "srgb", namespace = "eva-record", layer = "overlay", anchors = { top = true },
    width = S.TARGET * 6, height = S.TARGET + S.xs, margin_top = S.s, exclusive_zone = 0,
    keyboard_focus = "none", visible = true,
    root = ui.Item { anchors = { fill = true }, pill },
  }
  morf.time.timer(1000, function()
    model.elapsed:set(model.elapsed:get() + 1)
    if not model.check() then done() end
  end, true)
end

return M
