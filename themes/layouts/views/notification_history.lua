-- Notification history, in the page template (themes/layouts/page.lua):
-- the panel's frame titles it "Notifications"; under that what silences them,
-- a way to take the last clear back, a summary card (how many, from how many
-- apps, Clear all), then one card per application under its shelf (Priority,
-- Conversations, Notifications, Silent) -- its picture, name, the card's word,
-- and its lines (shut) or, opened, every entry as a small status card with the
-- sender's buttons, a reply field, Dismiss, Copy and its tools. What is snoozed
-- and what went lately follow, then the way to the settings. An empty history
-- is the template's empty block. Grouping, expansion and actions are
-- shell/notification_history.lua's.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local N = require("themes.layouts.notification_parts")
local text_of = require("themes.notification_text")
local C = theme.color
local S = theme.space
local V = {}
local plain, ago, kind_of = text_of.plain, text_of.ago, text_of.kind

function V.build(state, width, height)
  local model = state.notifs
  local W = type(width) == "number" and width or 408
  local INNER = P.inner(W)
  local GROUPS, LINES, ITEMS = 8, 4, state.PAGE
  local SNOOZED, DISMISSED = 4, 5
  local LABEL_H = L.lh(L.role_size("label"))
  local BODY = theme.size.small
  local BODY_H = L.lh(BODY)
  local LINE = math.max(22, BODY_H)
  local APP_H = L.heading_h(L.role_size("section"))
  local HEAD_H = math.max(40, APP_H + LABEL_H + 2)
  -- An opened entry's card.
  local ITEM_SIZE = theme.size.small + 1
  local IT_Y = 8 + LABEL_H + 2
  local IB_Y = IT_Y + L.heading_h(ITEM_SIZE)
  local BTN_H = 30
  local PARTS_Y = IB_Y + BODY_H + 6
  local PART_X, PART_W = 12, INNER - 24

  local function group_kind(g)
    if not g then return "info" end
    if g.urgency == 2 then return "alert" end
    return kind_of(g.items[1])
  end
  local function hidden(n) return n ~= nil and model.redacted(n) end

  -- One line of a shut group: a mark, the summary, then the body, cut to fit.
  local function line(n_of, tag, shown, fits)
    local function signal() return kit.signal(kind_of(n_of()))() end
    local summary = kit.heading { id = "sidebar-summary-" .. tag, scope = "sidebar.notifications", level = "caption",
      visible = shown, ink = signal, font_size = BODY, height = LINE,
      text = function() local n = n_of() return n and (hidden(n) and "New notification" or plain(n.summary)) or "" end,
    }
    local body = kit.text {
      text = function() local n = n_of() return n and not hidden(n) and plain(n.body) or "" end,
      font_size = BODY, elide = "right", height = LINE, vertical_alignment = "center",
      width = function() return math.max(0, INNER - 20 - (summary.layout_width or summary.width or 0) - 14) end,
      color = kit.ink("lo"),
    }
    return ui.Row {
      width = INNER, height = LINE, gap = 8, align = "center",
      visible = fits,
      ui.Item { width = 6, height = 6 },
      kit.surface { width = 6, height = 6, radius = L.control_round(6), color = signal },
      summary, body,
    }
  end

  -- An entry of an opened group: a small status card.
  local function item(n_of, tag, shown)
    local function kind() return kind_of(n_of()) end
    local function signal() return kit.signal(kind())() end
    local function act(action) return function() local n = n_of() if n then action(n) end end end
    local IW = INNER
    local function answers() local n = n_of() return n ~= nil and not hidden(n) and state.answers(n) end
    local function replying() local n = n_of() return n ~= nil and model.replying:get() == n.id end
    local function tooled() local n = n_of() return n ~= nil and model.tools:get() == n.id end
    local function has_chips() local n = n_of() return n ~= nil and not hidden(n) and #N.chips_of(n, model) > 0 end
    local function has_buttons() local n = n_of() return answers() and N.button_rows(n, model) > 0 end
    local STACK = {
      { "chips", function() return has_chips() and N.ROW_H or 0 end },
      { "buttons", function() return has_buttons() and N.button_rows(n_of(), model) * N.ROW_H or 0 end },
      { "reply", function() return replying() and N.ROW_H or 0 end },
      { "base", function() return BTN_H + S.s end },
      { "tools", function() return tooled() and N.ROW_H or 0 end },
    }
    local function below(part)
      local y = PARTS_Y
      for _, row in ipairs(STACK) do
        if row[1] == part then return y end
        y = y + row[2]()
      end
      return y
    end
    local function at(part) return function() return below(part) end end
    local function whole() return below("end") + S.xs end
    return ui.Item {
      width = IW, height = whole,
      visible = function() return n_of() ~= nil end,
      kit.surface { anchors = { fill = true }, radius = kit.round(12),
        color = function() return C.surfaceContainerHigh:mix(signal(), .05) end },
      kit.label { x = 12, y = 8, width = IW - 24 - 70, elide = "right", color = signal,
        text = function()
          local n = n_of()
          if not n then return "" end
          local code = kit.code(n.id, "SD. ###/##.##")
          return text_of.word(kind()) .. (code ~= "" and ("  " .. code) or "")
        end },
      kit.label { anchors = { right = true, right_margin = 12 }, y = 8, width = 70, horizontal_alignment = "right",
        text = function() local n = n_of() return n and ago(n.time) or "" end },
      N.avatar { id = "sidebar-avatar-" .. tag, x = 12, y = IT_Y + 2, size = 26, n = n_of, kind = kind,
        hidden = function() return hidden(n_of()) end },
      kit.heading { id = "sidebar-item-title-" .. tag, scope = "sidebar.notifications", level = "caption", visible = shown,
        x = 48, y = IT_Y, width = IW - 60, elide = "right", ink = signal, font_size = ITEM_SIZE,
        text = function() local n = n_of() return n and (hidden(n) and "New notification" or plain(n.summary)) or "" end,
      },
      N.body { id = "sidebar-item-body-" .. tag, n = n_of, x = 48, y = IB_Y, width = IW - 60, height = BODY_H, elide = "right",
        font_size = BODY, color = kit.ink("lo"), raw = function(x) return hidden(x) and "Hidden" or x.body end },
      N.chips { id = "sidebar-chip-" .. tag, x = PART_X, y = at("chips"), width = PART_W, n = n_of, model = model,
        shown = has_chips },
      N.buttons { id = "sidebar-action-" .. tag, x = PART_X, y = at("buttons"), width = PART_W, n = n_of, model = model,
        shown = has_buttons },
      N.reply { id = "sidebar-reply-" .. tag, x = PART_X, y = at("reply"), width = PART_W, n = n_of, model = model,
        shown = replying },
      ui.Row { x = PART_X, y = at("base"), gap = S.s, align = "center",
        P.button { id = "sidebar-dismiss-" .. tag, icon = "close", label = "Dismiss", height = BTN_H,
          on_clicked = act(function(n) state.forget(n.id) end) },
        P.button { id = "sidebar-copy-" .. tag, icon = "content_copy", label = "Copy", height = BTN_H,
          on_clicked = act(function(n) state.copy(n) end) },
        L.icon_button { id = "sidebar-tools-" .. tag, width = BTN_H, height = BTN_H, icon = "more_horiz", size = 18,
          name = "Snooze, mute, rules", on = tooled, on_clicked = act(function(n) model.toggle_tools(n.id) end) },
      },
      N.tools { id = "sidebar-tool-" .. tag, x = PART_X, y = at("tools"), width = PART_W, n = n_of, model = model,
        shown = tooled },
    }
  end

  -- An application's card: its head (picture, name, word and time, the
  -- disclosure), then its lines or its entries. The entries are built the first
  -- time their group opens.
  local rows = {}
  local list
  local function group_row(i)
    local function g() return state.groups()[i] end
    local function kind() return group_kind(g()) end
    local function signal() return kit.signal(kind())() end
    local function is_open() local x = g() return x ~= nil and state.is_open(x.key) end
    local lines = { width = INNER, gap = 0 }
    for k = 1, LINES do
      local function n_of()
        local x = g()
        return x and x.items[k] or nil
      end
      local function fits() return k <= state.preview() and n_of() ~= nil end
      lines[k] = line(n_of, i .. "-" .. k, function() return fits() and not is_open() end, fits)
    end
    lines.visible = function() return g() ~= nil and not is_open() end
    local items_column = ui.Column { width = INNER, gap = S.s, visible = function() return g() ~= nil and is_open() end }
    local item_nodes, building = {}, false
    local function want()
      local x = g()
      return x and math.min(ITEMS, #x.items) or 0
    end
    -- One entry a tick, as many as the group has: a card is a handler's worth.
    local function grow()
      building = false
      local k = #item_nodes + 1
      if k > want() then return end
      local function n_of()
        local x = g()
        return x and x.items[k + state.offset(x.key)] or nil
      end
      local function build()
        item_nodes[k] = item(n_of, i .. "-" .. k, function() return n_of() ~= nil and is_open() end)
        ui.reparent(item_nodes[k], items_column)
      end
      if kit.with_viewport then kit.with_viewport(function() return list end, build) else build() end
      kit.bud({ item_nodes[k] }, true, { delay = 30 })
      if k < want() then
        building = true
        morf.time.timer(1, grow, false)
      end
    end
    local function ensure_items()
      if building or #item_nodes >= want() then return end
      building = true
      morf.time.timer(1, grow, false)
    end
    local paging = P.buttons { width = INNER,
      { id = "sidebar-newer-" .. i, label = "Newer", height = BTN_H,
        visible = function() local x = g() return x ~= nil and is_open() and state.has_less(x) end,
        on_clicked = function() local x = g() if x then state.page(x.key, -1) end end },
      { id = "sidebar-older-" .. i, label = "Older", height = BTN_H,
        visible = function() local x = g() return x ~= nil and is_open() and state.has_more(x) end,
        on_clicked = function() local x = g() if x then state.page(x.key, 1) end end },
    }
    local paged = ui.Item { width = INNER, height = BTN_H, paging, visible = function()
      local x = g()
      return x ~= nil and is_open() and (state.has_less(x) or state.has_more(x))
    end }
    local expand = kit.disclose_area({
      id = "sidebar-group-expand-" .. i,
      anchors = { right = true, vertical_center = true }, width = 52, height = 30, cursor = "pointer",
      ui.Row {
        anchors = { center_in = true }, gap = 2, align = "center",
        kit.text { text = function() local x = g() return x and tostring(#x.items) or "" end,
          font_size = theme.size.small, color = signal },
        kit.icon(function() return is_open() and "expand_less" or "expand_more" end, 18, signal),
      },
    }, is_open, function()
      local x = g()
      if not x then return end
      state.toggle(x.key)
      -- Opening, its entries come in evenly, one after the other.
      if state.is_open(x.key) then kit.bud(item_nodes, true, { delay = 30, stagger = 40 }) end
    end)
    kit.hover(expand, function(hovered) return signal():alpha(hovered and .2 or .07) end, L.control_round(30))
    morf.effect("eva.history.items." .. i, function() if is_open() then ensure_items() end end, { owner = expand })
    local clear_app = L.icon_button { id = "sidebar-clear-app-" .. i, anchors = { right = true, vertical_center = true,
      right_margin = 52 + S.xs }, width = 30, height = 30, icon = "delete_sweep", size = 18, name = "Clear this app",
      on_clicked = function() local x = g() if x then state.clear_app(x.key) end end }
    local text_w = INNER - 40 - 64 - 34
    local head = ui.Item { width = INNER, height = HEAD_H,
      N.avatar { id = "sidebar-group-avatar-" .. i, anchors = { vertical_center = true }, size = 28, kind = kind,
        n = function() local x = g() return x and x.items[1] or nil end,
        hidden = function() local x = g() return x ~= nil and hidden(x.items[1]) end },
      ui.Column { x = 40, anchors = { vertical_center = true }, gap = 2,
        kit.heading { scope = "sidebar.notifications", level = "section", visible = function() return g() ~= nil end,
          id = "sidebar-group-app-" .. i, ink = kit.ink("hi"), width = text_w, height = APP_H, elide = "right",
          text = function() local x = g() return x and x.app or "" end },
        kit.label { width = text_w, elide = "right", color = signal,
          text = function()
            local x = g()
            if not x then return "" end
            local code = kit.code(x.app, "GRP. ##-###")
            local when = x.items[1] and ago(x.items[1].time) or ""
            return text_of.word(kind()) .. (when ~= "" and ("  ·  " .. when) or "") .. (code ~= "" and ("  " .. code) or "")
          end },
      },
      clear_app, expand,
    }
    -- A shelf's name over its first group, where more than one shelf has any.
    local function leads()
      local all, x = state.groups(), g()
      if not x or i == 1 and #all == 1 then return false end
      local previous = all[i - 1]
      if previous and previous.shelf == x.shelf then return false end
      return previous ~= nil or all[#all].shelf ~= x.shelf
    end
    local function silent() local x = g() return x ~= nil and x.shelf == 4 end
    local shelf = ui.Item { id = "sidebar-shelf-" .. i, width = W, height = BTN_H, visible = leads,
      kit.label { x = S.xs, anchors = { vertical_center = true }, width = W - 120, elide = "right",
        text = function() local x = g() return x and state.SHELVES[x.shelf] or "" end },
      ui.Item { anchors = { right = true, vertical_center = true }, width = 100, height = BTN_H, visible = silent,
        P.button { id = "sidebar-clear-silent", width = 100, height = BTN_H, label = "Clear silent",
          on_clicked = state.clear_silent } },
    }
    return ui.Column { id = "sidebar-slot-" .. i, width = W, gap = S.xs, visible = function() return g() ~= nil end,
      shelf,
      P.section { id = "sidebar-group-" .. i, width = W, visible = function() return g() ~= nil end,
        head, L.rule { width = INNER }, ui.Column(lines), items_column, paged },
    }
  end

  -- ---------------------------------------------------------- what silences --

  local focus = require("focus_model")
  local function quiet() return focus.reason() end
  local silenced = P.section { id = "sidebar-focus", width = W, visible = function() return quiet() ~= nil end,
    P.row { id = "sidebar-focus-row", width = INNER, icon = function()
        local mode = focus.active()
        return mode and mode.icon or "do_not_disturb_on"
      end,
      title = function() return focus.status() end, subtitle = "Only what it allows comes through",
      trailing = P.button { id = "sidebar-focus-off", label = "Turn off", visible = function() return focus.active() ~= nil end,
        on_clicked = function() focus.stop() end } } }

  local undo = P.section { id = "sidebar-undo", width = W, visible = function() return state.undo() ~= false end,
    P.row { id = "sidebar-undo-row", width = INNER, icon = "undo",
      title = function()
        local u = state.undo()
        return u and u.label or ""
      end,
      subtitle = function()
        local u = state.undo()
        if not u then return "" end
        return ("%d notification%s"):format(u.count, u.count == 1 and "" or "s")
      end,
      trailing = P.button { id = "sidebar-undo-button", label = "Undo", on_clicked = state.restore } } }

  -- ------------------------------------------------------------- summary --

  local alert = kit.signal("alert")
  local function tally()
    local apps, n = #state.groups(), state.count()
    return ("%d app%s · %d notification%s"):format(apps, apps == 1 and "" or "s", n, n == 1 and "" or "s")
  end
  local clear = P.button { id = "sidebar-clear", icon = "clear_all", label = "Clear all", on_clicked = state.clear }
  local summary = P.section { id = "sidebar-summary", width = W, title = "History",
    note = function() local c = kit.code("history.buffer", "BUF ##/99") return c ~= "" and c or "" end,
    visible = function() return state.count() > 0 end,
    P.row { id = "sidebar-summary-row", width = INNER, icon = "notifications",
      on = function()
        for _, g in ipairs(state.groups()) do if g.urgency == 2 then return true end end
        return false
      end,
      title = function()
        local n = state.count()
        return ("%d notification%s"):format(n, n == 1 and "" or "s")
      end,
      subtitle = tally, trailing = clear },
    kit.meter { width = INNER, height = 6, count = 20,
      value = function() return math.min(1, state.count() / 20) end,
      color = function()
        for _, g in ipairs(state.groups()) do if g.urgency == 2 then return alert() end end
        return kit.signal("accent")()
      end },
  }

  -- Nothing kept: the template's empty block (with the ids the specs read).
  local empty = P.section { id = "sidebar-empty", width = W, visible = function() return state.count() == 0 end,
    ui.Column { width = INNER, gap = 8, align = "center",
      ui.Item { width = 1, height = 8 },
      kit.emblem { size = 42, kind = "ok" },
      kit.heading { scope = "sidebar.notifications", visible = function() return state.count() == 0 end,
        id = "sidebar-empty-label", level = "caption", ink = kit.ink("hi"),
        text = L.term("history.empty", "You're all caught up"), horizontal_alignment = "center", width = INNER - 2 * P.PAD },
      kit.text { text = "No notifications", font_size = L.SIZE.body, color = kit.ink("lo"),
        horizontal_alignment = "center", width = INNER - 2 * P.PAD },
      ui.Item { width = 1, height = 8 },
    } }

  -- ------------------------------------------------- snoozed and dismissed --

  local function later(id, title, cap, list_of, subtitle, label, on_press)
    local section = { id = id, width = W, title = title, visible = function() return #list_of() > 0 end }
    for k = 1, cap do
      local function n_of() return list_of()[k] end
      section[#section + 1] = P.row { id = id .. "-" .. k, width = INNER, height = P.ROW_H, icon = "schedule",
        visible = function() return n_of() ~= nil end,
        title = function() local n = n_of() return n and plain(n.summary) or "" end,
        subtitle = function() local n = n_of() return n and subtitle(n) or "" end,
        trailing = P.button { id = id .. "-button-" .. k, label = label,
          on_clicked = function() local n = n_of() if n then on_press(n) end end } }
    end
    return P.section(section)
  end
  local snoozed = later("sidebar-snoozed", "Snoozed", SNOOZED, state.snoozed,
    function(n) return n.app .. " · back at " .. morf.time.format("%H:%M", n.wake_at or 0) end,
    "Wake", function(n) model.wake(n.id) end)
  local function recent()
    local all, out = state.dismissed(), {}
    for i = #all, math.max(1, #all - DISMISSED + 1), -1 do out[#out + 1] = all[i] end
    return out
  end
  local dismissed = later("sidebar-dismissed", "Recently dismissed", DISMISSED, recent,
    function(n) return n.app .. " · " .. ago(n.time) end, "Restore", function(n) model.bring_back(n.id) end)

  local settings = P.section { id = "sidebar-settings", width = W,
    P.row { id = "sidebar-settings-row", width = INNER, icon = "tune", title = "Notification settings",
      subtitle = "Sounds, apps, history", trailing = P.chevron(), on_clicked = state.settings } }

  -- The page scrolls (P.page's shape; built by hand so the groups' headings
  -- know the viewport they reveal in).
  local list_node, _, _, list_ctl
  list_node, list, _, list_ctl = kit.scroll({ id = "sidebar-history-list", width = W, height = height,
    clip = true })
  local function build_rows() for i = 1, GROUPS do rows[i] = group_row(i) end end
  if kit.with_viewport then kit.with_viewport(function() return list end, build_rows) else build_rows() end
  local col = { width = W, gap = P.GAP, silenced, undo, summary, empty }
  for i = 1, GROUPS do col[#col + 1] = rows[i] end
  col[#col + 1] = snoozed
  col[#col + 1] = dismissed
  col[#col + 1] = settings
  col[#col + 1] = ui.Item { width = 1, height = P.GAP }
  local column = ui.Column(col)
  ui.reparent(column, list)
  list_ctl.set_content(column)

  --- Clears the history: the groups fade and shrink a touch, one after the
  --- other, then go.
  local clearing = false
  local running, leaving = {}, {}
  local function stop(handles)
    for _, handle in ipairs(handles) do handle:stop() end
  end
  local function animate_clear()
    clearing = true
    stop(running) running = {}
    local shown = {}
    for _, row in ipairs(rows) do if row.visible then shown[#shown + 1] = row end end
    if #shown == 0 then return 0 end
    shown[#shown + 1] = summary
    leaving = kit.bud(shown, false, { leave_stagger = 35 })
    return 170 + 35 * (#shown - 1)
  end
  local function reset_clear()
    stop(leaving) leaving = {}
    clearing = false
    for _, row in ipairs(rows) do row.scale, row.opacity = 1, 1 end
    summary.scale, summary.opacity = 1, 1
  end

  local pane = ui.Item { id = "sidebar-history", width = W, height = height, list_node }

  local was, count = false, state.count()
  morf.effect("eva.history.presentation", function()
    local active, now = state.active(), state.count()
    if not clearing then
      if active ~= was then
        stop(running) running = {}
        if active then running = kit.bud(rows, true, { delay = 90, stagger = 30 }) end
      elseif active and now ~= count then
        stop(running)
        running = kit.bud({ now == 0 and empty or rows[1] }, true, { delay = 0 })
      end
    end
    was, count = active, now
  end, { owner = pane })
  return { node = pane, animate_clear = animate_clear, reset_clear = reset_clear }
end
return V
