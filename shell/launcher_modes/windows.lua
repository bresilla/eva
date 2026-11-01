-- The open windows, and what can be done to them: on Hyprland through the window
-- menu's own buttons, elsewhere through the toplevel list every wlroots
-- compositor gives.
local morf = require("morf")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")

local M = {}

local function hyprland()
  local ok, h = pcall(require, "lib.compositor.hyprland")
  if ok and h.available() then return h end
end

-- The window menu's buttons a row offers, as `{ name, material, button id }`.
local BUTTONS = {
  { "Float or tile", "picture_in_picture", "top:float" }, { "Fullscreen", "fullscreen", "top:fullscreen" },
  { "Maximize", "crop_free", "top:maximize" }, { "Pin to every workspace", "keep", "top:pin" },
  { "Center", "center_focus_strong", "top:center" }, { "Stash away", "inventory", "left:stash" },
  { "Force quit", "dangerous", "bottom:kill" },
}

local function hypr_actions(c, h)
  local address = c.address
  local actions = {
    { name = "Switch to it", material = "open_in_browser",
      run = function() h.dispatch("focuswindow", "address:" .. address) return "close" end },
    { name = "Bring it here", material = "move_down",
      run = function() h.dispatch("movetoworkspace", "+0,address:" .. address) return "close" end },
    { name = "Close it", material = "close",
      run = function() h.dispatch("closewindow", "address:" .. address) return "close" end },
  }
  for _, button in ipairs(BUTTONS) do
    actions[#actions + 1] = { name = button[1], material = button[2], run = function()
      local menu = require("window_menu")
      menu.address:set(address)
      menu.press(button[3])
      return "close"
    end }
  end
  for id = 1, 5 do
    actions[#actions + 1] = { name = "Move to workspace " .. id, material = "drive_file_move", run = function()
      local menu = require("window_menu")
      menu.address:set(address)
      menu.press("left:ws" .. id)
      return "close"
    end }
  end
  return actions
end

local function toplevel_actions(w)
  local id = w.identifier
  local t = morf.toplevels
  return {
    { name = "Switch to it", material = "open_in_browser", run = function() t.activate(id) return "close" end },
    { name = "Close it", material = "close", run = function() t.close(id) return "close" end },
    { name = w.maximized and "Restore it" or "Maximize it", material = "crop_free",
      run = function() t.set_maximized(id, not w.maximized) return "close" end },
    { name = w.fullscreen and "Leave fullscreen" or "Fullscreen", material = "fullscreen",
      run = function() t.set_fullscreen(id, not w.fullscreen) return "close" end },
    { name = w.minimized and "Restore it" or "Minimize it", material = "minimize",
      run = function() t.set_minimized(id, not w.minimized) return "close" end },
  }
end

--- Every open window, as rows; `focused` is the row of the active one, when a
--- list knows it.
function M.window_rows()
  local out, focused = {}, nil
  local h = hyprland()
  if h then
    local active = h.state.active_window
    local model = h.state.clients
    for i = 1, model:len() do
      local c = model:get(i)
      if c.mapped ~= false and not c.hidden then
        local actions = hypr_actions(c, h)
        local r = rows.row {
          id = "window:" .. c.address, name = c.title ~= "" and c.title or c.class, tag = "Window",
          description = c.class .. "  ·  workspace " .. tostring(c.workspace), keywords = c.class,
          icon = c.class:lower(), actions = actions, run = actions[1].run,
        }
        out[#out + 1] = r
        if active and active.address == c.address then focused = r end
      end
    end
    return out, focused
  end
  if morf.toplevels and morf.toplevels.list then
    local ok, list = pcall(morf.toplevels.list)
    for _, w in ipairs(ok and type(list) == "table" and list or {}) do
      local actions = toplevel_actions(w)
      local r = rows.row {
        id = "window:" .. tostring(w.identifier), name = w.title ~= "" and w.title or w.app_id, tag = "Window",
        description = tostring(w.app_id), keywords = w.app_id, icon = tostring(w.app_id):lower(),
        actions = actions, run = actions[1].run,
      }
      out[#out + 1] = r
      if w.activated then focused = r end
    end
  end
  return out, focused
end

registry.mode { id = "windows", name = "Windows", material = "desktop_windows", shape = "square", prefix = "@",
  words = { "windows", "win" }, bare = false, hint = "find a window; Tab: move it, close it, float it",
  search = function(term)
    local list = M.window_rows()
    if #list == 0 then
      return { rows.note("windows", "No open windows", "Nothing to switch to", "desktop_windows") }
    end
    return rows.fuzzy(list, term, { "name", { "keywords", 0.6 } })
  end }

registry.mode { id = "window", name = "This window", material = "web_asset", shape = "square", words = { "window" },
  hint = "float, fullscreen, pin or move the window you are in",
  search = function(term)
    local _, focused = M.window_rows()
    if not focused then
      return { rows.note("window", "No window has the focus", "Open one and come back", "web_asset") }
    end
    local out = {}
    for i, action in ipairs(focused.actions) do
      out[i] = rows.row { id = "window-action:" .. i, name = action.name, description = focused.name,
        material = action.material, run = action.run }
    end
    return rows.fuzzy(out, term, "name")
  end }

registry.mode { id = "workspace", name = "Workspaces", material = "view_carousel", shape = "square", words = { "ws", "workspace" },
  hint = "ws 3  ·  go to a workspace", search = function(term)
    local services = require("services")
    local out = {}
    local wanted = tonumber(term)
    for id = 1, 10 do
      if not wanted or wanted == id then
        out[#out + 1] = rows.row { id = "workspace:" .. id, name = "Workspace " .. id, material = "view_carousel",
          description = services.workspace.occupied(id) and "Has windows" or "Empty",
          run = function() services.workspace.go(id) return "close" end }
      end
    end
    return out
  end }

return M
