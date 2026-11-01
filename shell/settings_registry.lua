-- Every Settings page, once: its route, name, icon, the words it is found by,
-- and the category the home listing files it under. Plain data, no nodes and
-- no signals, so anything may read it.
--
--   local registry = require("settings_registry")
--   registry.list()             -- { { key, name, icon, keywords } }, every page
--   registry.entries()          -- those, and each setting a page holds
--   registry.search("repeat")   -- entries matching, best first
--
-- `key` is what `morf ipc call settings KEY` and `eva open settings/KEY` take.
local M = {}

M.HOME = "home"

M.CATEGORIES = {
  { id = "connections", name = "Connections" },
  { id = "device", name = "Device" },
  { id = "look", name = "Look and feel" },
  { id = "shell", name = "Eva" },
  { id = "apps", name = "Apps" },
  { id = "system", name = "System" },
}

-- `summary` is the home row's second line. `items` are the settings a page
-- holds, each `{ name, keywords }`, found by search on their own.
M.PAGES = {
  { key = "home", name = "All settings", icon = "settings", summary = "Every page, by category",
    keywords = "search find everything" },

  { key = "network", name = "Network", icon = "wifi", category = "connections", summary = "Wi-Fi, hidden networks, sharing",
    keywords = "wifi wi-fi wireless ssid internet connect password",
    items = { { "Join a hidden network", "ssid hidden" }, { "Share Wi-Fi with a QR code", "qr code share password" } } },
  { key = "network/connection", name = "Connection", icon = "tune", parent = "network",
    keywords = "ip address static dhcp dns gateway metered mac details",
    items = { { "Static IP address", "manual ipv4 gateway subnet" }, { "DNS servers", "dns resolver nameserver private over tls" },
      { "Metered connection", "data limit" }, { "Random MAC address", "privacy mac cloned" } } },
  { key = "network/proxy", name = "Proxy", icon = "shield", parent = "network",
    keywords = "proxy socks http pac automatic" },
  { key = "wired", name = "Wired", icon = "lan", category = "connections", summary = "Ethernet ports",
    keywords = "ethernet cable lan port" },
  { key = "mobile", name = "Mobile networks", icon = "signal_cellular_alt", category = "connections",
    summary = "Mobile data, SIM and APN", keywords = "cellular modem sim apn roaming sms ussd lte 5g data" },
  { key = "bluetooth", name = "Bluetooth", icon = "bluetooth", category = "connections", summary = "Pair, connect, send files",
    keywords = "pair headphones earbuds speaker adapter",
    items = { { "Rename this computer's Bluetooth", "adapter alias name" }, { "Send a file over Bluetooth", "obex transfer" } } },
  { key = "phone", name = "Phone", icon = "smartphone", category = "connections", summary = "A paired phone, by KDE Connect",
    keywords = "kde connect kdeconnect android ring find send file battery" },
  { key = "hotspot", name = "Hotspot", icon = "wifi_tethering", category = "connections", summary = "Share this connection",
    keywords = "tether share access point" },
  { key = "mesh", name = "Mesh", icon = "hub", category = "connections", summary = "NetBird, Tailscale, ZeroTier",
    keywords = "vpn tailscale netbird zerotier" },
  { key = "tunnel", name = "Tunnel", icon = "vpn_lock", category = "connections", summary = "VPN, Mullvad, Proton, Tor",
    keywords = "vpn wireguard openvpn mullvad proton tor" },

  { key = "displays", name = "Displays", icon = "monitor", category = "device", summary = "Monitors, scale and arrangement",
    keywords = "screen monitor resolution refresh rate scale rotate mirror vrr" },
  { key = "sound", name = "Sound", icon = "volume_up", category = "device", summary = "Outputs, apps, equalizer",
    keywords = "audio volume speaker headphones output balance mute" },
  { key = "sound/more", name = "More sound settings", icon = "tune", parent = "sound",
    keywords = "theme devices codec profile",
    items = { { "Sound theme", "event sounds alert" }, { "Preferred devices", "default output rules priority" },
      { "Bluetooth codec", "ldac aptx aac sbc profile" }, { "Card profile", "surround stereo hdmi" } } },
  { key = "sound/equalizer", name = "Equalizer", icon = "equalizer", parent = "sound",
    keywords = "eq bass treble presets tone" },
  { key = "sound/equalizer/audiogram", name = "Audiogram", icon = "hearing", parent = "sound/equalizer",
    keywords = "hearing compensation ear" },
  { key = "microphone", name = "Microphone", icon = "mic", category = "device", summary = "Inputs, level and test",
    keywords = "input mic recording gain", items = { { "Test the microphone", "level meter loud quiet" } } },
  { key = "input", name = "Keyboard", icon = "keyboard", category = "device", summary = "Layouts, switching, repeat",
    keywords = "layout language repeat delay rate numlock xkb compose caps",
    items = { { "Keyboard layouts", "add language qwerty dvorak azerty" }, { "Switch layout key", "alt shift super space" },
      { "Key repeat", "rate delay speed" } } },
  { key = "input/pointer", name = "Mouse and touchpad", icon = "mouse", parent = "input", category = "device",
    summary = "Speed, tap to click, cursor",
    keywords = "mouse touchpad trackpad pointer cursor scroll natural tap click sensitivity acceleration left handed",
    items = { { "Tap to click", "touchpad" }, { "Natural scrolling", "reverse invert" }, { "Cursor size", "pointer theme big" } } },
  { key = "input/devices", name = "Input devices", icon = "devices", parent = "input",
    keywords = "per device each mouse keyboard tablet disable" },
  { key = "power", name = "Power", icon = "battery_full", category = "device", summary = "Battery, profiles, sleep and lid",
    keywords = "battery charge profile saver performance",
    items = { { "When the lid closes", "lid suspend" }, { "Power button", "key action" },
      { "Idle timeouts", "lock screen off sleep suspend timeout" }, { "Charge limit", "battery threshold 80" },
      { "Graphics mode", "gpu hybrid integrated nvidia" } } },
  { key = "storage", name = "Storage", icon = "hard_drive", category = "device", summary = "Drives, usage and trash",
    keywords = "disk drive usb mount eject unlock encrypted luks space free trash",
    items = { { "Empty the trash", "bin delete" }, { "Low space warning", "disk full" } } },
  { key = "printers", name = "Printers", icon = "print", category = "device", summary = "Queues and scanners",
    keywords = "print cups queue job scanner scan add" },

  { key = "theme", name = "Theme", icon = "palette", category = "look", summary = "Dark, light and colours",
    keywords = "appearance dark light mode auto colour color" },
  { key = "theme/lule", name = "Lule", icon = "colors", parent = "theme",
    keywords = "wallpaper colours font palette" },
  { key = "theme/wallpaper", name = "Wallpaper", icon = "wallpaper", parent = "theme", category = "look",
    summary = "Picture, transitions, slideshow", keywords = "background picture image draw slideshow transition per workspace" },
  { key = "theme/desktop", name = "Desktop", icon = "widgets", parent = "theme", category = "look",
    summary = "Widgets on the wallpaper", keywords = "widgets clock weather visualiser desktop arrange standby" },
  { key = "theme/look", name = "Look", icon = "tune", parent = "theme", category = "look",
    summary = "Schemes, glass, density, corners", keywords = "catppuccin gruvbox nord dracula glass density corners cursor icons gtk qt font" },
  { key = "nightlight", name = "Night light", icon = "nightlight", category = "look", summary = "Warmer colours",
    keywords = "blue light temperature warm evening hyprsunset" },
  { key = "accessibility", name = "Accessibility", icon = "accessibility_new", category = "look",
    summary = "Text size, contrast, filters, keys",
    keywords = "a11y large text high contrast colour blind filter sticky keys magnifier zoom reduce motion mouse keys",
    items = { { "Large text", "font size bigger" }, { "High contrast", "stronger colours" },
      { "Colour filters", "grayscale invert protanopia deuteranopia tritanopia" }, { "Sticky keys", "modifier latch" },
      { "Mouse keys", "numpad pointer" }, { "Screen magnifier", "zoom" }, { "Reduce motion", "animation" } } },

  { key = "eva", name = "Eva", icon = "dashboard_customize", category = "shell", summary = "The shell itself",
    keywords = "shell motion hover panels bounce" },
  { key = "bar", name = "Bar", icon = "toolbar", parent = "eva", category = "shell", summary = "Where it stands, what it shows",
    keywords = "edge top bottom tray titles" },
  { key = "bar/more", name = "Clock and screen shape", icon = "schedule", parent = "bar",
    keywords = "clock 12 hour cutout notch rounded corner bluetooth program" },
  { key = "osd", name = "On-screen displays", icon = "picture_in_picture", parent = "eva", category = "shell",
    summary = "Where each appears", keywords = "volume popup position notification place" },
  { key = "launcher", name = "Launcher", icon = "apps", parent = "eva", category = "shell", summary = "Results and prefix",
    keywords = "search results action prefix" },
  { key = "rail", name = "Workspace rail", icon = "view_week", parent = "eva", category = "shell", summary = "Left edge workspaces",
    keywords = "workspaces left edge hold" },
  { key = "panels", name = "Panels", icon = "dock_to_right", parent = "eva", category = "shell", summary = "Which page each panel holds",
    keywords = "tabs arrange move notifications tasks calendar sheet" },
  { key = "capture", name = "Capture", icon = "screenshot_monitor", parent = "eva", category = "shell",
    summary = "Screenshots and recordings", keywords = "screenshot record folder upload editor blur hotkey" },
  { key = "osk", name = "On-screen keyboard", icon = "keyboard_alt", parent = "eva", category = "shell",
    summary = "When it comes up", keywords = "touch virtual keyboard auto" },
  { key = "weather", name = "Weather", icon = "partly_cloudy_day", parent = "eva", category = "shell",
    summary = "Location and units", keywords = "location city imperial metric celsius fahrenheit" },
  { key = "commands", name = "Commands", icon = "terminal", parent = "eva", category = "shell",
    summary = "What the buttons run", keywords = "lock suspend logout shutdown reboot hibernate game mode microphone custom" },
  { key = "assistant", name = "Assistant", icon = "auto_awesome", parent = "eva", category = "shell",
    summary = "Provider, model and history", keywords = "ai chat llm anthropic claude openai ollama key model" },
  { key = "calendars", name = "Calendars", icon = "calendar_month", parent = "eva", category = "shell",
    summary = "Files, folders and addresses", keywords = "ics vdir events reminders lead subscribe" },
  { key = "focus", name = "Focus", icon = "tune", category = "shell", summary = "Modes, do not disturb, ring, keep awake",
    keywords = "dnd do not disturb silent vibrate awake caffeine work sleep schedule mode" },
  { key = "focus/mode", name = "Mode", icon = "tune", parent = "focus", keywords = "schedule allowed apps people" },
  { key = "notifications", name = "Notifications", icon = "notifications", parent = "eva", category = "shell",
    summary = "Sounds, popups, history, each app's rules", keywords = "sound popup history rules mute badge lock previews" },
  { key = "notifications/app", name = "App", icon = "apps", parent = "notifications", keywords = "rules mute urgency" },

  { key = "apps", name = "Default apps", icon = "apps", category = "apps", summary = "What opens what",
    keywords = "browser mail music video pdf editor terminal file manager mime type association" },
  { key = "startup", name = "Startup apps", icon = "rocket_launch", category = "apps", summary = "Apps and user services",
    keywords = "autostart login boot systemd service background" },
  { key = "notes", name = "Notes", icon = "sticky_note_2", category = "apps", summary = "Quick notes, in a folder",
    keywords = "jot write markdown text" },

  { key = "datetime", name = "Date and time", icon = "schedule", category = "system", summary = "Timezone and clock",
    keywords = "timezone ntp clock 24 hour automatic time zone" },
  { key = "region", name = "Region and language", icon = "language", category = "system", summary = "Language and formats",
    keywords = "locale language formats" },
  { key = "users", name = "Users", icon = "group", category = "system", summary = "Accounts and pictures",
    keywords = "account avatar picture face administrator wheel name" },
  { key = "privacy", name = "Privacy and security", icon = "privacy_tip", category = "system", summary = "App permissions, recent use",
    keywords = "permission location camera microphone flatpak portal recent history secure boot encryption polkit",
    items = { { "Clear recent files", "history" }, { "Authentication agent", "polkit" } } },
  { key = "firewall", name = "Firewall", icon = "security", category = "system", summary = "Incoming connections",
    keywords = "ufw firewalld ports block" },
  { key = "updates", name = "Updates", icon = "system_update", category = "system", summary = "System and firmware",
    keywords = "upgrade update firmware fwupd nixos rebuild" },
  { key = "about", name = "About", icon = "info", category = "system", summary = "This machine and its versions",
    keywords = "hardware version hostname computer name cpu memory gpu kernel system information" },
}

M.BY_KEY = {}
for _, page in ipairs(M.PAGES) do M.BY_KEY[page.key] = page end

--- The category's pages, in order.
function M.category(id)
  local out = {}
  for _, page in ipairs(M.PAGES) do
    if page.category == id then out[#out + 1] = page end
  end
  return out
end

local function row(page)
  local words = { page.keywords or "" }
  for _, item in ipairs(page.items or {}) do words[#words + 1] = item[1]:lower() .. " " .. (item[2] or "") end
  return { key = page.key, name = page.name, icon = page.icon, keywords = table.concat(words, " ") }
end

--- Every page as `{ key, name, icon, keywords }`.
function M.list()
  local out = {}
  for _, page in ipairs(M.PAGES) do
    if page.key ~= M.HOME then out[#out + 1] = row(page) end
  end
  return out
end

--- Every page and every setting a page holds, each `{ key, name, icon,
--- keywords, page }`: `page` names the page a setting is on, nil for a page.
function M.entries()
  local out = {}
  for _, page in ipairs(M.PAGES) do
    if page.key ~= M.HOME then
      out[#out + 1] = row(page)
      for _, item in ipairs(page.items or {}) do
        out[#out + 1] = { key = page.key, name = item[1], icon = page.icon, keywords = item[2] or "", page = page.name }
      end
    end
  end
  return out
end

--- How well `entry` answers the lowered `words`: higher is better, 0 is not
--- at all. Every word must match.
local function score(entry, words)
  local name, keywords = entry.name:lower(), entry.keywords:lower()
  local total = 0
  for _, word in ipairs(words) do
    if name:sub(1, #word) == word then total = total + 8
    elseif name:find(" " .. word, 1, true) then total = total + 6
    elseif name:find(word, 1, true) then total = total + 4
    elseif keywords:find(word, 1, true) then total = total + 2
    else return 0 end
  end
  return total + (entry.page and 0 or 1)
end

--- The entries matching `query`, best first.
function M.search(query)
  local words = {}
  for word in tostring(query or ""):lower():gmatch("%S+") do words[#words + 1] = word end
  if #words == 0 then return {} end
  local found = {}
  for index, entry in ipairs(M.entries()) do
    local value = score(entry, words)
    if value > 0 then found[#found + 1] = { entry = entry, score = value, index = index } end
  end
  table.sort(found, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.index < b.index
  end)
  local out = {}
  for index, hit in ipairs(found) do out[index] = hit.entry end
  return out
end

return M
