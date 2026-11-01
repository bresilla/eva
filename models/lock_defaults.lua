-- What the lock shows and does by default; shell/config.lua and the lock read
-- this. Everything that could reveal something or let someone in starts off.
return {
  -- `level`: "all", "senders", "count" or "none". `style`: "list" or "dots".
  notifications = { level = "senders", style = "list", silent = false, new_only = true },
  status = { battery = true, network = true, bluetooth = true, mode = true },
  -- In order: "flashlight", "camera", "media", "command".
  shortcuts = { "flashlight", "camera", "media", "command" },
  camera = { "xdg-open", "camera:" },
  -- `safe` runs it without the password.
  command = { name = "", icon = "terminal", argv = {}, safe = false },
  power_buttons = false,
  -- Ids of models.desktop_widgets.
  widgets = {},
  emergency = {
    text = "", name = "", blood = "", allergies = "", medication = "", contact = "",
    numbers = { "112", "911" },
  },
  -- Seconds after an idle lock in which any key opens it.
  grace_seconds = 0,
  on_suspend = true,
  on_lid = true,
  at_startup = false,
  readers = true,
  reader_tries = 5,
  attempts = { limit = 5, wait = 30 },
  media = true,
  weather = true,
  avatar = true,
  name = true,
  clock = { position = "centre", size = 1, twelve_hour = false },
  wallpaper = "",
  blur = 28,
  tint = 0.4,
  force_layout = "",
  -- Seconds at rest before a locked screen goes dark; 0 keeps it lit.
  blank_after = 60,
  -- "text", or "digits" for the on-screen keyboard's number pad.
  keypad = "text",
  -- With "digits", a pad whose digits change places each time it comes up.
  scramble = false,
  always_on = { enabled = false, music = true, notifications = true },
}
