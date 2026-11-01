-- eva: a clean-room reimplementation of caelestia-dots/shell's look
-- and behaviour on morf, written from watching the original run (its
-- screenshots and films in a sandbox), not from its source. MIT.
--
-- The signature: a thin frame round the whole screen in the surface colour,
-- with rounded inner corners; the workspaces as pills down its left side; and drawers that
-- grow out of the frame with concave fillets -- the launcher at the bottom,
-- the dashboard at the top.
--
--     morf shell/init.lua
--     morf ipc call launcher          -- toggle; or `launcher open`, `launcher close`
--     morf ipc call dashboard         -- the same; `session` too
--     morf ipc call close             -- every drawer
--
-- The frame, the rail and the drawers are one fullscreen layer surface; only
-- what can be clicked takes the pointer (the engine derives the input
-- region from the MouseAreas), so the desk under the opening stays usable.
-- The wallpaper, when the shell paints it (`wallpaper.draw`), is a
-- background layer of its own.

local morf = require("morf")
local ui = require("morf.ui")

-- Before anything asks for the compositor.
require("windows_stand_in").install()

local config = require("config")
local theme = require("theme")
local drawer = require("drawer")
local wallpaper = require("wallpaper")
local rail = require("rail")
local responsive = require("responsive")

-- Qt mixes translucent colours in sRGB; so does the original.
morf.surface.blend = "srgb"
morf.surface.namespace = "eva-drawers"
morf.surface.anchors = { top = true, bottom = true, left = true, right = true }
morf.surface.width = 0
morf.surface.height = 0
morf.surface.layer = "top"
morf.surface.keyboard_focus = "none"
-- The whole output, whatever other surfaces reserve (our own reservers
-- below among them).
morf.surface.exclusive_zone = -1
-- Windows keep inside the frame.

-- Where the tools of apps/ find these settings.
if config.path then
  local state = morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")
  morf.fs.write(state .. "/eva/settings-path", config.path, { atomic = true, parents = true })
end

require("displays_hotplug").start()
for _, name in ipairs { "input_model", "access_model", "keys_model", "window_rules_model", "layouts_model", "audio_rules",
  "lid_watch", "privacy_page_model", "drive_watch" } do
  require(name).start()
end

-- ------------------------------------------------------------------ colour --

-- Two palettes: `theme.color`, the Material scheme, built from
-- `theme.source` -- "lule" (the colour tool's accent: lule, pywal; see
-- terminal_colors.lua), "wallpaper", a colour, or "auto" (lule when it has
-- set anything, else the wallpaper) -- and `theme.lule`, the tool's own
-- colours as they are, for whatever wants them.
local terminal_colors = require("terminal_colors")
morf.effect("eva.lule", function() theme.apply_lule(terminal_colors.current:get()) end)
morf.effect("eva.scheme", function()
  theme.track(terminal_colors.current:get(), wallpaper.current:get())
end)
require("appearance_model").start()

-- ------------------------------------------------------------------ scale --

-- The scale slider (quick settings): everything drawn bigger or smaller,
-- from -1 (half) through 0 (the compositor's own scale) to 1 (twice). The
-- windows follow at once; once the slider rests, the shell is built again
-- in place (no teardown: what is open stays open) so every layout -- a
-- panel's four fifths, a phone's column -- is worked out for the new size.
local function zoom()
  -- (A stand-in configuration, a test's, may have no `get`.)
  local v = config.get and tonumber(config.get("appearance.zoom")) or 0
  return math.max(-1, math.min(1, v))
end
local zoom_first, zoom_settle = true, nil
morf.effect("eva.scale", function()
  local v = zoom()
  if require("themes.ui_scale").compositor then require("themes.ui_scale").apply()
  elseif morf.window.density then morf.window.density(v ~= 0 and { zoom = 2 ^ v } or nil) end
  if zoom_first then zoom_first = false return end
  if zoom_settle then zoom_settle:cancel() end
  zoom_settle = morf.time.timer(300, function()
    zoom_settle = nil
    require("themes.session").hold()
    morf.reload()
  end, false)
end)

-- How things move is read as the theme is built: a change builds the shell
-- again in place, as the scale does.
local motion_first, motion_settle = true, nil
morf.effect("eva.motion", function()
  local style = config.get and { config.get("appearance.motion"), config.get("appearance.reduce_motion"),
    config.get("appearance.density"), config.get("appearance.corners"), config.get("appearance.speed"),
    config.get("appearance.deform"), config.get("island.enabled"), require("themes.motion_style").reduced(),
    config.get("appearance.text_scale"), config.get("appearance.high_contrast"), config.get("appearance.font_file"),
    config.get("polkit.agent") }
  if motion_first or not style then motion_first = false return end
  if motion_settle then motion_settle:cancel() end
  motion_settle = morf.time.timer(120, function()
    motion_settle = nil
    require("themes.session").hold()
    morf.reload()
  end, false)
end)

-- --------------------------------------------------------------- rotation --

-- A screen turned between portrait and landscape, or a keyboard docked: this
-- output's shell is built again in place for the other layout, and what is
-- open stays open.
local built_layout = require("responsive").layout()
require("responsive").watch_input()
morf.effect("eva.rotation", function()
  morf.window.screens_revision()
  local layout = require("responsive").layout()
  if layout ~= built_layout then
    built_layout = layout
    require("themes.session").hold()
    morf.reload { output = true }
  end
end)
-- Auto-rotation while the rotation is not locked, a night light left on, and
-- the battery's charge limit.
require("auto_rotate").start()
require("quick_hardware").nightlight()
require("quick_hardware").start()
require("charge_limit_model").start()
do
  local alarm = require("services").alarm
  alarm.load()
  morf.time.timer(3000, alarm.sync, false)
  -- What the launcher sets rings the one way anything rings.
  local ok, timers = pcall(require, "timers_model")
  if ok then timers.use(alarm) end
end

-- ---------------------------------------------------------------- drawers --

local launcher = require("launcher")
require("providers")
require("launcher_modes.shell").sync_scripts()
require("launcher_plugins").load()
require("text_expansion").start()
require("timers_model")
local dashboard = require("dashboard")
local session = require("session")
local polkit = require("polkit")
local keyring = require("keyring")
local authsteps = require("authsteps")
local headphones = require("headphones")
local osd = require("osd")
local notifs = require("notifs")
local sidebar = require("sidebar")
local leftbar = require("leftbar")
local capture = require("capture")
local bottom = require("bottom")
local pages = require("pages")
require("planner")
-- The capture tool's panel and this drawer occupy the same edge; only one can
-- be open, and a capture takes nothing of the drawer with it. (Where the panels
-- are sheets the bottom edge is the dashboard's, and capture's alone.)
if drawer.bottom then
  local own = bottom.drawer
  function own.set(on)
    if on and #bottom.panel.tabs == 0 then return end
    if on then capture.drawer.set(false) end
    own.open:set(on and true or false)
  end
  function own.toggle() own.set(not own.open:get()) end
  morf.effect("eva.capture.bottom", function()
    if capture.panel:get() or capture.phase:get() == "countdown" then own.open:set(false) end
  end)
end
local keyboard = require("keyboard")
local bar = require("bar")
local window_menu = require("window_menu")
require("calendar_reminders").start()
require("panel_room").watch()
require("phone")
local overview = require("overview")
local window_switcher = require("window_switcher")
local snap = require("snap")
local kill_mode = require("kill_mode")
local dock = require("dock")

-- One policy for the shared surface. Closing a launcher or auth dialog
-- must not disable typing in the task editor that is still open.
morf.effect("eva.keyboard.focus", function()
  local exclusive = launcher.drawer.open:get() or session.drawer.open:get() or window_menu.opened:get()
    or overview.opened:get() or window_switcher.opened:get() or snap.picking:get() or snap.assisting:get()
    or kill_mode.active:get()
    or (polkit.drawer.open:get() and polkit.pending:get()) or keyring.drawer.open:get()
    or notifs.replying:get() ~= false
  -- Typed into on a click: the Tasks and Calendar pages, the terminal, Lule's
  -- page, wherever their panels hold them.
  local settings_open = pages.on_show("settings")
  local shown = require("utilities").displayed:get()
  local editor_open = pages.typing()
    or (dashboard.drawer.open:get() and dashboard.tab:get() == dashboard.TERMINAL_TAB)
    or (settings_open and (shown == "theme/lule" or shown == "theme/desktop" or shown == "theme/look"
      or shown == "theme" or shown == "hotspot" or shown == "panels" or shown == "bar"
      or shown == "notifications" or shown == "focus/mode"
      or pages.typed_route(shown) or require("utilities").tiles.editing:get()))
  morf.surface.keyboard_focus = exclusive and "exclusive" or editor_open and "on_demand" or "none"
end)

-- ------------------------------------------------------------------- frame --

-- Frame geometry and composition belong to the selected visual theme.
local rail_node=rail.build()
local levels=require("levels")
local levels_node=levels.build()
-- Where the panels are sheets the levels show only while one changes.
if require("responsive").sheets() then
  levels_node.visible=function() return levels.shown:get()~="" end
end
local overlays={
  -- The desk dims under the session menu.
  session.dim(),
  -- A notification lights the screen's edge.
  notifs.overlay(),
  -- A press on the desk shuts what is open: each drawer's close policy
  -- (shell/drawer.lua), not catchers here.
}
local triggers=require("responsive").touch() and {} or require("responsive").sheets() and {
  -- A narrow window: the top edge brings quick settings down, the bottom one
  -- the dashboard up; the side edges are left to the workspace gestures, and
  -- the planner and the assistant wait for theirs. Under a finger the edges
  -- are the gestures' alone.
  require("hover").edge {
    name = "sidebar", drawer = sidebar.drawer, edge = "top",
    length = function() local _, _, w = bar.desk() return w - 2 * (theme.BORDER + theme.ROUNDING) end,
    setting = "sidebar.hover",
  },
  dashboard.edge_trigger(),
} or {
  dashboard.edge_trigger(),
  -- The bottom edge opens the tabbed assistant workspace.
  require("hover").edge {
    name = "bottom", drawer = bottom.drawer, edge = "bottom",
    length = bottom.width, setting = "bottom.hover",
    enabled = function()
      local phase = capture.phase:get()
      return not capture.drawer.open:get() and (phase == "ready" or phase == "error")
    end,
  },
  -- Near the right edge, anywhere down it, the sidebar opens; near the left
  -- edge above or below the rail, the left panel. The rail's own stretch is
  -- for the workspaces.
  require("hover").edge {
    name = "sidebar", drawer = sidebar.drawer, edge = "right",
    from = function() return theme.BORDER + theme.ROUNDING end,
    length = function()
      local _, _, _, h = bar.desk()
      return h - 2 * (theme.BORDER + theme.ROUNDING)
    end,
    setting = "sidebar.hover",
  },
  require("hover").edge {
    name = "leftbar", drawer = leftbar.drawer, edge = "left",
    from = function() return theme.BORDER + theme.ROUNDING end,
    length = function()
      local _, _, _, h = bar.desk()
      local from = rail.span()
      return (from or h - theme.BORDER - theme.ROUNDING) - theme.BORDER - theme.ROUNDING
    end,
    setting = "leftbar.hover",
  },
  require("hover").edge {
    name = "leftbar-below", drawer = leftbar.drawer, edge = "left",
    from = function()
      local _, to = rail.span()
      return to or 0
    end,
    length = function()
      local _, _, _, h = bar.desk()
      local _, to = rail.span()
      return to and h - theme.BORDER - theme.ROUNDING - to or 0
    end,
    setting = "leftbar.hover",
  },
}
-- The rail's targets, over the panels.
if rail.hits then triggers[#triggers+1]=rail.hits end
local frame_view=require("themes").view("frame")
local frame_root=frame_view.build {desk=bar.desk,bar=bar.build(),bar_edge=bar.side,bar_reach=bar.THICK,drawers=drawer.all,
  rail={node=rail_node,shape=rail.shape},levels={node=levels_node,shape=levels.shape,panels=levels.panels},
  island=require("island").build(bar.desk),overlays=overlays,triggers=triggers}
require("phone_gestures").attach(frame_root)
require("prek_controls").attach(frame_root)
require("lock_bridge").start()
require("idle_warning").attach(frame_root)
do
  local idle = require("idle_model")
  idle.start()
  idle.watch_sleep()
  idle.watch_lid()
  idle.lock_at_start()
end
-- The shell's window, to a screen reader.
frame_root.accessible_name = "Eva"
-- The focused window's menu, over it: in the screen's own coordinates.
ui.reparent(dock.node,frame_root)
ui.reparent(require("window_modes").node,frame_root)
ui.reparent(window_menu.node,frame_root)
ui.reparent(overview.node,frame_root)
ui.reparent(window_switcher.node,frame_root)
ui.reparent(snap.node,frame_root)
ui.reparent(kill_mode.node,frame_root)
ui.reparent(require("hot_corners").build(),frame_root)
-- Authentication can interrupt editing without ending up behind its overlay.
morf.effect("eva.capture.authentication",function()
  if (polkit.pending:get() or keyring.request:get()) and capture.editor.running() then capture.cancel() end
end)

-- Windows keep inside the opening: the frame, and the bar when it is up.
morf.effect("eva.bar.reserve", function()
  local insets = frame_view.insets(bar.insets())
  insets[dock.edge()] = (insets[dock.edge()] or 0) + dock.reserve()
  morf.surface.reserve = insets
end)

wallpaper.open_layer()
do
  local pictures = require("wallpaper_model")
  pictures.start()
  pictures.watch_hook()
end
require("desktop").start()
require("standby").start()

-- -------------------------------------------------------------------- ipc --

-- Every screen runs the shell and hears every verb. What opens appears on
-- the focused screen only (`services.here()`); a close shuts it wherever it
-- is. A screen that does nothing answers nothing, so the reply is the one
-- that acted.
-- Every verb is kept here as well as given to `morf.ipc` (which only
-- takes them), so the shell's keyboard shortcuts can call the same ones.
local ipc = setmetatable({}, { __newindex = function(t, k, v) rawset(t, k, v) morf.ipc[k] = v end })
local here = require("services").here
local function verb(d)
  return function(how)
    how = how or "toggle"
    if how == "close" then
      d.set(false)
      if here() then return d.is_open() end
      return
    end
    if how ~= "open" and how ~= "toggle" and how ~= "state" then
      error("`" .. tostring(how) .. "`: open, close, toggle or state")
    end
    if not here() then
      -- Opened elsewhere now: shut here, so one screen has it at a time.
      if how ~= "state" then d.set(false) end
      return
    end
    if how == "open" then d.set(true)
    elseif how == "toggle" then d.toggle() end
    return d.is_open()
  end
end

-- `launcher [how]`; `launcher apps` or `launcher web`: the launcher on one of its
-- menus (menus.lua); `launcher mode WORD`: on a mode; `launcher query TEXT`: with
-- that typed; `launcher selection`: with the selection typed; `launcher dmenu IN OUT
-- [PROMPT]`: the lines of file IN to choose from, the choice written to file OUT.
ipc.launcher = function(how, ...)
  local rest = { ... }
  if how == "apps" or how == "web" then
    if not here() then return nil end
    require("menus").open(how)
    launcher.drawer.set(true)
    return true
  end
  if how == "mode" or how == "query" then
    if not here() then return nil end
    local text = rest[1] or ""
    if how == "mode" then
      local mode = require("lib.shell.launcher.registry").by_word(text)
      if not mode then error("No such mode: " .. text) end
      text = require("lib.shell.launcher.registry").entry(mode)
    end
    launcher.open_on(text)
    return true
  end
  if how == "selection" then
    if not here() then return nil end
    morf.process.run({ "wl-paste", "--primary", "--no-newline" }, { timeout_ms = 1000 }, function(result)
      launcher.open_on((tostring(result and result.stdout or ""):gsub("%s+", " ")))
    end)
    return true
  end
  if how == "dmenu" then
    if not here() then return nil end
    local input, output = rest[1], rest[2]
    local lines = {}
    for line in tostring(morf.fs.read(input) or ""):gmatch("[^\n]+") do lines[#lines + 1] = line end
    require("menus").dmenu(lines, rest[3], function(line) morf.fs.write(output, line and (line .. "\n") or "") end)
    launcher.open_on("")
    return true
  end
  return verb(launcher.drawer)(how)
end
-- `dashboard [how [TAB]]`: TAB is one of its tabs by name, such as battery.
ipc.dashboard = function(how, tab)
  if tab and here() then require("dashboard_state").show(tab) end
  return verb(dashboard.drawer)(how)
end
-- Builds the shell and the capture tool again from their files, in place.
ipc.reload = function()
  if here() then capture.ask("reload") end
  morf.reload()
  return true
end
-- The frame, the rail and the bar come in again: a lock lifting.
-- What the lock asked to open once the password was right: an id, never a command.
ipc.lock_shortcut = function(id) return require("lock_bridge").open(id) end
-- `idle warn`: the warning before the lock, to look at; `idle stop` ends it.
ipc.idle = function(how)
  local idle = require("idle_model")
  if how == "warn" then idle.warning_ms:set(8000) idle.phase:set("warning")
  elseif how == "stop" then idle.phase:set("")
  elseif how == "status" then
    local holding, stages = {}, {}
    for _, row in ipairs(idle.inhibitors()) do holding[#holding + 1] = row.who end
    for _, item in ipairs(idle.plan()) do stages[#stages + 1] = item.stage .. ":" .. item.seconds end
    return { phase = idle.phase:get(), holding = holding, stages = stages }
  end
  return idle.phase:get()
end
ipc.reveal = function()
  require("lock_bridge").seen()
  return require("themes.reveal").replay()
end
-- The scale, as the slider sets it: `scale -0.25` (smaller), `scale 0`
-- (the compositor's), `scale 0.5` (bigger), or nothing to ask.
ipc.scale = function(value)
  if value ~= nil then config.set("appearance.zoom", math.max(-1, math.min(1, tonumber(value) or 0))) end
  return config.get("appearance.zoom")
end
-- The screen as the shell sees it: its size in the shell's pixels, the
-- scale it is drawn at, and what the compositor and the panel say.
ipc.screen = function()
  local s = morf.screens[1] or {}
  return { width = s.width, height = s.height, scale = s.density_scale,
    logical_width = s.logical_width, pixel_width = s.pixel_width }
end
ipc["dashboard-history"] = function(output)
  local name = (morf.screens[1] or {}).name
  if output and output ~= name then return end
  local status = require("dashboard_state").history_status()
  status.output = name
  return status
end
ipc.session = verb(session.drawer)
-- `window_menu [open|close|toggle|state]`: the menu of the focused window,
-- over it on the screen it is on. Opening answers true, false when no window
-- has the focus, or nothing while it asks the compositor.
ipc.window_menu = function(how)
  how = how or "toggle"
  local mine = window_menu.here()
  if how == "close" then window_menu.close() end
  if how == "close" or how == "state" then
    if mine then return window_menu.opened:get() end
    return
  end
  if how ~= "open" and how ~= "toggle" then error("`" .. tostring(how) .. "`: open, close, toggle or state") end
  if not mine then window_menu.close() return end
  if how == "open" then return window_menu.open() end
  return window_menu.toggle()
end
-- `polkit` says whether this screen is the agent and what it is asking;
-- `polkit demo` opens the dialog on a made-up request (any password but
-- "wrong" is taken, and it goes nowhere). `view`, `answer` and `cancel`
-- are the screens talking to each other (polkit.lua).
ipc.polkit = function(how, ...)
  if how == "demo" then
    if not here() then return nil end
    polkit.demo()
    return true
  end
  if how == "cancel" and select("#", ...) == 0 then polkit.cancel() return true end
  if how == "view" or how == "answer" or how == "cancel" or how == "closed" then
    polkit.message(how, ...)
    return nil
  end
  -- The state, from the agent's screen.
  if not polkit.registered:get() then return nil end
  local r = polkit.request:get()
  return { agent = true, open = polkit.drawer.open:get(), phase = polkit.phase:get(), action = r and r.action or "" }
end

-- `auth-step STEP [SERVICE]`: the markers in a PAM stack (helpers/pam)
-- saying where sudo has got to: face, finger, password, ok.
ipc["auth-step"] = function(step, service) return authsteps.steps.mark(step, service) end

-- A page by its key, in whichever panel holds it on this form: opening
-- selects it there; a toggle over another page of that panel turns to it, and
-- shuts it only when it is the one on show. False where no panel holds it.
local function page_verb(key)
  return function(how)
    how = how or "open"
    local panel = pages.holder(key)
    if not panel then return false end
    local showing = panel.panel.showing(key)
    if how == "close" then
      if showing then return verb(panel.drawer)("close") end
      return false
    end
    if how == "state" then
      local open = verb(panel.drawer)("state")
      if open == nil then return nil end
      return open and showing
    end
    if how == "toggle" and panel.drawer.is_open() and not showing then how = "open" end
    if here() then panel.panel.select(key) end
    return verb(panel.drawer)(how)
  end
end
-- A panel by the name it has on a desk. Where the panels are sheets, one with
-- no page named lands on the first page of its own that the sheet holds.
local function panel_verb(name, edge)
  return function(how, tab)
    if not tab and name ~= "sidebar" and responsive.sheets() then
      for _, key in ipairs(config.get("panels." .. edge) or {}) do
        if pages.panel_name(key) then tab = key break end
      end
    end
    if tab then
      if here() and not pages.all[tab] then error("`" .. tostring(tab) .. "`: no such page") end
      return page_verb(tab)(how or "toggle")
    end
    return verb(require(name).drawer)(how)
  end
end

-- `sidebar`, `leftbar` or `bottom [how [PAGE]]`: the panel, on PAGE, which
-- lands wherever it is held. `utilities` is Settings; `settings PAGE` opens
-- one of its pages (network, bluetooth, sound). `tasks`, `calendar`,
-- `assistant`, `drop` and `notifications` are those pages.
ipc.sidebar = panel_verb("sidebar", "right")
ipc.leftbar = panel_verb("leftbar", "left")
ipc.bottom = panel_verb("bottom", "bottom")
ipc.utilities = function(how) return page_verb("settings")(how or "toggle") end
for _, key in ipairs { "tasks", "calendar", "assistant", "drop" } do
  ipc[key] = page_verb(key)
end
ipc.settings = function(page)
  if not here() then return nil end
  if not require("utilities").request(page or "") then error("No such Settings page: " .. tostring(page)) end
  pages.open("settings")
  return page or ""
end
-- `power-key`: the power button, bound here while Settings chose its action.
ipc["power-key"] = function() require("lid_watch").power_key() return true end
-- `settings-search`: every page and setting, for the launcher and scripts.
ipc["settings-search"] = function(query)
  if query and query ~= "" then return require("settings_registry").search(query) end
  return require("settings_registry").list()
end
-- `tablet on` or `tablet off`: the hinge moved, as Hyprland's switch binds say;
-- the kernel is asked before it counts. `tablet pin on|off` holds the posture
-- whatever the switch says, `tablet auto` lets it go, `tablet state` reads it.
ipc.tablet = function(how, value)
  local posture = require("models.posture")
  if how == "on" or how == "off" then posture.report(how == "on")
  elseif how == "pin" and (value == "on" or value == "off") then posture.pin(value == "on")
  elseif how == "auto" then posture.pin(nil)
  elseif how ~= nil and how ~= "state" then error("`" .. tostring(how) .. "`: on, off, pin on|off, auto or state") end
  return posture.state()
end
-- `quick edit` or `quick done`: the quick settings' tiles being arranged.
ipc.quick = function(how)
  if how ~= "edit" and how ~= "done" then error("`" .. tostring(how) .. "`: edit or done") end
  if not here() then return nil end
  require("utilities").request("")
  pages.open("settings")
  require("utilities").tiles.editing:set(how == "edit")
  return how == "edit"
end
-- `bar modules`: what stands on the bar, zone by zone, and what could. `bar add
-- ID [ZONE]`, `bar remove ID`, `bar move ID INDEX [ZONE]`, `bar small ID`, `bar
-- reset`, `bar show on|off|auto`, `bar side EDGE` and `bar live toggle|next`.
-- `bar output NAME on|off|follow`, `own|shared` or `add ID [ZONE]`: one screen's.
ipc.bar = function(how, id, a, b)
  local model = bar.model
  local board = model.board
  if how == "output" then
    local store = require("bar_store")
    if a == "on" or a == "off" then store.set_on(id, a) return true end
    if a == "follow" then store.set_on(id, "") return true end
    if a == "own" or a == "shared" then store.set_own(id, a == "own", require("responsive").form()) return true end
    if a == "add" and store.output() == id then return board.add(b) end
    return nil
  end
  if how == "show" then config.set("edgebar.enabled", id) return bar.on() end
  if how == "side" then bar.set_side(id) return bar.side() end
  if how == "modules" then
    local out = {}
    for _, zone in ipairs(board.zones) do
      out[zone] = {}
      for i, item in ipairs(board.shown(zone)) do out[zone][i] = item.id end
    end
    out.spare = {}
    for i, item in ipairs(board.spare()) do out.spare[i] = item.id end
    return out
  end
  if how == "add" then return board.add(id, a) end
  if how == "remove" then board.hide(id) return true end
  if how == "move" then return board.move(id, tonumber(a) or 1, b) end
  if how == "small" then board.toggle_size(id) return board.small(id) end
  if how == "reset" then board.reset() return true end
  if how == "live" then
    if id == "next" then model.live.cycle() else model.live.toggle() end
    return model.live.expanded:get()
  end
  error("`" .. tostring(how) .. "`: modules, add, remove, move, small, reset or live")
end
-- PrintScreen opens eva-screenshot's panel. The verbs of capture are the tool's;
-- the focused screen's shell passes each one on, and the tool answers by what it
-- publishes (shell/capture.lua).
ipc.capture = function(how)
  how=how or "toggle"
  if how=="menu" then how="open" end
  if how=="state" then return here() and capture.drawer.is_open() or nil end
  if how~="open" and how~="close" and how~="toggle" then
    error("`" .. tostring(how) .. "`: open, close, toggle or state")
  end
  if not here() then return end
  capture.ask("capture",how)
  return how=="open" or (how=="toggle" and not capture.drawer.is_open())
end
-- `ask QUESTION`: the assistant opens and answers it, as the launcher's `ai`.
ipc.ask = function(question)
  if here() then require("assistant_model").ask(question) end
  return true
end
-- `page KEY`: the page `KEY` (shell/pages.lua), wherever a panel holds it;
-- `assistant-settings` is that page's settings.
ipc.page = function(key)
  if not here() then return end
  if key == "assistant-settings" then return pages.settings("assistant") end
  return pages.reach(key)
end
-- `drop-target ID`: Drop opens on somebody's machine (`bob:laptop`, `orin`).
ipc["drop-target"] = function(id)
  if not here() then return end
  pages.reach("drop")
  require("drop_model").select(id)
  return true
end
-- `note NAME`: the note called NAME, opened or made.
ipc.note = function(name)
  if not here() then return end
  pages.reach("notes")
  require("notes_model").create(name)
  return true
end
-- `keyboard [how]`: the on-screen keyboard, for a key to bind. `how` is
-- open, close, toggle or state, or a mode to open it in: full, dev,
-- letters, numbers, phone or pattern. `keyboard VERB VALUE` is
-- shell/keyboard.lua's control: purpose, language, pane, tray, hand, floating,
-- split, private.
do
  local open_close = verb {set=keyboard.set,toggle=keyboard.toggle,is_open=keyboard.drawer.is_open}
  local MODES = { full = true, dev = true, letters = true, numbers = true, phone = true, pattern = true }
  ipc.keyboard = function(how, value)
    if MODES[how] then
      if not here() then return nil end
      keyboard.show(how)
      return true
    end
    if value ~= nil then
      if not here() then return nil end
      local done = keyboard.control(how, value)
      if done ~= nil then return done end
    end
    return open_close(how)
  end
end
ipc["capture-claim"]=function(name)
  if here() then capture.ask("capture-claim",name) end
end
ipc["capture-editor"] = function(action,...)
  if not here() then return end
  if action=="cancel" then return capture.cancel() or true end
  if action then capture.ask("capture-editor",action,...) return true end
  return {open=capture.editor.active:get(),phase=capture.phase:get()}
end
ipc.screenshot = function(what,how)
  if not here() then return nil end
  return capture.shoot(what,how=="quick")
end
ipc.record = function(what)
  if not here() then return nil end
  return capture.record(what)
end
-- `nightlight on|off|toggle|status|temperature|follow [VALUE]`: the tile's own
-- device, for eva-nightlight.
ipc.nightlight = function(how, value)
  if not here() then return nil end
  local text, why = require("quick_hardware").nightlight().command(how, value)
  if not text then error(why) end
  return text
end
-- `awake on|off|toggle|state [MINUTES]`: the quick settings' keep awake, the
-- shell's own inhibitor, for eva-awake.
ipc.awake = function(how, minutes)
  if not here() then return nil end
  local settings = require("settings_model")
  if how == "toggle" then how = settings.awake:get() and "off" or "on" end
  if how == "on" then settings.awake_for(tonumber(minutes))
  elseif how == "off" then settings.set_awake(false)
  elseif how ~= "state" and how ~= nil then error("`" .. tostring(how) .. "`: on, off, toggle or state") end
  return settings.awake_state()
end
ipc.workspace = function(n)
  if not here() then return nil end
  require("services").workspace.go(n)
  return require("services").workspace.active()
end
-- `lule open|close|toggle`: the studio. With no argument, keep the
-- existing terminal/accent diagnostics used by colour-tool integrations.
ipc.lule = function(how)
  if how then
    if here() and how ~= "close" then require("utilities").detail:set("theme/lule") end
    return page_verb("settings")(how)
  end
  local tty = require("terminal_colors").tty
  return tty and tty.path or "", theme.lule.accent:hex(), theme.color.primary:hex()
end
-- `wallpaper [get|state|set PATH [OUTPUT]|next|previous|random|transition KIND|draw on|off]`.
ipc.wallpaper = function(how, ...) return require("wallpaper_model").verb(how, ...) end
-- `desktop [state|edit|done|add ID|hide ID|size ID]`: the widgets on the desktop.
ipc.desktop = function(how, id) return require("desktop").verb(how, id) end
-- `island [on|off|toggle|next|state]`.
ipc.island = function(how) return require("island").verb(how) end
-- `standby [on [when-charging] [night]|off|toggle|state|clock|photos|widgets|world|alarm]`.
ipc.standby = function(how, ...) return require("standby_model").verb(how, ...) end
-- `osd [KIND]`: shows that display (the volume without one). False when its
-- service is absent or its setting has it off.
ipc.osd = function(kind)
  if not here() then return nil end
  return osd.flash(kind)
end
-- `notify SUMMARY [BODY [critical|normal|low [APP [ICON [IMAGE]]]]]` raises a
-- notification of the shell's own, as the reference's toaster does.
ipc.notify = function(summary, body, urgency, app, icon, image)
  if morf.window.primary and not morf.window.primary() then return nil end
  return notifs.push { summary = summary, body = body, app = app, icon = icon, image = image,
    urgency = urgency == "critical" and 2 or urgency == "low" and 0 or 1 }
end
-- `notifications [open|close|toggle|state]`: the page. `notifications VERB ...`:
-- status; list; invoke [ID [KEY]]; reply ID TEXT; dismiss [ID]; clear; clear-app
-- KEY; clear-silent; undo; snooze ID PRESET; mute KEY [SECONDS]; unmute KEY.
-- Without an ID, the newest.
local notifications_page = page_verb("notifications")
ipc.notifications = function(how, a, b)
  if how == nil or how == "open" or how == "close" or how == "toggle" or how == "state" then
    return notifications_page(how)
  end
  if morf.window.primary and not morf.window.primary() then return nil end
  local function newest()
    local list = notifs.list:get()
    return list[#list] and list[#list].id or nil
  end
  if how == "status" then return notifs.status() end
  if how == "list" then return notifs.history:get() end
  if how == "invoke" then
    local id = tonumber(a) or newest()
    return id ~= nil and notifs.invoke(id, b or "default") or false
  end
  if how == "reply" then return notifs.reply(tonumber(a), b) end
  if how == "dismiss" then
    local id = tonumber(a) or newest()
    if id then notifs.dismiss(id) end
    return id ~= nil
  end
  if how == "clear" then return notifs.clear() end
  if how == "clear-app" then return notifs.clear_app(a) end
  if how == "clear-silent" then return notifs.clear_silent() end
  if how == "undo" then return notifs.restore() end
  if how == "snooze" then return notifs.snooze(tonumber(a) or newest(), b or 900) end
  if how == "mute" then notifs.mute_app(a, tonumber(b) or 0) return true end
  if how == "unmute" then require("notification_rules").unmute(a) return true end
  error("`" .. tostring(how) .. "`: no such verb")
end
-- `focus VERB ...`: status; state, whether it is quiet; list; on [MODE [SECONDS]],
-- the last mode without one; off; toggle.
ipc.focus = function(how, mode, seconds)
  local focus = require("focus_model")
  how = how or "status"
  if how == "status" then
    return { active = focus.active_id(), status = focus.status(), quiet = focus.quiet(), ends = focus.ends() }
  end
  if how == "state" then return focus.quiet() end
  if how == "list" then
    local names = {}
    for i, row in ipairs(focus.modes()) do names[i] = row.id end
    return names
  end
  if morf.window.primary and not morf.window.primary() then return nil end
  if how == "on" then return focus.start(mode or config.get("focus.last"), { seconds = tonumber(seconds) or 0 }) end
  if how == "off" then return focus.stop() end
  if how == "toggle" then
    focus.toggle(tonumber(mode))
    return focus.quiet()
  end
  error("`" .. tostring(how) .. "`: no such verb")
end
ipc.close = function()
  capture.cancel()
  capture.drawer.set(false)
  drawer.close_all()
  return true
end
-- `phone VERB ARGS`: calls and what stands in for a modem (shell/phone.lua).
ipc.phone = function(...) return require("phone").ipc(...) end
-- `drawers` lists the open drawers; `drawers toggle NAME` (open, close)
-- acts on one by name, as the reference's IPC does.
ipc.drawers = function(how, name)
  if how ~= nil and how ~= "list" then
    if name == "capture" then return ipc.capture(how) end
    local d = drawer[name or ""]
    -- A desk panel's name reaches the sheet where the panels are sheets.
    if not d and (name == "leftbar" or name == "bottom") then d = sidebar.drawer end
    if not d then error("`" .. tostring(name) .. "`: no such drawer") end
    return verb(d)(how)
  end
  local open = {}
  for _, d in ipairs(drawer.all) do
    if d.is_open() then open[#open + 1] = d.name end
  end
  if capture.drawer.is_open() then open[#open + 1] = "capture" end
  return table.concat(open, " ")
end

-- Metadata only: never expose keyring answers through IPC.
ipc.keyring = function(how,mode)
  if here() then
    if how=="demo" then
      if mode and mode~="unlock" and mode~="new" and mode~="confirm" then
        error("Use `keyring demo [unlock|new|confirm]`.")
      end
      return keyring.demo(mode=="confirm" and "confirm" or "password",mode=="new")
    elseif how then error("Use `keyring` or `keyring demo [unlock|new|confirm]`.") end
    return {agent=keyring.registered:get(),open=keyring.drawer.open:get()}
  end
end


require("themes.switcher").start(function()
  if polkit.request:get() or keyring.request:get() or authsteps.steps.state.step ~= "idle" then
    return "Finish the authentication request before changing theme."
  end
  local phase = capture.phase:get()
  if phase ~= "ready" and phase ~= "error" then return "Finish the capture before changing theme." end
  if require("lule_studio").busy:get() then return "Wait for Lule to finish applying." end
  if require("planner").client.busy:get() then return "Wait for the task update to finish." end
end)
-- A theme this engine cannot show was set aside at start: say so.
if require("themes").refused then
  notifs.push { summary = "Theme unavailable", body = require("themes").refused .. "; using Material.",
    urgency = 1, app = "eva" }
end

require("windows_ipc").register(ipc)

-- The verbs above as keys, wherever the shell has the keyboard.
frame_root.shortcuts = require("shortcuts").table(ipc)
-- Settings, back open after a change that moved it to another panel.
require("utilities").panels.settle()
