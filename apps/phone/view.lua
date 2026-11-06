-- eva-phone's page in Tools: a dial pad, the recent calls and the contacts.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local model = require("apps.phone.model")
local C, S = theme.color, theme.space

local M = {}

local ROWS = 80
local MATCHES = 3

local function look()
  return { C = C, text = kit.text, icon = kit.icon, action = kit.action, round = kit.round }
end

local function dial(w, h)
  local pad = require("themes.phone_pad").build { look = look(), prefix = "phone-key",
    on_key = model.press, on_long = model.long_press }
  local rows = {}
  for index = 1, MATCHES do
    local function person() return model.matches()[index] end
    rows[index] = P.row { id = "phone-match-" .. index, width = w, height = S.TOUCH + S.s, icon = "person",
      visible = function() return person() ~= nil end,
      title = function() local p = person() return p and p.name or "" end,
      subtitle = function() return model.first_number(person()) end,
      on_clicked = function() model.call(model.first_number(person())) end }
  end
  rows.gap, rows.width = S.xxs, w
  local matches = ui.Column(rows)
  local call = kit.action {
    id = "phone-call", accessible_name = "Call", width = S.TOUCH + S.xl, height = S.TOUCH + S.xl,
    cursor = "pointer", on_clicked = function() model.call() end,
    ui.Rect { anchors = { fill = true }, radius = kit.round((S.TOUCH + S.xl) / 2),
      color = function() return C.primary end },
    kit.icon("call", S.xl + S.xs, function() return C.onPrimary end, { anchors = { center_in = true } }),
  }
  local foot = S.TOUCH + S.xl
  return ui.Item {
    id = "phone-dial", width = w, height = h,
    ui.Item { width = w, y = S.m, height = S.xxl + S.s,
      kit.text { id = "phone-number", anchors = { center_in = true }, font_size = S.xxl, color = kit.ink("hi"),
        text = function() local n = model.number:get() return n ~= "" and n or " " end } },
    ui.Item { y = S.xxl + S.xl, width = w, height = (S.TOUCH + S.s) * MATCHES, matches },
    ui.Item { width = w, height = S.l + S.s, y = function() return h() - pad.height - foot - 2 * S.l - S.xl end,
      kit.text { id = "phone-message", anchors = { center_in = true }, font_size = P.SUB, color = kit.ink("lo"),
        text = function() return model.message:get() end } },
    ui.Item { width = pad.width, height = pad.height, anchors = { horizontal_center = true },
      y = function() return h() - pad.height - foot - 2 * S.l end, pad.node },
    ui.Item { width = pad.width, height = foot, anchors = { horizontal_center = true },
      y = function() return h() - foot - S.s end,
      ui.Item { width = S.TOUCH + S.xl, height = foot, anchors = { horizontal_center = true }, call },
      ui.Item { width = S.TOUCH, height = S.TOUCH, anchors = { right = true, vertical_center = true },
        visible = function() return model.number:get() ~= "" end,
        L.icon_button { id = "phone-back", icon = "backspace", name = "Delete", width = S.TOUCH, height = S.TOUCH,
          on_clicked = model.back } },
    },
  }
end

local function recent_row(index, w)
  local function row() return model.recents()[index] end
  return P.row { id = "phone-recent-" .. index, width = w, height = P.ROW_H,
    visible = function() return row() ~= nil end,
    icon = function() local r = row() return r and r.icon or "call" end,
    on = function() local r = row() return r ~= nil and r.outcome == "missed" end,
    title = function() local r = row() return r and r.label or "" end,
    subtitle = function() local r = row() return r and model.detail(r) or "" end,
    on_clicked = function() local r = row() if r then model.call(r.number) end end,
    trailing = L.icon_button { id = "phone-block-" .. index, icon = "block", name = "Block this number",
      width = S.TOUCH, height = S.TOUCH,
      on = function() local r = row() return r ~= nil and model.blocked(r.number) end,
      on_clicked = function() local r = row() if r then model.toggle_block(r.number) end end } }
end

local function recents(w, h)
  local list = { gap = S.xxs, width = w }
  for index = 1, ROWS do list[index] = recent_row(index, w) end
  return ui.Item { id = "phone-recents", width = w, height = h,
    P.empty { id = "phone-recents-empty", icon = "call", title = "No calls yet",
      text = "Calls you make and miss show here.", width = w,
      visible = function() return #model.recents() == 0 end },
    (kit.scroll { id = "phone-recents-list", width = w, height = h, clip = true, ui.Column(list) }),
  }
end

local function person_row(index, w)
  local function person() return model.people()[index] end
  return P.row { id = "phone-person-" .. index, width = w, height = P.ROW_H,
    visible = function() return person() ~= nil end,
    icon = function() local p = person() return p and p.favourite and "star" or "person" end,
    on = function() local p = person() return p ~= nil and p.favourite end,
    title = function() local p = person() return p and p.name or "" end,
    subtitle = function() return model.first_number(person()) end,
    on_clicked = function() model.call(model.first_number(person())) end,
    trailing = ui.Row { gap = S.xs,
      L.icon_button { id = "phone-ice-" .. index, icon = "emergency", name = "Emergency contact",
        width = S.TOUCH, height = S.TOUCH,
        on = function() local p = person() return p ~= nil and p.emergency end,
        on_clicked = function()
          local p = person()
          if p then model.book.set_emergency(p.id, not p.emergency) end
        end },
      L.icon_button { id = "phone-star-" .. index, icon = "star", name = "Favourite",
        width = S.TOUCH, height = S.TOUCH,
        on = function() local p = person() return p ~= nil and p.favourite end,
        on_clicked = function()
          local p = person()
          if p then model.book.set_favourite(p.id, not p.favourite) end
        end } } }
end

local function people(w, h)
  local list = { gap = S.xxs, width = w }
  for index = 1, ROWS do list[index] = person_row(index, w) end
  local field = kit.text_field("entry", {
    id = "phone-search", width = w, height = S.TARGET, placeholder = "Search contacts",
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"),
    text = function() return model.query:get() end,
    on_text_changed = function(value) model.query:set(value) end,
  })
  local top = S.TARGET + S.m
  local function body() return math.max(1, h() - top) end
  return ui.Item { id = "phone-people", width = w, height = h, field,
    ui.Item { y = top, width = w, height = body,
      P.empty { id = "phone-people-empty", icon = "contacts", title = "No contacts",
        text = "vCards in the contacts folder show here.", width = w,
        visible = function() return #model.people() == 0 end },
      (kit.scroll { id = "phone-people-list", width = w, height = body, clip = true, ui.Column(list) }),
    } }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local tabs = kit.tabs { id = "phone", width = w, height = S.TOUCH + S.m, tab = model.tab, ids = "name",
    tabs = { { key = "dial", name = "Keypad", icon = "dialpad" }, { key = "recents", name = "Recents", icon = "history" },
      { key = "people", name = "Contacts", icon = "contacts" } } }
  local top = S.TOUCH + S.xl
  local function body() return math.max(1, h() - top) end
  local peeking = morf.signal("eva.phone.peeking", false)
  local function page(index, node)
    return ui.Item { x = function() return (index - 1) * w() end, width = w, height = body,
      visible = function() return model.tab:get() == index or peeking:get() end, node }
  end
  local track = ui.Item { width = function() return 3 * w() end, height = body,
    page(1, dial(w, body)), page(2, recents(w, body)), page(3, people(w, body)) }
  local pager = require("pager_drag").new { id = "phone", track = track, tab = model.tab, count = 3,
    offset = function(i) return (i - 1) * w() end, peeking = function(on) peeking:set(on) end,
    instant = function() return not peeking:get() end }
  return ui.Item { id = "phone-root", width = w, height = h, tabs,
    ui.Item { y = top, width = w, height = body, clip = true, on_panned = pager.on_panned,
      ui.MouseArea { anchors = { fill = true }, z = -1 }, track } }
end

return M
