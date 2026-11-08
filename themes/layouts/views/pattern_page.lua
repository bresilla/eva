-- The Pattern page, behind the Lock screen's: what patty holds for this account,
-- a new pattern drawn or typed twice, and clearing it. `model` is
-- shell/pattern_model.lua.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local C, S = theme.color, theme.space

local V = {}

local KINDS = { grid = "A grid pattern", keypad = "A keypad pattern" }

function V.build(model, active, w, h)
  local inner = P.inner(w)
  local armed = morf.signal("eva.pattern.armed", false)
  local function state() return model.state:get() end
  local function installed() return state().installed end
  local function has() return state().kind ~= "" end
  local function idle() return not model.busy:get() end

  local missing = P.section { id = "pattern-missing", width = w, title = "Pattern",
    visible = function() return not installed() end,
    P.row { id = "pattern-missing-row", width = inner, icon = "pattern", title = "patty is not installed on this machine",
      subtitle = "It puts a pattern before the password on the lock and login screens" } }

  local status = P.section { id = "pattern-status", width = w, title = "Your pattern", visible = installed,
    P.row { id = "pattern-kind", width = inner, icon = "pattern",
      title = function() return KINDS[state().kind] or "No pattern" end,
      subtitle = function()
        if not has() then return "Only the password opens the lock and login screens" end
        return "Tried before the password on the lock and login screens"
      end },
    P.row { id = "pattern-tries", width = inner, icon = "error", visible = function() return has() and state().locked == 0 end,
      title = function() return ("%d of %d wrong tries"):format(state().used, state().used + state().left) end,
      subtitle = "Five wrong, and it waits 5 minutes" },
    P.row { id = "pattern-locked", width = inner, icon = "lock_clock", visible = function() return has() and state().locked > 0 end,
      title = function() return "Locked until " .. morf.time.format("%H:%M", state().until_at) end,
      subtitle = "Too many wrong patterns. The password still works" },
  }

  local GRID = math.min(inner, 240)
  local look = { ring = function() return C.outlineVariant end, dot = function() return C.onSurfaceVariant end,
    lit = function() return C.primary end, line = function() return C.primary end,
    error = function() return C.error end, round = kit.round }
  local grid = require("themes.layouts.pattern_grid").build { id = "pattern-page-grid", size = GRID,
    trace = model.trace, look = look, enabled = idle, on_done = model.enter, on_start = model.started }
  local field, input = P.field { id = "pattern-page-digits", width = math.max(1, inner - 132), kind = "password",
    placeholder = "Or type the digits", on_changed = model.typing, on_accepted = function() model.accept() end }
  morf.effect("eva.pattern.page.field", function()
    if model.typed:get() == 0 and input then input.text = "" end
  end, { owner = field })

  local function said() return model.said:get() end
  local setting = P.section { id = "pattern-set", width = w, visible = installed,
    title = function() return has() and "Change the pattern" or "Set a pattern" end,
    P.row { id = "pattern-step", width = inner, icon = function() return model.step:get() == "first" and "draw" or "repeat" end,
      title = function() return model.step:get() == "first" and "Draw a new pattern, or type it" or "Again, to be sure" end,
      subtitle = "4 to 16 dots, or digits for a keypad" },
    ui.Item { id = "pattern-page-grid-box", width = inner, height = GRID,
      ui.Item { anchors = { horizontal_center = true }, width = GRID, height = GRID, grid } },
    ui.Row { id = "pattern-page-typing", width = inner, gap = S.s, align = "center", field,
      P.button { id = "pattern-page-next", label = "Next", icon = "arrow_forward", width = 124,
        enabled = function() return idle() and model.typed:get() > 0 end, on_clicked = model.accept } },
    kit.text { id = "pattern-said", width = inner, wrap = true, text = function() return said().text end,
      visible = function() return said().text ~= "" end, font_size = P.SUB,
      color = function() return said().bad and C.error or C.onSurfaceVariant end },
    P.buttons { id = "pattern-page-buttons", width = inner,
      { id = "pattern-start-again", label = "Start again", icon = "restart_alt", enabled = idle,
        visible = function() return model.step:get() ~= "first" end, on_clicked = model.reset },
      { id = "pattern-clear", label = function() return armed:get() and "Sure? Clear it" or "Clear the pattern" end,
        icon = "delete", enabled = idle, visible = has,
        on_clicked = function()
          if armed:get() then armed:set(false) model.clear() else armed:set(true) end
        end } },
  }

  local page = P.page { id = "pattern-scroll", width = w, height = h, missing, status, setting }
  morf.effect("eva.pattern.page", function()
    if active() then
      model.refresh()
    else
      model.reset()
      armed:set(false)
    end
  end, { owner = page })
  return page
end

return V
