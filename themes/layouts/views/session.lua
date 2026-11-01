-- The session menu: a power console.
--
-- The title and where the focus is, the person signed in (picture and
-- name), then one row per action: its icon, the action large, its detail
-- and the theme's code. A cursor frame glides between rows with the focus,
-- stretching along its run; the focused row's ground swells its corners
-- and its trailing emphasis sweeps out. The focused icon takes the
-- action's signal (shut down the alert one, restart the warning one).
-- Opening, the rows bud out of the frame one after another. Nothing moves
-- at rest. Any wording past the plain one is the theme's (L.term,
-- kit.code).
--
-- Actions, focus, keys and the dim are shell/session.lua's contract.
local morf = require("morf")
local ui = require("morf.ui")
local unicase = require("lib.util.unicase")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local C = theme.color
local V = {}

function V.build(M)
  -- Under a finger it takes most of the width, and taller rows.
  local responsive = require("responsive")
  local TOUCH = responsive.sheets()
  local NARROW, PAD, GAP = TOUCH and responsive.fit(560, 24) or 300, 12, 8
  local RW = NARROW - 2 * PAD
  local LABEL_H = L.lh(L.role_size("label"))
  local NAME = math.floor(L.role_size("title") * 1.15)
  local NAME_H = L.lh(NAME)
  local ROW_H = math.max(TOUCH and 72 or 54, 6 + NAME_H + LABEL_H + 8)
  local TITLE_H = L.heading_h(L.role_size("section"))
  local TITLE_Y = 12
  local HEAD_H = TITLE_Y + TITLE_H + 8
  local USER = math.floor(L.role_size("title") * 1.3)
  local OP_H = math.max(56, 2 + LABEL_H + L.lh(USER) + 6)
  local ROWS_Y = HEAD_H + OP_H + 14
  local FOOT_H = LABEL_H + 16
  -- One column where the screen has the height; two without the operator block
  -- where it does not.
  local count = #M.actions
  local function rows_of(columns) return (count + columns - 1) // columns end
  local function stack(columns, top)
    local rows = rows_of(columns)
    return top + rows * ROW_H + (rows - 1) * GAP + FOOT_H + 8
  end
  local screen = morf.screens and morf.screens[1]
  local COLUMNS = (not TOUCH and screen and stack(1, ROWS_Y) > screen.height - 2 * theme.BORDER) and 2 or 1
  local WIDE = COLUMNS == 2
  if WIDE then ROWS_Y = HEAD_H + 8 end
  local WIDTH = WIDE and 2 * RW + GAP + 2 * PAD or NARROW
  -- Who holds back sleep or shutdown: a line each, where there are any.
  local BLOCK_ROWS = 3
  local function blockers()
    local blocked, out, seen = M.blocked:get(), {}, {}
    for _, kind in ipairs { "sleep", "shutdown" } do
      for _, row in ipairs(blocked[kind] or {}) do
        local line = row.who .. (row.why ~= "" and (": " .. row.why) or "")
        if not seen[line] then seen[line] = true out[#out + 1] = line end
      end
    end
    return out
  end
  local function block_height()
    local shown = math.min(BLOCK_ROWS, #blockers())
    return shown > 0 and (shown + 1) * LABEL_H + 8 or 0
  end
  local function HEIGHT() return stack(COLUMNS, ROWS_Y) + block_height() end
  local function focused() return M.focus:get() end
  local function signal_of(item) return kit.signal(item and item.signal or "accent") end
  local function focused_item() return M.actions[focused()] end
  local function column_of(index) return (index - 1) // rows_of(COLUMNS) end
  local function line_of(index) return (index - 1) % rows_of(COLUMNS) end
  local function row_x(index) return PAD + column_of(index) * (RW + GAP) end
  local function row_y(index) return ROWS_Y + line_of(index) * (ROW_H + GAP) end

  -- The line under an action's name: its countdown, what blocks it, or what it does.
  local function detail_of(item)
    if M.pending:get() == item.id then return ("In %d s. Press again to go now"):format(M.left:get()) end
    local blocked = item.blocked_by and M.blocked:get()[item.blocked_by] or {}
    if #blocked > 0 then
      return "Blocked by " .. blocked[1].who .. (#blocked > 1 and (" and " .. (#blocked - 1) .. " more") or "")
    end
    if item.id == "switch" then
      local target = M.others:get()[1]
      if target then return "Lock, and go to " .. target.user end
    end
    return item.detail
  end

  -- The operator: picture (or the theme's mark), name and tags.
  local face = M.picture
  local PIC = OP_H - 8
  local picture = ui.Item {
    id = "session-picture", x = PAD, y = HEAD_H + 4, width = PIC, height = PIC,
    kit.shape { anchors = { fill = true }, shape = "square", color = function() return C.surfaceContainerHigh end },
    face and ui.Image { anchors = { fill = true, margins = 4 }, source = face, fill_mode = "preserve_aspect_crop",
      mask = kit.shape { width = PIC - 6, height = PIC - 6, shape = "square", color = "#ffffff" } }
      or kit.icon("person", 30, kit.signal("accent"), { anchors = { center_in = true }, fill = true }),
    L.decor_box("corners", { length = 7, color = kit.signal("accent"), inset = -3 }),
  }
  local OX = PAD + PIC + 12
  local OW = WIDTH - PAD - OX
  local code = kit.code(M.username, "UID ####")
  local NAME_Y = math.floor((OP_H - LABEL_H - L.lh(USER)) / 2)
  local operator = ui.Item { x = OX, y = HEAD_H + 4, width = OW, height = OP_H,
    kit.label { y = NAME_Y, width = OW, elide = "right",
      text = code ~= "" and ("Signed in  ·  " .. code) or "Signed in as" },
    kit.label { y = NAME_Y + LABEL_H, width = OW, height = L.lh(USER), elide = "right", text = tostring(M.username),
      font_size = USER, font_weight = 300, color = kit.ink("hi") },
  }

  local rows = {}
  local budding = morf.signal("eva.session.budding", false)
  local layers = {
    id = "session-field", anchors = { fill = true },
    blend = function() return theme.motion.liquid_cards ~= false and budding:get() and 16 or 0 end,
    behavior = { blend = { duration = 300, easing = theme.ease.standard } },
  }
  local REST = L.control_round(ROW_H)
  for index, item in ipairs(M.actions) do
    local on = function() return focused() == index end
    local signal = signal_of(item)
    local counting = function() return M.pending:get() == item.id end
    local area = kit.action {
      id = "session-" .. item.id,
      x = row_x(index), y = row_y(index),
      width = RW, height = ROW_H, cursor = "pointer",
      on_entered = function() M.focus:set(index) end,
      on_clicked = function() M.activate(item.id) end,
      kit.icon(item.icon, 22, function() return on() and signal() or kit.ink("hi")() end,
        { x = 12, y = math.floor((ROW_H - 22) / 2), fill = on }),
      kit.label { x = 44, y = 4, width = RW - 44 - 92, height = NAME_H, elide = "right", text = item.name,
        font_size = NAME, font_weight = 300,
        color = function() return on() and kit.ink("hi")() or kit.ink("lo")() end,
        behavior = { color = { duration = theme.duration.small } } },
      kit.label { id = "session-" .. item.id .. "-detail", x = 45, y = 4 + NAME_H, width = RW - 45 - 26, elide = "right",
        text = function() return detail_of(item) end,
        color = function() return counting() and signal() or kit.ink("lo")() end },
      -- Its letter, in the corner.
      kit.label { id = "session-" .. item.id .. "-key", anchors = { right = true, right_margin = 12 }, y = 4 + NAME_H,
        width = 16, horizontal_alignment = "right", text = unicase.upper(item.key or ""),
        color = kit.stroke("mark") },
      kit.action { id = "session-" .. item.id .. "-cancel", anchors = { right = true, right_margin = 8 },
        y = 2, width = 76, height = NAME_H + 2, cursor = "pointer", visible = counting,
        accessible_name = "Cancel", on_clicked = M.cancel,
        kit.label { anchors = { center_in = true }, text = "Cancel", color = kit.ink("hi") } },
      -- The focused row's trailing emphasis sweeps out to the right edge.
      ui.Item { x = RW - 86, y = 4 + math.floor((NAME_H - 16) / 2), height = 16, clip = true,
        width = function() return on() and not counting() and 76 or 1 end,
        opacity = function() return on() and not counting() and 1 or 0 end,
        behavior = { width = { duration = theme.duration.large, easing = theme.ease.spatial },
          opacity = { duration = theme.duration.small } },
        L.decor_box("hatch", { width = 76, height = 16, spacing = 8, weight = 3.5, color = signal }) },
      -- Its code holds the same slot while the row rests.
      kit.label { anchors = { right = true, right_margin = 8 }, y = 4 + math.floor((NAME_H - LABEL_H) / 2),
        width = 84, horizontal_alignment = "right", elide = "left", color = kit.stroke("mark"),
        opacity = function() return on() and 0 or 1 end, behavior = { opacity = { duration = theme.duration.small } },
        text = kit.code(item.id, "##-### // SYS") },
    }
    layers[#layers + 1] = ui.SdfShape {
      id = "session-" .. item.id .. "-shape", shape = "box", track = area,
      operation = index == 1 and "union" or "smooth_union",
      radius = function() return on() and REST * 2 or REST end,
      fill_color = function()
        local base = area.hovered and C.surfaceContainerHigh or C.surfaceContainer
        return base:mix(signal(), on() and .1 or .02)
      end,
      behavior = { fill_color = { duration = theme.duration.small },
        radius = { duration = theme.duration.large, easing = theme.ease.spatial } },
    }
    rows[index] = area
  end

  -- The cursor: a frame over the focused row that glides and stretches.
  local cursor = ui.Item { width = RW, height = ROW_H,
    x = function() return row_x(focused()) end,
    y = function() return row_y(focused()) end,
    behavior = { x = ui.spring { stiffness = 340, damping = 24 }, y = ui.spring { stiffness = 340, damping = 24 } },
    stretch = kit.STRETCH or { stiffness = 300, damping = 15, scale = .2, max = .3 },
    kit.surface { anchors = { fill = true }, color = "transparent", border_width = 1, radius = REST * 2,
      border_color = kit.stroke("hot") },
    L.decor_box("corners", { length = 9, weight = 2, inset = -3, color = kit.stroke("hot") }),
  }

  local keys
  keys = ui.TextInput {
    id = "session-keys",
    width = 1, height = 1, opacity = 0, tab_navigation = false,
    on_escape = M.close,
    on_accepted = M.accept,
    on_key_pressed = M.key,
    -- A letter lands in the field: it goes to its action, and the field empties.
    on_text_changed = function(text)
      if text == "" then return end
      keys.text = ""
      M.key(nil, text:sub(-1):lower())
    end,
  }

  local content = ui.Item {
    anchors = { fill = true },
    -- A pull toward its edge drags it shut.
    on_panned = function(phase, dx, dy, vx)
      local drawer = require("session").drawer
      if phase == "begin" then
        return dx > 0 and math.abs(dx) > math.abs(dy) * 1.2 and drawer.begin_drag()
      elseif phase == "update" then drawer.drag_by(dx)
      else drawer.end_drag(vx or 0, phase == "cancel") end
    end,
    -- The panel's empty parts take presses too.
    ui.MouseArea { anchors = { fill = true }, z = -1 },
    L.decor_box("corners", { length = 10 }),
    kit.heading { id = "session-title", x = PAD, y = TITLE_Y, width = RW - 80, height = TITLE_H, level = "section",
      text = "Session", active = function() return M.opened:get() end, ink = kit.ink("hi") },
    -- Where the focus is, sized to its text (no box a wide face overflows).
    kit.label { id = "session-position", anchors = { right = true, right_margin = PAD },
      y = TITLE_Y + math.floor((TITLE_H - LABEL_H) / 2), horizontal_alignment = "right",
      text = function() return ("%d of %d"):format(focused(), #M.actions) end },
    not WIDE and picture or ui.Item {}, not WIDE and operator or ui.Item {},
    L.rule { x = PAD, y = ROWS_Y - 8, width = WIDTH - 2 * PAD },
    ui.Sdf(layers),
    ui.Item { anchors = { fill = true }, table.unpack(rows) },
    cursor,
    -- What holds the machine back, named.
    ui.Column { id = "session-blockers", x = PAD, y = stack(COLUMNS, ROWS_Y) - FOOT_H - 8 + 2, gap = 0,
      visible = function() return block_height() > 0 end,
      kit.label { text = "Held back by", color = kit.signal("warn") },
      (function()
        local lines = { gap = 0 }
        for index = 1, BLOCK_ROWS do
          lines[#lines + 1] = kit.label { id = "session-blocker-" .. index, width = WIDTH - 2 * PAD, elide = "right",
            visible = function() return blockers()[index] ~= nil end,
            text = function() return blockers()[index] or "" end }
        end
        return ui.Column(lines)
      end)() },
    L.rule { x = PAD, anchors = { bottom = true, bottom_margin = FOOT_H - 4 }, width = WIDTH - 2 * PAD },
    kit.label { x = PAD, anchors = { bottom = true, bottom_margin = 8 }, width = RW - 80, elide = "right",
      text = "Arrows · Letters · Esc" },
    -- The focused action's state word, where the theme has one.
    kit.label { anchors = { right = true, right_margin = PAD, bottom = true, bottom_margin = 8 }, width = 70,
      horizontal_alignment = "right", elide = "left", color = function() return signal_of(focused_item())() end,
      text = function()
        local item = focused_item()
        return item and L.term("session." .. item.id, "") or ""
      end },
    keys,
  }

  -- Opening, each row buds out of the frame's edge in turn.
  local settle
  local function bud()
    budding:set(true)
    if settle then settle:cancel() end
    settle = morf.time.timer(60 + #rows * 60 + 460, function() settle = nil budding:set(false) end, false)
    for k, node in ipairs(rows) do
      morf.animation.play {
        { parallel = {
          { node = node, property = "translate_x", from = 90, to = 0, duration = 520,
            easing = theme.ease.spatial, delay = 60 + (k - 1) * 60 },
          { node = node, property = "scale_y", from = 0.1, to = 1, duration = 420,
            easing = theme.ease.spatial, delay = 60 + (k - 1) * 60 },
        } },
      }
    end
    morf.animation.play { { node = cursor, property = "opacity", from = 0, to = 1, duration = 260, delay = 300 } }
  end

  local function dim()
    return kit.surface {
      id = "session-dim",
      anchors = { fill = true },
      color = function() return C.surface:alpha(M.opened:get() and .55 or 0) end,
      behavior = { color = { duration = theme.duration.normal, easing = theme.ease.standard } },
      -- A press on it shuts the menu: the drawer's close policy, not a
      -- catcher here.
    }
  end

  return { content = content, width = WIDTH, height = HEIGHT, edge = "right", dim = dim,
    shown = function(on) keys.focus = on if on then bud() end end }
end
return V
