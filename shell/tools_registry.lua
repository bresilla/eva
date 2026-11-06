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
}

return require("page_registry").new(M)
