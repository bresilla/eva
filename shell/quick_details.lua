-- The quick controls' own pages, in the panel holding the quick controls: what
-- a tile's ">" opens, sliding in over the cards. The panel has a navigation of
-- its own over these keys alone, apart from the Settings window's
-- (shell/settings_model.lua), and builds its own node of each page. A page's
-- way to the whole of it, and what it links to beyond these, open in the
-- Settings window.
local morf = require("morf")
local session = require("themes.session")
local M = {}

--- The panel's pages, in order; one whose parent is among them goes back to it.
M.KEYS = { "network", "bluetooth", "wired", "mobile", "mesh", "tunnel", "hotspot", "sound", "sounds",
  "microphone", "power", "focus", "focus/mode", "screen_time", "nightlight", "flashlight", "filters" }
local ALIASES = { tor = "tunnel" }

--- The panel's book over `settings`, the settings model. It answers for the
--- settings model where it has nothing of its own, so a page built in the panel
--- reads its controls; its requests stay in the panel for its own pages.
function M.new(settings)
  local book = setmetatable({ name = "quick" }, { __index = settings })
  local held = {}
  for _, key in ipairs(M.KEYS) do held[key] = true end
  book.DETAILS = {}
  for index, key in ipairs(M.KEYS) do
    local page = settings.registry.BY_KEY[key]
    book.DETAILS[index] = { key = key, name = page.name, parent = held[page.parent or ""] and page.parent or nil }
  end
  --- The page over the cards ("" for none), and the one drawn there.
  book.detail = session.keep("eva.settings.quick.detail", "")
  book.displayed = session.keep("eva.settings.quick.displayed", "")
  if book.detail:get() == "tor" then book.detail:set("tunnel") end
  book.navigation = require("lib.shell.settings.pages").new(book.DETAILS, book.detail, ALIASES)
  book.navigation.on_back = function() require("themes.layouts.page").hold_place() end
  -- How far a page has been pulled back under a finger, in pixels.
  book.peek = morf.signal("eva.settings.quick.peek", 0)
  book.breadcrumb = book.navigation.breadcrumb
  book.back = book.navigation.back
  book.opened = settings.quick
  book.close = settings.close_panel

  --- Whether `key` is one of the panel's own pages.
  function book.holds(key) return held[ALIASES[key] or key] == true end
  --- Opens `key`: one of the panel's own over the cards ("" back to them), any
  --- other in the Settings window; `from` is the page Back returns to.
  function book.request(key, from)
    if key == nil or key == "" or book.holds(key) then return book.navigation.request(key or "", from) end
    return settings.request(key, from)
  end
  --- The panel open on `key`, one of its own, or on its cards without one.
  function book.open(key)
    if not book.navigation.request(key or "") then return false end
    local pages = require("pages")
    if not pages.on_show("settings") then pages.open("settings") end
    return true
  end
  --- The page on show, whole, in the Settings window: the panel steps aside.
  function book.more()
    local key = book.detail:get()
    if key == "" then return settings.open_home() end
    return settings.request(key)
  end
  function book.present(key) if key == book.detail:get() then book.displayed:set(key) end end
  --- A function: whether the panel has page `key` on show.
  function book.showing(key) return require("presentation").active("quick." .. key) end
  --- Page `key` as the panel builds it, its own node.
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
