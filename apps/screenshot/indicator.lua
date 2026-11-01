-- The pill at the top of the screen while a recording runs with no shell to
-- show it.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local C, S = theme.color, theme.space

local M = {}

M.HEIGHT = S.TARGET + S.xs + 2 * S.s

--- "m:ss" for `seconds`.
function M.clock(seconds)
  return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

--- The pill: shown by `shown` (a fn), reading and stopping `capture`.
function M.build(capture, shown)
  local dot = S.m
  return kit.card {
    id = "record-indicator", width = S.TARGET * 6, height = S.TARGET + S.xs, radius = kit.round(S.l),
    anchors = { horizontal_center = true, top = true, top_margin = S.s }, visible = shown,
    ui.Rect {
      x = S.m, width = dot, height = dot, radius = dot / 2, anchors = { vertical_center = true },
      color = function() return C.error end,
    },
    kit.text {
      id = "record-elapsed", x = S.m + dot + S.s, anchors = { vertical_center = true },
      color = kit.ink("hi"), font_size = theme.size.normal,
      text = function() return M.clock(capture.elapsed:get()) end,
    },
    ui.Row {
      anchors = { right = true, right_margin = S.xs, vertical_center = true },
      P.button {
        id = "record-indicator-stop", label = "Stop", height = S.TARGET - S.s, width = S.TARGET * 2,
        on_clicked = function() capture.record() end,
      },
    },
  }
end

return M
