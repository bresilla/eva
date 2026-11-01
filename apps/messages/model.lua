-- eva-messages' state: which thread is open and what is being written. Texts
-- are the shell's to receive and notify; here they are read, sent and deleted.
local morf = require("morf")
local config = require("config")
local contacts = require("lib.services.contacts")

local M = {
  open = morf.signal("messages.open", ""),
  draft = morf.signal("messages.draft", ""),
  to = morf.signal("messages.to", ""),
  composing = morf.signal("messages.composing", false),
}

M.mobile, M.standin = require("lib.services.modem").session()
M.book = contacts.open {
  folder = morf.env("EVA_CONTACTS") or config.get("phone.contacts"), country = config.get("phone.country"),
}
M.log = require("lib.services.journal").open { name = "messages" }
M.segments = require("models.phone_messages").segments
if M.mobile and M.mobile.messaging then
  M.messages = require("models.phone_messages").new {
    mobile = M.mobile, book = M.book, log = M.log, owner = false,
    report = config.get("phone.delivery_reports") == true,
  }
end

--- Whether anything can be sent.
function M.can_send() return M.messages ~= nil and M.mobile.messaging.present:get() end

function M.threads() return M.messages and M.messages.threads() or {} end
function M.thread() return M.messages and M.messages.thread(M.open:get()) or {} end

--- Opens the thread with `number`, reading it.
function M.show(number)
  M.composing:set(false)
  M.open:set(number)
  if M.messages then M.messages.read(number) end
end

function M.close()
  M.open:set("")
  M.composing:set(false)
end

--- Starts a new thread, to `number` if given.
function M.compose(number)
  M.open:set("")
  M.to:set(number or "")
  M.composing:set(true)
end

--- Sends what is written, to the open thread or the new one's number.
function M.send()
  local number = M.open:get() ~= "" and M.open:get() or M.to:get()
  local text = M.draft:get()
  if not M.messages or text == "" or number == "" then return false end
  local sent = M.messages.send(number, text)
  M.draft:set("")
  if M.composing:get() then M.show(contacts.normal(number, M.book.country)) end
  return sent
end

--- Deletes the open thread.
function M.forget()
  if M.messages and M.open:get() ~= "" then M.messages.forget(M.open:get()) end
  M.close()
end

--- The title over the open thread.
function M.title()
  if M.composing:get() then return "New message" end
  local number = M.open:get()
  return number ~= "" and M.book.label(number) or "Messages"
end

--- What a sent message's mark says.
function M.mark(row)
  if row.direction == "in" then return "" end
  if row.state == "failed" then return "Not sent" end
  if row.state == "sending" then return "Sending…" end
  if row.delivery == "delivered" then return "Delivered" end
  if row.delivery == "failed" then return "Not delivered" end
  return "Sent"
end

--- The clock for a message: today's by the hour, older by the day.
function M.when(time)
  time = tonumber(time) or 0
  if morf.time.format("%Y-%m-%d", time) == morf.time.format("%Y-%m-%d") then return morf.time.format("%H:%M", time) end
  return morf.time.format("%-d %b", time)
end

return M
