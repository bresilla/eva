-- Every page of the Tools window, once: a tool of apps/ each, its route, name,
-- icon, the words it is found by and the category its home files it under.
-- Plain data, no nodes and no signals, so anything may read it; nothing of a
-- tool loads until its page opens.
--
-- `key` is the tool's name, what `morf ipc call tools KEY` and `eva open
-- tools/KEY` take. `page` is the module of apps/ that builds it (`page.lua` in
-- the tool's folder); `actions` marks one with controls for the window's head.
-- A tool that draws over the whole screen has `overlay`: its page holds what
-- it starts with, and starting it shuts the window.
local M = {}

M.HOME = "home"

M.CATEGORIES = {
  { id = "time", name = "Time", icon = "schedule" },
  { id = "text", name = "Text", icon = "text_fields" },
  { id = "screen", name = "Screen", icon = "screenshot_monitor" },
  { id = "system", name = "System", icon = "monitor_heart" },
  { id = "phone", name = "Calls and texts", icon = "call" },
}

M.PAGES = {
  { key = "home", name = "All tools", icon = "handyman", summary = "Every tool, by category",
    keywords = "search find everything" },

  { key = "clock", name = "Clock", icon = "alarm", category = "time", page = "apps.clock.page",
    summary = "Alarms, timers, a stopwatch and world clocks",
    keywords = "alarm timer stopwatch world clock time zone wake ring lap countdown",
    items = { { "Set an alarm", "wake morning ring" }, { "Start a timer", "countdown minutes" },
      { "Stopwatch", "lap time" }, { "World clocks", "city time zone" } } },
  { key = "pomodoro", name = "Pomodoro", icon = "timelapse", category = "time", page = "apps.pomodoro.page",
    summary = "A focus timer of work and breaks", keywords = "focus timer work break tomato session concentrate" },

  { key = "clipboard", name = "Clipboard", icon = "content_paste", category = "text", page = "apps.clipboard.page",
    summary = "History of what was copied", keywords = "copy paste history pin clip" },
  { key = "text", name = "Text", icon = "text_fields", category = "text", page = "apps.text.page",
    summary = "Transforms and generators, for a developer",
    keywords = "scratchpad case upper lower sort json base64 hash sha256 md5 uuid password passphrase lorem encode decode",
    items = { { "Make a password", "passphrase random secret" }, { "Make a UUID", "uuid guid" },
      { "Format JSON", "pretty json" } } },
  { key = "translate", name = "Translate", icon = "translate", category = "text", page = "apps.translate.page",
    summary = "Offline where this machine can", keywords = "language translation argos dictionary" },
  { key = "qr", name = "QR code", icon = "qr_code_2", category = "text", page = "apps.qr.page",
    summary = "A code from text or a Wi-Fi network", keywords = "qr code barcode wifi share link" },

  { key = "monitor", name = "Monitor", icon = "monitor_heart", category = "system", page = "apps.monitor.page",
    actions = true, summary = "Processes, resources and sensors",
    keywords = "task manager process cpu memory gpu sensors temperature kill top htop" },
  { key = "logs", name = "Logs", icon = "receipt_long", category = "system", page = "apps.logs.page", actions = true,
    summary = "The system journal, live", keywords = "journal journalctl log errors systemd unit boot" },
  { key = "disk", name = "Disk usage", icon = "pie_chart", category = "system", page = "apps.disk.page",
    summary = "What takes the room under a folder", keywords = "disk usage space treemap folder size baobab" },
  { key = "webapp", name = "Web apps", icon = "web", category = "system", page = "apps.webapp.page",
    summary = "A site as an app of its own", keywords = "web app site pwa desktop entry browser" },

  { key = "phone", name = "Phone", icon = "call", category = "phone", page = "apps.phone.page",
    summary = "A dial pad, recent calls and contacts", keywords = "call dial contacts recent telephone number" },
  { key = "messages", name = "Messages", icon = "sms", category = "phone", page = "apps.messages.page", actions = true,
    summary = "Text messages, as threads", keywords = "sms text messages threads send" },
}

return require("page_registry").new(M)
