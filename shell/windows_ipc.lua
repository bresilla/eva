-- The window features' verbs, kept in `ipc` as the shell's others are.
local morf = require("morf")
local M = {}

--- A window for an answer: what a test or a script reads.
local function brief(c)
  return { address = c.address, class = c.class, title = c.title, workspace = c.workspace, x = c.x, y = c.y,
    width = c.width, height = c.height, floating = c.floating, pinned = c.pinned, fullscreen = c.fullscreen,
    opacity = c.opacity, toplevel = c.toplevel, focus_history = c.focus_history }
end

function M.register(ipc)
  local windows = require("windows_model")
  local hyprland = require("services").hyprland
  -- `windows`: the list as the shell has it. `windows wire`: what was sent
  -- to the stand-in. `windows real`: what morf.toplevels says.
  ipc.windows = function(how)
    if how == "wire" then return hyprland.wire or {} end
    if how == "sent" then return windows.sent end
    if how == "real" then return morf.toplevels and morf.toplevels.list() or {} end
    if how == "shots" then
      local shots, out = require("window_shots"), { refused = require("window_shots").refused }
      for _, c in ipairs(windows.list()) do out[c.address] = shots.source(c.address) end
      return out
    end
    local out = {}
    for _, c in ipairs(windows.recent()) do out[#out + 1] = brief(c) end
    return out
  end
  if hyprland.stand_in then
    ipc.stand_in_cursor = function(x, y) hyprland.set_cursor(tonumber(x), tonumber(y)) end
  end
  local here = require("services").here
  local overview = require("overview")
  -- `overview [open|close|toggle|state]`, or `overview app`: only the focused
  -- application's windows, wherever they are.
  ipc.overview = function(how, amount)
    how = how or "toggle"
    if how == "close" then overview.close() end
    -- As a finger holds it, part of the way out: `overview pull 0.4`.
    if how == "pull" then
      if here() then overview.follow(tonumber(amount) or 1) end
      return overview.pull:get()
    end
    if how == "app" then
      if not here() then return end
      local c = windows.active()
      overview.open()
      return overview.search(c and c.class or "")
    end
    if how == "close" or how == "state" then
      if here() then return overview.opened:get() end
      return
    end
    if how ~= "open" and how ~= "toggle" then error("`" .. tostring(how) .. "`: open, close, toggle or state") end
    if not here() then overview.close() return end
    if how == "open" then return overview.open() end
    return overview.toggle()
  end
  ipc.overview_menu = function(index)
    local row = overview.cards:get(tonumber(index) or 1)
    if row then overview.menu_for:set(row.address) end
  end
  local switcher = require("window_switcher")
  -- `switcher next|prev|same [free]`: a press of the key, Alt held unless
  -- `free` says it is not. `commit`, `cancel`, `state`.
  ipc.switcher = function(how, free)
    how = how or "next"
    if not here() then switcher.cancel() return end
    local hold = free ~= "free"
    if how == "next" then return switcher.step(1, hold) end
    if how == "prev" then return switcher.step(-1, hold) end
    if how == "same" then return switcher.same(hold) end
    if how == "commit" then return switcher.commit() end
    if how == "cancel" then switcher.cancel() return false end
    if how == "state" then
      local c = switcher.chosen()
      return { open = switcher.opened:get(), shown = switcher.shown:get(), title = c and c.title or "" }
    end
    error("`" .. tostring(how) .. "`: next, prev, same, commit, cancel or state")
  end
  ipc.switcher_scope = function(scope)
    if scope then require("config").set("windows.switcher.scope", scope) end
    return switcher.scope()
  end
  local snap = require("snap")
  -- `snap CELL`: the focused window into a cell (left, right, top, bottom,
  -- top_left, ..., full, center). `snap layout KEY`: the workspace into a
  -- layout. `snap picker`, and `snap drag` and `snap drop` as the compositor's
  -- drag begins and ends.
  ipc.snap = function(how, key)
    if how == "drag" then return snap.drag() end
    if how == "drop" then return snap.drop() end
    if how == "state" then
      return { dragging = snap.dragging:get(), zone = snap.zone:get(), assisting = snap.assisting:get() }
    end
    if not here() then return end
    if how == "picker" then snap.toggle_pick() return snap.picking:get() end
    if how == "layout" then return snap.tile(key) end
    if require("snap_model").CELLS[how or ""] then return snap.snap(how) end
    error("`" .. tostring(how) .. "`: a cell, layout KEY, picker, drag or drop")
  end
  -- `dock [on|off|auto]`: asks for it on a desk. `dock pin ID` pins an
  -- application or lets it go, `dock state` says what there is.
  ipc.dock = function(how, id)
    local dock = require("dock")
    local config = require("config")
    if how == "on" or how == "off" or how == "auto" then config.set("dock.enabled", how)
    elseif how == "hide" then config.set("dock.autohide", id)
    elseif how == "pin" then return dock.toggle_pin(id)
    elseif how == "peek" then dock.entered() end
    return { mode = dock.mode(), shown = dock.shown(), rows = dock.rows:len(), overflow = dock.overflow:get() }
  end
  ipc.dock_clear = function(buttons)
    local config = require("config")
    config.set("dock.pins", {})
    config.set("dock.buttons", buttons == "buttons")
  end
  -- `dock_magnify [AT]`: the swell as if the pointer were AT along the row.
  ipc.dock_magnify = function(at) require("dock").pointer:set(tonumber(at) or -1) end
  ipc.dock_menu = function(index)
    local dock = require("dock")
    local row = dock.rows:get(tonumber(index) or 1)
    if row then dock.open_menu(row.key) end
  end
  ipc.dock_launch = function(key) return require("dock").launch(key) end
  ipc.dock_reserve = function() return require("dock").reserve() end
  ipc.dock_order = function()
    local out, dock = {}, require("dock")
    for i = 1, dock.rows:len() do out[i] = dock.rows:get(i).key end
    return out
  end
  ipc.dock_reorder = function(from, to) return require("dock").reorder(tonumber(from), tonumber(to)) end
  -- `rules [list]`, `rules add JSON`, `rules set JSON` (it has its id), `rules
  -- remove ID`, `rules on ID` and `rules off ID`, `rules from ADDRESS` (a draft
  -- from a running window), `rules dim on|off [STRENGTH]`.
  ipc.rules = function(how, value, strength)
    local rules = require("window_rules_model")
    if how == nil or how == "list" then return rules.list() end
    if how == "dim" then
      local config = require("config")
      if tonumber(strength) then config.set("windows.dim_strength", tonumber(strength)) end
      config.set("windows.dim_inactive", value == "on")
      return true
    end
    if how == "from" then return rules.from_window(value) end
    if not require("services").here() then return end
    if how == "add" or how == "set" then
      local id, why = rules.save(morf.json.decode(value))
      return id or why
    end
    if how == "remove" then rules.remove(value) return true end
    if how == "on" or how == "off" then rules.set_enabled(value, how == "on") return true end
    error("`" .. tostring(how) .. "`: list, add, set, remove, on, off or from")
  end
  local spaces = require("workspaces_model")
  local function shown_workspace() return windows.int(require("services").workspace.active()) end
  -- `workspace_empty`: the first workspace with nothing on it.
  ipc.workspace_empty = function()
    return windows.send('hl.dispatch(hl.dsp.focus({ workspace = "empty" }))', "workspace", "empty")
  end
  -- `workspace_name [NAME [ID]]`: names a workspace, this one by default;
  -- with no name it says what it is called.
  ipc.workspace_name = function(name, id)
    id = tonumber(id) or shown_workspace()
    if name == nil then return spaces.label(id) end
    return spaces.rename(id, name)
  end
  -- `workspace_layout [LAYOUT [ID]]`: dwindle, master, scrolling or monocle;
  -- `next` steps through them; with nothing it says which.
  ipc.workspace_layout = function(layout, id)
    id = tonumber(id) or shown_workspace()
    if layout == nil then return spaces.layout(id) end
    if layout == "next" then return spaces.cycle_layout(id) end
    return spaces.set_layout(id, layout)
  end
  -- `layouts [list]`, `layouts save NAME`, `layouts restore NAME`, `layouts
  -- remove NAME`, `layouts login [NAME]`, `layouts report`.
  ipc.layouts = function(how, name)
    local layouts = require("layouts_model")
    if how == nil or how == "list" then return layouts.list() end
    if how == "report" then return layouts.report:get() end
    if not here() then return end
    if how == "save" then layouts.save(name) return true end
    if how == "restore" then return layouts.restore(name) end
    if how == "remove" then layouts.remove(name) return true end
    if how == "login" then layouts.set_login(name) return true end
    error("`" .. tostring(how) .. "`: list, save, restore, remove, login or report")
  end
  -- `workspace_move ID SCREEN`, `workspace_swap A B` (windows, name and layout
  -- trade places), `workspace_reorder FROM TO`, `workspace_screens A B` (two
  -- screens trade what they show).
  ipc.workspace_move = function(id, monitor) if here() then return spaces.to_monitor(tonumber(id), monitor) end end
  ipc.workspace_swap = function(first, second) if here() then return spaces.swap(tonumber(first), tonumber(second)) end end
  ipc.workspace_reorder = function(from, to) if here() then return spaces.reorder(tonumber(from), tonumber(to)) end end
  ipc.workspace_screens = function(first, second) if here() then return spaces.swap_screens(first, second) end end
  -- `scratchpad NAME`: shows or hides it. `scratchpad list`. `scratchpad send
  -- NAME`: the focused window goes there.
  ipc.scratchpad = function(how, name)
    if how == "list" then return spaces.scratchpads() end
    if how == "send" then
      local c = windows.active()
      return c and spaces.to_scratch(c.address, name) or false
    end
    if how == nil then error("`scratchpad NAME`, `list` or `send NAME`") end
    return spaces.toggle_scratch(how)
  end
  -- `pip [toggle|close]`, `float`, `split`: the focused window.
  local modes = require("window_modes")
  ipc.pip = function(how)
    if how == "close" then return modes.close_pip() end
    if how == "state" then return modes.pip:get() end
    local c = windows.active()
    return modes.toggle_pip(c and c.address or nil)
  end
  ipc.float = function()
    local c = windows.active()
    return c and modes.toggle_float(c.address) or false
  end
  ipc.split = function()
    local c = windows.active()
    return c and modes.split_with(c.address) or false
  end
  -- `show_desktop`: the windows on this workspace aside, or back.
  ipc.show_desktop = function() return windows.show_desktop(shown_workspace()) end
  -- `lock_now`: the session's lock command.
  ipc.lock_now = function() return require("session").run("lock") end
  local corners = require("hot_corners")
  corners.attach(ipc)
  -- `corner NAME [ACTION [GUARD]]`: what a hot corner does; a guard of `?`
  -- asks which key it wants.
  ipc.corner = function(name, action, guard)
    if guard == "?" then return corners.guard(name) end
    if action then corners.set_action(name, action) end
    if guard then corners.set_guard(name, guard) end
    return corners.action(name)
  end
  ipc.settings_detail = function() return require("settings_model").detail:get() end
  ipc.split_nudge = function(delta) return modes.nudge(tonumber(delta) or 0) end
  ipc.split_pair = function()
    local a, b = modes.pair()
    return a and { a.title, b.title } or {}
  end
  -- `keep_above`, `opacity [VALUE]`: the focused window.
  ipc.keep_above = function()
    local c = windows.active()
    return c and windows.keep_above(c.address) or false
  end
  ipc.opacity = function(value)
    local c = windows.active()
    if not c then return false end
    if value then return windows.set_opacity(c.address, tonumber(value) or 1) end
    return windows.next_opacity(c.address)
  end
  -- `kill_aim X Y`, `pip_controls`: what a pointer or a tap does, for a
  -- session with neither.
  ipc.kill_aim = function(x, y) require("kill_mode").aim(tonumber(x), tonumber(y)) end
  ipc.pip_controls = function() require("window_modes").toggle_controls() end
  -- `kill_mode`: press a window to force quit it.
  ipc.kill_mode = function(how)
    local kill = require("kill_mode")
    if how == "stop" then kill.stop() return false end
    if not here() then return end
    return kill.start()
  end
end

return M
