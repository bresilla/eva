-- The session row at the top of the quick settings: who is signed in, with
-- Lock and the actions that end the session. Lock runs at once; the others
-- count only once held (the kit's hold button, which fills as it is held and
-- drains if let go).
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local widgets = require("themes.kit.widgets")
local P = require("themes.layouts.page")
local C = theme.color
local S = theme.space

local V = {}
local PICTURE = S.TARGET
local HOLD = 800
-- One line once the name has this much beside the buttons.
local NAME_MIN = 88

--- The card, `w` wide. Returns the node.
function V.build(model, w)
  local inner = w - 2 * P.PAD
  local stamp = tostring({})
  local hint = morf.signal("eva.quick.session.hint." .. stamp, "")
  local clearing
  local function say(text, ms)
    if clearing then clearing:cancel() clearing = nil end
    hint:set(text)
    if ms then clearing = morf.time.timer(ms, function() clearing = nil hint:set("") end, false) end
  end

  local actions = {}
  for _, action in ipairs(model.SESSION) do
    if model.session_available(action.id) then actions[#actions + 1] = action end
  end
  local BUTTON = S.TARGET
  local across = #actions * BUTTON + math.max(0, #actions - 1) * S.xs
  local one_line = inner - PICTURE - S.m - S.m - across >= NAME_MIN
  local spread = one_line and BUTTON or math.floor((inner - math.max(0, #actions - 1) * S.xs) / math.max(1, #actions))

  local buttons = { gap = S.xs }
  for _, action in ipairs(actions) do
    buttons[#buttons + 1] = widgets.hold_button {
      id = "utilities-session-" .. action.id, accessible_name = action.name, icon = action.icon,
      width = spread, height = BUTTON, hold = action.hold and HOLD or 0,
      tone = action.tone,
      on_pressed = action.hold and function() say(action.name .. "…") end or nil,
      on_hold_canceled = function() say("Hold to confirm", 1800) end,
      on_clicked = function()
        say("")
        model.session_run(action.id)
      end,
    }
  end

  local user = model.session_user()
  local mask = kit.shape { width = PICTURE, height = PICTURE, shape = "circle", color = "#ffffff" }
  local picture = ui.Item { id = "utilities-session-picture", width = PICTURE, height = PICTURE,
    kit.shape { anchors = { fill = true }, shape = "circle", color = function() return C.primaryContainer end },
    user.face and ui.Image { anchors = { fill = true }, source = user.face, fill_mode = "preserve_aspect_crop", mask = mask }
      or kit.icon("person", 24, function() return C.onPrimaryContainer end, { anchors = { center_in = true }, fill = true }),
  }
  local NAME_W = one_line and inner - PICTURE - S.m - S.m - across or inner - PICTURE - S.m
  local who = ui.Row { gap = S.m, align = "center",
    picture,
    ui.Column { gap = 0, width = NAME_W,
      kit.text { id = "utilities-session-name", width = NAME_W, elide = "right", text = user.label,
        font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi") },
      kit.subtitle { id = "utilities-session-hint", width = NAME_W, elide = "right", font_size = theme.size.small,
        text = function()
          local said = hint:get()
          return said ~= "" and said or "Signed in"
        end,
        color = function() return hint:get() ~= "" and kit.ink("accent")() or kit.ink("lo")() end },
    },
  }
  local row = ui.Row(buttons)
  local content = one_line
    and ui.Row { x = P.PAD, y = P.PAD, gap = S.m, align = "center", who, row }
    or ui.Column { x = P.PAD, y = P.PAD, gap = S.m, who, row }
  return kit.card { id = "utilities-session", width = w, radius = kit.round(P.RADIUS),
    height = function() return (content.layout_height or 0) + 2 * P.PAD end, content }
end

return V
