-- One StatusNotifier item, for the tray scenario: it registers with the
-- session's watcher from the connection it serves on, as any program does.
local morf = require("morf")
local ui = require("morf.ui")

local NAME = "org.eva.See.TrayItem"
local PROPERTIES = "org.freedesktop.DBus.Properties"

morf.surface.width, morf.surface.height = 1, 1
ui.Item { width = 1, height = 1 }

local function typed(signature, value) return { signature = signature, value = value } end
local PIXEL = string.char(255, 120, 200, 255)
local PROPS = {
  Category = "ApplicationStatus", Id = "see-tray", Title = "See tray", Status = "Active", IconName = "",
  IconPixmap = typed("a(iiay)", { { 22, 22, PIXEL:rep(22 * 22) } }), ItemIsMenu = false,
}
local item = morf.dbus.serve("session", NAME, "/StatusNotifierItem", false)
item:on_call(function(call)
  if call.interface == PROPERTIES and call.member == "GetAll" then item:reply(call.id, PROPS)
  elseif call.interface == PROPERTIES and call.member == "Get" then item:reply(call.id, typed("v", PROPS[call.arguments[2]]))
  else item:reply(call.id, nil) end
end)
morf.time.timer(800, function()
  item:call("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher",
    "RegisterStatusNotifierItem", "/StatusNotifierItem")
end, false)
