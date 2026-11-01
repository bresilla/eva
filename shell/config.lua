-- The shell's settings: defaults here, what differs in a JSON file under the
-- state directory, every value a signal (lib/util/settings.lua).
--
-- EVA_SETTINGS names another file (the tests point it at a scratch
-- one); CAELESTIA_SETTINGS, the name before eva, is read when it is unset.

local morf = require("morf")
local settings = require("lib.shell.settings")
local capture_tools={}
for _,tool in ipairs(require("lib.shell.capture.annotation").tools) do
  capture_tools[tool[1]]={color="#ef5350",width=tool[1]=="text" and 24 or 4,filled=false}
end

-- Each on-screen display: its place ("" for the default), whether it shows,
-- its hold in ms (0 for the default) and whether it reads a percentage.
local osd_kinds={}
for _,kind in ipairs {"volume","brightness","mic","caps","num","layout","profile","dnd","focus","awake","night",
  "ring","bluetooth","headphones","media"} do
  osd_kinds[kind]={position="",enabled=true,hold=0,percent=true}
end

local path = (morf.env and (morf.env("EVA_SETTINGS") or morf.env("CAELESTIA_SETTINGS")))
  or morf.paths.state("eva.json")

local config = settings.open {
  path = path,
  defaults = {
    theme = {
      -- What the Material scheme is built from: "lule" (the colour
      -- tool's accent -- lule, pywal), "wallpaper", a colour, or "auto"
      -- (lule when it has set anything, else the wallpaper). The tool's
      -- own colours are theme.lule either way.
      source = "auto",
      variant = "tonal_spot",
    },
    appearance = {
      -- A font file every label is set in ("" for the installed faces).
      font_file = "",
      -- How big everything is drawn, from -1 (half the size) through 0 (the
      -- compositor's own scale) to 1 (twice it): the scale slider.
      zoom = 0,
      -- How much things bounce: "calm", "balanced" or "playful".
      motion = "balanced",
      -- Everything lands at once, with no travel.
      reduce_motion = false,
    },
    wallpaper = {
      -- A picture to paint under everything; "" reads the path the
      -- eva tools keep in ~/.local/state/eva/wallpaper/path.txt.
      path = "",
      -- Whether the shell paints it at all. Off: the compositor's own
      -- wallpaper tool (hyprpaper, which lule drives) shows through, and
      -- the compositor has one full-screen layer fewer to blend on every
      -- redraw. The scheme follows the picture either way.
      draw = false,
    },
    bar = {
      workspaces = { shown = 5 },
      clock = { twelve_hour = true },
      -- What the Bluetooth popout's "Open settings" starts.
      bluetooth_settings = { "blueman-manager" },
    },
    dashboard = {
      -- Opens when the pointer reaches the top edge over it.
      hover = true,
    },
    sidebar = {
      -- Opens when the pointer reaches the middle of the right edge.
      hover = true,
    },
    -- Which pages each edge's panel holds (shell/pages.lua): a desk's right
    -- and left panels, and a phone's sheet from the top. A page moves by
    -- moving its key.
    panels = {
      right = { "settings", "notifications" },
      left = { "tasks", "calendar" },
      top = { "notifications", "tasks", "calendar", "assistant", "drop", "settings" },
    },
    leftbar = {
      -- Opens when the pointer reaches the left edge above the rail.
      hover = true,
    },
    bottom = {
      -- Opens the assistant workspace from the bottom edge.
      hover = true,
    },
    lule = {
      -- Empty follows LULE_W, then the current wallpaper's directory.
      folder = "",
      source = "files",
      logo = "",
      logo_size = 40,
    },
    capture = {
      -- Where screenshots and recordings go, both.
      folder = "~/Pictures/Captures",
      editor = true,
      tools = capture_tools,
      blur = 24, pixelate = 14, zoom = 2,
      cursor = false, save_dialog = false, copy_on_save = true, copy_to_disk = false,
      upload_endpoint = "https://litterbox.catbox.moe/resources/internals/api.php",
      hotkey = "Print", keybind_file = "",
      -- What each capture runs: `$FILE` is the file to write (in the
      -- folder, named for the time, with its extension), `~/` and `$HOME`
      -- expanded. An empty list runs nothing.
      commands = {
        screenshot_region = { "sh", "-c", "grim -g \"$(slurp)\" \"$0\" && wl-copy < \"$0\"", "$FILE.png" },
        screenshot_window = { "sh", "-c", "grim -g \"$(hyprctl -j activewindow | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"')\" \"$0\" && wl-copy < \"$0\"", "$FILE.png" },
        screenshot_screen = { "sh", "-c", "grim -o \"$(hyprctl -j monitors | jq -r '.[] | select(.focused) | .name')\" \"$0\" && wl-copy < \"$0\"", "$FILE.png" },
        record_region = { "sh", "-c", "region=$(slurp -f '%wx%h+%x+%y') || exit; exec gpu-screen-recorder -w region -region \"$region\" -f 60 -o \"$0\"", "$FILE.mp4" },
        record_window = { "sh", "-c", "region=$(hyprctl -j activewindow | jq -er '\"\\(.size[0])x\\(.size[1])+\\(.at[0])+\\(.at[1])\"') && exec gpu-screen-recorder -w region -region \"$region\" -f 60 -o \"$0\"; exec gpu-screen-recorder -w portal -f 60 -o \"$0\"", "$FILE.mp4" },
        record_screen = { "gpu-screen-recorder", "-w", "screen", "-f", "60", "-o", "$FILE.mp4" },
        open = { "xdg-open" },
      },
    },
    launcher = {
      max_shown = 7,
      action_prefix = ">",
    },
    -- The on-screen displays, and where the notification popups stand ("" for
    -- the default).
    osd = { kinds = osd_kinds, notifications = "" },
    rail = {
      -- The workspaces down the left edge.
      enabled = true,
      -- How long the numbered bud stays out after a switch, in ms.
      hold = 800,
    },
    -- The bar along an edge (bar.lua) -- not `bar`, the reference's settings.
    edgebar = {
      -- "on", "off", or "auto": up on narrow or portrait screens (a phone),
      -- down on a wide desk. The quick settings' Bar tile sets it.
      enabled = "auto",
      -- top, bottom, left or right.
      side = "top",
      -- "on" or "off": each window's title beside its icon, along a top or
      -- bottom bar.
      titles = "on",
      -- How far the screen's rounded corners reach along the bar, in logical
      -- pixels; 0 works it out. A cutout, in the panel's upright orientation:
      -- its left edge, its width and how far down it goes.
      corner = 0,
      cutout = { x = 0, width = 0, height = 0 },
      -- "on" or "off": the system tray on a desk's bar.
      tray = "on",
      -- The wheel over a desk's bar: over the status it changes the volume,
      -- over the clock the workspace.
      wheel_volume = false,
      wheel_workspace = false,
    },
    -- Airplane mode, and what was on before it (to bring back).
    airplane = { on = false, was = { wifi = false, bluetooth = false, mobile = false } },
    -- sound, vibrate or silent (lib/util/ringer.lua; vibrate where feedbackd is).
    ringer = { mode = "sound" },
    -- The notification server and how it behaves (shell/notifs.lua).
    notifications = {
      -- Off, another daemon keeps the bus name; the shell's own still show.
      daemon = true,
      -- The screen popups stand on, "" for the one in use.
      output = "",
      -- ms on screen, 0 for the default of 5 s.
      timeout = 0,
      ignore_app_timeouts = false,
      max_popups = 5,
      -- Popups of one app fold into one card with a count.
      stack = true,
      -- Sounds, off until asked for, at this volume; a file or event name
      -- instead of the sound theme's own.
      sounds = false,
      volume = 60,
      sound = "",
      -- Repeated arrivals from one app stay silent for a while.
      cooldown = true,
      -- Action buttons, and code and link chips.
      actions = true,
      smart = true,
      -- How long the buttons of an expired notification keep working, in ms.
      keep_actions = 900000,
      -- "show", or "hide": content stays hidden until a card is opened.
      previews = "show",
      -- What a lock screen may show: "all", "app", "count" or "none".
      lock_previews = "app",
      -- When the summary of `digest` apps arrives.
      digest_times = { "08:00", "18:00" },
      -- A screen flash and a ring round the edge on arrival.
      flash = false,
      edge_light = false,
      -- Per-app rules (shell/notification_rules.lua) and who has notified.
      rules = {},
      apps = {},
      history = {
        enabled = true,
        -- Entries kept, and for how many days; 0 days keeps them for good.
        limit = 200,
        days = 30,
        keep_dismissed = true,
        -- Groups stand open, and how many lines a shut one shows.
        open_groups = false,
        preview = 3,
      },
    },
    -- Focus modes (shell/focus_model.lua).
    focus = {
      -- The mode on, when a timed one ends, and what turned it on.
      active = "", ends = 0, source = "", last = "dnd",
      -- The session length the tile starts: seconds, 0 until off, -1 until 8:00.
      duration = 0,
      -- Stay quiet while the screen is shared, or a window is fullscreen.
      sharing = true,
      fullscreen = false,
      -- Windows turned off by hand: "<mode>@<date>".
      skip = {},
      modes = {
        { id = "dnd", name = "Do not disturb", icon = "do_not_disturb_on",
          allow = { urgency = 2, apps = {}, people = {}, calls = false, alarms = true },
          schedule = { on = false, days = { 1, 2, 3, 4, 5, 6, 7 }, from = "22:00", to = "07:00", charging = false, paused = false },
          triggers = { apps = {}, display = "", gamepad = false },
          effects = { night = false, dark = false, saver = false, awake = false, ring = "" },
          hide_badges = false, on_enter = {}, on_exit = {} },
        { id = "work", name = "Work", icon = "work",
          allow = { urgency = 2, apps = {}, people = {}, calls = true, alarms = true },
          schedule = { on = false, days = { 1, 2, 3, 4, 5 }, from = "09:00", to = "17:00", charging = false, paused = false },
          triggers = { apps = {}, display = "", gamepad = false },
          effects = { night = false, dark = false, saver = false, awake = false, ring = "" },
          hide_badges = false, on_enter = {}, on_exit = {} },
        { id = "personal", name = "Personal", icon = "person",
          allow = { urgency = 1, apps = {}, people = {}, calls = true, alarms = true },
          schedule = { on = false, days = { 6, 7 }, from = "10:00", to = "20:00", charging = false, paused = false },
          triggers = { apps = {}, display = "", gamepad = false },
          effects = { night = false, dark = false, saver = false, awake = false, ring = "" },
          hide_badges = false, on_enter = {}, on_exit = {} },
        { id = "sleep", name = "Sleep", icon = "bedtime",
          allow = { urgency = 2, apps = {}, people = {}, calls = false, alarms = true },
          schedule = { on = false, days = { 1, 2, 3, 4, 5, 6, 7 }, from = "23:00", to = "07:00", charging = false, paused = false },
          triggers = { apps = {}, display = "", gamepad = false },
          effects = { night = true, dark = true, saver = false, awake = false, ring = "silent" },
          hide_badges = true, on_enter = {}, on_exit = {} },
        { id = "gaming", name = "Gaming", icon = "sports_esports",
          allow = { urgency = 2, apps = {}, people = {}, calls = false, alarms = true },
          schedule = { on = false, days = { 1, 2, 3, 4, 5, 6, 7 }, from = "20:00", to = "23:00", charging = false, paused = false },
          triggers = { apps = {}, display = "", gamepad = false },
          effects = { night = false, dark = false, saver = false, awake = true, ring = "" },
          hide_badges = false, on_enter = {}, on_exit = {} },
      },
    },
    -- The shell as the session's polkit agent (polkit.lua): "on", or "off"
    -- to leave the job to another (hyprpolkitagent, polkit-gnome).
    polkit = { agent = "on" },
    keyboard = {
      -- Up by itself when a program asks for text and no real keyboard
      -- is attached (a tablet, a detached keyboard); by hand either way.
      auto = true,
    },
    services = {
      weather_location = "",
      imperial = false,
    },
    utilities = {
      commands = {
        mic_on = { "wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "0" },
        mic_off = { "wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "1" },
        settings = {},
        -- Game mode on Hyprland: no animations, blur, gaps or rounding.
        gamemode_on = { "hyprctl", "--batch",
          "keyword animations:enabled 0; keyword decoration:blur:enabled 0; keyword general:gaps_in 0; keyword general:gaps_out 0; keyword decoration:rounding 0" },
        gamemode_off = { "hyprctl", "reload" },
      },
    },
    session = {
      -- What each of the session menu's actions runs (`$USER` is the
      -- user's name).
      commands = {
        lock = { "morf", "lock" },
        logout = { "loginctl", "terminate-user", "$USER" },
        suspend = { "systemctl", "suspend" },
        shutdown = { "systemctl", "poweroff" },
        hibernate = { "systemctl", "hibernate" },
        reboot = { "systemctl", "reboot" },
      },
    },
    -- The quick settings' tiles shown on each kind of machine, in order,
    -- and which of them are drawn small. A tile the machine lacks is skipped.
    quick = {
      tiles = {
        desk = { "wifi", "bluetooth", "wired", "mobile", "mesh", "tunnel", "airplane", "hotspot", "sound", "mic",
          "nightlight", "powersaver", "battery", "focus", "theme", "eva" },
        tablet = { "wifi", "bluetooth", "rotation", "keyboard", "airplane", "hotspot", "sound", "mic", "nightlight",
          "powersaver", "battery", "mesh", "tunnel", "focus", "theme", "eva" },
        phone = { "wifi", "mobile", "bluetooth", "hotspot", "flashlight", "rotation", "airplane", "nightlight",
          "powersaver", "sound", "mic", "battery", "mesh", "tunnel", "focus", "theme", "eva" },
      },
      small = { desk = {}, tablet = {}, phone = { "flashlight", "rotation", "nightlight", "powersaver" } },
    },
    -- The night light (hyprsunset): whether it is on, and how warm, in kelvin.
    nightlight = { on = false, temperature = 4500 },
    -- Whether the screen keeps its rotation: "on", "off", or "auto" (a desk
    -- keeps it, a phone or a tablet follows the accelerometer).
    rotation = { lock = "auto" },
  },
}
return require("themes.ui_scale").link(config)
