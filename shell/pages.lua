-- The pages a panel can hold, by key. Which panel holds which is a setting
-- (`panels.<edge>`: a list of keys), so a page can move from panel to panel
-- -- Settings, Eva, Panels moves it -- while each page is built the one way.
-- A desk arranges its right, left and bottom panels; a phone or a tablet has
-- the one sheet from the top.
--
-- A page: `name`, `icon`, `build(panel, w, h)` -- `panel` is the side panel
-- model it is built in (its `opened` and `showing`, for a page that works
-- only while it is on show) -- and optionally `fit` (how tall it wants to
-- stand), `tall` (whether it wants all there is, just now) and `typed` (it
-- takes text, so its panel takes the keyboard on a click).
local morf = require("morf")
local config = require("config")
local M = {}

-- A page of the workspace kind (assistant, drop) takes a context: its title,
-- what its connection says, and whether it is on show.
local function workspace(key, title, status)
  return function(panel, w, h)
    local ctx = { key = key, title = title, status = status,
      active = function() return panel.opened:get() and panel.showing(key) end }
    return require(key).build(ctx, w, h)
  end
end

M.all = {
  settings = { name = "Settings", icon = "tune", title_id = "settings-title", build = function(_, w, h) return require("utilities").page(w, h) end,
    fit = function() return require("utilities").fit() end },
  notifications = { name = "Notifications", icon = "notifications", title_id = "sidebar-title",
    build = function(_, w, h) return require("notification_history").build(w, h) end },
  tasks = { name = "Tasks", icon = "checklist", title_id = "tasks-title", typed = true,
    build = function(_, w, h) return require("tasks_page").build(w, h) end,
    tall = function() return require("tasks_page").editing() end },
  calendar = { name = "Calendar", icon = "calendar_month", title_id = "planner-title", typed = true,
    build = function(_, w, h) return require("calendar_page").build(w, h) end },
  assistant = { name = "Assistant", icon = "auto_awesome", title_id = "assistant-title", typed = true,
    build = workspace("assistant", "Assistant", "Not connected"),
    tall = function() return require("assistant_model").state() == "ready" end },
  drop = { name = "Drop", icon = "forum", title_id = "drop-title", typed = true,
    build = workspace("drop", "Drop", "Not connected yet") },
  notes = { name = "Notes", icon = "sticky_note_2", title_id = "notes-title", typed = true,
    build = function(_, w, h) return require("notes_page").build(M.shown("notes"), w, h) end,
    tall = function() return require("notes_model").selected:get() ~= "" end },
  linked_phone = { name = "Linked phone", icon = "smartphone", title_id = "phone-title", typed = true,
    build = function(_, w, h) return require("linked_phone_page").build(M.shown("linked_phone"), w, h) end },
}

-- The order pages are offered in, where order matters and no setting says.
M.ORDER = { "settings", "notifications", "tasks", "calendar", "assistant", "drop", "notes", "linked_phone" }

-- The panel an edge's pages hang in.
local PANELS = { right = "sidebar", left = "leftbar", bottom = "bottom", top = "sidebar" }

--- The sets this form arranges, in the order a page is looked for in them.
function M.edges()
  if require("responsive").sheets() then return { "top" } end
  return { "right", "left", "bottom" }
end

-- Every set as it stands: known keys, each in the first set naming it, and
-- Settings always in one, so the page that moves pages cannot be lost.
local function sets()
  local edges, out, seen = M.edges(), {}, {}
  for _, edge in ipairs(edges) do
    out[edge] = {}
    for _, key in ipairs(config.get("panels." .. edge) or {}) do
      if M.all[key] and not seen[key] then
        seen[key] = true
        out[edge][#out[edge] + 1] = key
      end
    end
  end
  if not seen.settings then table.insert(out[edges[1]], 1, "settings") end
  return out
end

--- The keys the panel on `edge` holds on this form, in order.
function M.keys(edge) return sets()[edge] or {} end

--- The name of the panel holding `key`, or nil while none does.
function M.panel_name(key)
  for edge, keys in pairs(sets()) do
    for _, held in ipairs(keys) do if held == key then return PANELS[edge] end end
  end
end

-- Panels as they are built: one asks after its own pages while it loads.
local built = {}
function M.publish(name, panel) built[name] = panel end

--- The panel holding `key`: its `drawer` and `panel`, or nil.
function M.holder(key)
  local name = M.panel_name(key)
  return name and (built[name] or require(name)) or nil
end

--- `key` on show: its panel selects it and opens. False where no panel holds it.
function M.open(key)
  local holder = M.holder(key)
  if not holder then return false end
  holder.panel.select(key)
  holder.drawer.set(true)
  return true
end

--- Shuts the panel holding `key`.
function M.close(key)
  local holder = M.holder(key)
  if holder then holder.drawer.set(false) end
end

--- Whether `key` is what its panel is showing, open.
function M.on_show(key)
  local holder = M.holder(key)
  return holder ~= nil and holder.drawer.open:get() and holder.panel.showing(key)
end

--- Whether any page that takes text is on show.
function M.typing()
  for key, page in pairs(M.all) do
    if page.typed and M.on_show(key) then return true end
  end
  return false
end

--- A function: whether `key`'s panel has it presented, whichever panel that is.
function M.active(key)
  local presentation = require("presentation")
  return function()
    local name = M.panel_name(key)
    return name ~= nil and presentation.active(name .. "." .. key)()
  end
end

--- `M.active`, for a page that also stands as the settings page of its key.
function M.shown(key)
  local in_panel, in_settings = M.active(key), require("presentation").active("settings." .. key)
  return function() return in_panel() or in_settings() end
end

--- Whether the settings page `route` takes text.
function M.typed_route(route)
  if route == "calendars" or route == "windows/rule" or route == "windows/layouts"
    or require("settings_forms").PAGES[route] then return true end
  return M.all[route] ~= nil and M.all[route].typed == true
end

--- Opens the settings page `route`.
function M.settings(route)
  require("utilities").request(route)
  return M.open("settings")
end

--- `key` on show in the panel that holds it, or as a settings page where none does.
function M.reach(key) return M.open(key) or M.settings(key) end

do
  local KEYWORDS = { settings = "quick tiles toggles", notifications = "history alerts", tasks = "taskwarrior todo",
    calendar = "agenda dates schedule", assistant = "ai chat ask", drop = "share files send", notes = "jot write markdown",
    linked_phone = "phone kde connect android" }
  local index = require("lib.shell.launcher.search_index")
  for key, page in pairs(M.all) do
    index.register { id = "page:" .. key, name = page.name, keywords = KEYWORDS[key], material = page.icon, tag = "Panel",
      description = "Panel", kind = "menu", run = function() return M.reach(key) and "close" or "keep" end }
  end
end

--- The pages the panel on `edge` holds, as side panel tabs (`key`, `name`,
--- `icon`, `fit`, `build(w, h)` once `bind(model)` has given them their
--- panel). `fit()` is how tall a page wants to stand, or nil for all there is.
function M.tabs(edge)
  local tabs, panel = {}, nil
  for _, key in ipairs(M.keys(edge)) do
    local page = M.all[key]
    -- How to read its height, once its frame is built; `framed` moves as
    -- that changes, so what fits to it reads it again.
    local natural
    local framed = morf.signal("eva.pages.framed." .. edge .. "." .. key, 0)
    -- Every page in the one frame: its name over its body
    -- (themes/layouts/page.lua), whatever draws the body.
    tabs[#tabs + 1] = { key = key, name = page.name, icon = page.icon,
      fit = function()
        if page.tall and page.tall() then return nil end
        if page.fit then return page.fit() end
        framed:get()
        return natural and natural() or nil
      end,
      build = function(w, h)
        return require("themes.layouts.page").frame { id = "page-" .. key, width = w, height = h,
          title = page.name, title_id = page.title_id,
          titled = require("responsive").compact() or require("responsive").sheets(),
          -- Its title reads in (where the theme reads titles in) as its
          -- panel shows it.
          active = function() return panel ~= nil and require("presentation").active(panel.id .. "." .. key)() end,
          measured = function(read, gone)
            if not read and natural ~= gone then return end
            natural = read
            framed:set(framed:get() + 1)
          end,
          build = function(bw, bh) return page.build(panel, bw, bh) end }
      end }
  end
  return tabs, function(model) panel = model end
end

return M
