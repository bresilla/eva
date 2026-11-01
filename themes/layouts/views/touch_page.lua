-- The Touch gestures pages: the switch and what the reader is doing, a small
-- screen to try gestures on, each gesture with what it does, and a page per
-- gesture to choose that. In the page template (themes/layouts/page.lua).
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.option_rows")
local C = theme.color
local S = theme.space

local M = {}

-- As many fingers as the small screen shows, and how big each is.
local FINGERS, DOT = 10, S.l

local WORDS = { desk = "Desk", phone = "Phone" }

--- The small screen: a dot where each finger is.
local function screen(model, w)
  local sw, sh = model.screen()
  local aspect = sw / math.max(1, sh)
  local H = math.floor(aspect >= 1 and math.min(w / aspect, 188) or 228)
  local W = math.floor(H * aspect)
  local x = math.floor((w - W) / 2)
  local box = kit.surface { id = "touch-screen", x = x, width = W, height = H, radius = kit.round(S.s),
    color = function() return C.surfaceContainerHighest end }
  local area = ui.Item { id = "touch-fingers", x = x, width = W, height = H, clip = true }
  for index = 1, FINGERS do
    local function at(axis, span, full)
      local finger = model.finger(index)
      return finger and math.floor(finger[axis] / math.max(1, full) * span - DOT / 2) or 0
    end
    ui.reparent(kit.surface { id = "touch-finger-" .. index, width = DOT, height = DOT, radius = kit.round(DOT / 2),
      color = function() return C.primary end, visible = function() return model.finger(index) ~= nil end,
      x = function()
        local full = model.screen()
        return at("x", W, full)
      end,
      y = function()
        local _, full = model.screen()
        return at("y", H, full)
      end }, area)
  end
  return ui.Item { id = "touch-preview", width = w, height = H, box, area }
end

local function forms(model, w)
  local row = { id = "touch-forms", width = w }
  for _, form in ipairs(model.FORMS) do
    row[#row + 1] = { id = "touch-form-" .. form, group = "touch-form", label = WORDS[form],
      selected = function() return model.form() == form end, on_clicked = function() model.pick_form(form) end }
  end
  return P.buttons(row)
end

local function outputs(model, w)
  local row = { id = "touch-outputs", width = w, { id = "touch-output-auto", group = "touch-output", label = "Find it",
    selected = function() return model.output() == "" end, on_clicked = function() model.set_output("") end } }
  for _, name in ipairs(model.outputs()) do
    row[#row + 1] = { id = "touch-output-" .. name, group = "touch-output", label = name,
      selected = function() return model.output() == name end, on_clicked = function() model.set_output(name) end }
  end
  return P.buttons(row)
end

function M.build(model, w, h)
  local inner = P.inner(w)
  local function status(part)
    return function() return (select(part, model.status())) end
  end
  local sections = { id = "touch-scroll", width = w, height = h, active = model.active,
    P.section { id = "touch-driver", width = w, title = "Anywhere on the screen",
      F.switch { id = "touch-enabled", width = inner, icon = "swipe", title = "Touch gestures",
        subtitle = "Two from an edge, three anywhere", on = model.on, set = model.set_on },
      P.row { id = "touch-status", width = inner, icon = "info", title = status(1), subtitle = status(2) },
    },
    P.section { id = "touch-try", width = w, title = "Try one", visible = model.can_try,
      P.row { id = "touch-try-row", width = inner, icon = "gesture", title = model.heard, subtitle = model.would,
        trailing = P.button { id = "touch-try-button", label = "Try", icon = "play_arrow", tone = "primary",
          on_clicked = function() model.set_trying(not model.trying()) end,
          selected = model.trying } },
      screen(model, inner),
    },
    P.section { id = "touch-where", width = w, title = "On this screen",
      visible = function() return #model.outputs() > 1 end, outputs(model, inner) },
    P.section { id = "touch-form", width = w, title = "Gestures for", forms(model, inner) },
  }
  for _, group in ipairs(model.GROUPS) do
    local section = { id = "touch-group-" .. group.id, width = w, title = group.name }
    for _, gesture in ipairs(model.gestures(group.id)) do
      section[#section + 1] = P.row { id = "touch-gesture-" .. gesture.key, width = inner, icon = gesture.icon,
        title = gesture.short, subtitle = function() return model.does(gesture.key) end,
        trailing = P.chevron(), on_clicked = function() model.open(gesture.key) end }
    end
    sections[#sections + 1] = P.section(section)
  end
  sections[#sections + 1] = P.section { id = "touch-reset", width = w,
    P.row { id = "touch-reset-row", width = inner, icon = "restart_alt", title = "As they came",
      subtitle = function() return "Every gesture for this form" end,
      trailing = P.button { id = "touch-reset-button", label = "Reset", on_clicked = model.reset } } }
  return P.page(sections)
end

--- A gesture's page: every action, one chosen, and a command for the last.
function M.gesture(model, w, h)
  local inner = P.inner(w)
  local list = { id = "touch-actions", width = w, title = "Does" }
  for _, action in ipairs(model.ACTIONS) do
    local function picked() return model.action() == action.key end
    local tick = kit.icon("check", 22, kit.ink("accent"))
    tick.visible = picked
    list[#list + 1] = P.row { id = "touch-action-" .. action.key, width = inner, height = 52, icon = action.icon,
      title = action.name, on = picked, trailing = tick, on_clicked = function() model.pick(action.key) end }
  end
  return P.page { id = "touch-gesture-scroll", width = w, height = h, active = model.active,
    P.section { id = "touch-gesture-head", width = w,
      P.row { id = "touch-gesture-name", width = inner, icon = "swipe", title = model.name,
        subtitle = function() return model.is_default() and "As it came" or "Changed" end },
      P.buttons { id = "touch-gesture-buttons", width = inner,
        { id = "touch-gesture-reset", label = "Reset", on_clicked = model.reset } } },
    P.section(list),
    P.section { id = "touch-command", width = w, title = "Command", visible = model.is_command,
      F.text { id = "touch-command-field", width = inner, title = "Command, as words",
        value = model.command, set = model.set_command } },
  }
end

return M
