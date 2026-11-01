-- What the lock shows and does by default. The shell's settings and the lock
-- both start from this table; everything that could reveal something or let
-- someone in starts off.
return {
  notifications = {
    -- "all", "senders", "count" or "none".
    level = "senders",
    -- "list", or "dots": one mark per app.
    style = "list",
    -- Low-urgency notifications on the lock.
    silent = false,
    -- Only what came in since the last unlock.
    new_only = true,
  },
  status = { battery = true, network = true, bluetooth = true, mode = true },
  -- Which shortcuts stand at the rest screen's corners, in order:
  -- "flashlight", "camera", "media", "command".
  shortcuts = { "flashlight", "camera", "media", "command" },
  -- What Camera opens, after the password.
  camera = { "xdg-open", "camera:" },
  -- The chosen command: `safe` runs it without the password.
  command = { name = "", icon = "terminal", argv = {}, safe = false },
  power_buttons = false,
  -- Widget ids of models.desktop_widgets, in order.
  widgets = {},
  emergency = {
    text = "", name = "", blood = "", allergies = "", medication = "", contact = "",
    -- What the emergency card may dial. Never anything else.
    numbers = { "112", "911" },
  },
  -- Seconds after an idle lock in which any key opens it. Never after sleep.
  grace_seconds = 0,
  -- Lock when the machine sleeps, on a closed lid, and at the shell's start.
  on_suspend = true,
  on_lid = true,
  at_startup = false,
  -- The fingerprint and face readers, and how many misses each may have.
  readers = true,
  reader_tries = 5,
  -- Wrong passwords before the field waits, and for how many seconds.
  attempts = { limit = 5, wait = 30 },
  media = true,
  weather = true,
  avatar = true,
  name = true,
  clock = { position = "centre", size = 1, twelve_hour = false },
  -- "" keeps the desktop's wallpaper.
  wallpaper = "",
  blur = 28,
  tint = 0.4,
  -- A layout the password is always typed in ("" keeps the current one).
  force_layout = "",
  -- Seconds at rest before a locked screen goes dark; 0 keeps it lit.
  blank_after = 60,
  -- "text", or "digits": the on-screen keyboard opens on its number page.
  keypad = "text",
  -- On a phone with an OLED panel the lock can stay lit, dark and dim.
  always_on = { enabled = false, music = true, notifications = true },
}
