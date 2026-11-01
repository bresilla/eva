-- The word a limit or downtime has with a person: what ran out, that it is a
-- reminder and not a lock, and the way on. `model` is shell/screen_time_model.lua.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local S = theme.space

local V = {}

--- The notice over the whole screen.
function V.build(model)
  local WIDTH = 360
  local function now() return model.notice:get() or {} end
  local function width() return math.min(WIDTH, (require("responsive").size()) - 2 * S.l) end
  local function inner() return width() - 2 * S.l end
  local function downtime() return now().kind == "downtime" end
  local function limit_words()
    local minutes = model.limit(now().key or "")
    return minutes and model.words(minutes * 60) or "your limit"
  end
  local body = ui.Column { x = S.l, y = S.l, width = inner, gap = S.s,
      kit.icon(function() return downtime() and "bedtime" or "hourglass_bottom" end, S.xl, kit.ink("accent")),
      kit.text { id = "screen-time-title", width = inner, wrap = true, font_size = theme.size.larger, font_weight = 600,
        color = kit.ink("hi"),
        text = function()
          if downtime() then return "It is downtime" end
          return (now().name or "") .. " has had " .. limit_words() .. " today"
        end },
      kit.text { id = "screen-time-why", width = inner, wrap = true, font_size = theme.size.small, color = kit.ink("lo"),
        text = "A reminder you set, not a lock: a shell cannot stop an app, so going on is up to you." },
      P.button { id = "screen-time-away", label = "Step away", icon = "close", tone = "primary", width = inner,
        on_clicked = model.step_away },
      P.button { id = "screen-time-more", label = model.MORE .. " more minutes", icon = "more_time", width = inner,
        visible = function() return not downtime() end, on_clicked = model.extend },
      P.button { id = "screen-time-override", label = "Go on for today", icon = "skip_next", width = inner,
        on_clicked = model.override },
    }
  local card = kit.card { id = "screen-time-notice", width = width, anchors = { center_in = true },
    height = function() return (body.layout_height or 0) + 2 * S.l end, body }
  return ui.Rect { id = "screen-time-veil", anchors = { fill = true }, z = 50, color = morf.color("#000000"):alpha(0.5),
    visible = function() return model.notice:get() ~= false end,
    ui.MouseArea { anchors = { fill = true }, on_clicked = model.step_away },
    card }
end

return V
