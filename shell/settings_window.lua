-- The Settings window: every page of shell/settings_registry.lua in one shell
-- surface over everything, the rest of the screen dimmed under it. Its pages
-- are utilities.lua's builders and its state is shell/settings_model.lua's
-- (`opened`, `detail`, `request`, `back`, `close`); the selected theme's view
-- lays it out. Escape, a press outside it and its close control shut it.
local morf = require("morf")
local responsive = require("responsive")
local settings = require("utilities")
local M = {}

local phone = responsive.form() == "phone"
local HOME = settings.registry.HOME
local parents = {}
for _, d in ipairs(settings.DETAILS) do parents[d.key] = d.parent or "" end

-- Whether the page on show stands one level into another page, its parent's or
-- the one it was opened from: not All settings, nor a category of it.
local function nested()
  local path = settings.navigation.path(settings.detail:get())
  local above = path[#path - 1]
  return above ~= nil and above.key ~= HOME and parents[above.key] ~= HOME
end

-- What the screen's top keeps for itself on a phone: a cutout there.
local function top()
  local cut = phone and responsive.cutout()
  return cut and cut.y == 0 and cut.height or 0
end

-- An authentication prompt hides the window while it asks, and gives it back.
local covered = morf.signal("eva.settings.window.covered", false)

local ctx = setmetatable({
  phone = phone, size = responsive.size, top = top(),
  covered = function() return covered:get() end,
  -- One page at a time, Back goes up to All settings; beside the way round,
  -- only a page one level into another has a way back.
  nested = nested,
  can_back = function()
    local key = settings.detail:get()
    if phone then return key ~= "" and key ~= HOME end
    return nested()
  end,
  -- The search takes the keys as All settings comes on show.
  searching = function() return settings.opened:get() and settings.detail:get() == HOME end,
}, { __index = settings })

local view = require("themes").view("settings_window").build(ctx)
M.node = view.node

require("themes.kit.popup").track(view.window, {
  open = function() return settings.opened:get() and not covered:get() end,
  close_policy = "escape+outside", except = { require("drawer").keyboard_input },
  on_close = function() settings.close() end,
})
morf.effect("eva.settings.window.keys", function() view.shown(settings.opened:get() and not covered:get()) end)
-- The edges' hover strips stay shut under it.
require("hover").cover(function() return settings.opened:get() end)

-- What else comes up: a prompt that asks for a password covers the window;
-- any other panel opening takes the screen from it. The keyboard and the
-- notifications' popups do neither.
local ASKS = { polkit = true, keyring = true, authsteps = true }
local QUIET = { keyboard = true, notifications = true }
local drawers = require("drawer").all
local was = {}
for _, d in ipairs(drawers) do was[d.name] = d.open:get() end
morf.effect("eva.settings.window.others", function()
  local asking, arrived = false, false
  for _, d in ipairs(drawers) do
    local on = d.open:get()
    if on and ASKS[d.name] then asking = true end
    if on and not was[d.name] and not ASKS[d.name] and not QUIET[d.name] then arrived = true end
    was[d.name] = on
  end
  covered:set(asking)
  if arrived and settings.opened:get() then settings.close() end
end)

-- The Lule studio works while its page is on show.
morf.effect("eva.settings.window.lule", function()
  local on = settings.opened:get() and settings.displayed:get() == "theme/lule"
  local studio = package.loaded.lule_studio or (on and require("lule_studio"))
  if studio and studio.active then studio.active:set(on) end
end)

return M
