-- Drives and volumes, from UDisks2: what is plugged in, mounting, ejecting and
-- unlocking. Actions go over the system bus without waiting, since polkit may
-- ask first; a LUKS passphrase travels only as the argument of `Unlock` and is
-- kept nowhere here.
--
--   local disks = require("lib.services.udisks").connect()
--   disks.volumes()              -- { { path, device, label, size, fs, mounted, ... } }
--   disks.mount(row, function(mount_point, err) end)
--   disks.on_added(function(row) end)
local morf = require("morf")
local host = require("lib.services.host")
local dbus_client = require("lib.services.dbus")

local M = {}

local NAME = "org.freedesktop.UDisks2"
local ROOT = "/org/freedesktop/UDisks2"
local BLOCK, DRIVE = NAME .. ".Block", NAME .. ".Drive"
local FILESYSTEM, ENCRYPTED = NAME .. ".Filesystem", NAME .. ".Encrypted"
local PARTITION = NAME .. ".Partition"
local TIMEOUT = 60000

local typed = dbus_client.typed
local function no_options() return typed("a{sv}", {}) end

--- Bytes UDisks sends with a closing NUL, as text.
local function text(bytes)
  local out = dbus_client.bytes_to_string(bytes)
  while out:sub(-1) == "\0" do out = out:sub(1, -2) end
  return out
end

--- `size` as a person reads it.
function M.human(size)
  size = tonumber(size) or 0
  local units = { "B", "KB", "MB", "GB", "TB" }
  local value, unit = size, 1
  while value >= 1000 and unit < #units do value, unit = value / 1000, unit + 1 end
  return unit == 1 and ("%d B"):format(value) or ("%.1f %s"):format(value, units[unit])
end

--- The tree as drives and volumes.
function M.parse(objects)
  local drives, volumes = {}, {}
  for path, interfaces in pairs(objects or {}) do
    local drive = interfaces[DRIVE]
    if drive then
      drives[path] = { path = path, vendor = drive.Vendor or "", model = drive.Model or "", size = drive.Size or 0,
        removable = drive.Removable == true or drive.MediaRemovable == true, ejectable = drive.Ejectable == true,
        can_power_off = drive.CanPowerOff == true, bus = drive.ConnectionBus or "" }
    end
  end
  local clear = {}
  for path, interfaces in pairs(objects or {}) do
    local block = interfaces[BLOCK]
    if block and block.CryptoBackingDevice and block.CryptoBackingDevice ~= "/" then
      clear[block.CryptoBackingDevice] = path
    end
  end
  for path, interfaces in pairs(objects or {}) do
    local block = interfaces[BLOCK]
    local filesystem, encrypted = interfaces[FILESYSTEM], interfaces[ENCRYPTED]
    if block and (filesystem or encrypted) and block.HintIgnore ~= true then
      local drive = drives[block.Drive or ""]
      local backing = block.CryptoBackingDevice and block.CryptoBackingDevice ~= "/"
      local points = {}
      for _, point in ipairs(filesystem and filesystem.MountPoints or {}) do points[#points + 1] = text(point) end
      local unlocked = clear[path]
      local inner = unlocked and objects[unlocked] and objects[unlocked][FILESYSTEM]
      local row = {
        path = path, device = text(block.PreferredDevice or block.Device), size = block.Size or 0,
        label = block.IdLabel or "", fs = block.IdType or "", drive = block.Drive or "/",
        removable = drive ~= nil and drive.removable, system = block.HintSystem == true,
        encrypted = encrypted ~= nil, unlocked = unlocked, is_clear = backing == true,
        filesystem = filesystem ~= nil, partition = interfaces[PARTITION] ~= nil,
        mount_point = points[1] or "", mounted = #points > 0,
      }
      if inner and #(inner.MountPoints or {}) > 0 then
        row.mount_point, row.mounted = text(inner.MountPoints[1]), true
      end
      local vendor = drive and (drive.vendor .. " " .. drive.model):gsub("^%s+", ""):gsub("%s+$", "") or ""
      row.drive_name = vendor
      row.name = row.label ~= "" and row.label or (vendor ~= "" and vendor or row.device)
      row.can_eject = drive ~= nil and (drive.ejectable or drive.can_power_off)
      if not backing then volumes[#volumes + 1] = row end
    end
  end
  table.sort(volumes, function(a, b)
    if a.removable ~= b.removable then return a.removable end
    return a.device < b.device
  end)
  return drives, volumes
end

--- Starts watching, while the configuration loads. Absent UDisks reads as no
--- drives and is never started by watching.
function M.connect(options)
  options = options or {}
  local client = options.client or host.bus("system")
  local disks = {}
  local snapshot = morf.signal("eva.udisks.snapshot", { available = false, drives = {}, volumes = {} })
  local known, armed, listeners = {}, false, {}

  local function publish(objects)
    if not objects then snapshot:set { available = false, drives = {}, volumes = {} } return end
    local drives, volumes = M.parse(objects)
    snapshot:set { available = true, drives = drives, volumes = volumes }
    local seen = {}
    for _, row in ipairs(volumes) do
      seen[row.path] = true
      if armed and row.removable and not known[row.path] then
        for _, handler in ipairs(listeners) do pcall(handler, row) end
      end
    end
    known, armed = seen, true
  end

  --- Re-reads the tree; `start` lets the read start the service.
  function disks.refresh(start)
    if not (start or client.has_owner(NAME)) then return publish(nil) end
    local sent = client.call1_async(NAME, ROOT, "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", nil,
      TIMEOUT, function(objects) publish(type(objects) == "table" and objects or nil) end)
    if not sent then publish(nil) end
  end

  function disks.available() return snapshot:get().available end
  function disks.volumes() return snapshot:get().volumes end
  function disks.on_added(handler) listeners[#listeners + 1] = handler end

  local function after(done, value)
    return function(reply, why)
      disks.refresh()
      if reply == nil then return done(nil, why) end
      done(value ~= nil and value or dbus_client.first(reply))
    end
  end
  local function send(path, interface, method, arguments, done, what, value)
    done = done or function() end
    if host.held(what) then done(true) return true end
    local sent, why = client.call_async(NAME, path, interface, method, arguments, TIMEOUT, after(done, value))
    if not sent then done(nil, why) end
    return sent
  end

  --- Where a row's filesystem is: itself, or what it unlocked to.
  local function target(row) return row.unlocked or row.path end

  --- Mounts it. `done(mount_point, err)`.
  function disks.mount(row, done) return send(target(row), FILESYSTEM, "Mount", { no_options() }, done, "mount " .. row.device) end
  function disks.unmount(row, done) return send(target(row), FILESYSTEM, "Unmount", { no_options() }, done, "unmount " .. row.device, true) end

  --- Unlocks a LUKS volume with `passphrase`. `done(cleartext_path, err)`.
  function disks.unlock(row, passphrase, done)
    return send(row.path, ENCRYPTED, "Unlock", { passphrase, no_options() }, done, "unlock " .. row.device)
  end
  function disks.lock(row, done) return send(row.path, ENCRYPTED, "Lock", { no_options() }, done, "lock " .. row.device, true) end

  --- Makes the drive safe to pull: every mount undone, then powered off
  --- where it can be, ejected where not.
  function disks.eject(row, done)
    done = done or function() end
    local drive = snapshot:get().drives[row.drive]
    if not drive then done(nil, "No drive to eject") return nil end
    local method = drive.can_power_off and "PowerOff" or "Eject"
    local pending = {}
    for _, each in ipairs(disks.volumes()) do
      if each.drive == row.drive and each.mounted then pending[#pending + 1] = each end
    end
    local function next_one()
      local one = table.remove(pending, 1)
      if not one then return send(row.drive, DRIVE, method, { no_options() }, done, "eject " .. row.drive, true) end
      disks.unmount(one, function(ok, why)
        if ok == nil then return done(nil, why) end
        next_one()
      end)
    end
    next_one()
    return true
  end

  client.watch_name(NAME, function() disks.refresh() end)
  local function changed() disks.refresh() end
  local debounced = dbus_client.debounce(200, changed)
  client.on_signal(NAME, ROOT, "org.freedesktop.DBus.ObjectManager", "InterfacesAdded", debounced)
  client.on_signal(NAME, ROOT, "org.freedesktop.DBus.ObjectManager", "InterfacesRemoved", debounced)
  disks.refresh()
  return disks
end

return M
