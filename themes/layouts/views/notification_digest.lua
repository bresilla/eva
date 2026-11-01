-- The scheduled summary at the head of the history: conversations first, by
-- who is talking, then each app with what it said last, and what to do with
-- the lot. Under that, what is waiting for the next one. Rows are fixed slots
-- filled from shell/notification_history.lua's `digest()`.
local morf = require("morf")
local ui = require("morf.ui")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local text_of = require("themes.notification_text")
local V = {}

local CONVERSATIONS, APPS = 4, 4

function V.build(state, W)
  local inner = P.inner(W)
  local plain = text_of.plain
  local hidden = state.notifs.redacted

  local function line(row)
    if not row then return "" end
    local n = row.latest
    if hidden(n) then return "New notification" end
    local body = plain(n.body or "")
    return body ~= "" and body or plain(n.summary or "")
  end
  local function count(row, word)
    local total = #row.items
    return total > 1 and (("%d %ss · "):format(total, word)) or ""
  end

  local function rows(list_of, prefix, limit, icon, word, heading)
    local column = { width = inner, gap = P.ROW_GAP,
      visible = function() local s = state.digest() return s ~= nil and #list_of(s) > 0 end }
    column[#column + 1] = F.note(inner, heading, { id = prefix .. "-heading" })
    for index = 1, limit do
      local function row() local s = state.digest() return s and list_of(s)[index] or nil end
      column[#column + 1] = P.row { id = prefix .. "-" .. index, width = inner, icon = icon,
        visible = function() return row() ~= nil end,
        title = function() local r = row() return r and (hidden(r.latest) and r.app or plain(r.title)) or "" end,
        subtitle = function() local r = row() return r and (count(r, word) .. line(r)) or "" end,
        on_clicked = function() local r = row() if r then state.digest_open(r) end end }
    end
    return ui.Column(column)
  end

  local actions = P.buttons { width = inner,
    { id = "digest-done", label = "Done", icon = "check", tone = "primary", on_clicked = state.digest_done },
    { id = "digest-clear", label = "Clear them", icon = "clear_all", on_clicked = state.digest_clear },
  }

  local summary = P.section { id = "digest", width = W, visible = function() return state.digest() ~= nil end,
    title = "Your summary",
    note = function()
      local s = state.digest()
      return s and morf.time.format("%H:%M", s.at) .. " · " .. tostring(s.total) or ""
    end,
    rows(function(s) return s.conversations end, "digest-conversation", CONVERSATIONS, "forum", "message", "Conversations"),
    rows(function(s) return s.apps end, "digest-app", APPS, "apps", "notification", "Everything else"),
    actions,
  }

  local function waiting() return state.digest_waiting() end
  local held = P.section { id = "digest-waiting", width = W, visible = function() return waiting() ~= nil end,
    P.row { id = "digest-waiting-row", width = inner, icon = "summarize",
      title = function()
        local w = waiting()
        return w and ("%d for your summary"):format(w.count) or ""
      end,
      subtitle = function()
        local w = waiting()
        if not w then return "" end
        return w.next and ("Next at " .. w.next) or "No time is set for it"
      end,
      trailing = P.button { id = "digest-now", label = "Show now", on_clicked = state.digest_now } } }
  return ui.Column { id = "digest-area", width = W, gap = P.GAP, summary, held,
    visible = function() return state.digest() ~= nil or waiting() ~= nil end }
end

return V
