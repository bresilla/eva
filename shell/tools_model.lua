-- The Tools window's book (shell/window_host.lua): its state, its routes and
-- its pages, every tool of shell/tools_registry.lua. A tool's page is built
-- from its folder's page.lua (apps/NAME/page.lua) the first time it opens, and
-- what it reads runs only while it is on show. No scene nodes or geometry.
local morf = require("morf")
local session = require("themes.session")

local M = { name = "tools", title = "Tools", search_hint = "Search tools", page_max = 1040, preload = false,
  forget = true }

M.registry = require("tools_registry")
local HOME = M.registry.HOME

--- Whether the Tools window is open over everything, the page on show, and
--- that page once it has come on show.
M.opened = session.keep("eva.tools.opened", false)
M.detail = session.keep("eva.tools.detail", "")
M.displayed = session.keep("eva.tools.displayed", "")
-- How far a page has been pulled back under a finger, in pixels.
M.peek = morf.signal("eva.tools.peek", 0)

M.DETAILS = {}
for index, page in ipairs(M.registry.PAGES) do
  M.DETAILS[index] = { key = page.key, name = page.name, parent = page.parent }
end
M.navigation = require("lib.shell.settings.pages").new(M.DETAILS, M.detail, nil, "Tools")
M.navigation.on_back = function() require("themes.layouts.page").hold_place() end
function M.breadcrumb() return M.registry.trail(M.navigation.path(M.detail:get())) end

function M.present(key) if key == M.detail:get() then M.displayed:set(key) end end

--- The Tools window open, on the page it shows or on All tools; any other
--- window of pages shuts.
function M.open()
  if M.detail:get() == "" then M.navigation.request(HOME) end
  if M.opened:get() then return end
  require("window_host").only(M)
  M.opened:set(true)
end
--- The Tools window shut.
function M.close() M.opened:set(false) end
--- Opens page `key`, All tools without one; `from` is the page Back returns to.
function M.request(key, from)
  if key == nil or key == "" then key = HOME end
  if not M.navigation.request(key, from) then return false end
  M.open()
  return true
end
--- One page back: its parent, or the page it was opened from, else All tools;
--- from All tools the window shuts.
function M.back()
  local key = M.detail:get()
  if key == "" or key == HOME then M.close() return true end
  M.navigation.back()
  if M.detail:get() == "" then M.navigation.request(HOME) end
  return true
end
function M.page_present() return true end

--- The tools of apps/ whose page is a Settings page, tool -> its route there.
M.SETTINGS = { keys = "input/shortcuts", breaks = "breaks" }

-- The pages of tools built so far, by key, and a count that moves as one is.
local loaded, count, made = {}, 0, morf.signal("eva.tools.made", 0)

--- The module of tool `key`'s page, loaded the first time it is asked for.
function M.page(key)
  local entry = M.registry.BY_KEY[key]
  if not (entry and entry.page) then return nil end
  if not loaded[key] then
    loaded[key] = require(entry.page)
    count = count + 1
    made:set(count)
  end
  return loaded[key]
end

local function active(key) return require("presentation").active("tools." .. key) end
local function home_model(key)
  return { active = active(key), request = M.request, page_present = M.page_present, registry = M.registry,
    name = M.name, search_hint = M.search_hint }
end

--- Page `key`, `w` by `h`: All tools, a category, or a tool.
function M.page_content(key, w, h)
  local home = require("themes").view("settings_home")
  if key == HOME then
    local responsive = require("responsive")
    local sw, sh = responsive.size()
    if require("themes").view("page_window").single(sw, sh, responsive.form() == "phone") then
      return home.build(home_model(key), w, h)
    end
    return home.index(home_model(key), w, h)
  end
  for _, category in ipairs(M.registry.CATEGORIES) do
    if category.key == key then return home.category(home_model(key), category, w, h) end
  end
  return assert(M.page(key), "Unknown Tools page: " .. tostring(key)).build(w, h)
end
function M.has_page(key) return M.registry.BY_KEY[key] ~= nil end
function M.has_actions(key) return (M.registry.BY_KEY[key] or {}).actions == true end
function M.page_actions(key) return M.page(key).actions() end

--- Opens tool `key` at its page, handing it `args` (`eva-disk FOLDER`, a
--- `tel:` or `sms:` link). False for a tool that has no page.
function M.open_tool(key, args)
  local entry = M.registry.BY_KEY[key]
  if not (entry and entry.page) then return false end
  local page = M.page(key)
  if args and #args > 0 and page.open then page.open(args) end
  return M.request(key)
end

--- Calls `verb` of tool `key`'s page with `...`, in Tools or Settings; its
--- page is loaded for it.
function M.verb(key, verb, ...)
  local page = M.page(key) or (M.SETTINGS[key] and require("apps." .. key .. ".page"))
  if not page then error("No such tool: " .. tostring(key)) end
  local handler = (page.verbs or {})[verb]
  if not handler then error(("`%s`: %s has no such verb"):format(tostring(verb), key)) end
  return handler(...)
end

-- Each page built hears whether it is on show; what it reads stops when not.
morf.effect("eva.tools.lifecycle", function()
  made:get()
  local open, key = M.opened:get(), M.displayed:get()
  for name, page in pairs(loaded) do
    if page.shown then page.shown(open and key == name) end
  end
end)
morf.effect("eva.tools.presentation", function()
  local open, key = M.opened:get(), M.displayed:get()
  local presentation = require("presentation")
  presentation.set("tools.detail", open and key ~= "")
  for _, detail in ipairs(M.DETAILS) do presentation.set("tools." .. detail.key, open and key == detail.key) end
end)
require("tools_search").register()

return M
