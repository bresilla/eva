-- One call screen for the desktop and the lock. The host gives the model and a
-- `look` (`C`, the colour roles; `text(props)`, `icon(name, size, color, props)`,
-- `action(props)`, a press target; `round(r)`, the theme's corners; `bounce`,
-- `{ duration, easing }` for what springs back). Everything here is the screen.
--
--   local node = require("themes.call_screen").build { phone = model, look = look,
--     width = fn, height = fn, compact = false }
--
-- `compact` is the desk's heads-up card; otherwise it fills what it is given.
-- An incoming call is taken by pulling the orb to a side of its rail, or by a
-- press on that side: a field of distance shapes, so the rail swells out to
-- the orb and runs into the target it reaches.
local morf = require("morf")
local ui = require("morf.ui")
local S = require("themes.spacing")

local M = {}

M.AVATAR = 96
local ROUND = 72        -- a round button
local ORB = 80          -- the orb and its rail's height
-- How far along the rail a pull commits, of the way to its end.
local COMMIT = 0.7

--- `m:ss`, or `h:mm:ss`.
function M.clock(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local h, m, s = seconds // 3600, (seconds % 3600) // 60, seconds % 60
  if h > 0 then return ("%d:%02d:%02d"):format(h, m, s) end
  return ("%d:%02d"):format(m, s)
end

local function status(phone)
  local stage = phone.stage:get()
  if stage == "ended" then return phone.ended:get() end
  if stage == "incoming" then return "Incoming call" end
  if stage == "dialing" then
    local row = phone.current()
    return row and row.state == "ringing-out" and "Ringing…" or "Calling…"
  end
  if phone.conference() then return "Conference · " .. M.clock(phone.seconds:get()) end
  if phone.on_hold() then return "On hold" end
  return M.clock(phone.seconds:get())
end

-- A round button with a caption: `on` lights it.
local function round_button(look, spec)
  local C = look.C
  local size = spec.size or ROUND
  local function lit() return spec.on and spec.on() end
  local function face()
    if spec.tone == "danger" then return C.error end
    if lit() then return C.primary end
    return C.surfaceContainerHigh
  end
  local function ink()
    if spec.tone == "danger" then return C.onError end
    return lit() and C.onPrimary or C.onSurface
  end
  local press = look.action {
    id = spec.id, accessible_name = spec.name, width = size, height = size, cursor = "pointer",
    enabled = spec.enabled, on_clicked = spec.on_clicked,
    ui.Rect { anchors = { fill = true }, radius = look.round(size / 2), color = face,
      behavior = { color = { duration = 150 } } },
    look.icon(spec.icon, size // 2 - S.xs, ink, { anchors = { center_in = true } }),
  }
  local column = { gap = S.s, align = "center", press }
  if spec.caption then
    column[#column + 1] = look.text { text = spec.caption, font_size = S.m + S.xxs,
      color = function() return C.onSurfaceVariant end }
  end
  return ui.Column(column)
end

-- The rail: decline at one end, answer at the other.
local function rail(look, phone, width)
  local C = look.C
  local function reach() return math.max(1, (width() - ORB) / 2) end
  local orb
  local function settle()
    morf.animation.play { { node = orb, property = "translate_x", to = 0,
      duration = look.bounce.duration, easing = look.bounce.easing } }
  end
  local function act(direction)
    if direction > 0 then phone.answer() else phone.decline() end
  end
  local held = morf.signal("eva.call.rail.held", false)
  orb = ui.MouseArea {
    id = "call-orb", width = ORB, height = ORB, anchors = { horizontal_center = true },
    on_panned = function(phase, dx, _, vx)
      if phase == "begin" then held:set(true) return true end
      local at = math.max(-reach(), math.min(reach(), dx or 0))
      if phase == "update" then orb.translate_x = at return end
      held:set(false)
      local fling = math.abs(vx or 0) > 900 and math.abs(at) > ORB / 2
      if phase == "end" and (math.abs(at) >= reach() * COMMIT or fling) then
        orb.translate_x = at > 0 and reach() or -reach()
        act(at)
        return
      end
      settle()
    end,
    ui.Rect { anchors = { fill = true }, radius = look.round(ORB / 2),
      color = function() return C.primary end,
      scale = function() return held:get() and 0.92 or 1 end,
      behavior = { scale = { duration = 120 } } },
    look.icon("call", ORB // 2 - S.xs, function() return C.onPrimary end, { anchors = { center_in = true } }),
  }
  local function target(id, name, side, icon, color, on_clicked)
    return look.action {
      id = id, accessible_name = name, width = ORB, height = ORB, cursor = "pointer",
      anchors = side == "left" and { left = true } or { right = true }, on_clicked = on_clicked,
      look.icon(icon, ORB // 2 - S.m, color, { anchors = { center_in = true } }),
    }
  end
  return ui.Item {
    id = "call-rail", width = width, height = ORB,
    ui.Sdf {
      anchors = { fill = true }, fill_color = function() return C.surfaceContainerHigh end,
      blend = S.xl, blend_profile = "circular",
      ui.SdfShape { id = "call-rail-track", shape = "box", radius = look.round(ORB / 2),
        anchors = { fill = true, top_margin = S.m, bottom_margin = S.m } },
      ui.SdfShape { id = "call-rail-orb", shape = "box", radius = look.round(ORB / 2),
        operation = "smooth_union", track = orb },
    },
    target("call-decline", "Decline", "left", "call_end", function() return C.error end, phone.decline),
    target("call-answer", "Answer", "right", "call", function() return C.primary end, phone.answer),
    orb,
  }
end

local function keypad(look, phone, width)
  local pad = require("themes.phone_pad").build { look = look, prefix = "call-key",
    on_key = function(key) phone.tone(key) end }
  return ui.Item { id = "call-keypad", width = width, height = pad.height,
    visible = function() return phone.keypad:get() end,
    ui.Item { width = pad.width, height = pad.height, anchors = { horizontal_center = true }, pad.node },
  }
end

local function waiting_card(look, phone, width)
  local C = look.C
  local function row() return phone.waiting() end
  return ui.Item {
    id = "call-waiting", width = width, height = S.TOUCH * 2,
    visible = function() return row() ~= nil end,
    ui.Rect { anchors = { fill = true }, radius = look.round(S.l),
      color = function() return C.surfaceContainerHigh end },
    ui.Column { anchors = { left = true, vertical_center = true, left_margin = S.l }, gap = S.xxs,
      look.text { text = "Call waiting", font_size = S.m + S.xxs,
        color = function() return C.onSurfaceVariant end },
      look.text { id = "call-waiting-name", font_size = S.l,
        text = function() local r = row() return r and r.label or "" end },
    },
    ui.Row { anchors = { right = true, vertical_center = true, right_margin = S.m }, gap = S.s,
      round_button(look, { id = "call-waiting-decline", name = "Decline", icon = "call_end", tone = "danger",
        size = S.TOUCH, on_clicked = phone.decline }),
      round_button(look, { id = "call-waiting-answer", name = "Hold this call and answer", icon = "call",
        size = S.TOUCH, on = function() return true end, on_clicked = phone.answer }),
    },
  }
end

local function controls(look, phone, width)
  local buttons = {
    round_button(look, { id = "call-mute", name = "Mute", caption = "Mute", icon = "mic_off",
      on = phone.muted, enabled = phone.audio_ready, on_clicked = function() phone.set_muted(not phone.muted()) end }),
    round_button(look, { id = "call-keypad-toggle", name = "Keypad", caption = "Keypad", icon = "dialpad",
      on = function() return phone.keypad:get() end,
      on_clicked = function() phone.keypad:set(not phone.keypad:get()) end }),
    round_button(look, { id = "call-speaker", name = "Speaker", caption = "Speaker", icon = "volume_up",
      on = phone.on_speaker, enabled = phone.audio_ready,
      on_clicked = function() phone.set_speaker(not phone.on_speaker()) end }),
    round_button(look, { id = "call-hold", name = "Hold", caption = "Hold", icon = "pause",
      on = phone.on_hold, on_clicked = phone.hold }),
  }
  local merge = round_button(look, { id = "call-merge", name = "Merge calls", caption = "Merge", icon = "call_merge",
    on_clicked = phone.merge })
  merge.visible = function() return phone.held() ~= nil end
  buttons[#buttons + 1] = merge
  return ui.Item { id = "call-controls", width = width, height = ROUND + S.xl + S.s,
    ui.Row { anchors = { horizontal_center = true }, gap = S.l, table.unpack(buttons) } }
end

M.CHIP_W, M.CHIP_H = 240, S.TOUCH

--- A call left running: who and how long, and a press to go back to it.
function M.chip(spec)
  local phone, look = spec.phone, spec.look
  local C = look.C
  return look.action {
    id = "call-chip", accessible_name = "Back to the call", width = M.CHIP_W, height = M.CHIP_H, cursor = "pointer",
    on_clicked = function() phone.minimised:set(false) end,
    ui.Rect { anchors = { fill = true }, radius = look.round(M.CHIP_H / 2), color = function() return C.primary end },
    ui.Row { anchors = { center_in = true }, gap = S.s, align = "center",
      look.icon("call", S.l + S.xs, function() return C.onPrimary end),
      look.text { id = "call-chip-text", font_size = S.m + S.xs, color = function() return C.onPrimary end,
        text = function()
          local row = phone.current()
          return (row and row.label or "Call") .. " · " .. M.clock(phone.seconds:get())
        end },
    },
  }
end

--- The screen for `spec.phone`, `spec.width` by `spec.height` (fns). `held_open`
--- leaves out the way back to the phone: the lock has none to go to.
function M.build(spec)
  local phone, look, width, height = spec.phone, spec.look, spec.width, spec.height
  local C = look.C
  local compact = spec.compact
  local function inner() return math.max(1, width() - 2 * S.xl) end
  local function stage() return phone.stage:get() end
  local function who()
    local row = phone.current()
    return row and row.label or ""
  end
  local function initial()
    local row = phone.current()
    if not row or row.name == "" then return "" end
    return utf8.char(utf8.codepoint(row.name, 1)):upper()
  end
  local face = compact and S.TOUCH + S.s or M.AVATAR
  local avatar = ui.Item { id = "call-avatar", width = face, height = face,
    ui.Sdf { anchors = { fill = true }, fill_color = function() return C.primaryContainer end,
      blend = S.s,
      ui.SdfShape { shape = "box", radius = look.round(face / 2), anchors = { fill = true } },
    },
    look.text { id = "call-initial", anchors = { center_in = true }, text = initial, font_size = face // 2,
      color = function() return C.onPrimaryContainer end },
    look.icon("person", face // 2, function() return C.onPrimaryContainer end,
      { anchors = { center_in = true }, visible = function() return initial() == "" end }),
  }
  local number = look.text { id = "call-number", font_size = compact and S.m + S.xxs or S.l,
    color = function() return C.onSurfaceVariant end,
    visible = function()
      local row = phone.current()
      return row ~= nil and row.name ~= ""
    end,
    text = function() local row = phone.current() return row and row.number or "" end }
  local name = look.text { id = "call-name", text = who, font_size = compact and S.l + S.xxs or S.xl + S.xl }
  local said = look.text { id = "call-status", text = function() return status(phone) end,
    font_size = compact and S.m + S.xxs or S.l + S.xxs, color = function() return C.onSurfaceVariant end }
  local head
  if compact then
    head = ui.Row { id = "call-head", gap = S.m, align = "center", avatar,
      ui.Column { gap = S.xxs, name, number, said } }
  else
    head = ui.Column { id = "call-head", gap = S.s, align = "center", avatar, name, number, said }
  end
  local talking = ui.Column { id = "call-talking", gap = S.l, align = "center",
    visible = function() local s = stage() return s == "talking" or s == "dialing" end,
    keypad(look, phone, inner),
    controls(look, phone, inner),
    round_button(look, { id = "call-end", name = "End call", icon = "call_end", tone = "danger",
      on_clicked = phone.hangup }),
  }
  local take = ui.Item { id = "call-incoming", width = inner, height = ORB,
    visible = function() return stage() == "incoming" end, rail(look, phone, inner) }
  local foot = ui.Item { id = "call-foot", width = inner,
    height = function()
      if stage() == "incoming" then return ORB end
      if stage() == "talking" or stage() == "dialing" then return talking.layout_height or 0 end
      return 0
    end,
    take, talking }
  local waiting = waiting_card(look, phone, inner)
  if compact then
    local body = ui.Column { id = "call-body", x = S.xl, y = S.xl, gap = S.l, head, waiting, foot }
    return ui.Rect {
      id = "call-screen", width = width, height = function() return (body.layout_height or 0) + 2 * S.xl end,
      radius = look.round(S.xl), color = function() return C.surface end,
      border_width = 1, border_color = function() return C.outlineVariant end,
      body,
    }
  end
  local leave = not spec.held_open and look.action {
    id = "call-minimise", accessible_name = "Back to the phone", width = S.TOUCH, height = S.TOUCH, x = S.m,
    y = S.xxl + S.l, cursor = "pointer", on_clicked = function() phone.minimised:set(true) end,
    visible = function() local s = stage() return s == "talking" or s == "dialing" end,
    look.icon("expand_more", S.xl + S.xs, function() return C.onSurface end, { anchors = { center_in = true } }),
  } or nil
  return ui.Rect {
    id = "call-screen", width = width, height = height, color = function() return C.surface end,
    leave,
    ui.Item { width = width, y = function() return math.floor(height() * 0.14) end, height = 1,
      ui.Item { anchors = { horizontal_center = true }, width = 1, height = 1,
        ui.Item { x = function() return -(head.layout_width or 0) / 2 end, width = 1, height = 1, head } } },
    ui.Column { id = "call-body", gap = S.xl, x = S.xl,
      y = function() return height() - (S.xxl + S.l) - (foot.height or 0) - (phone.waiting() and S.TOUCH * 2 + S.xl or 0) end,
      waiting, foot },
  }
end

return M
