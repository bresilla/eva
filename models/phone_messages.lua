-- Text conversations: every message kept in a private journal, grouped into
-- threads by who they are with. No nodes. The shell runs one as the owner: it
-- takes what the modem receives into the journal, notifies, and clears the
-- modem's copy. A tool runs another that reads, marks and sends.
--
--   local messages = require("models.phone_messages").new { mobile = m, book = contacts,
--     log = journal, owner = true, notify = fn, ring = ringer }
--   messages.threads()          -- { { number, label, last, time, unread, count }, ... }, newest first
--   messages.thread(number)     -- its messages, oldest first
--   messages.send(number, text, done)
--   messages.read(number)
--
-- A row: `{ id, number, text, direction = "in"|"out", time, state = received, sending,
-- sent or failed, delivery, read, blocked }`.
local morf = require("morf")
local contacts = require("lib.services.contacts")

local M = {}

-- Characters of the GSM 7-bit default alphabet and its extension, which fit a
-- text as 160, or 153 a part once it splits; anything else makes it UCS-2.
local GSM = "@£$¥èéùìòÇ\nØø\rÅåΔ_ΦΓΛΩΠΨΣΘΞ ÆæßÉ !\"#¤%&'()*+,-./0123456789:;<=>?¡ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÑÜ§¿abcdefghijklmnopqrstuvwxyzäöñüà"
local EXTENDED = "^{}\\[~]|€"
local seven = {}
for _, code in utf8.codes(GSM) do seven[code] = 1 end
for _, code in utf8.codes(EXTENDED) do seven[code] = 2 end

--- How many parts `text` goes as, and the characters left in the last one.
function M.segments(text)
  local units, wide = 0, false
  for _, code in utf8.codes(text or "") do
    local cost = seven[code]
    if not cost then wide = true break end
    units = units + cost
  end
  if wide then
    units = 0
    for _, code in utf8.codes(text) do units = units + (code > 0xFFFF and 2 or 1) end
  end
  local single, part = wide and 70 or 160, wide and 67 or 153
  if units <= single then return 1, single - units end
  local parts = math.ceil(units / part)
  return parts, parts * part - units
end

--- An ISO 8601 stamp as seconds since 1970, or nil.
function M.seconds(stamp)
  local ok, seconds = pcall(morf.time.parse, tostring(stamp or ""))
  return ok and tonumber(seconds) or nil
end

local serial = 0

function M.new(options)
  serial = serial + 1
  local mobile, book, log = options.mobile, options.book, options.log
  local sms = mobile.messaging
  local owner = options.owner == true
  local messages = { message = morf.signal("eva.messages." .. serial .. ".message", "") }
  local pending = {}

  local function key(number)
    local bare = contacts.digits(number):gsub("%D", "")
    return bare ~= "" and bare:sub(-9) or tostring(number)
  end

  local function visible(row) return not row.blocked end

  --- The conversations, newest first.
  function messages.threads()
    local by, order = {}, {}
    for _, row in ipairs(log.rows:get()) do
      if visible(row) then
        local at = key(row.number)
        local thread = by[at]
        if not thread then
          thread = { number = row.number, count = 0, unread = 0, time = 0, last = "" }
          by[at] = thread
          order[#order + 1] = thread
        end
        thread.count = thread.count + 1
        if row.direction == "in" and not row.read then thread.unread = thread.unread + 1 end
        if (row.time or 0) >= thread.time then
          thread.time, thread.last, thread.number = row.time or 0, row.text or "", row.number
        end
      end
    end
    for _, thread in ipairs(order) do thread.label = book.label(thread.number) end
    table.sort(order, function(a, b)
      if a.time ~= b.time then return a.time > b.time end
      return a.number < b.number
    end)
    return order
  end

  --- The messages with `number`, oldest first.
  function messages.thread(number)
    local at, out = key(number), {}
    for _, row in ipairs(log.rows:get()) do
      if visible(row) and key(row.number) == at then out[#out + 1] = row end
    end
    table.sort(out, function(a, b)
      if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) < (b.time or 0) end
      return a.id < b.id
    end)
    return out
  end

  --- Messages not yet read.
  function messages.unread()
    local count = 0
    for _, row in ipairs(log.rows:get()) do
      if row.direction == "in" and not row.read and visible(row) then count = count + 1 end
    end
    return count
  end

  --- Marks the thread with `number` read.
  function messages.read(number)
    local at = key(number)
    for _, row in ipairs(log.rows:get()) do
      if key(row.number) == at and row.direction == "in" and not row.read then
        log.update(row.id, { read = true })
      end
    end
  end

  --- Deletes the thread with `number`.
  function messages.forget(number)
    local at = key(number)
    for _, row in ipairs(log.rows:get()) do
      if key(row.number) == at then log.remove(row.id) end
    end
  end

  --- Sends `text` to `number`: a row at once, `sent` or `failed` as it goes.
  function messages.send(number, text, done)
    done = done or function() end
    local to = contacts.normal(number, book.country)
    if not to:match("^%+?[%d*#]+$") or (text or "") == "" then
      messages.message:set("Enter a number and a message")
      done(false, "nothing to send")
      return false
    end
    local id = "out:" .. tostring(morf.time.now_ms()) .. ":" .. tostring(serial)
    log.put { id = id, number = to, text = text, direction = "out", time = morf.time.now(), state = "sending",
      read = true, delivery = "" }
    return sms.send(to, text, { report = options.report == true }, function(ok, why, path)
      log.update(id, { state = ok and "sent" or "failed" })
      if ok and path ~= "" then
        pending[path] = id
        if not options.report then sms.delete(path) pending[path] = nil end
      end
      if not ok then messages.message:set(tostring(why or "Not sent")) end
      done(ok, why)
    end)
  end

  -- A status report on a message sent, whether its object is still here.
  morf.effect("eva.messages." .. serial .. ".delivery", function()
    for _, row in ipairs(sms.list:get()) do
      local id = pending[row.path]
      if id and row.delivery ~= "" then
        log.update(id, { delivery = row.delivery })
        pending[row.path] = nil
        sms.delete(row.path)
      end
    end
  end)

  if owner then
    sms.on_received(function(row)
      if row.pdu == "status-report" then
        if row.path then sms.delete(row.path) end
        return
      end
      local time = M.seconds(row.time) or morf.time.now()
      local blocked = book.blocked(row.number)
      log.put { id = table.concat({ "in", row.number, row.time, tostring(#row.text) }, ":"),
        number = row.number, text = row.text, direction = "in", time = time, state = "received",
        read = false, blocked = blocked or nil, delivery = "" }
      if not blocked then
        if options.ring then options.ring.trigger("message-new-sms") end
        if options.notify then
          options.notify { summary = book.label(row.number), body = row.text, app = "Messages", urgency = 1,
            reply = row.number }
        end
      end
      sms.delete(row.path)
    end)
  end

  return messages
end

return M
