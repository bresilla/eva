-- logind, behind one seam for the lock, the greeter and the shell. Connected
-- the first time it is asked for. Under EVA_DRY_RUN, EVA_FAKE_LOGIND stands in
-- for the bus: a JSON object with `can`, `inhibitors`, `sessions`, `firmware`,
-- `lid`, and nothing it is asked to do reaches a machine.
local morf = require("morf")
local M = {}

local NAME, MANAGER_PATH = "org.freedesktop.login1", "/org/freedesktop/login1"
local MANAGER = NAME .. ".Manager"

local function dry()
  local v = morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

local function stand_in(spec)
  local inhibitors = morf.signal("eva.fake.logind.inhibitors", spec.inhibitors or {})
  local handlers = { sleep = {}, lock = {} }
  local fake = { fake = true, calls = {} }
  fake.state = { can = spec.can or {}, preparing_for_sleep = false, lid_closed = spec.lid == true,
    session = { locked = false } }
  local function record(name) fake.calls[#fake.calls + 1] = name morf.log("info", "eva: logind " .. name .. " (dry run)") return true end
  function fake.available() return spec.available ~= false end
  function fake.can(what) return (spec.can or {})[what] or "na" end
  function fake.inhibitors() return inhibitors:get() end
  function fake.sessions() return spec.sessions or {} end
  function fake.activate(id) return record("ActivateSession " .. tostring(id)) end
  function fake.can_firmware() return spec.firmware or "na" end
  function fake.reboot_to_firmware() return record("RebootToFirmware") end
  function fake.power(method) return record(method) end
  function fake.on_prepare_for_sleep(fn) handlers.sleep[#handlers.sleep + 1] = fn end
  function fake.on_lock(fn) handlers.lock[#handlers.lock + 1] = fn end
  function fake.fire(kind, ...) for _, fn in ipairs(handlers[kind]) do fn(...) end end
  function fake.inhibit() return { release = function() end } end
  function fake.refresh() end
  return fake
end

local function real()
  local ok, login = pcall(function() return require("lib.services.logind").connect { udev = false } end)
  if not ok or not login then return nil end
  local client = require("lib.services.dbus").new { bus = "system" }
  local function call(method, arguments) return client.call1(NAME, MANAGER_PATH, MANAGER, method, arguments) end

  --- `{ what, who, why, mode, uid, pid }` for each inhibitor held now.
  function login.inhibitors()
    local rows, list = {}, call("ListInhibitors")
    for _, entry in ipairs(type(list) == "table" and list or {}) do
      rows[#rows + 1] = { what = entry[1] or "", who = entry[2] or "", why = entry[3] or "",
        mode = entry[4] or "", uid = entry[5] or -1, pid = entry[6] or -1 }
    end
    return rows
  end

  --- The other sessions on this seat: `{ id, user, uid, seat }`.
  function login.sessions()
    local list = call("ListSessions")
    local rows = {}
    for _, entry in ipairs(type(list) == "table" and list or {}) do
      rows[#rows + 1] = { id = entry[1], uid = entry[2], user = entry[3], seat = entry[4] }
    end
    return rows
  end

  function login.activate(id, done)
    return client.call_async(NAME, MANAGER_PATH, MANAGER, "ActivateSession", { id }, 25000,
      function(reply, err) if done then done(reply ~= nil, err) end end)
  end

  function login.can_firmware()
    local answer = call("CanRebootToFirmwareSetup")
    return type(answer) == "string" and answer or "na"
  end

  --- Whether the lid is shut, asked now: logind does not announce it.
  function login.lid_closed() return client.get(NAME, MANAGER_PATH, MANAGER, "LidClosed") == true end

  --- Boots into the firmware's own setup screen. `interactive` as for any
  --- power action.
  function login.reboot_to_firmware(interactive, done)
    return client.call_async(NAME, MANAGER_PATH, MANAGER, "SetRebootToFirmwareSetup", { true }, 25000,
      function(reply, err)
        if reply == nil then
          if done then done(false, err) end
          return
        end
        login.reboot(interactive, done)
      end)
  end
  return login
end

--- The connection, or nil where there is no logind.
function M.connect()
  if M.made ~= nil then return M.made or nil end
  local spec = dry() and morf.env("EVA_FAKE_LOGIND")
  if spec and spec ~= "" then
    local ok, value = pcall(morf.json.decode, spec)
    M.made = stand_in(ok and type(value) == "table" and value or {})
    return M.made
  end
  M.made = real() or false
  return M.made or nil
end

--- What a lock asks of it, read fresh: whether it can be heard at all, whether
--- the machine is going to sleep, whether the lid is shut.
function M.guard()
  local login = M.connect()
  if not login then return nil end
  return {
    available = function() return login.available() end,
    preparing = function() return login.state.preparing_for_sleep == true end,
    lid_closed = function()
      if login.lid_closed then return login.lid_closed() end
      return login.state.lid_closed == true
    end,
    on_sleep = function(fn) login.on_prepare_for_sleep(function(going) if going then fn() end end) end,
    on_lock = login.on_lock,
  }
end

return M
