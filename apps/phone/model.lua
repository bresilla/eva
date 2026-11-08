-- eva-phone's state: what is typed, the recent calls and the address book. The
-- call itself is the shell's, on the modem both watch: dialling here brings up
-- the shell's call screen.
local morf = require("morf")
local config = require("config")
local contacts = require("lib.services.contacts")

local M = {
  number = morf.signal("phone.number", ""),
  query = morf.signal("phone.query", ""),
  tab = morf.signal("phone.tab", 1),
  message = morf.signal("phone.message", ""),
}

-- The shell's own modem, or its stand-in with EVA_FAKE_MODEM.
M.mobile, M.standin = require("services").modem, require("services").modem_standin
M.book = contacts.open {
  folder = morf.env("EVA_CONTACTS") or config.get("phone.contacts"), country = config.get("phone.country"),
}
M.log = require("lib.services.journal").open { name = "calls" }
if M.mobile and M.mobile.voice then
  M.phone = require("models.phone_calls").new { mobile = M.mobile, book = M.book, owner = false }
end

--- Whether a modem that can call is there.
function M.can_call()
  return M.phone ~= nil and M.mobile.voice.present:get()
end

function M.press(key)
  M.number:set(M.number:get() .. key)
  M.message:set("")
end
function M.back() M.number:set(M.number:get():sub(1, -2)) end
function M.clear() M.number:set("") end

--- A digit held down: 0 gives the +.
function M.long_press(key)
  if key == "0" then M.number:set(M.number:get() .. "+") end
end

--- People the typed digits spell or number.
function M.matches() return M.book.t9(M.number:get()) end

--- Calls `number`, or what is typed.
function M.call(number)
  number = number or M.number:get()
  if number == "" then return false end
  if number:match("#$") then
    M.message:set("USSD codes are on the Mobile page")
    return false
  end
  if not M.can_call() then
    M.message:set("No modem")
    return false
  end
  local to = M.phone.is_emergency(number) and number or contacts.normal(number, M.book.country)
  M.phone.dial(to, function(ok, why)
    if ok then M.number:set("") else M.message:set(tostring(why or "Could not call")) end
  end)
  return true
end

local ICONS = { answered = "call_received", outgoing = "call_made", missed = "call_missed", declined = "call_end",
  unanswered = "call_made", failed = "call_end", blocked = "block" }

--- The recent calls, newest first, with who and what became of them.
function M.recents()
  local out = {}
  local rows = M.log.rows:get()
  for index = #rows, 1, -1 do
    local row = rows[index]
    row.label = M.book.label(row.number)
    row.icon = ICONS[row.outcome] or "call"
    out[#out + 1] = row
  end
  return out
end

--- When, and how long, for a line under a call.
function M.detail(row)
  local when = morf.time.format("%a %-d %b, %H:%M", row.time or 0)
  local length = tonumber(row.duration) or 0
  if length > 0 then return ("%s · %d:%02d"):format(when, length // 60, length % 60) end
  return when .. " · " .. (row.outcome or "")
end

local blocked_now = morf.signal("phone.blocked", 0)
--- Whether calls and texts from `number` are turned away.
function M.blocked(number)
  local _ = blocked_now:get()
  return M.book.blocked(number)
end
function M.toggle_block(number)
  M.book.block(number, not M.book.blocked(number))
  blocked_now:set(blocked_now:get() + 1)
end

--- Marks every missed call seen.
function M.seen()
  for _, row in ipairs(M.log.rows:get()) do
    if row.seen == false then M.log.update(row.id, { seen = true }) end
  end
end

--- Missed calls not yet seen.
function M.unseen()
  local count = 0
  for _, row in ipairs(M.log.rows:get()) do
    if row.seen == false then count = count + 1 end
  end
  return count
end

function M.people() return M.book.search(M.query:get()) end

--- A person's first number.
function M.first_number(person)
  local entry = person and person.numbers[1]
  return entry and entry.number or ""
end

return M
