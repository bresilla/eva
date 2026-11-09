-- Shared Settings readings, state and actions. No scene nodes or geometry.
local morf = require("morf")
local config = require("config")
local services = require("services")
local notifs = require("notifs")
local unicase = require("lib.util.unicase")
local M = {}
local function dry_run()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end
M.dry_run = dry_run

local function expand(words)
  local home = morf.fs.home()
  local stamp = morf.time.format("%Y%m%d_%H-%M-%S")
  local out = {}
  for i, w in ipairs(words) do
    out[i] = tostring(w):gsub("^~/", home .. "/"):gsub("%$HOME", home):gsub("%$DATE", stamp)
  end
  return out
end

--- Runs the command the settings keep under `utilities.commands.<name>`
--- (a list of words; `~/`, `$HOME` and `$DATE` expanded). Dry, it logs.
function M.run(name)
  local words = config.get("utilities.commands." .. name)
  if type(words) ~= "table" or #words == 0 then
    morf.log("info", "eva: utilities " .. name .. ": nothing to run")
    return false
  end
  local argv = expand(words)
  if dry_run() then
    morf.log("info", "eva: utilities " .. name .. " (dry run): " .. table.concat(argv, " "))
    return true
  end
  morf.process.run(argv, {}, function(result)
    if result and not result.ok then
      morf.log("warn", "eva: utilities " .. name .. " failed: " .. tostring(result.stderr or result.code))
    end
  end)
  return true
end

--- Whether the command kept under `name` has something to run: its first
--- word on PATH and, for `hyprctl`, a Hyprland to talk to.
function M.can_run(name)
  local words = config.get("utilities.commands." .. name)
  if type(words) ~= "table" or #words == 0 then return false end
  local program = tostring(words[1])
  if program == "hyprctl" and not (services.hyprland and services.hyprland.available()) then return false end
  return services.installed ~= nil and services.installed(program)
end

--- The quick settings' panel shut, as what a tile starts takes the screen.
function M.close_panel() require("pages").close("settings") end

--- A screenshot of a region, once the panel is out of the way.
function M.shoot()
  local capture = require("capture")
  M.close_panel()
  if capture.shoot then capture.shoot("region") end
end

--- A recording of the chosen target started, or the one running stopped.
function M.record()
  local capture = require("capture")
  M.close_panel()
  if capture.record then capture.record(capture.target and capture.target:get() or "screen") end
end

-- The session row: Lock acts at once, what ends the session must be held. One
-- list with the session menu's (shell/session_model.lua).
M.SESSION = {}
for _, action in ipairs(require("session_model").ACTIONS) do
  if action.quick then M.SESSION[#M.SESSION + 1] = action end
end

--- Whether the session action `id` can be done here.
function M.session_available(id) return require("session_model").available(id) end

--- Who is signed in: `label` (the name to show) and `face` (a picture, or nil).
function M.session_user()
  local ok, me = pcall(function() return require("lib.services.accounts").me() end)
  if ok and me then return me end
  return { label = morf.env("USER") or "user" }
end

--- Runs session action `id` (shell/session.lua's commands) as the panel shuts.
function M.session_run(id)
  M.close_panel()
  return require("session").run(id)
end

-- ------------------------------------------------------------ keep awake --

local idle = require("idle_model")
M.idle = idle
M.awake = idle.awake
local awake_since = require("themes.session").keep("eva.utilities.awake_since", "")

local function clock(at)
  if config.get("bar.clock.twelve_hour") then
    return (morf.time.format("%-I:%M %p", at):lower())
  end
  return (morf.time.format("%H:%M", at))
end

--- Keeps the session awake, for `seconds` if given.
function M.set_awake(on, seconds)
  if on and not M.awake:get() then awake_since:set(clock(morf.time.now())) end
  idle.set_awake(on, seconds)
end

--- Stays awake for `minutes`, or until told otherwise without them.
function M.awake_for(minutes) M.set_awake(true, minutes and minutes * 60 or nil) end

--- `eva awake`'s answer: whether it is on, and when it lets go, 0 for never.
function M.awake_state() return { on = M.awake:get(), ["until"] = idle.awake_until() } end

local local_state = {
  wifi = morf.signal("eva.utilities.wifi", false),
  bluetooth = morf.signal("eva.utilities.bluetooth", false),
  mic = morf.signal("eva.utilities.mic", true),
  gamemode = morf.signal("eva.utilities.gamemode", false),
}

--- The VPNs of `kind` that are up, by name: the mesh ones and the tunnel
--- apps by their links (no command run), and for tunnels NetworkManager's
--- own VPN and WireGuard profiles.
function M.vpn_names(kind)
  local names = {}
  local n = services.net
  local ok, vpns = pcall(require, "lib.services.vpns")
  if kind == "tunnel" and n and n.state.available then
    local model = n.state.vpn_connections
    for i = 1, model:len() do
      local v = model:get(i)
      if v.active and not (ok and vpns.is_mesh_link(v.id)) then names[#names + 1] = v.id end
    end
  end
  if ok then
    -- A link is read, not watched: re-read as the network changes.
    if n and n.state.available then n.state.devices:len() end
    for _, name in ipairs(vpns.links(kind)) do names[#names + 1] = name end
  end
  return names
end

--- Airplane mode on: what was on is remembered, then every radio is shut;
--- off, what was on comes back.
function M.set_airplane(on)
  local net, bt, modem = services.net, services.bt, services.modem
  local nfc = require("quick_hardware").nfc()
  if dry_run() then
    morf.log("info", "eva: airplane mode " .. (on and "on" or "off") .. " (dry run)")
    config.set("airplane.on", on == true)
    return
  end
  if on then
    config.set("airplane.was", {
      wifi = net ~= nil and net.state.available and net.state.wifi_enabled == true,
      bluetooth = bt ~= nil and bt.state.available and bt.state.powered == true,
      mobile = modem ~= nil and modem.state.data == true,
      nfc = nfc.present() and nfc.on(),
    })
    if net and net.state.available then pcall(net.set_wifi, false) pcall(net.set_wwan, false) end
    if bt and bt.state.available then pcall(bt.set_powered, false) end
    if nfc.present() then pcall(nfc.set, false) end
  else
    local was = config.get("airplane.was") or {}
    if net and net.state.available then
      if was.wifi then pcall(net.set_wifi, true) end
      if was.mobile then pcall(net.set_wwan, true) end
    end
    if bt and bt.state.available and was.bluetooth then pcall(bt.set_powered, true) end
    if was.nfc and nfc.present() then pcall(nfc.set, true) end
  end
  config.set("airplane.on", on == true)
end

--- The default audio input, or nil without one.
local function input()
  local ok, source = pcall(function() return morf.audio.available() and morf.audio.default_source() end)
  return ok and source or nil
end

M.TOGGLES = {
  {
    id = "wifi", icon = "wifi", name = "Wi-Fi", detail = "network",
    status = function()
      local n = services.net
      if n and n.state.available then
        local model = n.state.access_points
        for i = 1, model:len() do
          local ap = model:get(i)
          if ap.in_use then return ap.ssid or "Connected" end
        end
        if n.state.wifi_enabled then return "Not connected" end
      end
      return nil
    end,
    on = function()
      local n = services.net
      if n and n.state.available then return n.state.wifi_enabled == true end
      return local_state.wifi:get()
    end,
    set = function(now)
      local n = services.net
      if n and n.state.available and not dry_run() then pcall(n.set_wifi, now) return end
      if dry_run() then morf.log("info", "eva: wifi " .. (now and "on" or "off") .. " (dry run)") end
      local_state.wifi:set(now)
    end,
  },
  {
    id = "bluetooth", icon = "bluetooth", name = "Bluetooth", detail = "bluetooth",
    status = function()
      local b = services.bt
      if b and b.state.available then
        local model = b.state.devices
        for i = 1, model:len() do
          local d = model:get(i)
          if d.connected then return d.alias or d.name or "Connected" end
        end
      end
      return nil
    end,
    on = function()
      local b = services.bt
      if b and b.state.available then return b.state.powered == true end
      return local_state.bluetooth:get()
    end,
    set = function(now)
      local b = services.bt
      if b and b.state.available and not dry_run() then pcall(b.set_powered, now) return end
      if dry_run() then morf.log("info", "eva: bluetooth " .. (now and "on" or "off") .. " (dry run)") end
      local_state.bluetooth:set(now)
    end,
  },
  {
    -- Wired: the first wired port's state, a click connects or disconnects
    -- it; ">" lists every port. Without a port it is not offered.
    id = "wired", name = "Wired", detail = "wired",
    present = function()
      local n = services.net
      return n ~= nil and n.state.available == true and n.state.wired.device ~= ""
    end,
    icon = function()
      local n = services.net
      return (n and n.state.available and n.state.wired.carrier == false) and "settings_ethernet" or "lan"
    end,
    on = function()
      local n = services.net
      return n ~= nil and n.state.available and n.state.wired.connected == true
    end,
    set = function(now)
      local n = services.net
      if not (n and n.state.available) then return end
      local port = n.state.wired.device
      if port == "" then return end
      if dry_run() then morf.log("info", "eva: wired " .. tostring(now) .. " (dry run)") return end
      if now then pcall(n.connect_device, port) else pcall(n.disconnect, port) end
    end,
    status = function()
      local n = services.net
      if not (n and n.state.available) then return nil end
      local w = n.state.wired
      if w.device == "" then return "No port" end
      if w.connected then return w.ip4 ~= "" and w.ip4 or "Connected" end
      return w.carrier and "Disconnected" or "No cable"
    end,
  },
  {
    -- A phone's mobile data, offered once a modem is there; its page has the
    -- rest of it (roaming, network mode and 5G, the SIM).
    id = "mobile", name = "Mobile data", detail = "mobile",
    present = function()
      local m = services.modem
      return m ~= nil and m.state.available == true
    end,
    icon = function()
      local m = services.modem
      if not (m and m.state.available) then return "signal_cellular_nodata" end
      return m.state.data and "signal_cellular_alt" or "signal_cellular_off"
    end,
    on = function() local m = services.modem return m ~= nil and m.state.available and m.state.data end,
    set = function(now)
      local m = services.modem
      if not (m and m.state.available) then return end
      if dry_run() then morf.log("info", "eva: mobile data " .. tostring(now) .. " (dry run)") return end
      pcall(m.set_data, now)
    end,
    status = function()
      local m = services.modem
      if not (m and m.state.available) then return "No modem" end
      local s = m.state
      if s.locked then return "SIM locked" end
      if not s.data then return "Off" end
      return (s.technology ~= "" and (s.technology .. " · ") or "") .. (s.operator ~= "" and s.operator or "On")
        .. (s.roaming and " · Roaming" or "")
    end,
  },
  {
    -- Mesh VPNs: one's own machines (NetBird, Tailscale, ZeroTier).
    id = "mesh", icon = "hub", name = "Mesh", detail = "mesh",
    on = function() return #M.vpn_names("mesh") > 0 end,
    set = function() M.reach("mesh") end,
    status = function()
      local names = M.vpn_names("mesh")
      return #names == 0 and "Off" or table.concat(names, ", ")
    end,
  },
  {
    -- Tunnel VPNs: out to the internet through elsewhere (Mullvad, Proton).
    id = "tunnel", icon = "vpn_lock", name = "Tunnel", detail = "tunnel",
    on = function() return #M.vpn_names("tunnel") > 0 or services.tor ~= nil and services.tor.on() end,
    set = function() M.reach("tunnel") end,
    status = function()
      local names = M.vpn_names("tunnel")
      if services.tor and services.tor.on() then names[#names+1]="Tor" end
      return #names == 0 and "Off" or table.concat(names, ", ")
    end,
  },
  {
    -- Tor: the system's tor service, started and stopped -- never enabled,
    -- so it is off again after every boot.
    id = "tor", icon = "travel_explore", name = "Tor", detail = "tunnel",
    present = function() return services.tor ~= nil end,
    on = function() return services.tor ~= nil and services.tor.on() end,
    set = function(now)
      if dry_run() then morf.log("info", "eva: tor " .. tostring(now) .. " (dry run)") return end
      if services.tor then services.tor.set(now) end
    end,
    status = function()
      local t = services.tor
      if not t then return "Not installed" end
      local p = t.phase:get()
      if p == "starting" then return "Starting…" end
      if p == "stopping" then return "Stopping…" end
      if p == "failed" then return "Could not start" end
      if p == "on" then return ("SOCKS %d"):format(t.socks) end
      return "Off"
    end,
  },
  {
    -- Airplane mode: every radio off at once -- Wi-Fi, Bluetooth, mobile
    -- data -- and back as they were.
    id = "airplane", icon = "flight", name = "Airplane mode",
    on = function() return config.get("airplane.on") == true end,
    set = function(now) M.set_airplane(now) end,
    status = function() return config.get("airplane.on") == true and "On" or "Off" end,
  },
  {
    id = "sound", name = "Sound", detail = "sound",
    icon = function()
      local ok, sink = pcall(function() return morf.audio.available() and morf.audio.default_sink() end)
      return (ok and sink and sink.muted) and "volume_off" or "volume_up"
    end,
    on = function()
      local ok, sink = pcall(function() return morf.audio.available() and morf.audio.default_sink() end)
      if ok and sink then return not sink.muted end
      return true
    end,
    set = function(now)
      local ok, sink = pcall(function() return morf.audio.available() and morf.audio.default_sink() end)
      if not (ok and sink) then return end
      if dry_run() then morf.log("info", "eva: sound " .. (now and "on" or "off") .. " (dry run)") return end
      morf.audio.set_mute(sink.id, not now)
    end,
    status = function()
      local ok, sink = pcall(function() return morf.audio.available() and morf.audio.default_sink() end)
      if ok and sink and sink.volume then return ("%d%%"):format(math.floor(sink.volume * 100 + 0.5)) end
      return nil
    end,
  },
  {
    -- The default input's mute, or the configured commands without one.
    id = "mic", name = "Microphone", detail = "microphone",
    icon = function()
      local source = input()
      if source then return source.muted and "mic_off" or "mic" end
      return local_state.mic:get() and "mic" or "mic_off"
    end,
    on = function()
      local source = input()
      if source then return not source.muted end
      return local_state.mic:get()
    end,
    set = function(now)
      local source = input()
      if source then
        if dry_run() then morf.log("info", "eva: microphone " .. (now and "on" or "off") .. " (dry run)") return end
        morf.audio.set_mute(source.id, not now)
        return
      end
      M.run(now and "mic_on" or "mic_off")
      local_state.mic:set(now)
    end,
    status = function()
      local source = input()
      if not source then return nil end
      return source.muted and "Muted" or ("%d%%"):format(math.floor((source.volume or 0) * 100 + 0.5))
    end,
  },
  {
    -- The battery: its charge, and a ">" to the Power page (profiles,
    -- health, how it charges). A tap opens the page too.
    id = "battery", name = "Battery", detail = "power", icon = "power",
    glyph = function() return require("battery_status_model").read() end,
    on = function() return require("battery_status_model").read().charging end,
    set = function() M.reach("power") end,
    status = function()
      local battery = require("battery_status_model")
      return battery.describe(battery.read())
    end,
  },
  {
    id = "awake", icon = "coffee", name = "Keep awake",
    on = function() return M.awake:get() end,
    set = function(now) M.set_awake(now) end,
    status = function()
      if not M.awake:get() then return "Off" end
      local ends = idle.awake_until()
      if ends > 0 then return "Until " .. clock(ends) end
      return "Since " .. awake_since:get()
    end,
  },
  {
    -- How it calls for attention: sound, vibrate (on a phone) or silent.
    id = "ringer", name = "Ring mode",
    present = function() return services.ringer ~= nil end,
    icon = function()
      local r = services.ringer
      return require("lib.shell.audio.ringer").icon(r and r.state.mode or "sound")
    end,
    on = function() local r = services.ringer return r ~= nil and r.state.mode ~= "sound" end,
    set = function()
      if dry_run() then morf.log("info", "eva: ring mode (dry run)") return end
      local r = services.ringer if r then r.next() end
    end,
    status = function()
      local r = services.ringer
      local mode = r and r.state.mode or "sound"
      return unicase.capitalise(mode)
    end,
  },
  {
    -- The bar: up or down, and a ">" to where it goes.
    id = "bar", icon = "toolbar", name = "Bar", detail = "bar",
    on = function() return require("bar").on() end,
    set = function(now) require("bar").set_on(now) end,
    status = function()
      local b = require("bar")
      if not b.on() then return "Off" end
      local side = b.side()
      return unicase.capitalise(side)
    end,
  },
  {
    id = "dnd", icon = "notifications_off", name = "Do not disturb",
    on = function() return notifs.dnd:get() end,
    set = function(now) notifs.dnd:set(now) end,
  },
}

--- The page the Settings window shows ("" for none); the panel's own pages
--- are `M.in_panel`'s.
M.detail = require("themes.session").keep("eva.settings.detail", "")
--- Which app's rules, and which Focus mode, their pages show.
M.rules_app = require("themes.session").keep("eva.settings.rules_app", "")
M.focus_mode = require("themes.session").keep("eva.settings.focus_mode", "dnd")
if M.detail:get()=="tor" then M.detail:set("tunnel") end

-- The catalogue: every tile a machine could show. Which are shown, in what
-- order and at what size is the board's (`M.tiles`).
-- Retain the raw controls for the detail page, before overview read caching.
M.CONTROLS={}
do
  for _, t in ipairs(require("quick_tiles").list(M, local_state.gamemode)) do M.TOGGLES[#M.TOGGLES + 1] = t end
  for _, t in ipairs(M.TOGGLES) do
    M.CONTROLS[t.id]=t
    local set=t.set
    if set then
      t.set=function(...)
        require("haptics").fire("toggle")
        return set(...)
      end
    end
  end
  -- Focus is one entry point; each setting remains independent inside it.
  local focus=require("focus_model")
  M.TOGGLES[#M.TOGGLES + 1] = {id="focus",name="Focus",detail="focus",
    icon=function()
      if notifs.dnd:get() then return "notifications_off" end
      local mode=focus.active()
      if mode then return mode.icon end
      if focus.quiet() then return "notifications_off" end
      if M.awake:get() then return "coffee" end
      return "tune"
    end,
    on=function() return M.awake:get() or notifs.dnd:get() or focus.quiet() or M.CONTROLS.ringer.on() end,
    set=function() M.reach("focus") end,
    status=function()
      local names={}
      if M.awake:get() then names[#names+1]="Awake" end
      if M.CONTROLS.ringer.on() then names[#names+1]=M.CONTROLS.ringer.status() end
      if notifs.dnd:get() then names[#names+1]="DND"
      elseif focus.quiet() then names[#names+1]=focus.status() end
      return #names>0 and table.concat(names," · ") or "Sound · Normal sleep"
    end}
  -- One press on the mode last used, for the board that wants it.
  M.TOGGLES[#M.TOGGLES + 1] = {id="focus-mode",name="Focus mode",detail="focus",
    icon=function()
      local mode=focus.active() or focus.mode(config.get("focus.last"))
      return mode and mode.icon or "do_not_disturb_on"
    end,
    on=function() return focus.active()~=nil end,
    set=function() focus.toggle() end,
    status=function()
      if focus.active() then return focus.status() end
      local mode=focus.mode(config.get("focus.last"))
      return mode and mode.name or "Off"
    end}
  -- The shell itself: the bar, and how its panels open.
  M.TOGGLES[#M.TOGGLES + 1] = { id = "eva", name = "Desktop", detail = "eva", icon = "dashboard_customize",
    on = function() return false end,
    set = function() M.request("eva") end,
    status = function()
      local b = require("bar")
      return (b.on() and "Bar " .. b.side() or "No bar") .. " · " .. (M.edge_hover() and "Hover" or "Click")
    end }
end

--- Whether the panels open as the pointer reaches their edge; off, a press
--- at the edge opens them.
local EDGES = { "dashboard.hover", "sidebar.hover", "leftbar.hover", "bottom.hover" }
function M.edge_hover()
  for _, key in ipairs(EDGES) do if config.get(key) == false then return false end end
  return true
end
function M.set_edge_hover(on)
  for _, key in ipairs(EDGES) do config.set(key, on == true) end
end

--- How things move: how much they bounce, and whether they travel at all.
M.MOTIONS = { { "calm", "spa", "Calm" }, { "balanced", "balance", "Balanced" }, { "playful", "celebration", "Playful" } }
function M.motion_style() return config.get("appearance.motion") or "balanced" end
function M.set_motion_style(style) config.set("appearance.motion", style) end
function M.reduce_motion() return config.get("appearance.reduce_motion") == true end
function M.set_reduce_motion(on) config.set("appearance.reduce_motion", on == true) end

--- The window's book (shell/window_host.lua): its ids' prefix and name.
M.name, M.title = "settings", "Settings"
--- Whether the Settings window is open over everything, its pages on show.
M.opened = require("themes.session").keep("eva.settings.opened", false)
--- Whether the quick controls are on show: the panel holding Settings, open on it.
M.quick = morf.signal("eva.settings.quick", false)
M.displayed = require("themes.session").keep("eva.settings.displayed", "")

-- Every page is the registry's; a route's parent is what Back returns to.
M.registry=require("settings_registry")
M.DETAILS={}
for index,page in ipairs(M.registry.PAGES) do
  M.DETAILS[index]={key=page.key,name=page.name,parent=page.parent}
end
local aliases={tor="tunnel",osk="keyboard"}
for from,to in pairs(M.registry.ALIASES or {}) do aliases[from]=to end
M.navigation=require("lib.shell.settings.pages").new(M.DETAILS,M.detail,aliases)
M.navigation.on_back=function() require("themes.layouts.page").hold_place() end
-- How far a page has been pulled back under a finger, in pixels.
M.peek=morf.signal("eva.settings.peek",0)
function M.breadcrumb() return M.registry.trail(M.navigation.path(M.detail:get())) end
--- The quick controls' own pages, opened in their panel (shell/quick_details.lua).
M.in_panel=require("quick_details").new(M)
function M.overview() return M.quick:get() and M.in_panel.displayed:get()=="" end
-- What the tiles read rather than watch is looked at again as they come on show.
morf.effect("eva.settings.look",function()
  if M.overview() then require("quick_hardware").refresh() end
end)
function M.present(key) if key==M.detail:get() then M.displayed:set(key) end end
--- The Settings window open, on the page it shows or on All settings; the
--- panel holding the quick controls steps aside.
function M.open()
  if M.detail:get()=="" then M.navigation.request(M.registry.HOME) end
  if M.opened:get() then return end
  require("pages").put_away("settings")
  if package.loaded.window_host then package.loaded.window_host.only(M) end
  M.opened:set(true)
end
--- The Settings window shut.
function M.close() M.opened:set(false) end
--- Opens page `key` in the Settings window, All settings without one; `from`
--- is the page Back returns to, for a page without a parent of its own.
function M.request(key,from)
  if key==nil or key=="" then key=M.registry.HOME end
  if not M.navigation.request(key,from) then return false end
  M.open()
  return true
end
--- Opens All settings.
function M.open_home() return M.request(M.registry.HOME) end
--- Opens page `key` where it lives: a quick control's in its panel, else the window.
function M.reach(key,from)
  if M.in_panel.holds(key) then return M.in_panel.open(key) end
  return M.request(key,from)
end
--- A function: whether the Settings window has page `key` on show.
function M.showing(key) return require("presentation").active("settings."..key) end
--- One page back: its parent, or the page it was opened from, else All
--- settings; from All settings the window shuts.
function M.back()
  local key=M.detail:get()
  if key=="" or key==M.registry.HOME then M.close() return true end
  M.navigation.back()
  if M.detail:get()=="" then M.navigation.request(M.registry.HOME) end
  return true
end
-- The pages only some machines have, and what says so.
local PRESENT={
  mobile=function() return M.CONTROLS.mobile.present() end,
  wired=function() return M.CONTROLS.wired.present() end,
  hotspot=function() return M.CONTROLS.hotspot.present() end,
  nightlight=function() return M.CONTROLS.nightlight.present() end,
}
local function no_phone() return not require("responsive").phone() end
--- The pages only some forms have.
local FORMS={
  ["windows/rules"]=no_phone,["windows/rule"]=no_phone,["windows/layouts"]=no_phone,["input/remap"]=no_phone,
  ["bar/tray"]=function() return require("responsive").form()=="desk" end,
}
--- Whether page `key` is one this form has.
function M.page_fits(key)
  local check=FORMS[key]
  return check==nil or check()==true
end
--- Whether page `key` is one this machine can show.
function M.page_present(key)
  local check=PRESENT[key]
  return M.page_fits(key) and (check==nil or check()==true)
end
function M.capture()
  require("pages").close("settings")
  require("capture").drawer.set(true)
end
-- Retain the last displayed values while hidden, without refreshing sources.
local function reading(fn, initial, active)
  local cached=initial
  return function()
    if (active or M.overview)() then cached=fn() end
    return cached
  end
end
-- Each tile reads through a cache; `M.CONTROLS` keeps the live controls.
for index, control in ipairs(M.TOGGLES) do
  local toggle={}
  for key, value in pairs(control) do toggle[key]=value end
  toggle.on=reading(control.on,false)
  if control.status then toggle.status=reading(control.status,nil) end
  if type(control.icon)=="function" then toggle.icon=reading(control.icon,"") end
  if control.present then toggle.present=reading(control.present,false) end
  if control.glyph then toggle.glyph=reading(control.glyph,require("battery_status_model").NONE) end
  M.TOGGLES[index]=toggle
end
M.tiles=require("tiles_model").new(M.TOGGLES,function() return require("responsive").form_factor() end)
M.panels=require("panels_board").new(function() return M.opened:get() and M.detail:get()=="panels" end)
M.focus={}
local function focus_active()
  return M.opened:get() and M.displayed:get()=="focus" or M.quick:get() and M.in_panel.displayed:get()=="focus"
end
for _,id in ipairs {"awake","ringer","dnd"} do
  local control=M.CONTROLS[id]
  M.focus[#M.focus+1]={id=id,name=control.name,set=control.set,
    icon=type(control.icon)=="function" and reading(control.icon,"",focus_active) or control.icon,
    on=reading(control.on,false,focus_active),
    status=control.status and reading(control.status,id=="ringer" and "Sound" or "Off",focus_active) or nil}
end
M.levels={}
for _, kind in ipairs {"volume","brightness"} do
  M.levels[kind]=reading(function() return (require("osd")[kind]()) end,0)
  M.levels[kind.."_icon"]=reading(function() return require("osd")[kind.."_icon"]() end,
    kind=="volume" and "volume_mute" or "brightness_low")
  M.levels["set_"..kind]=function(value)
    if dry_run() then
      morf.log("info","eva: "..kind.." "..tostring(value).." (dry run)")
      return
    end
    require("osd")["set_"..kind](value)
  end
end
-- A screen without a backlight to read has no brightness to set.
M.levels.brightness_known=reading(function() return select(2,require("osd").brightness())~=false end,true)
morf.effect("eva.settings.presentation",function()
  local open,key=M.opened:get(),M.displayed:get()
  local presentation=require("presentation")
  presentation.set("settings.overview",M.overview())
  presentation.set("settings.detail",open and key~="")
  for _, detail in ipairs(M.DETAILS) do presentation.set("settings."..detail.key,open and key==detail.key) end
end)
require("settings_search").register(M)
return M
