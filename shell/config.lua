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
  "ring","bluetooth","headphones","media","workspace"} do
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
      -- Colours follow the album art while something plays.
      follow_song = false,
      -- Turns the source colour round the wheel, in degrees.
      hue = 0,
      -- What runs when the mode turns; `$MODE` is filled in.
      hook = {},
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
      -- "compact", "normal" or "spacious": a step along the spacing scale.
      density = "normal",
      -- How round the corners are: 0 square, 1 the theme's own, 2 twice it.
      corners = 1,
      -- Panels of glass over the picture, and how much of the picture shows.
      glass = false,
      glass_clarity = 0.45,
      -- The dark palette's surfaces all the way to black.
      pure_black = false,
      -- Push the mode, cursor and icons to GTK, Qt and the terminals.
      sync = true,
      -- Replace Qt's palette with the shell's colours too.
      sync_qt_colors = false,
      -- "" leaves each as the desktop has it.
      cursor_theme = "",
      cursor_size = 24,
      icon_theme = "",
      gtk_theme = "",
      -- How quick everything is, and how far surfaces deform as they move.
      speed = 1,
      deform = 1,
      -- Looks saved by name (shell/profiles_model.lua).
      profiles = {},
      -- How much larger every label is set, 1 for as designed.
      text_scale = 1,
      -- Stronger contrast: text at full strength, surfaces plainer.
      high_contrast = false,
    },
    -- What the Input pages chose (shell/input_model.lua): only what was
    -- changed, so everything else stays the compositor's own configuration.
    input = {
      -- The options chosen, each `{ key, value }`: input_config's names.
      chosen = {},
      -- The layouts, in order, each `{ layout, variant }`; empty keeps the
      -- compositor's. And what switches between them, an xkb option.
      layouts = {},
      switch = "grp:alt_shift_toggle",
      -- Each device's own options, `{ key = device name, value = options }`.
      devices = {},
    },
    -- What the Accessibility page keeps on (shell/access_model.lua).
    accessibility = {
      -- none, grayscale, invert, protanopia, deuteranopia or tritanopia.
      filter = "none",
      sticky_keys = false,
      mouse_keys = false,
      -- The screen's magnification, 1 for none.
      zoom = 1,
    },
    sound = {
      -- The event sound theme ("" leaves it alone).
      theme = "",
      -- The outputs and inputs wanted, most wanted first, by device name.
      preferred_outputs = {},
      preferred_inputs = {},
    },
    power = {
      -- What closing the lid and pressing the power button do while the
      -- shell runs: system (logind decides), or nothing, lock, suspend,
      -- hibernate, poweroff.
      lid_battery = "system", lid_ac = "system", button = "system",
    },
    storage = {
      -- Warn when a disk has less than this share free, 0 never.
      low_space = 10,
      -- A popup when a drive is plugged in.
      popup = true,
    },
    proxy = {
      -- none, manual or auto.
      mode = "none",
      http = "", https = "", socks = "", exclude = "localhost,127.0.0.1", pac = "",
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
      -- Lule's picture when `path` was chosen: the setting holds until Lule
      -- makes a new one.
      pin = "",
      -- How the picture fills the screen: crop, fit or stretch, and pictures
      -- that keep their own as `{ path, fit }`.
      fit = "crop",
      fits = {},
      -- A colour painted when there is no picture, and under one that does
      -- not cover the screen ("" for the theme's surface).
      color = "",
      -- `{ output, path }` and `{ workspace, path }`: this screen's or this
      -- workspace's own picture.
      outputs = {},
      workspaces = {},
      -- The pictures for light and for dark ("" for the usual one).
      day = "",
      night = "",
      -- How one picture becomes the next (themes/wallpaper_swap.lua): a kind
      -- or "random", in ms, and how soft its edge is, in pixels.
      transition = { kind = "random", duration = 1100, softness = 24, startup = false },
      -- How far the picture slides across the workspaces, a fraction of the
      -- screen's width.
      parallax = 0,
      -- Pictures taken in turn: seconds between them, "shuffle" or "name",
      -- the folder ("" for `lule.folder`), and whether Lule colours each one.
      slideshow = { on = false, interval = 1800, order = "shuffle", folder = "", recursive = false,
        favourites = false, pause = true, colors = true },
      favourites = {},
      -- What runs after a change; `$WALLPAPER` and `$OUTPUT` are filled in.
      hook = {},
      -- A second picture seen through a hole round the pointer ("" for none).
      xray = "",
      -- The picture brightens with every beat of the music.
      glow = false,
    },
    island = {
      -- A pill out of the top of the frame that morphs between what it shows.
      enabled = false,
    },
    -- The widgets on the desktop (shell/desktop_model.lua): which are shown on
    -- each kind of machine, which small, and where a desk or a tablet has
    -- them, as `{ id, x, y }` in fractions of the screen.
    desktop = {
      widgets = { desk = {}, tablet = {}, phone = {} },
      small = { desk = {}, tablet = {}, phone = {} },
      place = { desk = {}, tablet = {}, phone = {} },
      -- What a widget stands on: "glass", "solid", "none", or "stencil", the
      -- clock's digits cut through a veil onto the picture.
      chrome = "glass",
      -- The clock keeps to the quietest part of the picture.
      quiet_clock = false,
      -- A phone or tablet on charge, turned sideways, is a bedside screen.
      standby = true,
      -- The custom command, run through `sh -c`, and how often, in seconds.
      command = { title = "Command", run = "", interval = 60 },
      -- One line a line; "" for the built-in quotes.
      quotes = "",
      note = "",
      countdown = { title = "", date = "" },
      photo = "",
    },
    bar = {
      -- How many workspace buttons stand on the bar, past the ones in use.
      workspaces = { shown = 5 },
      clock = {
        twelve_hour = false,
        seconds = false,
        -- none, short, day, long or iso; `format` overrides it all with a
        -- strftime pattern of its own.
        date = "short",
        format = "",
        -- A second clock's IANA zone and how it is named.
        zone = "", zone_label = "",
      },
      -- What the Bluetooth popout's "Open settings" starts.
      bluetooth_settings = { "blueman-manager" },
      -- How thick the bar is along a top or bottom edge, 0 for its own size.
      height = 0,
      -- Whether the status writes the battery's percentage.
      percent = true,
      -- The modules along the bar on each kind of machine, zone by zone, in
      -- order; which are drawn as an icon alone. A module the machine lacks
      -- is skipped.
      modules = {
        desk = { start = { "logo", "workspaces", "windows" }, centre = { "live", "clock" },
          ["end"] = { "tray", "privacy", "notifications", "status" } },
        tablet = { start = { "logo", "clock", "workspaces", "windows" }, centre = { "live" },
          ["end"] = { "privacy", "status" } },
        phone = { start = { "clock", "notifications" }, centre = { "live" }, ["end"] = { "privacy", "status" } },
      },
      small = { desk = {}, tablet = {}, phone = { "clock", "notifications" } },
      -- A screen's own choices, by its output's name: `{ name, on, modules,
      -- small }`, `on` being "on", "off" or "" for the bar's own setting and
      -- `modules` this screen's zones, absent to follow the form's.
      outputs = {},
      -- Modules from a command: `{ id, name, icon, command, interval, stream,
      -- tooltip, press, right }`.
      custom = {},
      -- Fixed words for the Text module.
      text = "",
      -- The mount the Disk module reads.
      disk = { mount = "/" },
      -- A date the Countdown module counts to, as YYYY-MM-DD, and its name.
      countdown = { date = "", label = "" },
      -- Where the Updates module finds a flake.lock ("" looks in the usual
      -- places), and what a press on it runs.
      updates = { flake = "", command = {} },
    },
    dashboard = {
      -- Opens when the pointer reaches the top edge over it.
      hover = true,
    },
    sidebar = {
      -- Opens when the pointer reaches the middle of the right edge.
      hover = true,
    },
    -- Which pages each edge's panel holds (shell/pages.lua): a desk's right,
    -- left and bottom panels, and the sheet from the top on a phone or a
    -- tablet. A page moves by moving its key.
    panels = {
      right = { "settings", "notifications" },
      left = { "tasks", "calendar" },
      bottom = { "assistant", "drop" },
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
      -- What each recording runs: `$FILE` is the file to write (in the
      -- folder, named for the time, with its extension), `$REGION` the
      -- selection or the window as WxH+X+Y, `$OUTPUT` the screen, `$FPS` the
      -- frame rate; `~/` and `$HOME` expanded. An empty list runs nothing.
      -- `record_portal` is for a window whose place the compositor keeps.
      commands = {
        record_region = { "gpu-screen-recorder", "-w", "region", "-region", "$REGION", "-f", "$FPS", "-o", "$FILE.mp4" },
        record_window = { "gpu-screen-recorder", "-w", "region", "-region", "$REGION", "-f", "$FPS", "-o", "$FILE.mp4" },
        record_portal = { "gpu-screen-recorder", "-w", "portal", "-f", "$FPS", "-o", "$FILE.mp4" },
        record_screen = { "gpu-screen-recorder", "-w", "$OUTPUT", "-f", "$FPS", "-o", "$FILE.mp4" },
        open = { "xdg-open" },
      },
    },
    launcher = {
      -- How many rows a picker lists, and how many a search may list.
      max_shown = 7,
      max_results = 40,
      action_prefix = ">",
      -- The icon grid: "auto" on a phone or a tablet, "grid" everywhere, "list"
      -- nowhere.
      layout = "auto",
      -- What a plain search reaches, by name (universal.lua).
      sources = { "apps", "settings", "windows", "system", "actions", "app_actions", "places", "modes", "snippets",
        "recent", "bookmarks", "files" },
      -- Whether a plain search goes through the files; folders it leaves out.
      search_files = true,
      exclude = { ".git", "node_modules", ".cache", "target", ".direnv" },
      -- Whether what is picked is remembered, for ranking and history.
      remember = true,
      -- Whether the last search comes back with the launcher.
      keep_query = false,
      -- A pane beside the results for files and pictures, where there is room.
      preview_pane = true,
      -- A trigger typed anywhere expands its snippet (text_expansion.lua).
      expansion = true,
      -- Plugins from ~/.config/eva/plugin (launcher_plugins.lua).
      plugins = true,
      -- The terminal things run in, as words; empty uses $TERMINAL.
      terminal = {},
      -- What the person has pinned, hidden, filed and named.
      favourites = {}, hidden = {}, folders = {}, aliases = {},
      -- Their own search engines ({ bang, name, url }, %s for the words), links
      -- ({ name, url }, {query} for the words) and bookmarks ({ name, url }).
      engines = {}, quicklinks = {}, bookmarks = {},
      -- The language a translation goes to, Wikipedia's language, and the folders
      -- of projects.
      translate_to = "en",
      wiki_language = "en",
      projects = { "~/code", "~/src", "~/projects" },
      -- What `launcher apps` and `launcher web` read.
      menus = {
        -- Folders of AppImages.
        appimages = { "~/Applications", "~/AppImages", "~/.local/share/AppImages" },
        -- The `bookmark` tool's folder.
        bookmarks = "~/.local/share/bookmark",
        -- What plays a playlist's address.
        player = { "mpv" },
      },
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
    airplane = { on = false, was = { wifi = false, bluetooth = false, mobile = false, nfc = false } },
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
    -- Whether touches and gestures buzz (shell/haptics.lua).
    haptics = { on = true },
    -- Gestures anywhere on a touchscreen (shell/touch_driver.lua). `output` names
    -- the screen it sits on where that cannot be told; `commands` holds each
    -- gesture's own command; each form holds what its gestures do.
    gestures = {
      enabled = true,
      output = "",
      commands = require("touch_bindings").commands(),
      desk = require("touch_bindings").defaults("desk"),
      tablet = require("touch_bindings").defaults("tablet"),
      phone = require("touch_bindings").defaults("phone"),
    },
    phone = {
      -- A folder of vCards, and the code bare numbers get: "+31".
      contacts = "~/.local/share/contacts",
      country = "",
      -- Whether a text asks the network to say when it lands.
      delivery_reports = false,
      -- Which public warnings come through: national alerts always do.
      alerts = { extreme = true, severe = true, amber = true, test = false },
      -- Mobile data in a calendar month, in megabytes, before a warning; 0
      -- for none.
      data_limit = 0,
      -- Calls from numbers not in the address book do not ring.
      silence_unknown = false,
      -- What a stranger should know, shown on the lock's emergency pad: blood
      -- type, allergies, medication.
      medical = "",
      -- The power key ends a call that is up.
      power_ends_call = false,
      -- What pressing power twice runs: a command, as a list.
      double_power = {},
      -- Five presses of power count down to an emergency call.
      sos = false,
    },
    -- The shell as the session's polkit agent (polkit.lua): "on", or "off"
    -- to leave the job to another (hyprpolkitagent, polkit-gnome).
    polkit = { agent = "on" },
    keyboard = {
      -- Up by itself when a program asks for text and no real keyboard
      -- is attached (a tablet, a detached keyboard); by hand either way.
      auto = true,
      -- A permanent row of digits over the letters.
      number_row = false,
      -- Language ids from shell/keyboard_layouts.lua, in order; empty takes
      -- the locale's, then English. `layouts` adds languages of your own.
      languages = {},
      language = "",
      layouts = {},
      -- The keys' height, as a multiple, and a gap under them, in pixels.
      height = 1.0,
      bottom_gap = 0,
      -- Word prediction, from the offline lists in shell/assets/words.
      predict = true,
      -- A capital at the start of a sentence.
      autocaps = true,
      -- Two spaces make a full stop.
      double_space = true,
      -- A space after a picked word, and punctuation pulled back over it.
      auto_space = true,
      -- A prediction that spells an emoji's name offers the emoji.
      emoji_names = true,
      -- "today", "now" and "date" offer the date or the time.
      keywords = true,
      -- A strip of what eva-clipboard holds.
      clipboard = true,
      -- A buzz with each key.
      haptics = true,
      -- Replaces a misspelt word on space (README: off by default).
      autocorrect = false,
      -- Remembers typed words on disk to predict them (README: off by default).
      learn = false,
      -- "both", "left" or "right": squeezed to one side for one thumb.
      hand = "both",
      -- Two halves, on a screen wide enough to hold them.
      split = false,
      -- Free of the edge, and where it was left, as fractions of the screen.
      floating = false,
      float_x = 0.5,
      float_y = 0.6,
      -- Shortcuts typed that expand, as { "omw", "on my way" } pairs.
      replacements = {},
      -- A command that listens and prints what it heard, for a microphone
      -- in the strip: empty shows none.
      voice = {},
      -- What a window's class asks of the keyboard, as { "class", "purpose" }
      -- pairs: a purpose from shell/keyboard_model.lua.
      classes = {
        { "kitty", "dev" }, { "foot", "dev" }, { "alacritty", "dev" }, { "wezterm", "dev" }, { "ghostty", "dev" },
        { "org.wezfurlong.wezterm", "dev" }, { "com.mitchellh.ghostty", "dev" },
      },
    },
    services = {
      weather_location = "",
      imperial = false,
    },
    -- The assistant: `provider` is "", "anthropic", "openai" or "ollama"; keys
    -- are in the Secret Service, never here. `folder` keeps the conversations
    -- ("" for the state folder), `history` false keeps none.
    assistant = {
      provider = "",
      anthropic = { base = "https://api.anthropic.com", model = "claude-sonnet-5-5" },
      openai = { base = "https://api.openai.com/v1", model = "" },
      ollama = { base = "http://127.0.0.1:11434", model = "" },
      system = "",
      history = true,
      folder = "",
    },
    -- Quick notes: plain files in this folder.
    notes = { folder = "~/Notes" },
    -- Calendars read besides Taskwarrior: `.ics` files, folders of them (a
    -- vdir among them) and ICS addresses. `lead` is how many minutes before
    -- an event its reminder comes, when the event names none.
    calendar = { files = {}, folders = {}, urls = {}, discover = true, reminders = true, lead = 10 },
    -- eva-update: the flake it reads, or its folder; empty finds /etc/nixos's.
    update = { flake = "" },
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
      -- Seconds a confirmed action counts down in the menu; 0 runs it at once.
      countdown = 5,
      -- Actions left out of the menu and the quick settings, by id.
      hide = {},
      -- Entries of your own after the rest: `{ id, name, icon, command }`.
      custom = {},
      -- What each of the session menu's actions runs (`$USER` is the
      -- user's name).
      commands = {
        lock = { "morf", "lock" },
        logout = { "loginctl", "terminate-user", "$USER" },
        suspend = { "systemctl", "suspend" },
        shutdown = { "systemctl", "poweroff" },
        hibernate = { "systemctl", "hibernate" },
        suspend_hibernate = { "systemctl", "suspend-then-hibernate" },
        reboot = { "systemctl", "reboot" },
      },
    },
    -- The lock screen: models/lock_defaults.lua.
    lock = require("models.lock_defaults"),
    -- Idle: seconds to each stage, 0 for never (shell/idle_model.lua). `dim` is
    -- how long the warning shows before the lock; `battery` overrides a stage
    -- on battery where it is above 0.
    idle = {
      enabled = true,
      lock = 300, blank = 330, suspend = 1800, dim = 10,
      battery = { lock = 0, blank = 0, suspend = 0 },
      -- Window classes that keep the session awake while open.
      apps = {},
      fullscreen = true, media = false, charging = false,
      resume_command = {}, before_sleep = {}, after_sleep = {},
    },
    -- The quick settings' tiles shown on each kind of machine, in order,
    -- and which of them are drawn small. A tile the machine lacks is skipped.
    quick = {
      tiles = {
        desk = { "wifi", "bluetooth", "wired", "mobile", "mesh", "tunnel", "airplane", "hotspot", "sound", "mic",
          "nightlight", "powersaver", "battery", "focus", "theme", "eva", "notes", "linked_phone" },
        tablet = { "wifi", "bluetooth", "rotation", "keyboard", "autobrightness", "airplane", "hotspot", "sound", "mic",
          "nightlight", "powersaver", "battery", "mesh", "tunnel", "focus", "theme", "eva", "notes", "linked_phone" },
        phone = { "wifi", "mobile", "bluetooth", "hotspot", "flashlight", "rotation", "autobrightness", "nfc", "airplane",
          "nightlight", "powersaver", "location", "datasaver", "sound", "mic", "battery", "mesh", "tunnel", "focus",
          "theme", "eva", "camera", "calculator", "voicenote", "alarm", "notes", "linked_phone" },
      },
      small = { desk = {}, tablet = {}, phone = { "flashlight", "rotation", "autobrightness", "nfc", "nightlight",
        "powersaver", "location", "datasaver", "camera", "calculator", "voicenote", "alarm" } },
    },
    -- The night light (hyprsunset): whether it is on, how warm, in kelvin, and
    -- whether the sun at the weather's place turns it on and off.
    nightlight = { on = false, temperature = 4500, follow = false },
    -- The flashlight's strength, 0 to 1 of what the LED can do.
    flashlight = { level = 1 },
    -- The screen following the light sensor.
    autobrightness = { on = false },
    -- Connections marked metered, and which of them were marked here.
    datasaver = { on = false, marked = {} },
    -- Colour filters over the screen; `correction_kind` is protanopia,
    -- deuteranopia or tritanopia, `dim` how much light extra dim leaves.
    filters = { grayscale = false, invert = false, extradim = false, reading = false, correction = false,
      correction_kind = "deuteranopia", dim = 0.4 },
    -- Background sounds: rain, ocean or noise, and how loud, 0 to 1.
    sounds = { kind = "rain", level = 0.4 },
    dock = {
      -- "auto" keeps it down on a desk, and a taskbar on a tablet; "on" puts
      -- it up on a desk; "off" takes it away. A phone never has one.
      enabled = "auto",
      -- bottom, left or right.
      edge = "bottom",
      -- How big an icon is, in logical pixels.
      size = 48,
      -- Icons swell near the pointer.
      magnify = true,
      -- "off", "on", or "windows": it hides only while a window lies under it.
      autohide = "windows",
      -- The taskbar slides away until it is reached for.
      taskbar_hide = false,
      -- Only the windows on this screen.
      isolate = false,
      -- The launcher's and the overview's buttons at its ends.
      buttons = true,
      -- The pinned applications: desktop entry ids, in order.
      pins = {},
    },
    windows = {
      -- What a phone's bottom edge walks: "apps" or "workspaces".
      scrub = "apps",
      -- Each corner's action (shell/hot_corners.lua) and the key it wants held.
      corners = {
        top_left = { action = "none", guard = "", command = {} },
        top_right = { action = "none", guard = "", command = {} },
        bottom_left = { action = "none", guard = "", command = {} },
        bottom_right = { action = "none", guard = "", command = {} },
        -- How long the pointer rests there first, in ms.
        hold = 150,
      },
      -- The other windows are offered for the room a snapped one leaves.
      snap_assist = true,
      -- Leaving a playing video's workspace takes it along, small.
      pip_auto = false,
      -- Each workspace's name and how it tiles, by id.
      workspaces = { names = {}, layouts = {} },
      -- The scratchpads: `name`, `command` to start, `icon`.
      scratchpads = {},
      switcher = {
        -- What Alt+Tab walks: "all", "workspace" or "output".
        scope = "all",
        -- One card per application, with its windows stacked.
        group = true,
      },
    },
    -- Whether the screen keeps its rotation: "on", "off", or "auto" (a desk
    -- keeps it, a phone or a tablet follows the accelerometer).
    rotation = { lock = "auto" },
    -- Charging stops at `limit` percent: 100 for none, 0 leaves the kernel's
    -- as it is. With `adaptive` it waits lower overnight and is done by
    -- `ready`, in minutes after midnight.
    battery = { limit = 0, adaptive = false, ready = 420 },
  },
}
return require("themes.motion_style").link(require("themes.ui_scale").link(config))
