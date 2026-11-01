-- Text messages on the modem `lib.services.modem` watches: the Messaging
-- interface and one Sms object per message.
--
--   local sms = mobile.messaging
--   sms.list:get()     -- { { path, number, text, state, pdu, time, delivery, reference }, ... }
--   sms.send("+31...", "hello", { report = true }, done)   -- done(ok, why, path)
--   sms.on_received(function(row) end)   -- each message complete, once
--   sms.delete(path)
--
-- `state` is stored, receiving, received, sending or sent. A message the
-- network has not finished delivering is listed as receiving: `Added` comes
-- with its first part, and only `State` says when the last has come.
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = {}

local MM = "org.freedesktop.ModemManager1"
local MESSAGING = MM .. ".Modem.Messaging"
local SMS = MM .. ".Sms"
local PROPERTIES = "org.freedesktop.DBus.Properties"
local QUICK, SENDING = 10000, 60000

-- MMSmsState, MMSmsPduType.
M.STATES = { [0] = "unknown", "stored", "receiving", "received", "sending", "sent" }
M.PDUS = { [0] = "unknown", "deliver", "submit", "status-report", [32] = "deliver", [33] = "submit" }

--- What MMSmsDeliveryState means to the person who sent it: delivered,
--- pending (the network keeps trying), failed, or "" when it says nothing.
function M.delivery(value)
  value = tonumber(value)
  if value == nil or value == 0x100 then return "" end
  if value <= 0x02 then return "delivered" end
  if (value >= 0x20 and value <= 0x25) or (value >= 0x300 and value < 0x400) then return "pending" end
  return "failed"
end

local serial = 0

function M.attach(client, options)
  serial = serial + 1
  local name = "eva.modem." .. serial .. "."
  local dry = options.dry
  local sms = {
    present = morf.signal(name .. "messaging", false),
    list = morf.signal(name .. "sms", {}),
  }
  local bound
  local rows, order, watching, modem_handles, listeners = {}, {}, {}, {}, {}

  local function publish()
    local list = {}
    for _, path in ipairs(order) do
      if rows[path].ready then list[#list + 1] = rows[path] end
    end
    sms.list:set(list)
  end

  local function apply(row, p)
    if p.State ~= nil then row.state = M.STATES[tonumber(p.State)] or "unknown" end
    if p.PduType ~= nil then row.pdu = M.PDUS[tonumber(p.PduType)] or "unknown" end
    if p.Number ~= nil then row.number = tostring(p.Number) end
    if p.Text ~= nil then row.text = tostring(p.Text) end
    if p.Timestamp ~= nil then row.time = tostring(p.Timestamp) end
    if p.DeliveryState ~= nil then row.delivery = M.delivery(p.DeliveryState) end
    if p.MessageReference ~= nil then row.reference = tonumber(p.MessageReference) or 0 end
  end

  -- A message that came from the network, once: the first time it reads whole.
  local function announce(row)
    if row.announced or not row.ready or row.state ~= "received" then return end
    row.announced = true
    for _, listener in ipairs(listeners) do listener(row) end
  end

  local function follow(path)
    if watching[path] or type(path) ~= "string" then return end
    order[#order + 1] = path
    local row = { path = path, number = "", text = "", state = "unknown", pdu = "unknown", time = "",
      delivery = "", reference = 0, ready = false }
    rows[path] = row
    watching[path] = client.on_properties(MM, path, function(interface, changed)
      if interface ~= SMS then return end
      apply(row, changed)
      publish()
      announce(row)
    end) or {}
    client.call1_async(MM, path, PROPERTIES, "GetAll", { SMS }, QUICK, function(properties)
      if not rows[path] then return end
      if type(properties) == "table" then apply(row, properties) end
      row.ready = true
      publish()
      announce(row)
    end)
  end

  local function unfollow(path)
    local handle = watching[path]
    if not handle then return end
    if handle.close then pcall(handle.close) end
    watching[path], rows[path] = nil, nil
    for index, each in ipairs(order) do
      if each == path then table.remove(order, index) break end
    end
    client.forget(path, MM)
    publish()
  end

  local function clear()
    for _, handle in pairs(modem_handles) do pcall(handle.close) end
    modem_handles = {}
    local all = {}
    for path in pairs(watching) do all[#all + 1] = path end
    for _, path in ipairs(all) do unfollow(path) end
    bound = nil
    sms.present:set(false)
  end

  --- The modem to follow; nil lets go of it.
  function sms.bind(path)
    if path == bound then return end
    clear()
    if not path then return end
    bound = path
    sms.present:set(true)
    modem_handles = {
      client.on_signal(MM, path, MESSAGING, "Added", function(body) follow(body[1]) end),
      client.on_signal(MM, path, MESSAGING, "Deleted", function(body) unfollow(dbus_client.first(body)) end),
    }
    client.call1_async(MM, path, MESSAGING, "List", nil, QUICK, function(list)
      for _, each in ipairs(type(list) == "table" and list or {}) do follow(each) end
    end)
  end

  --- `listener(row)` for each message the network delivers.
  function sms.on_received(listener) listeners[#listeners + 1] = listener end

  --- Sends `text` to `number`. `opts.report` asks the network to say when
  --- it lands. `done(ok, why, path)`.
  function sms.send(number, text, opts, done)
    opts = opts or {}
    done = done or function() end
    if not bound then done(false, "no messaging modem") return false end
    if dry() then
      morf.log("info", "eva: phone send sms (dry run)")
      done(false, "dry run")
      return false
    end
    local properties = { number = number, text = text }
    if opts.report then properties["delivery-report-request"] = true end
    return client.call1_async(MM, bound, MESSAGING, "Create", { dbus_client.typed("a{sv}", properties) }, QUICK,
      function(path, err)
        if type(path) ~= "string" then return done(false, err) end
        client.call_async(MM, path, SMS, "Send", nil, SENDING, function(reply, failure)
          done(reply ~= nil, failure, path)
        end)
      end) == true
  end

  --- Takes a message off the modem.
  function sms.delete(path, done)
    done = done or function() end
    if not bound then done(false, "no messaging modem") return false end
    if dry() then done(false, "dry run") return false end
    return client.call_async(MM, bound, MESSAGING, "Delete", { dbus_client.o(path) }, QUICK, function(reply, err)
      done(reply ~= nil, err)
    end) == true
  end

  return sms
end

return M
