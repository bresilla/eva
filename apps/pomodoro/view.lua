-- eva-pomodoro's window: the dial, a ring of one distance field with the phase's
-- arc cut from it, the set's beads running together as they fill, and the
-- controls under them.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("common.controls")
local lib = require("lib.services.alarm")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

local BEAD = S.l
local BEAD_GAP = S.s
local LEAST = 160

local function session() return model.session:get() end

local function sweep()
  local part = model.progress()
  if part <= 0 then return 0 end
  return math.max(2, 360 * part)
end

-- The phase's arc: a ring cut by a pie, and the head riding its leading end.
local function arc(side, stroke)
  local accent = kit.signal("accent")
  local field = ui.Sdf {
    id = "pomodoro-arc", anchors = { fill = true }, fill_color = accent,
    opacity = function() return sweep() > 0 and 1 or 0 end,
    rotation = function() return sweep() / 2 end,
    behavior = { rotation = theme.spring.spatial, opacity = theme.spring.effects },
    ui.SdfShape { anchors = { fill = true }, shape = "ring", thickness = stroke },
    ui.SdfShape {
      id = "pomodoro-sweep", x = -S.xxs, y = -S.xxs, shape = "pie", operation = "intersect",
      width = function() return side() + 2 * S.xxs end, height = function() return side() + 2 * S.xxs end,
      angle = sweep, behavior = { angle = theme.spring.spatial },
    },
  }
  local head = ui.Sdf {
    id = "pomodoro-head", anchors = { fill = true }, fill_color = accent,
    rotation = sweep, behavior = { rotation = theme.spring.spatial, opacity = theme.spring.effects },
    opacity = function() return sweep() > 0 and 1 or 0 end,
    ui.SdfShape {
      shape = "box", radius = function() return kit.round(stroke()) end,
      x = function() return (side() - stroke() * 1.6) / 2 end, y = function() return -stroke() * 0.3 end,
      width = function() return stroke() * 1.6 end, height = function() return stroke() * 1.6 end,
    },
  }
  return field, head
end

local function dial(w, h)
  local function side() return math.floor(math.max(LEAST, math.min(w(), h()))) end
  local function stroke() return math.max(S.m, math.floor(side() / 24)) end
  local field, head = arc(side, stroke)
  return ui.Item {
    id = "pomodoro-dial", width = side, height = side,
    x = function() return (w() - side()) / 2 end, y = function() return (h() - side()) / 2 end,
    ui.Sdf {
      id = "pomodoro-track", anchors = { fill = true }, fill_color = C.surfaceContainerHighest,
      ui.SdfShape { anchors = { fill = true }, shape = "ring", thickness = stroke },
    },
    field, head,
    ui.Column {
      anchors = { center_in = true }, gap = S.xs, align = "center",
      kit.text {
        id = "pomodoro-phase", font_size = theme.size.normal, color = kit.ink("lo"),
        text = function() return model.PHASES[session().phase].name end,
      },
      kit.text {
        id = "pomodoro-left", font_weight = 200, color = kit.ink("hi"),
        font_size = function() return math.floor(side() / 5) end,
        text = function() return lib.running(model.left()) end,
      },
    },
  }
end

-- The set: a bead for each work phase, those done running together.
local function beads()
  local count = model.EVERY
  local width = count * BEAD + (count - 1) * BEAD_GAP
  local function left(index) return (index - 1) * (BEAD + BEAD_GAP) end
  local track, done = {
    id = "pomodoro-beads-track", anchors = { fill = true }, fill_color = C.surfaceContainerHighest,
  }, {
    id = "pomodoro-beads", anchors = { fill = true }, fill_color = kit.signal("accent"), blend = S.l,
  }
  for index = 1, count do
    local function on() return session().round >= index end
    track[index] = ui.SdfShape {
      shape = "box", radius = kit.round(BEAD / 2), x = left(index), y = 0, width = BEAD, height = BEAD,
    }
    done[index] = ui.SdfShape {
      id = "pomodoro-bead-" .. index, shape = "box", radius = kit.round(BEAD / 2),
      operation = index > 1 and "smooth_union" or "union",
      x = function() return left(index) + (on() and 0 or BEAD / 2) end,
      y = function() return on() and 0 or BEAD / 2 end,
      width = function() return on() and BEAD or 0 end,
      height = function() return on() and BEAD or 0 end,
      behavior = { x = theme.spring.spatial, y = theme.spring.spatial, width = theme.spring.spatial, height = theme.spring.spatial },
    }
  end
  return ui.Item { id = "pomodoro-set", width = width, height = BEAD, ui.Sdf(track), ui.Sdf(done) }
end

local function note(id, w, text)
  return kit.text {
    id = id, width = w, height = L.lh(theme.size.small), font_size = theme.size.small, color = kit.ink("lo"),
    horizontal_alignment = "center", elide = "right", text = text,
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local plans = {}
  for index, plan in ipairs(model.PLANS) do plans[index] = plan.name end
  local foot = BEAD + 2 * L.lh(theme.size.small) + 2 * (P.BUTTON_H + S.m) + 2 * S.xl
  local function face_h() return math.max(LEAST, h() - foot) end
  return ui.Item {
    id = "pomodoro-root", width = w, height = h,
    ui.Item { width = w, height = face_h, dial(w, face_h) },
    ui.Column {
      y = function() return face_h() + S.l end, width = w, gap = S.m, align = "center",
      beads(),
      note("pomodoro-count", w, function()
        local s = session()
        return ("%d of %d in this set · %d today · %d in all"):format(s.round, model.EVERY, s.today, s.total or 0)
      end),
      P.buttons {
        width = w,
        { id = "pomodoro-go", tone = "primary", icon = function() return session().running and "pause" or "play_arrow" end,
          label = function() return session().running and "Pause" or "Start" end, on_clicked = model.toggle },
        { id = "pomodoro-skip", icon = "skip_next", label = "Skip", on_clicked = model.skip },
        { id = "pomodoro-reset", icon = "restart_alt", label = "Reset", on_clicked = model.reset },
      },
      controls.segments {
        id = "pomodoro-plan", width = w, items = plans, current = function() return session().plan end,
        on_changed = model.set_plan,
      },
      note("pomodoro-note", w, function() return model.message:get() end),
    },
  }
end

return M
