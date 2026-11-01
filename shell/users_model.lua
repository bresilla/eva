-- The Users page: the accounts this machine has and this person's picture,
-- which the lock screen and the greeter read from the same place.
local morf = require("morf")
local accounts = require("lib.services.accounts")
local host = require("lib.services.host")
local page_model = require("page_model")

local M = {}

function M.new(key, active)
  local model = page_model.new(key, active)
  local rows = morf.signal("eva.users.rows", {})
  local revision = morf.signal("eva.users.face", 0)
  local fake = host.fake() and require("lib.services.host_fake")

  local function read()
    local list = fake and fake.accounts() or accounts.list()
    local admins = fake and fake.administrators() or accounts.administrators()
    local me = fake and list[1] or accounts.me()
    for _, row in ipairs(list) do
      row.admin = admins[row.name] == true
      row.me = me ~= nil and row.name == me.name
    end
    rows:set(list)
  end
  model.on_show(read)

  function model.list() return rows:get() end
  function model.me()
    revision:get()
    for _, row in ipairs(rows:get()) do if row.me then return row end end
    return rows:get()[1] or { name = morf.env("USER") or "user", label = morf.env("USER") or "user", home = morf.fs.home() }
  end
  function model.declared() return host.nixos() end
  model.choosing = morf.signal("eva.users.choosing", false)

  --- The picture at `path` becomes this person's.
  function model.set_face(path)
    return model.action(function(done)
      accounts.set_face(model.me(), path, function(result, why)
        read()
        revision:set(revision:get() + 1)
        done(result, why)
      end)
      return true
    end)
  end
  function model.set_label(label)
    if label == "" then model.say("Give it a name", true) return false end
    return model.action(function(done)
      accounts.set_label(model.me(), label, done)
      return true
    end, read)
  end
  return model
end

return M
