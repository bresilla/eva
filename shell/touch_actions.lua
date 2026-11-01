-- What a gesture can do: each action's name and icon for the Settings page, and
-- how it runs. An action has `run(event, key)`, what a finished gesture does, and
-- may have `follow(event)`: a handle `{ update, finish, cancel }` that keeps
-- what it moves under the fingers, or nil where it cannot. The panel, keyboard
-- and workspace moves are the ones the edge strips use.
local M = {}

local INWARD = { bottom = "up", top = "down", left = "right", right = "left" }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }
-- How far a drag moves a level from one end to the other.
local LEVEL_SPAN = 320

local function gestures() return require("phone_gestures") end

-- A panel on the fingers, when they travel the way it opens or shuts.
local function pull(drawer, event)
  local inward = INWARD[drawer.edge]
  if event.direction ~= inward and event.direction ~= OPPOSITE[inward] then return nil end
  local across = drawer.edge == "left" or drawer.edge == "right"
  gestures().close_panels(drawer)
  if not drawer.begin_drag() then return nil end
  local function travel(e) return across and e.dx or e.dy end
  local function speed(e) return across and (e.vx or 0) or (e.vy or 0) end
  return {
    update = function(e) drawer.drag_by(travel(e)) end,
    finish = function(e) drawer.drag_by(travel(e)) drawer.end_drag(speed(e), false) end,
    cancel = function() drawer.end_drag(0, true) end,
  }
end

-- The page in the panel that holds it, shut if it is on show.
local function page(key, action, opened)
  function action.follow(event)
    local holder = require("pages").holder(key)
    if not holder or holder.drawer.open:get() then return nil end
    holder.panel.select(key)
    if opened then opened() end
    return pull(holder.drawer, event)
  end
  function action.run()
    local holder = require("pages").holder(key)
    if not holder then return end
    if holder.drawer.open:get() and holder.panel.showing(key) then return holder.drawer.set(false) end
    gestures().close_panels(holder.drawer)
    holder.panel.select(key)
    if opened then opened() end
    holder.drawer.set(true)
  end
  return action
end

local function launcher_open(menu)
  local launcher = require("launcher")
  if launcher.drawer.open:get() then return launcher.drawer.set(false) end
  gestures().close_panels(launcher.drawer)
  if menu then require("menus").open(menu) end
  launcher.set_query("")
  launcher.drawer.set(true)
end

-- The pages under the fingers, sideways: workspaces, or with `apps` windows.
local function slide(event, apps)
  local controller = gestures().workspace_controller
  if not controller or (event.direction ~= "left" and event.direction ~= "right") then return nil end
  gestures().close_panels(nil)
  controller.begin("x", apps)
  return {
    update = function(e) controller.update(e.dx) end,
    finish = function(e)
      controller.update(e.dx)
      controller.finish(false, e.vx, gestures().global_allowed)
    end,
    cancel = function() controller.cancel() end,
  }
end

-- The next workspace is reached by going `way`: the pages move with the fingers.
local function workspace(action, step, way)
  function action.follow(event) return event.direction == way and slide(event) or nil end
  function action.run()
    gestures().close_panels(nil)
    require("services").workspace.step(step)
  end
  return action
end

-- The overview out as far as the fingers have gone.
local function overview_follow()
  local overview = require("overview")
  if overview.opened:get() then return nil end
  local function amount(e)
    local _, height = require("responsive").size()
    return math.min(1, math.max(0, (e.travel or 0) / math.max(1, height * .4)))
  end
  return {
    update = function(e) overview.follow(amount(e)) end,
    finish = function(e) overview.settle(e.committed == true) end,
    cancel = function() overview.settle(false) end,
  }
end

-- A level moved by how far the fingers go, up or right being more.
local function level(action, kind)
  function action.follow(event)
    local osd = require("osd")
    local from = (osd[kind]())
    local function set(e)
      local amount = (event.direction == "left" or event.direction == "right") and e.dx or -e.dy
      osd.adjust(kind, from + amount / LEVEL_SPAN)
      osd.flash(kind, true)
    end
    return { update = set, finish = set, cancel = function() osd.adjust(kind, from) end }
  end
  function action.run() end
  return action
end

M.ACTIONS = {
  { key = "none", name = "Nothing", icon = "block" },
  { key = "keyboard", name = "On-screen keyboard", icon = "keyboard",
    follow = function()
      local keyboard = require("keyboard")
      if not keyboard.pull_begin() then return nil end
      return {
        update = function(e) keyboard.drawer.drag_by(e.dy) end,
        finish = function(e) keyboard.drawer.drag_by(e.dy) keyboard.pull_end(e.vy or 0, false) end,
        cancel = function() keyboard.pull_end(0, true) end,
      }
    end,
    run = function()
      local keyboard = require("keyboard")
      if keyboard.active() then keyboard.set(false) else keyboard.show("full") end
    end },
  { key = "overview", name = "Overview", icon = "overview", follow = overview_follow,
    run = function() require("overview").toggle() end },
  { key = "recents", name = "Recent apps", icon = "history", follow = overview_follow,
    run = function() require("overview").toggle() end },
  { key = "launcher", name = "Launcher", icon = "search", run = function() launcher_open() end },
  { key = "app_grid", name = "App grid", icon = "apps", run = function() launcher_open("apps") end },
  { key = "dashboard", name = "Dashboard", icon = "dashboard",
    follow = function(event)
      local drawer = require("dashboard").drawer
      return not drawer.open:get() and pull(drawer, event) or nil
    end,
    run = function()
      local drawer = require("dashboard").drawer
      gestures().close_panels(drawer)
      drawer.toggle()
    end },
  page("settings", { key = "quick_settings", name = "Quick settings", icon = "tune" },
    function() require("utilities").request("") end),
  page("notifications", { key = "notifications", name = "Notifications", icon = "notifications" }),
  workspace({ key = "workspace_next", name = "Next workspace", icon = "arrow_forward" }, 1, "left"),
  workspace({ key = "workspace_previous", name = "Previous workspace", icon = "arrow_back" }, -1, "right"),
  { key = "switch_app", name = "Switch app", icon = "swap_horiz",
    follow = function(event) return slide(event, true) end,
    run = function() require("window_switcher").step(1, false) end },
  { key = "back", name = "Back", icon = "arrow_back",
    run = function()
      require("windows_model").send('hl.dispatch(hl.dsp.send_shortcut({ mods = "ALT", key = "Left" }))',
        "sendshortcut", "ALT,Left,")
    end },
  { key = "close_window", name = "Close window", icon = "close",
    run = function()
      local windows = require("windows_model")
      local c = windows.active()
      if c then windows.close(c.address) end
    end },
  { key = "show_desktop", name = "Show desktop", icon = "desktop_windows",
    run = function()
      local windows = require("windows_model")
      windows.show_desktop(windows.int(require("services").workspace.active()))
    end },
  { key = "screenshot", name = "Screenshot", icon = "screenshot_monitor",
    run = function() require("capture").shoot("screen", false) end },
  { key = "lock", name = "Lock", icon = "lock", run = function() require("session").run("lock") end },
  level({ key = "volume", name = "Volume, by dragging", icon = "volume_up" }, "volume"),
  level({ key = "brightness", name = "Brightness, by dragging", icon = "brightness_6" }, "brightness"),
  { key = "command", name = "Run a command", icon = "terminal",
    run = function(_, key) require("hot_corners").run(require("touch_bindings").command(key), "gesture") end },
}

M.BY_KEY = {}
for _, action in ipairs(M.ACTIONS) do M.BY_KEY[action.key] = action end

--- The name of the action `key`.
function M.name(key) return (M.BY_KEY[key] or M.BY_KEY.none).name end

--- The icon of the action `key`.
function M.icon(key) return (M.BY_KEY[key] or M.BY_KEY.none).icon end

return M
