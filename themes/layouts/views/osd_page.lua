-- The right panel's On-screen displays page, behind Eva's row: the displays
-- this machine has, then for the one chosen a small screen with its nine
-- places, its switches and a Try button. In the page template
-- (themes/layouts/page.lua).
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local C = theme.color
local S = theme.space

local M = {}

local WORDS = { top_left = "Top left", top_center = "Top centre", top_right = "Top right",
  center_left = "Left edge", center = "Centre", center_right = "Right edge",
  bottom_left = "Bottom left", bottom_center = "Bottom centre", bottom_right = "Bottom right" }

-- The little display on the screen: how long and how deep at each place.
local function mark_size(position, w, h)
  local long, deep = math.floor(w * .24), math.max(S.s, math.floor(h * .09))
  if position == "center" then return long, math.floor(long * .66) end
  if position == "center_left" or position == "center_right" then return deep, math.floor(h * .34) end
  return long, deep
end
local function mark_place(position, w, h)
  local mw, mh = mark_size(position, w, h)
  local x, y = math.floor((w - mw) / 2), math.floor((h - mh) / 2)
  if position:match("left$") then x = 0 elseif position:match("right$") then x = w - mw end
  if position:match("^top") then y = 0 elseif position:match("^bottom") then y = h - mh end
  return x, y, mw, mh
end

--- The screen: nine places to press, and the display travelling to the chosen.
local function preview(model, w)
  local _, _, dw, dh = require("bar").desk()
  local aspect = dw / math.max(1, dh)
  local H = math.floor(aspect >= 1 and math.min(w / aspect, 188) or 228)
  local W = math.floor(H * aspect)
  local x = math.floor((w - W) / 2)
  local screen = kit.surface { id = "osd-screen", x = x, width = W, height = H, radius = kit.round(S.s),
    color = function() return C.surfaceContainerHighest end }
  local area = ui.Item { x = x, width = W, height = H }
  local function chosen() return model.position() end
  local spring = theme.spring.spatial
  for i, position in ipairs(model.POSITIONS) do
    local column, row = (i - 1) % 3, (i - 1) // 3
    local cell_w, cell_h = math.floor(W / 3), math.floor(H / 3)
    local mx, my, mw, mh = mark_place(position, W, H)
    local press
    press = kit.action { id = "osd-place-" .. position, x = column * cell_w, y = row * cell_h, width = cell_w,
      height = cell_h, cursor = "pointer", accessible_name = WORDS[position],
      visible = function() return model.allows(position) end,
      on_clicked = function() model.place(position) end,
      kit.surface { x = mx - column * cell_w, y = my - row * cell_h, width = mw, height = mh, radius = kit.round(S.xs),
        color = function() return kit.stroke(press and press.hovered and "mark" or "idle")() end },
    }
    ui.reparent(press, area)
  end
  ui.reparent(kit.surface { id = "osd-mark", radius = kit.round(S.xs),
    color = function() return C.primary end,
    x = function() return (mark_place(chosen(), W, H)) end,
    y = function() return (select(2, mark_place(chosen(), W, H))) end,
    width = function() return (select(3, mark_place(chosen(), W, H))) end,
    height = function() return (select(4, mark_place(chosen(), W, H))) end,
    behavior = { x = spring, y = spring, width = spring, height = spring },
  }, area)
  return ui.Item { id = "osd-preview", width = w, height = H, screen, area }
end

--- The displays there are, as a grid of icons.
local function grid(model, w)
  local SIZE, GAP = S.TOUCH, S.xs
  local columns = math.max(1, (w + GAP) // (SIZE + GAP))
  local function here()
    local list = {}
    for _, kind in ipairs(model.kinds) do
      if model.present(kind.id) then list[#list + 1] = kind.id end
    end
    return list
  end
  local function slot(id)
    for i, candidate in ipairs(here()) do if candidate == id then return i end end
  end
  local node = ui.Item { id = "osd-kinds-grid", width = w,
    height = function() return ((#here() - 1) // columns + 1) * (SIZE + GAP) - GAP end }
  for _, kind in ipairs(model.kinds) do
    local function at() return (slot(kind.id) or 1) - 1 end
    local button = L.icon_button { id = "osd-kind-" .. kind.id, width = SIZE, height = SIZE, icon = kind.icon,
      name = kind.name, on = function() return model.selected() == kind.id end,
      on_clicked = function() model.select(kind.id) end }
    button.x = function() return (at() % columns) * (SIZE + GAP) end
    button.y = function() return (at() // columns) * (SIZE + GAP) end
    button.visible = function() return slot(kind.id) ~= nil end
    ui.reparent(button, node)
  end
  return node
end

local function holds(model, w)
  local row = { width = w }
  for _, ms in ipairs(model.HOLDS) do
    row[#row + 1] = { id = "osd-hold-" .. ms, group = "osd-hold", label = ms == 0 and "Auto" or ("%d s"):format(ms // 1000),
      selected = function() return model.hold() == ms end, on_clicked = function() model.set_hold(ms) end }
  end
  return P.buttons(row)
end

function M.build(model, w, h)
  local inner = P.inner(w)
  local function title() return model.kind().name end
  local function displayed() return not model.notifying() end
  return P.page { id = "osd-scroll", width = w, height = h, active = model.active,
    P.section { id = "osd-kinds", width = w, title = "Displays", grid(model, inner) },
    P.section { id = "osd-place", width = w, title = "Position",
      P.row { id = "osd-chosen", width = inner, icon = function() return model.kind().icon end, title = title,
        subtitle = function() return WORDS[model.position()] or "" end,
        trailing = P.button { id = "osd-try", label = "Try", icon = "play_arrow", tone = "primary",
          on_clicked = model.try } },
      preview(model, inner),
    },
    P.section { id = "osd-options", width = w, title = "Behaviour", visible = displayed,
      P.row { id = "osd-enabled", width = inner, icon = "visibility", title = "Show this display",
        subtitle = function() return model.enabled() and "Appears when it changes" or "Stays hidden" end,
        on = model.enabled, trailing = P.switch { id = "osd-enabled-switch", name = "Show this display",
          on = model.enabled, on_toggled = model.set_enabled } },
      P.row { id = "osd-percent", width = inner, icon = "percent", title = "Show the percentage", visible = model.level,
        on = model.percent, trailing = P.switch { id = "osd-percent-switch", name = "Show the percentage",
          on = model.percent, on_toggled = model.set_percent } },
      kit.subtitle { width = inner, font_size = theme.size.small, color = kit.ink("lo"), text = "How long it stays" },
      holds(model, inner),
    },
  }
end

return M
