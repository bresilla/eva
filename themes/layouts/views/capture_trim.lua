-- A recording in the editor: its frame, a timeline whose range and two grips are
-- one distance field, and what can be saved. Mouse and finger alike.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local C, S = theme.color, theme.space
local V = {}

local TRACK_H = S.TARGET + S.xs

function V.build(M)
  local function room()
    morf.window.screens_revision()
    return (morf.screens or {})[1] or { width = 1920, height = 1080 }
  end
  local function card_w() return math.min(720, room().width - 2 * S.m) end
  local function inner() return card_w() - 2 * S.l end
  local function picture_h() return math.min(math.floor(inner() * 9 / 16), room().height - 240) end
  local function x_of(seconds)
    local length = M.duration:get()
    return length > 0 and seconds / length * inner() or 0
  end
  local function grip_x(which)
    return x_of(which == "from" and M.from:get() or M.to:get()) - S.xs
  end

  local holding
  local track = ui.Item { id = "capture-trim-track", x = S.l, width = inner, height = TRACK_H,
    y = function() return S.xxl + S.l + picture_h() end,
    ui.Sdf { anchors = { fill = true }, fill_color = function() return C.surfaceContainerHighest end,
      ui.SdfShape { shape = "box", y = TRACK_H / 2 - S.xs, width = inner, height = S.s, radius = kit.round(S.xs) } },
    ui.Sdf { id = "capture-trim-range", anchors = { fill = true }, fill_color = function() return C.primary end, blend = S.xs,
      ui.SdfShape { shape = "box", y = TRACK_H / 2 - S.xs, height = S.s,
        x = function() return x_of(M.from:get()) end,
        width = function() return math.max(1, x_of(M.to:get()) - x_of(M.from:get())) end },
      ui.SdfShape { shape = "box", operation = "smooth_union", y = S.s, width = S.s, height = TRACK_H - 2 * S.s,
        radius = kit.round(S.xs), x = function() return grip_x("from") end },
      ui.SdfShape { shape = "box", operation = "smooth_union", y = S.s, width = S.s, height = TRACK_H - 2 * S.s,
        radius = kit.round(S.xs), x = function() return grip_x("to") end },
    },
    ui.MouseArea { id = "capture-trim-area", anchors = { fill = true }, cursor = "pointer",
      on_pressed = function(_, _, x)
        local length = M.duration:get()
        if length <= 0 then return end
        local at = x / inner() * length
        holding = math.abs(at - M.from:get()) <= math.abs(at - M.to:get()) and "from" or "to"
        M.move(holding, at)
      end,
      on_position_changed = function(_, _, _, _, x)
        if holding then M.move(holding, x / inner() * M.duration:get()) end
      end,
      on_dragged = function(_, _, _, _, x)
        if holding then M.move(holding, x / inner() * M.duration:get()) end
      end,
      on_released = function() holding = nil end },
  }

  local function ready() return M.duration:get() > 0 and not M.busy:get() end
  local buttons = ui.Row { x = S.l, gap = S.s, y = function() return S.xxl + S.l + picture_h() + TRACK_H + S.xl end,
    P.button { id = "capture-trim-save", label = "Save trim", enabled = ready, on_clicked = function() M.save("trim") end },
    P.button { id = "capture-trim-gif", label = "Save GIF", enabled = ready, on_clicked = function() M.save("gif") end },
    P.button { id = "capture-trim-cancel", label = "Cancel", on_clicked = M.close },
  }

  local function card_h() return S.xxl + S.l + picture_h() + TRACK_H + S.xl + S.TARGET + S.l end
  local card = ui.Item { id = "capture-trim-card", anchors = { center_in = true }, width = card_w, height = card_h,
    kit.card { anchors = { fill = true }, radius = kit.round(S.xl), color = function() return C.surfaceContainerHigh end },
    ui.MouseArea { anchors = { fill = true } },
    kit.heading { id = "capture-trim-title", x = S.l, y = S.m, text = "Trim", scope = "capture.trim", font_size = 16 },
    kit.label { id = "capture-trim-span", x = S.l, y = S.m + 2, width = inner, height = 18, horizontal_alignment = "right",
      font_size = 12, color = kit.ink("lo"),
      text = function()
        return ("%s to %s of %s"):format(M.clock(M.from:get()), M.clock(M.to:get()), M.clock(M.duration:get()))
      end },
    ui.Rect { x = S.l, y = S.xxl + S.s, width = inner, height = picture_h, radius = kit.round(S.m), clip = true,
      color = function() return C.surfaceContainerHighest end,
      ui.Image { id = "capture-trim-frame", anchors = { fill = true }, fill_mode = "preserve_aspect_fit",
        source = function() return M.frame:get() end },
    },
    track, buttons,
    kit.text { id = "capture-trim-note", x = S.l, y = function() return card_h() - S.l - S.xs end, width = inner, height = 16,
      elide = "right", font_size = 11, color = function() return C.onSurfaceVariant end,
      text = function() return M.note:get() end },
  }

  return ui.Item { id = "capture-trim", anchors = { fill = true }, z = 120,
    kit.surface { anchors = { fill = true }, color = function() return C.scrim:alpha(.56) end },
    ui.MouseArea { anchors = { fill = true }, focus = true,
      on_key_pressed = function(key) if key == 65307 then M.close() end end },
    card,
  }
end

return V
