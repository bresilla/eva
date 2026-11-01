-- Every module the bar can hold, as data. No nodes.
--
-- A module is `{ id, name, icon, kind, tier, present, active, text, gauge, tone,
-- tooltip, press, menu, wheel }`. `icon`, `text`, `gauge` (0..1), `tone` ("warn",
-- "alert", "ok", "extra") and `tooltip` are read in bindings. `present()` says the
-- machine can have it at all, `active()` whether it shows now. `press()` is what
-- a press does and `menu()` the items of a right press, each `{ label, icon,
-- on_clicked }`; the shell adds its own to them. `wheel(steps)` turns it. `tier`
-- is when it folds (bar_layout.lua). `kind` picks its drawing, a readout without.
local morf = require("morf")
local poll = require("lib.util.poll")
local clock = require("clock_format")

local M = {}

local function services() return require("services") end
local function sysinfo() return require("lib.services.sysinfo") end
local function osd() return require("osd") end
local function config() return require("config") end
local function hardware(name) return require("quick_hardware")[name]() end

local function dry()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= false and v ~= "" and v ~= "0"
end

--- Runs `argv` for a module, or says so in a dry run.
function M.run(argv)
  if type(argv) ~= "table" or #argv == 0 then return false end
  if dry() then
    morf.log("info", "eva: bar runs " .. table.concat(argv, " ") .. " (dry run)")
    return true
  end
  morf.process.run(argv, {}, function() end)
  return true
end

local function installed(name)
  local s = services()
  return s.installed ~= nil and s.installed(name) == true
end

local function percent(value) return ("%d%%"):format(math.floor((value or 0) + 0.5)) end

local function size_text(bytes)
  local text, unit = require("performance_model").bytes(bytes or 0)
  return text .. " " .. unit
end

-- A rate, short enough for a bar.
local function rate_text(bytes)
  local text, unit = require("performance_model").bytes(bytes or 0)
  return text .. unit:sub(1, 1)
end

local function ratio(value, whole)
  if not whole or whole <= 0 then return 0 end
  return math.max(0, math.min(1, (value or 0) / whole))
end

-- A level as a tone: past `warn`, past `alert`.
local function level(value, warn, alert)
  if value == nil then return nil end
  if value >= alert then return "alert" end
  if value >= warn then return "warn" end
  return nil
end

local sources = {}

-- What a command prints, parsed, while something reads it.
local function command(name, argv, every, parse, initial)
  if sources[name] then return sources[name] end
  sources[name] = poll.source { name = "eva.bar." .. name, interval = every, initial = initial,
    sample = function(done)
      morf.process.run(argv, { timeout_ms = 8000 }, function(result)
        if result and result.ok then done(parse(result.stdout or "")) else done(initial) end
      end)
    end }
  return sources[name]
end

local function lines_of(text)
  local count = 0
  for line in tostring(text):gmatch("[^\n]+") do
    if line:match("%S") then count = count + 1 end
  end
  return count
end

-- The dashboard, on a tab.
local function dashboard_tab(key)
  return function()
    local tabs = require("dashboard_model").tabs
    for index, tab in ipairs(tabs) do
      if tab.key == key then require("dashboard_model").select(index) end
    end
    require("dashboard").drawer.set(true)
  end
end

-- The settings, on a page.
local function settings_page(page)
  return function()
    require("utilities").request(page)
    local sidebar = require("sidebar")
    sidebar.select("settings")
    sidebar.drawer.set(true)
  end
end

local function item(label, icon, on_clicked) return { label = label, icon = icon, on_clicked = on_clicked } end

-- ---------------------------------------------------------------- readers --

local function primary_card()
  local cards = sysinfo().gpu().cards or {}
  return cards[1]
end

local function own_interface()
  local net = sysinfo().network()
  for _, row in ipairs(net.interfaces or {}) do
    if row.name == net.default then return row end
  end
  return { name = net.default or "", rx_rate = net.rx_rate or 0, tx_rate = net.tx_rate or 0 }
end

local function system_drive()
  local drives = sysinfo().drives().drives or {}
  for _, row in ipairs(drives) do if row.system then return row end end
  return drives[1] or {}
end

local function disk()
  local mount = config().get("bar.disk.mount")
  for _, row in ipairs(sysinfo().disks() or {}) do
    if row.mount == mount then return row end
  end
  return nil
end

--- Bluetooth and wireless batteries, each once: `{ name, level, kind }`.
function M.batteries()
  local s, out, seen = services(), {}, {}
  local function add(name, value, kind)
    name = tostring(name or "")
    if name == "" or value == nil or value < 0 or seen[name:lower()] then return end
    seen[name:lower()] = true
    out[#out + 1] = { name = name, level = math.floor(value + 0.5), kind = kind or "other" }
  end
  local bt = s.bt
  if bt and bt.state.available and bt.state.devices then
    local rows = bt.state.devices
    for i = 1, rows:len() do
      local row = rows:get(i)
      if row.connected and row.has_battery then add(row.alias or row.name, row.battery, row.icon) end
    end
  end
  local power = s.upower
  local rows = power and power.state and power.state.available and power.state.peripherals or nil
  for i = 1, rows and rows.len and rows:len() or 0 do
    local row = rows:get(i)
    add(row.model ~= "" and row.model or row.vendor, row.percentage, row.kind)
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- The screen's own workspaces, in decades, as the rail numbers them.
local STRIDE = 10

--- The workspaces a bar shows: `{ id, active, occupied }`, its decade's first
--- `bar.workspaces.shown`, and any past them that are in use.
function M.workspaces()
  local workspace = services().workspace
  local active = workspace.active()
  local base = active - ((active - 1) % STRIDE)
  local shown = math.max(1, math.min(STRIDE, tonumber(config().get("bar.workspaces.shown")) or 5))
  for id = base + STRIDE - 1, base + shown, -1 do
    if workspace.occupied(id) or id == active then shown = id - base + 1 break end
  end
  local out = {}
  for i = 1, shown do
    local id = base + i - 1
    out[i] = { id = id, active = id == active, occupied = workspace.occupied(id) == true }
  end
  return out
end

-- ------------------------------------------------------------- the modules --

--- The catalogue, for the bar model `bar`.
function M.list(bar)
  local list = {}
  local function add(spec)
    spec.tier = spec.tier or 1
    list[#list + 1] = spec
  end

  -- The bar's own parts.
  add { id = "logo", name = "Launcher", icon = "apps", kind = "logo", tier = 3,
    tooltip = function() return "Launcher" end, press = bar.toggle_launcher }
  add { id = "workspaces", name = "Workspaces", icon = "view_week", kind = "workspaces", tier = 3,
    tooltip = function() return "Workspace " .. tostring(services().workspace.active()) end,
    wheel = function(steps) bar.wheel_workspaces(steps) end,
    present = function()
      local workspace = services().workspace
      return workspace ~= nil and workspace.occupied ~= nil
    end,
    menu = function() return { item("Next workspace", "chevron_right", function() bar.step_workspace(1) end),
      item("Previous workspace", "chevron_left", function() bar.step_workspace(-1) end) } end }
  add { id = "windows", name = "Windows", icon = "select_window", kind = "windows", tier = 0 }
  add { id = "clock", name = "Clock", icon = "schedule", kind = "clock", tier = 0, press = bar.press_clock,
    tooltip = function() return morf.time.format("%A, %-d %B %Y") end,
    menu = function() return { item("Calendar", "calendar_month", function() bar.open_calendar() end),
      item("Clock settings", "tune", settings_page("bar")) } end }
  add { id = "status", name = "Status", icon = "signal_cellular_alt", kind = "status", tier = 0, press = bar.open_settings,
    menu = function() return { item("Quick settings", "tune", bar.open_settings),
      item("Network", "wifi", settings_page("network")), item("Sound", "volume_up", settings_page("sound")) } end }
  add { id = "tray", name = "System tray", icon = "apps", kind = "tray", tier = 2,
    present = function() return bar.tray ~= nil end }
  add { id = "live", name = "Live activity", icon = "radio_button_checked", kind = "live", tier = 0,
    tooltip = function() return bar.live.summary() end }
  add { id = "privacy", name = "Privacy", icon = "privacy_tip", kind = "privacy", tier = 0,
    tooltip = function() return table.concat(bar.privacy.summary(), "\n") end,
    active = function() return #bar.privacy.rows() > 0 end,
    menu = function() return { item("Microphone settings", "mic", settings_page("microphone")) } end }

  -- The panels, a press away.
  add { id = "notifications", name = "Notifications", tier = 3,
    icon = function()
      if bar.notifications.dnd() then return "notifications_off" end
      return bar.notifications.count() > 0 and "notifications_unread" or "notifications"
    end,
    text = function()
      local count = bar.notifications.count()
      return count > 0 and tostring(count) or ""
    end,
    tooltip = function()
      local count = bar.notifications.count()
      local words = count == 1 and "1 notification" or (count .. " notifications")
      return bar.notifications.dnd() and (words .. ", do not disturb") or words
    end,
    tone = function() return bar.notifications.count() > 0 and "accent" or nil end,
    active = function() return bar.notifications.count() > 0 or bar.notifications.dnd() or bar.form() ~= "phone" end,
    press = bar.open_notifications,
    menu = function() return { item(bar.notifications.dnd() and "Allow notifications" or "Do not disturb", "do_not_disturb_on",
      function() bar.notifications.toggle_dnd() end) } end }
  add { id = "dashboard", name = "Dashboard", icon = "dashboard", tier = 2, press = bar.toggle_dashboard,
    tooltip = function() return "Dashboard" end }
  add { id = "settings", name = "Quick settings", icon = "tune", tier = 2, press = bar.open_settings,
    tooltip = function() return "Quick settings" end }
  add { id = "session", name = "Session", icon = "power_settings_new", tier = 2,
    press = function() require("session").drawer.set(true) end, tooltip = function() return "Lock, log out, restart" end }
  add { id = "assistant", name = "Assistant", icon = "smart_toy", tier = 1,
    press = function() require("bottom").drawer.set(true) end, tooltip = function() return "Assistant" end }
  add { id = "clipboard", name = "Clipboard", icon = "content_paste", tier = 1,
    press = function() M.run { "sh", morf.paths.shell("../apps/launch"), "clipboard" } end,
    tooltip = function() return "Clipboard history" end }
  add { id = "screenshot", name = "Screenshot", icon = "screenshot_region", tier = 1,
    press = function() require("capture").shoot("region") end, tooltip = function() return "Take a screenshot" end,
    menu = function() return { item("Of a region", "screenshot_region", function() require("capture").shoot("region") end),
      item("Of a window", "select_window", function() require("capture").shoot("window") end),
      item("Of the screen", "fullscreen", function() require("capture").shoot("screen") end),
      item("Record the screen", "fiber_manual_record", function() require("capture").record("screen") end) } end }
  add { id = "wallpaper", name = "Wallpaper", icon = "wallpaper", tier = 1, press = settings_page("theme/lule"),
    tooltip = function() return "Wallpaper and colours" end }
  add { id = "osk", name = "On-screen keyboard", icon = "keyboard", tier = 1,
    press = function() require("keyboard").toggle() end, tooltip = function() return "On-screen keyboard" end }

  -- Sound and light.
  add { id = "volume", name = "Volume", tier = 2, icon = function() return osd().volume_icon() end,
    text = function() return percent(osd().volume() * 100) end,
    tooltip = function() return "Volume " .. percent(osd().volume() * 100) end,
    press = function() osd().toggle_mute() end,
    wheel = function(steps) osd().adjust("volume", osd().volume() - steps * 0.05) end,
    menu = function() return { item("Sound settings", "volume_up", settings_page("sound")),
      item("Equalizer", "equalizer", settings_page("sound/equalizer")) } end }
  add { id = "microphone", name = "Microphone", icon = "mic", tier = 1,
    text = function()
      local source = morf.audio and morf.audio.available() and morf.audio.default_source()
      return source and percent((source.volume or 0) * 100) or ""
    end,
    tooltip = function() return "Microphone" end, press = settings_page("microphone"),
    menu = function() return { item("Microphone settings", "mic", settings_page("microphone")) } end }
  add { id = "brightness", name = "Brightness", tier = 2, icon = function() return osd().brightness_icon() end,
    present = function() return osd().present("brightness") end,
    text = function() return percent(osd().brightness() * 100) end,
    tooltip = function() return "Brightness " .. percent(osd().brightness() * 100) end,
    wheel = function(steps) osd().adjust("brightness", osd().brightness() - steps * 0.05) end }

  -- The network.
  add { id = "network", name = "Network", tier = 3,
    icon = function()
      local icon = require("status_model").network_icon(services().net)
      return icon ~= "" and icon or "wifi_off"
    end,
    text = function() return services().network.name() or "" end,
    tooltip = function() return services().network.name() or "Not connected" end,
    press = settings_page("network") }
  add { id = "netspeed", name = "Network speed", icon = "swap_vert", tier = 2,
    text = function()
      local i = own_interface()
      return "↓" .. rate_text(i.rx_rate) .. " ↑" .. rate_text(i.tx_rate)
    end,
    tooltip = function()
      local i = own_interface()
      return ("%s\nDown %s/s\nUp %s/s"):format(i.name, size_text(i.rx_rate), size_text(i.tx_rate))
    end,
    press = dashboard_tab("performance") }
  add { id = "lan_ip", name = "Local address", icon = "lan", tier = 1,
    present = function() return installed("ip") end,
    text = function()
      return command("lan_ip", { "ip", "-4", "-o", "route", "get", "1.1.1.1" }, 30000, function(text)
        return text:match("src (%S+)") or ""
      end, ""):get()
    end,
    tooltip = function() return "Address on this network" end, press = settings_page("network") }
  add { id = "public_ip", name = "Public address", icon = "public", tier = 1,
    text = function()
      if not sources.public_ip then
        sources.public_ip = poll.source { name = "eva.bar.public_ip", interval = 600000, initial = "",
          sample = function(done)
            morf.http.get("https://api.ipify.org", {}, function(reply)
              done(reply and reply.ok and tostring(reply.body or ""):match("^%s*(%S+)") or "")
            end)
          end }
      end
      return sources.public_ip:get()
    end,
    tooltip = function() return "Address the internet sees" end }
  add { id = "vpn", name = "VPN", icon = "vpn_key", tier = 2,
    active = function()
      local model = require("settings_model")
      return #model.vpn_names("mesh") + #model.vpn_names("tunnel") > 0
    end,
    text = function()
      local names = require("settings_model").vpn_names("tunnel")
      return names[1] or require("settings_model").vpn_names("mesh")[1] or ""
    end,
    tooltip = function() return "VPN connected" end, press = settings_page("tunnel") }
  add { id = "bluetooth", name = "Bluetooth", tier = 2, icon = function() return services().bluetooth.icon() end,
    present = function() return services().bt ~= nil and services().bt.state.available == true end,
    text = function()
      local count = services().bt.state.connected_count or 0
      return count > 0 and tostring(count) or ""
    end,
    tooltip = function()
      local count = services().bt.state.connected_count or 0
      return count == 1 and "1 device connected" or (count .. " devices connected")
    end,
    press = settings_page("bluetooth") }
  add { id = "bt_batteries", name = "Device batteries", icon = "bluetooth_connected", kind = "batteries", tier = 2,
    active = function() return #M.batteries() > 0 end,
    tooltip = function()
      local lines = {}
      for i, row in ipairs(M.batteries()) do lines[i] = row.name .. " " .. row.level .. "%" end
      return table.concat(lines, "\n")
    end,
    press = settings_page("bluetooth") }

  -- Power.
  add { id = "battery", name = "Battery", icon = "battery_full", kind = "battery", tier = 3,
    present = function() return bar.reading:get().battery.present end,
    tooltip = function()
      local b = bar.reading:get().battery
      local words = require("battery_status_model").describe(b)
      if (b.remaining or 0) > 0 then words = words .. ", " .. clock.elapsed(b.remaining // 60 * 60):gsub(":%d%d$", "") .. " left" end
      return words
    end,
    press = dashboard_tab("battery"), menu = function() return { item("Power settings", "bolt", settings_page("power")) } end }
  add { id = "power_draw", name = "Power draw", icon = "electric_bolt", tier = 1,
    present = function() return bar.reading:get().battery.present end,
    text = function()
      local display = services().upower and services().upower.state.display
      return display and ("%.1f W"):format(display.energy_rate or 0) or ""
    end,
    tooltip = function() return "Going in or out of the battery" end, press = dashboard_tab("battery") }
  add { id = "power_profile", name = "Power profile", tier = 1, icon = function() return services().power.icon() end,
    present = function()
      local power = services().upower
      return power ~= nil and power.state ~= nil and power.state.profiles ~= nil and power.state.profiles.available == true
    end,
    text = function() return (services().upower.state.profiles.active or ""):gsub("^%l", string.upper) end,
    tooltip = function() return "Power profile: " .. tostring(services().upower.state.profiles.active or "") end,
    press = function() bar.next_profile() end, menu = function() return { item("Power settings", "bolt", settings_page("power")) } end }

  -- The machine.
  add { id = "cpu", name = "CPU", icon = "memory", tier = 2,
    text = function() return percent(sysinfo().cpu().usage) end,
    gauge = function() return ratio(sysinfo().cpu().usage, 100) end,
    tone = function() return level(sysinfo().cpu().usage, 80, 95) end,
    tooltip = function()
      local cpu = sysinfo().cpu()
      local load = cpu.load or {}
      return ("CPU %s at %.2f GHz\nLoad %.2f %.2f %.2f"):format(percent(cpu.usage), (cpu.frequency or 0) / 1000,
        load[1] or 0, load[2] or 0, load[3] or 0)
    end,
    press = dashboard_tab("performance") }
  add { id = "cores", name = "CPU cores", icon = "developer_board", kind = "cores", tier = 1,
    tooltip = function() return ("%d cores at %s"):format(sysinfo().cpu().count or 0, percent(sysinfo().cpu().usage)) end,
    press = dashboard_tab("performance") }
  add { id = "cpu_frequency", name = "CPU speed", icon = "speed", tier = 1,
    text = function() return ("%.1f GHz"):format((sysinfo().cpu().frequency or 0) / 1000) end,
    tooltip = function() return ("Mean of %d cores"):format(sysinfo().cpu().count or 0) end,
    press = dashboard_tab("performance") }
  add { id = "memory", name = "Memory", icon = "memory_alt", tier = 2,
    text = function() return percent(sysinfo().memory().percent) end,
    gauge = function() return ratio(sysinfo().memory().percent, 100) end,
    tone = function() return level(sysinfo().memory().percent, 80, 92) end,
    tooltip = function()
      local memory = sysinfo().memory()
      return ("%s of %s in use\n%s cached"):format(size_text(memory.used), size_text(memory.total), size_text(memory.cached))
    end,
    press = dashboard_tab("performance") }
  add { id = "swap", name = "Swap", icon = "swap_horizontal_circle", tier = 1,
    text = function() return percent(sysinfo().memory().swap.percent) end,
    gauge = function() return ratio(sysinfo().memory().swap.percent, 100) end,
    tooltip = function()
      local swap = sysinfo().memory().swap
      return ("%s of %s swap in use"):format(size_text(swap.used), size_text(swap.total))
    end,
    press = dashboard_tab("performance") }
  add { id = "temperature", name = "Temperature", icon = "device_thermostat", tier = 2,
    text = function()
      local t = sysinfo().temperatures().cpu
      return t and ("%d°C"):format(math.floor(t + 0.5)) or "--"
    end,
    gauge = function() return ratio((sysinfo().temperatures().cpu or 0), 100) end,
    tone = function() return level(sysinfo().temperatures().cpu, 75, 90) end,
    tooltip = function()
      local temps = sysinfo().temperatures()
      local lines = {}
      for _, row in ipairs(temps.sensors or {}) do
        if #lines < 6 then lines[#lines + 1] = ("%s %s %d°C"):format(row.chip or "", row.label or "", math.floor((row.celsius or 0) + 0.5)) end
      end
      return #lines > 0 and table.concat(lines, "\n") or "No sensors"
    end,
    press = dashboard_tab("performance") }
  add { id = "gpu", name = "GPU", icon = "videogame_asset", tier = 2,
    present = function()
      local cards = (sysinfo().gpu() or {}).cards
      return cards ~= nil and #cards > 0
    end,
    text = function()
      local card = primary_card() or {}
      if card.suspended then return "Off" end
      return card.busy and percent(card.busy) or "--"
    end,
    gauge = function() return ratio((primary_card() or {}).busy, 100) end,
    tone = function() return level((primary_card() or {}).temperature, 80, 92) end,
    tooltip = function()
      local card = primary_card() or {}
      local lines = { card.model or card.name or "GPU" }
      if card.temperature then lines[#lines + 1] = card.temperature .. "°C" end
      if card.vram_total then lines[#lines + 1] = ("%s of %s memory"):format(size_text(card.vram_used), size_text(card.vram_total)) end
      return table.concat(lines, "\n")
    end,
    press = dashboard_tab("performance") }
  add { id = "fans", name = "Fans", icon = "mode_fan", tier = 1,
    present = function() return #((sysinfo().fans() or {}).fans or {}) > 0 end,
    text = function()
      local top = 0
      for _, fan in ipairs(sysinfo().fans().fans or {}) do top = math.max(top, fan.rpm or 0) end
      return tostring(top)
    end,
    tooltip = function()
      local lines = {}
      for i, fan in ipairs(sysinfo().fans().fans or {}) do lines[i] = ("%s %d RPM"):format(fan.label or fan.key, fan.rpm or 0) end
      return table.concat(lines, "\n")
    end,
    press = dashboard_tab("performance") }
  add { id = "disk", name = "Disk", icon = "hard_drive", tier = 2,
    text = function()
      local row = disk()
      return row and percent(row.percent) or "--"
    end,
    gauge = function() return ratio((disk() or {}).percent, 100) end,
    tone = function() return level((disk() or {}).percent, 85, 95) end,
    tooltip = function()
      local row = disk()
      if not row then return "Nothing mounted at " .. tostring(config().get("bar.disk.mount")) end
      return ("%s: %s free of %s"):format(row.mount, size_text(row.available), size_text(row.total))
    end,
    press = dashboard_tab("performance") }
  add { id = "disk_io", name = "Disk activity", icon = "sync_alt", tier = 1,
    text = function()
      local row = system_drive()
      return rate_text(row.read_rate) .. " R " .. rate_text(row.write_rate) .. " W"
    end,
    tooltip = function()
      local row = system_drive()
      return ("%s\nRead %s/s\nWrite %s/s"):format(row.name or "", size_text(row.read_rate), size_text(row.write_rate))
    end,
    press = dashboard_tab("performance") }
  add { id = "load", name = "Load average", icon = "monitoring", tier = 1,
    text = function() return ("%.2f"):format((sysinfo().cpu().load or {})[1] or 0) end,
    tooltip = function()
      local load = sysinfo().cpu().load or {}
      return ("1, 5 and 15 minutes: %.2f %.2f %.2f"):format(load[1] or 0, load[2] or 0, load[3] or 0)
    end,
    press = dashboard_tab("performance") }
  add { id = "uptime", name = "Uptime", icon = "timer", tier = 1,
    text = function()
      local seconds = sysinfo().system().uptime or 0
      local days, hours = seconds // 86400, (seconds % 86400) // 3600
      return days > 0 and ("%dd %dh"):format(days, hours) or ("%dh %dm"):format(hours, (seconds % 3600) // 60)
    end,
    tooltip = function() return "Since it started" end, press = dashboard_tab("performance") }
  add { id = "host", name = "Machine name", icon = "computer", tier = 1,
    text = function() return sysinfo().system().hostname or "" end,
    tooltip = function() return sysinfo().system().kernel or "" end }
  add { id = "user", name = "User", icon = "person", tier = 1,
    text = function() return require("settings_model").session_user().label or "" end,
    tooltip = function() return "Signed in" end, press = function() require("session").drawer.set(true) end }

  -- Time.
  add { id = "world_clock", name = "World clock", icon = "public", tier = 1,
    present = function() return config().get("bar.clock.zone") ~= "" end,
    text = function()
      morf.time.minute_clock:get()
      local ok, value = pcall(morf.time.format, clock.pattern(clock.options()), morf.time.now(), { tz = config().get("bar.clock.zone") })
      return ok and value or "--"
    end,
    tooltip = function()
      local label = config().get("bar.clock.zone_label")
      return label ~= "" and label or config().get("bar.clock.zone")
    end,
    press = bar.press_clock }
  add { id = "fuzzy_clock", name = "Fuzzy clock", icon = "schedule", tier = 1,
    text = function()
      morf.time.minute_clock:get()
      local now = morf.time.date()
      return clock.fuzzy(now.hour, now.minute)
    end,
    tooltip = function() return morf.time.format("%H:%M") end, press = bar.press_clock }
  add { id = "binary_clock", name = "Binary clock", icon = "grid_on", kind = "binary", tier = 1,
    tooltip = function() return morf.time.format("%H:%M") end, press = bar.press_clock }
  add { id = "countdown", name = "Countdown", icon = "hourglass_top", tier = 1,
    present = function() return clock.days_to(config().get("bar.countdown.date")) ~= nil end,
    text = function()
      morf.time.hour_clock:get()
      local days = clock.days_to(config().get("bar.countdown.date")) or 0
      return days .. "d"
    end,
    tooltip = function()
      local label = config().get("bar.countdown.label")
      return (label ~= "" and label or "Countdown") .. ", " .. config().get("bar.countdown.date")
    end,
    press = bar.press_clock }
  add { id = "next_event", name = "Next event", icon = "event", tier = 1,
    active = function() return bar.next_event() ~= nil end,
    text = function() return (bar.next_event() or {}).text or "" end,
    tooltip = function() return (bar.next_event() or {}).tooltip or "" end,
    press = function() bar.open_calendar() end }

  -- Media.
  add { id = "media", name = "Media", icon = "music_note", kind = "media", tier = 3,
    active = function() return require("media_state").something() end,
    tooltip = function()
      local media = require("media_state")
      local artist = media.field("artist")()
      local title = media.field("title")()
      return artist ~= "" and (title .. "\n" .. artist) or title
    end,
    press = function() require("media_state").control("play_pause") end,
    wheel = function(steps) require("media_state").control(steps > 0 and "next" or "previous") end,
    menu = function() return { item("Previous", "skip_previous", function() require("media_state").control("previous") end),
      item("Next", "skip_next", function() require("media_state").control("next") end),
      item("Open the player", "queue_music", dashboard_tab("media")) } end }
  add { id = "visualiser", name = "Audio visualiser", icon = "graphic_eq", kind = "visualiser", tier = 2,
    active = function() return require("media_state").playing() end,
    tooltip = function() return "What is playing" end, press = dashboard_tab("media") }
  add { id = "lyrics", name = "Lyrics", icon = "lyrics", tier = 1,
    active = function() return require("media_state").lyric(0) ~= "" end,
    text = function() return require("media_state").lyric(0) end,
    tooltip = function() return require("media_state").field("title")() end, press = dashboard_tab("media") }

  -- Toggles.
  add { id = "idle", name = "Keep awake", tier = 3,
    icon = function() return bar.awake() and "coffee" or "bedtime" end,
    tone = function() return bar.awake() and "accent" or nil end,
    tooltip = function() return bar.awake() and "Staying awake" or "Sleeps when idle" end,
    press = function() bar.toggle_awake() end }
  add { id = "focus", name = "Focus", tier = 3,
    icon = function()
      if bar.notifications.dnd() then return "do_not_disturb_on" end
      return "do_not_disturb_off"
    end,
    tone = function() return bar.notifications.dnd() and "accent" or nil end,
    tooltip = function() return bar.notifications.dnd() and "Focus on: no popups" or "Focus off" end,
    press = function() bar.notifications.toggle_dnd() end,
    menu = function() return { item("Focus settings", "tune", settings_page("focus")) } end }
  add { id = "nightlight", name = "Night light", icon = "nightlight", tier = 1,
    present = function() return hardware("nightlight").present() end,
    tone = function() return hardware("nightlight").on() and "accent" or nil end,
    tooltip = function() return "Night light " .. hardware("nightlight").status() end,
    press = function() local n = hardware("nightlight") n.set(not n.on()) end,
    menu = function() return { item("Night light settings", "tune", settings_page("nightlight")) } end }
  add { id = "dark_mode", name = "Dark mode", tier = 1,
    icon = function() return require("themes.color_mode").resolve() == "light" and "light_mode" or "dark_mode" end,
    tooltip = function() return "Dark or light" end,
    press = function() bar.toggle_mode() end }
  add { id = "rotation", name = "Rotation lock", tier = 1,
    present = function() return hardware("rotation").present() end,
    icon = function() return hardware("rotation").on() and "screen_lock_rotation" or "screen_rotation" end,
    tooltip = function() return "Rotation " .. hardware("rotation").status() end,
    press = function() local r = hardware("rotation") r.set(not r.on()) end }
  add { id = "flashlight", name = "Flashlight", icon = "flashlight_on", tier = 1,
    present = function() return hardware("torch").present() end,
    tone = function() return hardware("torch").on() and "accent" or nil end,
    tooltip = function() return "Flashlight " .. hardware("torch").status() end,
    press = function() local t = hardware("torch") t.set(not t.on()) end }

  -- What is going on.
  add { id = "recording", name = "Recording", icon = "fiber_manual_record", tier = 0,
    active = function() return bar.recording() end,
    text = function() return clock.elapsed(require("capture").elapsed:get()) end,
    tone = function() return "alert" end,
    tooltip = function() return "Recording. Press to stop" end,
    press = function() require("capture").record() end }
  add { id = "screen_share", name = "Screen sharing", icon = "screen_share", tier = 0,
    active = function() return bar.privacy.in_use("screen") end,
    tone = function() return "warn" end,
    tooltip = function() return table.concat(bar.privacy.summary(), "\n") end,
    press = function() bar.show_privacy() end }
  add { id = "weather", name = "Weather", tier = 2,
    icon = function()
      local w = services().weather()
      return w.available and services().weather_symbol(w.code, w.is_day) or "cloud"
    end,
    text = function()
      local w = services().weather()
      return w.available and w.temperature and ("%d°"):format(math.floor(w.temperature + 0.5)) or ""
    end,
    tooltip = function()
      local w = services().weather()
      if not w.available then return "No weather yet" end
      return ("%s, %s"):format(require("weather_model").place_name(w.place), w.condition or "")
    end,
    press = dashboard_tab("weather") }
  add { id = "updates", name = "Updates", icon = "system_update_alt", tier = 2,
    present = function() return bar.updates().present == true end,
    text = function() return bar.updates().text or "" end,
    tone = function() return bar.updates().tone end,
    tooltip = function() return bar.updates().tooltip or "" end,
    press = function() M.run(config().get("bar.updates.command")) end }

  -- The compositor.
  add { id = "window_title", name = "Window title", icon = "title", kind = "title", tier = 1,
    text = function() return services().window.title() end,
    tooltip = function() return services().window.title() end,
    press = function() require("window_menu").toggle() end }
  add { id = "keyboard_layout", name = "Keyboard layout", icon = "language", tier = 3,
    present = function()
      local h = services().hyprland
      return h ~= nil and h.available ~= nil and h.available()
    end,
    text = function() return (tostring(services().hyprland.state.keyboard_layout or ""):sub(1, 2):upper()) end,
    tooltip = function() return tostring(services().hyprland.state.keyboard_layout or "") end,
    press = function() bar.next_layout() end }
  add { id = "lock_keys", name = "Caps and Num Lock", icon = "keyboard_capslock", tier = 2,
    present = function() return osd().present("caps") or osd().present("num") end,
    active = function() return osd().read("caps").on == true or osd().read("num").on == true end,
    text = function()
      local words = {}
      if osd().read("caps").on then words[#words + 1] = "Caps" end
      if osd().read("num").on then words[#words + 1] = "Num" end
      return table.concat(words, " ")
    end,
    tooltip = function() return "Lock keys that are on" end }
  add { id = "submap", name = "Key mode", icon = "keyboard_command_key", tier = 3,
    present = function()
      local h = services().hyprland
      return h ~= nil and h.available ~= nil and h.available()
    end,
    active = function() return (services().hyprland.state.submap or "") ~= "" end,
    text = function() return services().hyprland.state.submap or "" end,
    tooltip = function() return "Hyprland submap" end }

  -- Counted from commands.
  add { id = "failed_units", name = "Failed services", icon = "report", tier = 2,
    present = function() return installed("systemctl") end,
    active = function()
      return command("failed", { "systemctl", "--failed", "--no-legend", "--plain" }, 60000, lines_of, 0):get() > 0
    end,
    text = function() return tostring(command("failed", { "systemctl", "--failed", "--no-legend", "--plain" }, 60000, lines_of, 0):get()) end,
    tone = function() return "alert" end,
    tooltip = function() return "Services that failed" end }
  add { id = "containers", name = "Containers", icon = "deployed_code", tier = 1,
    present = function() return installed("podman") or installed("docker") end,
    text = function()
      local tool = installed("podman") and "podman" or "docker"
      return tostring(command("containers", { tool, "ps", "-q" }, 30000, lines_of, 0):get())
    end,
    tooltip = function() return "Containers running" end }
  add { id = "ssh", name = "SSH sessions", icon = "terminal", tier = 1,
    present = function() return installed("who") end,
    active = function() return bar.ssh_sessions() > 0 end,
    text = function() return tostring(bar.ssh_sessions()) end,
    tooltip = function() return "Logged in over a network" end }
  add { id = "tmux", name = "Tmux sessions", icon = "view_quilt", tier = 1,
    present = function() return installed("tmux") end,
    text = function() return tostring(command("tmux", { "tmux", "list-sessions", "-F", "#S" }, 30000, lines_of, 0):get()) end,
    tooltip = function() return "Tmux sessions" end }
  add { id = "trash", name = "Trash", icon = "delete", tier = 1,
    text = function()
      local count = bar.trash_count()
      return count > 0 and tostring(count) or ""
    end,
    tooltip = function() return bar.trash_count() .. " in the trash" end,
    press = function() M.run { "xdg-open", "trash:///" } end,
    menu = function() return { item("Empty the trash", "delete_forever", function() M.run { "gio", "trash", "--empty" } end) } end }
  add { id = "printer", name = "Print jobs", icon = "print", tier = 1,
    present = function() return installed("lpstat") end,
    active = function() return command("printer", { "lpstat", "-o" }, 15000, lines_of, 0):get() > 0 end,
    text = function() return tostring(command("printer", { "lpstat", "-o" }, 15000, lines_of, 0):get()) end,
    tooltip = function() return "Jobs waiting to print" end }
  add { id = "gamemode", name = "GameMode", icon = "sports_esports", tier = 2,
    present = function() return installed("gamemoded") end,
    active = function()
      return command("gamemode", { "gamemoded", "-s" }, 10000, function(text)
        return text:match("is active") ~= nil
      end, false):get()
    end,
    tooltip = function() return "GameMode is on" end }

  -- Layout helpers.
  add { id = "text", name = "Text", icon = "text_fields", tier = 1,
    text = function() return config().get("bar.text") end,
    present = function() return config().get("bar.text") ~= "" end,
    tooltip = function() return config().get("bar.text") end }
  for _, id in ipairs { "spacer", "spacer_2" } do
    add { id = id, name = id == "spacer" and "Spacer" or "Spacer 2", icon = "space_bar", kind = "spacer", tier = 1 }
  end
  for _, id in ipairs { "divider", "divider_2" } do
    add { id = id, name = id == "divider" and "Divider" or "Divider 2", icon = "more_vert", kind = "divider", tier = 1 }
  end

  for _, module in ipairs(require("bar_custom").modules(M.run)) do add(module) end
  return list
end

return M
