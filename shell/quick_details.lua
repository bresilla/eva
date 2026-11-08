-- The quick controls' own pages, sliding in over the cards of their panel: a
-- navigation of the panel's own over these keys, apart from the Settings
-- window's, each page built as the panel's own node.
local morf = require("morf")
local session = require("themes.session")
local M = {}

--- The panel's pages; one whose parent is among them goes back to it.
M.KEYS = { "network", "bluetooth", "wired", "mobile", "mesh", "tunnel", "hotspot", "sound", "sounds",
  "microphone", "power", "focus", "focus/mode", "screen_time", "nightlight", "flashlight", "filters" }
local ALIASES = { tor = "tunnel" }

--- The panel's book over the settings model `settings`, which answers for it
--- where it has nothing of its own.
function M.new(settings)
  local book = setmetatable({ name = "quick" }, { __index = settings })
  local held = {}
  for _, key in ipairs(M.KEYS) do held[key] = true end
  book.DETAILS = {}
  for index, key in ipairs(M.KEYS) do
    local page = settings.registry.BY_KEY[key]
    book.DETAILS[index] = { key = key, name = page.name, parent = held[page.parent or ""] and page.parent or nil }
  end
  book.detail = session.keep("eva.settings.quick.detail", "")
  book.displayed = session.keep("eva.settings.quick.displayed", "")
  if book.detail:get() == "tor" then book.detail:set("tunnel") end
  book.navigation = require("lib.shell.settings.pages").new(book.DETAILS, book.detail, ALIASES)
  book.navigation.on_back = function() require("themes.layouts.page").hold_place() end
  book.peek = morf.signal("eva.settings.quick.peek", 0)
  book.breadcrumb = book.navigation.breadcrumb
  book.back = book.navigation.back
  book.opened = settings.quick
  book.close = settings.close_panel

  function book.holds(key) return held[ALIASES[key] or key] == true end
  --- Opens `key`: one of the panel's own over the cards, any other in the window.
  function book.request(key, from)
    if key == nil or key == "" or book.holds(key) then return book.navigation.request(key or "", from) end
    return settings.request(key, from)
  end
  function book.open(key)
    if not book.navigation.request(key or "") then return false end
    local pages = require("pages")
    if not pages.on_show("settings") then pages.open("settings") end
    return true
  end
  --- More settings: the page on show, whole, in the Settings window.
  function book.more()
    local key = book.detail:get()
    if key == "" then return settings.open_home() end
    return settings.request(key)
  end
  function book.present(key) if key == book.detail:get() then book.displayed:set(key) end end
  function book.showing(key) return require("presentation").active("quick." .. key) end
  function book.page_content(key, w, h) return settings.page_content(key, w, h, book) end

  morf.effect("eva.settings.quick.presentation", function()
    local open, key = settings.quick:get(), book.displayed:get()
    local presentation = require("presentation")
    presentation.set("quick.detail", open and key ~= "")
    for _, detail in ipairs(book.DETAILS) do presentation.set("quick." .. detail.key, open and key == detail.key) end
  end)
  return book
end

return M
