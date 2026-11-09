-- A window of pages over the shell, the rest of the screen dimmed under it:
-- Settings and Tools are each one, on a book of their own. A book is the
-- model of one window, its state and its pages:
--
--   name, title            the ids' prefix ("settings") and what it is called
--   registry               its pages (shell/page_registry.lua)
--   DETAILS, navigation    the routes and their tree (lib/shell/settings/pages.lua)
--   opened, detail, displayed, peek    signals: open, the route, the route on
--                          show, how far a page is pulled back
--   open, close, request(key, from), back, present(key), breadcrumb
--   page_content(key, w, h), page_present(key)
--   has_actions(key), page_actions(key), page_max, preload   optional
--
-- The selected theme's `page_window` view lays it out. Escape, a press outside
-- it and its close control shut it; one window is open at a time.
local morf = require("morf")
local responsive = require("responsive")
local M = {}

local books = {}

--- Shuts every window but `book`'s, as it opens.
function M.only(book)
  for _, other in ipairs(books) do
    if other ~= book and other.opened:get() then other.close() end
  end
end

--- The window of `book`: `node` (the whole screen, for the frame's `above`
--- layer), `dismiss()` (shuts it on every screen), `screen` (the shared name of
--- the screen holding it, "" for none) and `where()`.
function M.new(book)
  books[#books + 1] = book
  local name = book.name
  local phone = responsive.form() == "phone"
  local HOME = book.registry.HOME
  local listing = {}
  for _, category in ipairs(book.registry.CATEGORIES or {}) do listing[category.key] = true end

  -- Whether the page on show stands one level into another page, its parent's
  -- or the one it was opened from: not the home, nor a category's list.
  local function nested()
    local path = book.navigation.path(book.detail:get())
    local above = path[#path - 1]
    return above ~= nil and above.key ~= HOME and not listing[above.key]
  end

  -- What the screen's top keeps for itself on a phone: a cutout there.
  local function top()
    local cut = phone and responsive.cutout()
    return cut and cut.y == 0 and cut.height or 0
  end

  -- An authentication prompt hides the window while it asks, and gives it back.
  local covered = morf.signal("eva." .. name .. ".window.covered", false)

  -- The screen the window is open on, for every screen's runtime: "" with
  -- none. The others dim while it is open, and a press on their dim shuts it.
  local holder = morf.shared("eva." .. name .. ".window.screen", "")
  local me = require("focused").output()
  if me == "" then me = "here" end
  local function elsewhere()
    local screen = holder:get()
    return screen ~= "" and screen ~= me
  end

  local ctx = setmetatable({
    phone = phone, size = responsive.size, top = top(),
    covered = function() return covered:get() end,
    elsewhere = elsewhere,
    dismiss = function() book.close() holder:set("") end,
    -- One page at a time, Back goes up to the home; beside the way round,
    -- only a page one level into another has a way back.
    nested = nested,
    can_back = function()
      local key = book.detail:get()
      if phone then return key ~= "" and key ~= HOME end
      return nested()
    end,
    -- The search takes the keys as the home comes on show.
    searching = function() return book.opened:get() and book.detail:get() == HOME end,
  }, { __index = book })

  local view = require("themes").view("page_window").build(ctx)
  local host = { node = view.node, dismiss = ctx.dismiss, screen = holder, book = book }
  --- Whether the window is open on this screen, or on none, or on another.
  function host.where()
    local screen = holder:get()
    if screen == "" then return "none" end
    return screen == me and "here" or "elsewhere"
  end

  require("themes.kit.popup").track(view.window, {
    open = function() return book.opened:get() and not covered:get() end,
    close_policy = "escape+outside", except = { require("drawer").keyboard_input },
    on_close = function() book.close() end,
  })
  morf.effect("eva." .. name .. ".window.keys", function() view.shown(book.opened:get() and not covered:get()) end)
  -- The edges' hover strips stay shut under it, and under the dim.
  require("hover").cover(function() return book.opened:get() or elsewhere() end)

  -- Opening here takes the window from any other screen; shutting it here, or
  -- a press on another screen's dim, lets every screen go.
  if book.opened:get() then holder:set(me) end
  local was_open, was_holder = book.opened:get(), holder:get()
  morf.effect("eva." .. name .. ".window.screens", function()
    local open, screen = book.opened:get(), holder:get()
    if open and not was_open then holder:set(me)
    elseif not open and was_open then
      if screen == me then holder:set("") end
    elseif open and screen ~= was_holder and screen ~= me then book.close() end
    was_open, was_holder = open, screen
  end)

  -- What else comes up: a prompt that asks for a password covers the window;
  -- any other panel opening takes the screen from it. The keyboard and the
  -- notifications' popups do neither.
  local ASKS = { polkit = true, keyring = true, authsteps = true }
  local QUIET = { keyboard = true, notifications = true }
  local drawers = require("drawer").all
  local was = {}
  for _, d in ipairs(drawers) do was[d.name] = d.open:get() end
  morf.effect("eva." .. name .. ".window.others", function()
    local asking, arrived = false, false
    for _, d in ipairs(drawers) do
      local on = d.open:get()
      if on and ASKS[d.name] then asking = true end
      if on and not was[d.name] and not ASKS[d.name] and not QUIET[d.name] then arrived = true end
      was[d.name] = on
    end
    covered:set(asking)
    if arrived and book.opened:get() then book.close() end
  end)

  return host
end

return M
