-- eva-messages' page in Tools: the conversations, one of them open, and a line to write.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local model = require("apps.messages.model")
local C, S = theme.color, theme.space

local M = {}

local THREADS = 60
local BUBBLES = 80
-- A bubble's width, of the window; a glyph's, of its size; room for a time and
-- a mark under the words.
local WIDE, GLYPH, FOOT = 0.78, 0.62, 120

local function thread_row(index, w)
  local function thread() return model.threads()[index] end
  return P.row { id = "messages-thread-" .. index, width = w, height = P.ROW_H,
    visible = function() return thread() ~= nil end,
    icon = "person", on = function() local t = thread() return t ~= nil and t.unread > 0 end,
    title = function() local t = thread() return t and t.label or "" end,
    subtitle = function() local t = thread() return t and (t.last:gsub("%s+", " ")) or "" end,
    trailing = kit.text { id = "messages-when-" .. index, font_size = P.SUB, color = kit.ink("lo"),
      text = function() local t = thread() return t and model.when(t.time) or "" end },
    on_clicked = function() local t = thread() if t then model.show(t.number) end end }
end

local function threads(w, h)
  local list = { gap = S.xxs, width = w }
  for index = 1, THREADS do list[index] = thread_row(index, w) end
  return ui.Item { id = "messages-list", width = w, height = h,
    P.empty { id = "messages-empty", icon = "sms", title = "No messages",
      text = "Texts you send and receive show here.", width = w,
      visible = function() return #model.threads() == 0 end },
    (kit.scroll { id = "messages-threads", width = w, height = h, clip = true, ui.Column(list) }),
    ui.Item { width = S.TOUCH + S.m, height = S.TOUCH + S.m, anchors = { right = true, bottom = true },
      kit.action { id = "messages-new", accessible_name = "New message", anchors = { fill = true }, cursor = "pointer",
        on_clicked = function() model.compose() end,
        ui.Rect { anchors = { fill = true }, radius = kit.round(S.l), color = function() return C.primary end },
        kit.icon("edit", S.xl, function() return C.onPrimary end, { anchors = { center_in = true } }) } },
  }
end

--- The width for `words` at `size`, the longest line's, within `limit`.
function M.fit(words, size, limit)
  local longest = 0
  for line in (words .. "\n"):gmatch("(.-)\n") do longest = math.max(longest, utf8.len(line) or #line) end
  return math.min(limit, math.max(FOOT, math.ceil(longest * size * GLYPH)))
end

-- One message, on the side it came from, as tall as its words.
local function bubble(index, w)
  local function row() return model.thread()[index] end
  local function outgoing() local r = row() return r ~= nil and r.direction == "out" end
  local function widest() return math.floor(w() * WIDE) end
  local foot = kit.text { id = "messages-mark-" .. index, font_size = S.m - S.xxs, color = kit.ink("lo"),
    text = function()
      local r = row()
      if not r then return "" end
      local mark = model.mark(r)
      return model.when(r.time) .. (mark ~= "" and (" · " .. mark) or "")
    end }
  local function words() local r = row() return r and r.text or "" end
  local function inner() return M.fit(words(), theme.size.normal, widest() - 2 * S.m) end
  local text = kit.text { id = "messages-text-" .. index, wrap = true, width = inner, text = words,
    font_size = theme.size.normal, color = function() return outgoing() and C.onPrimaryContainer or C.onSurface end }
  local body = ui.Column { y = S.s, width = inner, gap = S.xxs, text, foot }
  local function high() return (body.layout_height or 0) + 2 * S.s end
  local function wide() return inner() + 2 * S.m end
  local function left() return outgoing() and w() - wide() or 0 end
  body.x = function() return left() + S.m end
  return ui.Item { id = "messages-bubble-" .. index, width = w, height = high,
    visible = function() return row() ~= nil end,
    measure,
    ui.Rect { x = left, width = wide, height = high, radius = kit.round(S.l),
      color = function() return outgoing() and C.primaryContainer or C.surfaceContainerHigh end },
    body }
end

local function writer(w)
  local function room() return math.max(1, w() - S.TOUCH - S.s) end
  local field = kit.text_field("entry", {
    id = "messages-draft", width = room, height = S.TOUCH, placeholder = "Text message",
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"),
    text = function() return model.draft:get() end,
    on_text_changed = function(value) model.draft:set(value) end,
    on_accepted = function() model.send() end,
  })
  return ui.Column { id = "messages-writer", width = w, gap = S.xxs,
    kit.text { id = "messages-parts", font_size = P.SUB, color = kit.ink("lo"),
      visible = function() return #model.draft:get() > 120 end,
      text = function()
        local parts, left = model.segments(model.draft:get())
        return parts > 1 and ("%d messages · %d left"):format(parts, left) or (left .. " left")
      end },
    ui.Row { gap = S.s, align = "center", field,
      L.icon_button { id = "messages-send", icon = "send", name = "Send", width = S.TOUCH, height = S.TOUCH,
        on = function() return model.draft:get() ~= "" end, on_clicked = model.send } },
  }
end

local function conversation(w, h)
  local list = { gap = S.s, width = w }
  for index = 1, BUBBLES do list[index] = bubble(index, w) end
  local foot = S.TOUCH + S.xl
  local top = S.xl + S.s
  local function body() return math.max(1, h() - foot - top) end
  local to = kit.text_field("entry", {
    id = "messages-to", width = w, height = S.TARGET, y = top, placeholder = "To: a number",
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"),
    text = function() return model.to:get() end,
    on_text_changed = function(value) model.to:set(value) end,
  })
  to.visible = function() return model.composing:get() end
  local scroll = kit.scroll { id = "messages-conversation", width = w, height = body, clip = true, ui.Column(list) }
  return ui.Item { id = "messages-open", width = w, height = h,
    visible = function() return model.open:get() ~= "" or model.composing:get() end,
    kit.text { id = "messages-person", font_size = S.l + S.xxs, color = kit.ink("hi"), text = model.title },
    to,
    ui.Item { width = w, y = top, height = body, visible = function() return not model.composing:get() end, scroll },
    ui.Item { width = w, y = function() return h() - foot + S.s end, height = foot, writer(w) },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  return ui.Item { id = "messages-root", width = w, height = h,
    ui.Item { width = w, height = h, visible = function() return model.open:get() == "" and not model.composing:get() end,
      threads(w, h) },
    conversation(w, h),
  }
end

--- The header's buttons: back and delete, on an open thread.
function M.actions()
  local function opened() return model.open:get() ~= "" or model.composing:get() end
  return ui.Row { gap = S.xs, visible = opened,
    L.icon_button { id = "messages-delete", icon = "delete", name = "Delete thread", width = S.TARGET, height = S.TARGET,
      on_clicked = model.forget },
    L.icon_button { id = "messages-back", icon = "arrow_back", name = "Back", width = S.TARGET, height = S.TARGET,
      on_clicked = model.close },
  }
end

return M
