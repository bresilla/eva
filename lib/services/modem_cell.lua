-- Cell broadcast on the modem `lib.services.modem` watches: the CellBroadcast
-- interface (ModemManager 1.24 and later) and one Cbm object per alert.
--
--   local cell = mobile.cell
--   cell.on_alert(function(row) end)   -- { path, channel, code, update, text, language }
--   cell.channels({ { 4370, 4383 } })  -- what the modem listens to
--   cell.delete(path)
--
-- An alert is announced once, when it is whole and when its channel, code and
-- update are new: networks repeat them for as long as the alert stands.
local morf = require("morf")
local dbus_client = require("lib.services.dbus")

local M = {}

local MM = "org.freedesktop.ModemManager1"
local CELL = MM .. ".Modem.CellBroadcast"
local CBM = MM .. ".Cbm"
local PROPERTIES = "org.freedesktop.DBus.Properties"
local QUICK = 10000
local RECEIVED = 2 -- MMCbmState

local serial = 0

function M.attach(client, options)
  serial = serial + 1
  local dry = options.dry
  local cell = { present = morf.signal("eva.modem." .. serial .. ".cell", false) }
  local bound
  local handles, watching, seen, listeners = {}, {}, {}, {}

  local function fresh(row)
    local mark = ("%d/%d/%d"):format(row.channel, row.code, row.update)
    if seen[mark] then return false end
    seen[mark] = true
    return true
  end

  local function read(path)
    client.call1_async(MM, path, PROPERTIES, "GetAll", { CBM }, QUICK, function(p)
      if type(p) ~= "table" or not watching[path] or tonumber(p.State) ~= RECEIVED then return end
      local row = { path = path, text = tostring(p.Text or ""), channel = tonumber(p.Channel) or 0,
        code = tonumber(p.MessageCode) or 0, update = tonumber(p.Update) or 0,
        language = tostring(p.Language or "") }
      local handle = watching[path]
      if type(handle) == "table" and handle.close then pcall(handle.close) end
      watching[path] = true
      if fresh(row) then
        for _, listener in ipairs(listeners) do listener(row) end
      end
    end)
  end

  local function follow(path)
    if watching[path] or type(path) ~= "string" then return end
    watching[path] = client.on_properties(MM, path, function(interface)
      if interface == CBM then read(path) end
    end) or true
    read(path)
  end

  local function unfollow(path)
    local handle = watching[path]
    if type(handle) == "table" and handle.close then pcall(handle.close) end
    watching[path] = nil
    client.forget(path, MM)
  end

  --- The modem to follow; nil lets go of it.
  function cell.bind(path)
    if path == bound then return end
    for _, handle in pairs(handles) do pcall(handle.close) end
    handles = {}
    local all = {}
    for each in pairs(watching) do all[#all + 1] = each end
    for _, each in ipairs(all) do unfollow(each) end
    bound = path
    cell.present:set(path ~= nil)
    if not path then return end
    handles = {
      client.on_signal(MM, path, CELL, "Added", function(body) follow(dbus_client.first(body)) end),
      client.on_signal(MM, path, CELL, "Deleted", function(body) unfollow(dbus_client.first(body)) end),
    }
    client.call1_async(MM, path, CELL, "List", nil, QUICK, function(list)
      for _, each in ipairs(type(list) == "table" and list or {}) do follow(each) end
    end)
  end

  --- `listener(row)` for each new alert.
  function cell.on_alert(listener) listeners[#listeners + 1] = listener end

  --- Sets the channels listened to: `ranges` as `{ { first, last }, ... }`.
  function cell.channels(ranges, done)
    done = done or function() end
    if not bound then done(false, "no cell broadcast") return false end
    if dry() then done(false, "dry run") return false end
    return client.call_async(MM, bound, CELL, "SetChannels", { dbus_client.typed("a(uu)", ranges) }, QUICK,
      function(reply, err) done(reply ~= nil, err) end) == true
  end

  --- Takes an alert off the modem.
  function cell.delete(path, done)
    done = done or function() end
    if not bound or dry() then done(false, "no cell broadcast") return false end
    return client.call_async(MM, bound, CELL, "Delete", { dbus_client.o(path) }, QUICK,
      function(reply, err) done(reply ~= nil, err) end) == true
  end

  return cell
end

return M
