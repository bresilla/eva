-- The pill of a scrolling capture, away from what is being captured: how far it
-- has come, and its way out. Page Down is offered where there are keys.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local C, S = theme.color, theme.space
local V = {}

local WIDTH, HEIGHT = S.TARGET * 9, S.TARGET + S.xs

--- The pill's size: width, height.
function V.size()
  local screen = (morf.screens or {})[1] or { width = 1920 }
  return math.min(WIDTH, (screen.width or WIDTH) - 2 * S.s), HEIGHT
end

function V.build(M)
  local width = V.size()
  local keys = not require("responsive").sheets()
  return kit.card { id = "capture-scroll-pill", width = width, height = HEIGHT, radius = kit.round(S.l),
    kit.text { id = "capture-scroll-count", x = S.m, width = width - S.TARGET * 6 - S.xl, anchors = { vertical_center = true }, elide = "right",
      font_size = 12, color = function() return C.onSurface end,
      text = function()
        if M.state:get() == "joining" then return "Joining…" end
        if M.rows:get() == 0 then return "Scroll the window" end
        return M.rows:get() .. " rows"
      end },
    ui.Row { anchors = { right = true, right_margin = S.xs, vertical_center = true }, gap = S.xs,
      P.button { id = "capture-scroll-auto", height = S.TARGET - S.s, width = S.TARGET * 2, visible = keys,
        label = function() return M.auto:get() and "By hand" or "Auto" end, on_clicked = M.follow_keys },
      P.button { id = "capture-scroll-done", height = S.TARGET - S.s, width = S.TARGET * 2, tone = "primary", label = "Done",
        on_clicked = M.done },
      P.button { id = "capture-scroll-cancel", height = S.TARGET - S.s, width = S.TARGET * 2, label = "Cancel",
        on_clicked = M.cancel },
    },
  }
end

return V
