-- Drives, usage, trash and printers. The passphrase of an encrypted drive
-- reaches this module as a plain argument and leaves it as one: no signal or
-- field here ever holds it.
local morf = require("morf")
local config = require("config")
local udisks = require("lib.services.udisks")
local trash = require("lib.services.trash")
local printers = require("lib.services.printers")
local page_model = require("page_model")

local M = {}

local connected

--- The one connection to UDisks2.
function M.disks()
  if not connected then connected = udisks.connect() end
  return connected
end

--- What `row`'s mount uses, or nil: `{ used, total, share }`.
function M.usage(mount)
  if (mount or "") == "" then return nil end
  local ok, disk = pcall(morf.fs.disk, mount)
  if not ok or type(disk) ~= "table" or (disk.total or 0) <= 0 then return nil end
  return { used = disk.used, total = disk.total, free = disk.available, share = disk.used / disk.total }
end

function M.new(active)
  local model = page_model.new("storage", active)
  local disks = M.disks()
  local bin = morf.signal("eva.storage.trash", { count = 0, size = 0 })
  model.asking = morf.signal("eva.storage.asking", "")
  model.emptying = morf.signal("eva.storage.emptying", false)
  model.human = udisks.human

  local function refresh()
    disks.refresh(true)
    bin:set(trash.read())
  end
  model.on_show(refresh)
  morf.time.timer(5000, function() if model.active() then refresh() end end, true)

  function model.available() return disks.available() end
  function model.volumes() return disks.volumes() end
  function model.removable()
    local out = {}
    for _, row in ipairs(disks.volumes()) do if row.removable then out[#out + 1] = row end end
    return out
  end
  function model.fixed()
    local out = {}
    for _, row in ipairs(disks.volumes()) do if not row.removable then out[#out + 1] = row end end
    return out
  end
  function model.home() return M.usage(morf.fs.home()) end
  function model.root() return M.usage("/") end
  function model.usage(row) return M.usage(row.mount_point) end
  function model.trash() return bin:get() end

  function model.mount(row)
    return model.action(function(done) disks.mount(row, done) return true end)
  end
  function model.unmount(row)
    return model.action(function(done) disks.unmount(row, done) return true end)
  end
  function model.eject(row)
    return model.action(function(done) disks.eject(row, done) return true end, function()
      model.say(("%s can be removed safely"):format(row.name))
    end)
  end
  function model.lock(row)
    return model.action(function(done) disks.lock(row, done) return true end)
  end
  function model.ask(row) model.asking:set(row.path) end
  function model.dismiss() model.asking:set("") end
  function model.asked()
    for _, row in ipairs(disks.volumes()) do if row.path == model.asking:get() then return row end end
  end
  --- Unlocks the asked volume with `passphrase`, and mounts what opens.
  function model.unlock(passphrase)
    local row = model.asked()
    model.asking:set("")
    if not row or (passphrase or "") == "" then return false end
    return model.action(function(done)
      disks.unlock(row, passphrase, function(path, why)
        if not path then return done(nil, why) end
        disks.mount({ path = path, device = row.device }, done)
      end)
      return true
    end)
  end
  function model.empty_trash()
    model.emptying:set(false)
    return model.action(function(done) trash.empty(done) return true end, function() bin:set(trash.read()) end)
  end
  function model.low_space() return tonumber(config.get("storage.low_space")) or 0 end
  function model.set_low_space(value) config.set("storage.low_space", value) end
  function model.popup() return config.get("storage.popup") == true end
  function model.set_popup(on) config.set("storage.popup", on == true) end
  return model
end

--- The printers page.
function M.printers(active)
  local model = page_model.new("printers", active)
  local state = morf.signal("eva.printers.state", { available = false, printers = {}, jobs = {}, scanners = {} })
  local found = morf.signal("eva.printers.found", {})
  model.searching = morf.signal("eva.printers.searching", false)
  model.declared = require("lib.services.host").nixos

  local function refresh() printers.read(function(snapshot) state:set(snapshot) end) end
  model.on_show(refresh)

  function model.available() return state:get().available end
  function model.list() return state:get().printers end
  function model.jobs() return state:get().jobs end
  function model.scanners() return state:get().scanners or {} end
  function model.found() return found:get() end
  function model.discover()
    model.searching:set(true)
    printers.discover(function(list)
      model.searching:set(false)
      found:set(list)
      if #list == 0 then model.say("No printers answered on this network") end
    end)
  end
  function model.add(row)
    return model.action(function(done) printers.add(row.name, row.uri, done) return true end, refresh)
  end
  function model.add_address(name, uri)
    return model.action(function(done) printers.add(name, uri, done) return true end, refresh)
  end
  function model.remove(row)
    return model.action(function(done) printers.remove(row.name, done) return true end, refresh)
  end
  function model.set_default(row)
    return model.action(function(done) printers.set_default(row.name, done) return true end, refresh)
  end
  function model.set_enabled(row, on)
    return model.action(function(done) printers.set_enabled(row.name, on, done) return true end, refresh)
  end
  function model.cancel(job)
    return model.action(function(done) printers.cancel(job.id, done) return true end, refresh)
  end
  return model
end

return M
