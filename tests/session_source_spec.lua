-- The session's actions have one source: what the session menu, the quick
-- settings' row, the lock, the greeter, Settings and the launcher call an action
-- and draw it with.
--
--     morf test --no-dbus tests/session_source_spec.lua
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local source = require("models.session_actions")
  local model = require("session_model")
  local power = require("models.auth_power")
  morf.ipc.shared = function()
    return { list = model.ACTIONS == source.LIST, by_id = model.BY_ID == source.BY_ID }
  end
  morf.ipc.login = function()
    local out = {}
    for id, action in pairs(power.ACTIONS) do
      out[id] = { same = source.BY_ID[action.id] == action, can = action.can, method = action.method, name = action.name }
    end
    return out
  end
  morf.ipc.order = function() return power.ORDER end
  morf.ipc.form = function()
    for _, section in ipairs(require("settings_forms").PAGES.commands.sections) do
      if section.title == "Session" then
        local out = {}
        for _, field in ipairs(section.fields) do
          out[#out + 1] = { key = field.key, title = field.title, icon = field.icon }
        end
        return out
      end
    end
  end
  morf.ipc.launcher = function()
    local out = {}
    for _, row in ipairs(require("providers").system_rows("")) do
      out[(row.id:gsub("^system:", ""))] = { name = row.name, material = row.material }
    end
    return out
  end
]]

local function load()
  test.load("../shell/init.lua", { size = { 100, 100 }, source = HOST, env = { EVA_DRY_RUN = "1" } })
  test.advance(50)
end

test.it("the session menu reads the shared list", function()
  load()
  test.eq(test.ipc("shared"), { list = true, by_id = true })
end)

test.it("the login screens' three are the session's own, under their logind names", function()
  load()
  local login = test.ipc("login")
  test.eq(login.suspend, { same = true, can = "suspend", method = "Suspend", name = "Suspend" })
  test.eq(login.reboot, { same = true, can = "reboot", method = "Reboot", name = "Restart" })
  test.eq(login.poweroff, { same = true, can = "power_off", method = "PowerOff", name = "Power off" })
end)

test.it("the login screens keep their order", function()
  load()
  test.eq(test.ipc("order"), { "suspend", "reboot", "poweroff" })
end)

test.it("Settings names each command as the menu does", function()
  load()
  local form = test.ipc("form")
  test.eq(#form, 7)
  test.eq(form[1], { key = "session.commands.lock", title = "Lock", icon = "lock" })
  test.eq(form[5], { key = "session.commands.suspend_hibernate", title = "Suspend, then hibernate", icon = "hotel" })
  test.eq(form[7], { key = "session.commands.shutdown", title = "Power off", icon = "power_settings_new" })
end)

test.it("the launcher names them as the menu does, its own wording for Lock kept", function()
  load()
  local rows = test.ipc("launcher")
  test.eq(rows.reboot, { name = "Restart", material = "restart_alt" })
  test.eq(rows.shutdown, { name = "Power off", material = "power_settings_new" })
  test.eq(rows.lock, { name = "Lock the screen", material = "lock" })
end)

test.it("no other file spells the actions out", function()
  for _, name in ipairs { "shell/session_model.lua", "models/auth_power.lua", "themes/layouts/lock.lua",
    "themes/layouts/greet.lua", "shell/providers.lua", "shell/settings_forms.lua" } do
    local source = morf.fs.read(name)
    for _, word in ipairs { '"restart_alt"', '"power_settings_new"', '"bedtime"' } do
      test.falsy(source:find(word, 1, true), name .. " still holds " .. word)
    end
  end
end)
