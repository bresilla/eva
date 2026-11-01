-- The Assistant page, in the page template (themes/layouts/page.lua): the
-- conversations beside the chat where there is room, one over the other where
-- there is not. Until a provider answers, the page says what is missing and
-- offers the settings page.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local R = require("themes.layouts.rows")
local markup = require("themes.layouts.markup")
local mirror = require("themes.layouts.mirror")
local C = theme.color
local S = theme.space
local M = {}

local LIST_W, WIDE = 272, 760
local INPUT_H = 72

local function get(v) if type(v) == "function" then return v() end return v end

-- A small round press with an icon.
local function tool(spec)
  local side = spec.size or P.BUTTON_H
  local button = kit.action { id = spec.id, accessible_name = spec.name, width = side, height = side, cursor = "pointer",
    visible = spec.visible, on_clicked = spec.on_clicked,
    kit.icon(spec.icon, 20, spec.ink or kit.ink("lo"), { anchors = { center_in = true } }) }
  kit.hover(button, function(hovered) return hovered and C.onSurface:alpha(0.08) or C.onSurface:alpha(0) end, R.round(side))
  return button
end

-- One message: a person's in a bubble, a reply on the page, and what can be
-- done with it underneath.
local function message_node(model, row, width, on_link)
  local id = "assistant-message-" .. row.id
  local current = row
  local blocks = morf.list_model(row.blocks or {})
  local revision = morf.signal(id .. ".revision", 0)
  local mine = row.role == "user"
  local inner = function() return get(width) - (mine and 2 * S.m + S.xxl or 0) end
  local body = markup.view { id = id, width = inner, blocks = blocks, on_link = on_link,
    on_copy = function(block, text) model.copy(block, text) end }
  local waiting = kit.text { id = id .. "-waiting", text = "Thinking…", font_size = P.SUB, color = kit.ink("lo"),
    visible = function() revision:get() return current.busy and current.text == "" end }
  local failed = kit.text { id = id .. "-failed", width = inner, wrap = true, font_size = P.SUB, color = function() return C.error end,
    text = function() revision:get() return current.failed end,
    visible = function() revision:get() return current.failed ~= "" end }
  local note = kit.text { id = id .. "-note", width = inner, wrap = true, font_size = P.SUB, color = kit.ink("lo"),
    text = function() revision:get() return current.note end,
    visible = function() revision:get() return current.note ~= "" end }
  local attached = kit.text { id = id .. "-attached", width = inner, font_size = L.SIZE.label, color = kit.ink("lo"),
    elide = "right", text = function() revision:get() return current.attached ~= "" and ("With " .. current.attached) or "" end,
    visible = function() revision:get() return current.attached ~= "" end }
  local stack = ui.Column { width = inner, gap = S.xs, attached, body, waiting, failed, note }
  local tools = ui.Row { gap = S.xs, height = 32,
    visible = function() revision:get() return not current.busy and current.role ~= nil end,
    tool { id = id .. "-copy", name = "Copy", size = 32,
      icon = function() return model.copied:get() == id and "check" or "content_copy" end,
      on_clicked = function() model.copy(id, model.text_of(current.id)) end },
    tool { id = id .. "-regenerate", name = "Regenerate", size = 32, icon = "refresh",
      visible = function() revision:get() return model.can_regenerate(current.id) end,
      on_clicked = model.regenerate },
  }
  local content
  if mine then
    local bubble = kit.surface { id = id .. "-bubble", width = function() return get(width) - S.xxl end, radius = kit.round(S.m),
      height = function() return (stack.layout_height or 0) + 2 * S.s end,
      x = S.xxl, color = function() return C.surfaceContainerHighest end,
      ui.Item { x = S.m, y = S.s, width = inner, height = function() return stack.layout_height or 0 end, stack } }
    content = ui.Item { width = width, height = function() return bubble.height end, bubble }
  else
    content = stack
  end
  local column = ui.Column { id = id, width = width, gap = S.xxs, enter = kit.enter(), content, tools }
  return column, function(next)
    current = next
    blocks:replace(next.blocks or {}, "key")
    revision:set(revision:get() + 1)
  end
end

--- The page: `model` is shell/assistant_model.lua with this panel's `active`.
function M.build(model, w, h)
  local keeper = ui.Item { width = 1, height = 1 }
  local function own(list) return mirror.new(list, "id", keeper) end
  local compact = require("responsive").compact()
  local function wide() return not compact and get(w) >= WIDE end
  local function chat_w() return wide() and get(w) - LIST_W - P.GAP or get(w) end
  local function ready() return model.state() == "ready" end
  local function browsing() return model.browsing:get() and not wide() end
  local function open_link(href) morf.process.detach { "xdg-open", href } end

  -- ------------------------------------------------------ what is missing --
  local setup = ui.Item { width = w, height = h, visible = function() return not ready() end,
    P.empty { id = "assistant-setup", width = w, icon = "auto_awesome",
      title = function() return (model.explain()) end,
      text = function() return (select(2, model.explain())) end,
      action = { id = "assistant-open-settings", label = "Open assistant settings", icon = "settings",
        tone = "primary", on_clicked = model.open_settings } } }

  -- -------------------------------------------------------- conversations --
  local conversations = ui.Repeater { as = "column", gap = S.xs, width = function() return wide() and LIST_W or get(w) end,
    model = own(model.conversations),
    delegate = function(row)
      local item_w = function() return wide() and LIST_W or get(w) end
      local open = kit.action { id = "assistant-chat-" .. row.id, x = 0, height = 56, cursor = "pointer",
        width = function() return item_w() - P.BUTTON_H end,
        on_clicked = function() model.open(row.id) end,
        ui.Column { x = S.s, gap = S.xxs, anchors = { vertical_center = true },
          width = function() return item_w() - P.BUTTON_H - S.m end, clip = true,
          kit.text { text = row.title, font_size = theme.size.normal, font_weight = 500, elide = "right",
            width = function() return item_w() - P.BUTTON_H - S.m end,
            color = function() return model.current:get() == row.id and C.primary or kit.ink("hi")() end },
          kit.text { text = row.when, font_size = L.SIZE.label, color = kit.ink("lo") },
        } }
      kit.hover(open, function(hovered) return hovered and C.onSurface:alpha(0.06) or C.onSurface:alpha(0) end, kit.round(S.s))
      local remove = tool { id = "assistant-chat-delete-" .. row.id, name = "Delete this conversation", icon = "delete",
        on_clicked = function() model.delete(row.id) end }
      remove.x = function() return item_w() - P.BUTTON_H end
      remove.anchors = { vertical_center = true }
      return ui.Item { width = item_w, height = 56, open, remove }
    end }
  local list_w = function() return wide() and LIST_W or get(w) end
  local none = kit.text { id = "assistant-no-chats", text = "Nothing saved yet.", font_size = P.SUB, color = kit.ink("lo"),
    x = S.s, visible = function() return model.conversations:len() == 0 end }
  local back = P.button { id = "assistant-back", label = "Back to the chat", icon = "arrow_back",
    visible = function() return not wide() end, on_clicked = function() model.browsing:set(false) end }
  local list_h = function() return get(h) - (wide() and 0 or P.BUTTON_H + P.GAP) end
  local list_node = kit.scroll { id = "assistant-chats", width = list_w, height = list_h, clip = true,
    ui.Column { width = list_w, gap = S.xs, none, conversations } }
  local list = ui.Column { id = "assistant-list", width = list_w, height = h, gap = P.GAP,
    visible = function() return ready() and (wide() or model.browsing:get()) end, back, list_node }

  -- ------------------------------------------------------------- its bar --
  local bar = ui.Item { id = "assistant-bar", width = chat_w, height = P.BUTTON_H,
    kit.text { id = "assistant-summary", text = model.summary, font_size = P.SUB, color = kit.ink("lo"), elide = "right",
      anchors = { vertical_center = true }, width = function() return math.max(1, chat_w() - 3 * P.BUTTON_H) end },
    ui.Row { anchors = { right = true, vertical_center = true }, gap = S.xs,
      tool { id = "assistant-browse", name = "Conversations", icon = "forum", visible = function() return not wide() end,
        on_clicked = function() model.browsing:set(true) end },
      tool { id = "assistant-new", name = "New conversation", icon = "add", on_clicked = model.new_conversation },
      tool { id = "assistant-settings", name = "Assistant settings", icon = "settings", on_clicked = model.open_settings },
    } }

  -- ---------------------------------------------------------------- chat --
  local input_node, input = kit.text_field("text_area", {
    id = "assistant-input", x = S.m, y = S.xs, width = function() return chat_w() - 2 * S.m end, height = INPUT_H - 2 * S.xs,
    font_family = theme.font, font_size = theme.size.normal, color = function() return C.onSurface end,
    placeholder = "Ask anything. Ctrl+Enter sends.", placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(0.3) end,
    on_text_changed = function(text) model.draft:set(text) end,
    on_accepted = function(text) model.send(text) end,
  })
  morf.effect("assistant.draft", function()
    local text = model.draft:get()
    if input.text ~= text then input.text = text end
  end, { owner = input_node })
  local well = R.well { width = chat_w, height = INPUT_H, input_node }

  local send = P.button { id = "assistant-send", label = "Send", icon = "send", tone = "primary",
    visible = function() return not model.streaming:get() end,
    enabled = function() return model.draft:get() ~= "" or model.attachments:len() > 0 end,
    on_clicked = function() model.send(model.draft:get()) end }
  local stop = P.button { id = "assistant-stop", label = "Stop", icon = "stop_circle",
    visible = function() return model.streaming:get() end, on_clicked = model.stop }
  local attach = ui.Row { gap = S.xs, align = "center",
    tool { id = "assistant-attach-clipboard", name = "Attach the clipboard", icon = "content_paste", on_clicked = model.attach_clipboard },
    tool { id = "assistant-attach-screenshot", name = "Attach a screenshot", icon = "screenshot_monitor", on_clicked = model.attach_screenshot },
    tool { id = "assistant-attach-window", name = "Attach the focused window's title", icon = "select_window", on_clicked = model.attach_window },
    tool { id = "assistant-private", name = "Keep this conversation off the disk",
      icon = function() return model.private:get() and "visibility_off" or "visibility" end,
      ink = function() return model.private:get() and C.primary or kit.ink("lo")() end,
      on_clicked = function() model.set_private(not model.private:get()) end },
  }
  local actions = ui.Item { width = chat_w, height = P.BUTTON_H, attach,
    ui.Row { anchors = { right = true, vertical_center = true }, gap = S.s, send, stop } }

  local chips = ui.Repeater { as = "row", gap = S.xs, model = own(model.attachments),
    delegate = function(row)
      return P.button { id = "assistant-attached-" .. row.id, label = row.name, icon = "close",
        accessible_name = "Remove " .. row.name, on_clicked = function() model.detach(row.id) end }
    end }
  local chip_row = ui.Item { width = chat_w, height = P.BUTTON_H, clip = true,
    visible = function() return model.attachments:len() > 0 end, chips }

  local notice = kit.text { id = "assistant-notice", width = chat_w, wrap = true, font_size = P.SUB,
    color = function() return C.error end, text = function() return model.notice:get() end,
    visible = function() return model.notice:get() ~= "" end }

  local foot = ui.Column { width = chat_w, gap = S.s, notice, chip_row, well, actions }
  local log_h = function() return math.max(0, get(h) - (foot.layout_height or 0) - P.BUTTON_H - 2 * P.GAP) end

  local welcome = P.empty { id = "assistant-welcome", width = chat_w, icon = "auto_awesome", title = "Room to think.",
    text = function() return "Ask anything. " .. model.summary() .. " answers here." end,
    visible = function() return model.messages:len() == 0 end }
  local transcript = ui.Repeater { as = "column", gap = P.GAP, width = chat_w, model = own(model.messages),
    delegate = function(row) return message_node(model, row, chat_w, open_link) end }
  local column = ui.Column { width = chat_w, gap = P.GAP, welcome, transcript, ui.Item { width = 1, height = S.s } }
  local pinned = true
  local log, flick = kit.scroll { id = "assistant-log", width = chat_w, height = log_h, clip = true, column,
    on_scrolled = function(_, y)
      pinned = y >= (column.layout_height or 0) - log_h() - S.xxl
    end }
  morf.effect("assistant.follow", function()
    model.tick:get()
    local tall = column.layout_height or 0
    if pinned then flick.content_y = math.max(0, tall - log_h()) end
  end, { owner = log })
  morf.effect("assistant.pin", function()
    model.current:get()
    pinned = true
  end, { owner = log })

  local chat = ui.Column { id = "assistant-chat", width = chat_w, height = h, gap = P.GAP,
    x = function() return wide() and LIST_W + P.GAP or 0 end,
    visible = function() return ready() and not browsing() end, bar, log, foot }

  local root = ui.Item { id = "assistant-page", width = w, height = h, keeper, setup, list, chat }
  morf.effect("assistant.shown", function()
    local shown = model.active()
    if shown then morf.time.timer(1, function() model.begin() end, false) end
  end, { owner = root })
  return root
end
return M
