-- The home of a window of pages (Settings, Tools): a search box over every page
-- and what each holds, and the pages by category. The box takes focus as the
-- page comes on show, Enter opens the first result, and leaving the page clears
-- it. `model.registry` is the window's book (shell/page_registry.lua) and
-- `model.name` the prefix of its ids, `settings` without one.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local rows = require("themes.layouts.rows")
local S = theme.space

local M = {}

local RESULTS = 12
local NAMED = 3

-- The book, the ids' prefix and the search's hint of `model`.
local function book(model)
  local name = model.name or "settings"
  return model.registry or require("settings_registry"), name, model.search_hint or ("Search " .. name)
end

--- The first pages of `category` this machine has, for its row.
function M.names(model, category)
  local registry = book(model)
  if category.only then return (registry.BY_KEY[category.only] or {}).summary or "" end
  local names = {}
  for _, entry in ipairs(registry.category(category.id)) do
    if model.page_present(entry.key) then names[#names + 1] = entry.name end
    if #names >= NAMED then break end
  end
  return table.concat(names, ", ")
end

--- One category's pages.
function M.category(model, category, w, h)
  local registry, name = book(model)
  local inner = P.inner(w)
  local section = { id = name .. "-pages-" .. category.id, width = w }
  for _, entry in ipairs(registry.category(category.id)) do
    section[#section + 1] = P.row { id = name .. "-open-" .. entry.key:gsub("/", "-"), width = inner, icon = entry.icon,
      title = entry.name, subtitle = entry.summary, trailing = P.chevron(),
      visible = function() return model.page_present(entry.key) end,
      on_clicked = function() model.request(entry.key, category.key) end }
  end
  return ui.Item { id = name .. "-category-page-" .. category.id, width = w, height = h,
    P.page { id = name .. "-" .. category.id .. "-scroll", width = w, height = h, active = model.active,
      P.section(section) } }
end

-- The search over `registry` as typed into `query`: what this machine has, at
-- most RESULTS of it. Each row reads the list; the search runs once per text.
local function finder(model, registry, query)
  local searched, found = nil, {}
  return function()
    local typed = query:get()
    if typed ~= searched then searched, found = typed, registry.search(typed) end
    local out = {}
    for _, entry in ipairs(found) do
      if model.page_present(entry.present or entry.key) then out[#out + 1] = entry end
      if #out >= RESULTS then break end
    end
    return out
  end
end

-- The rows of what the search found, `chevron` at their right.
local function hits(registry, name, width, results, open, chevron)
  return F.list(width, name .. "-result-", function() return #results() end, function(index, row_w)
    local function entry() return results()[index] or {} end
    return P.row { id = name .. "-hit-" .. index, width = row_w, icon = function() return entry().icon or "settings" end,
      title = function() return entry().name or "" end,
      subtitle = function()
        local e = entry()
        return e.page or (registry.BY_KEY[e.key or ""] or {}).summary or ""
      end,
      trailing = chevron and P.chevron() or nil, on_clicked = function() open(entry()) end }
  end, "Nothing matches", RESULTS)
end

function M.build(model, w, h)
  local registry, name, hint = book(model)
  local inner = P.inner(w)
  local query = morf.signal("eva." .. name .. ".home.query", "")
  local results = finder(model, registry, query)
  local function searching() return query:get():find("%S") ~= nil end
  local box, handle
  local function clear()
    query:set("")
    handle.text = ""
  end
  local function open(entry) model.request(entry.key, registry.HOME) end
  box, handle = P.field { id = name .. "-search", kind = "search", width = w, placeholder = hint,
    on_changed = function(value) query:set(value) end,
    on_accepted = function() local first = results()[1] if first then open(first) end end,
    on_escape = clear }

  local categories = { id = name .. "-categories", width = w, visible = function() return not searching() end }
  for _, category in ipairs(registry.CATEGORIES) do
    categories[#categories + 1] = P.row { id = name .. "-category-" .. category.id, width = inner, icon = category.icon,
      title = category.name, subtitle = function() return M.names(model, category) end, trailing = P.chevron(),
      visible = function() return M.has(model, category) end,
      on_clicked = function() M.go(model, category) end }
  end

  local page = { id = name .. "-home-scroll", width = w, height = h, active = model.active,
    box,
    P.section { id = name .. "-results", width = w, title = "Results", visible = searching,
      hits(registry, name, inner, results, open, true) },
    P.section(categories),
  }

  morf.effect("eva." .. name .. ".home.focus", function()
    local on = model.active() == true
    if not on then clear() end
    handle.focus = on
  end)
  return ui.Item { id = name .. "-home", width = w, height = h, P.page(page) }
end

--- Every page this machine has, by category: the home beside a desk's way
--- round, where the categories already stand.
function M.index(model, w, h)
  local registry, name = book(model)
  local inner = P.inner(w)
  local page = { id = name .. "-index-scroll", width = w, height = h, active = model.active }
  for _, category in ipairs(registry.CATEGORIES) do
    local section = { id = name .. "-index-" .. category.id, width = w, title = category.name }
    for _, entry in ipairs(registry.category(category.id)) do
      section[#section + 1] = P.row { id = name .. "-index-open-" .. entry.key:gsub("/", "-"), width = inner,
        icon = entry.icon, title = entry.name, subtitle = entry.summary, trailing = P.chevron(),
        visible = function() return model.page_present(entry.key) end,
        on_clicked = function() model.request(entry.key, category.key) end }
    end
    page[#page + 1] = P.section(section)
  end
  return ui.Item { id = name .. "-index", width = w, height = h, P.page(page) }
end

--- The category `key` is filed under in `registry` (Settings' without one),
--- and the page the way round marks for it: the route itself, or the first of
--- its parents a category holds. A category's own page marks no page.
function M.place(key, registry)
  registry = registry or require("settings_registry")
  local page = registry.BY_KEY[key]
  while page do
    if page.category then return page.category, page.key end
    for _, category in ipairs(registry.CATEGORIES) do
      if category.key == page.key then return category.id, nil end
    end
    page = page.parent and registry.BY_KEY[page.parent] or nil
  end
end

-- A row of the way round: a pointer's target, a finger's on a touchscreen.
local function nav_row() return require("responsive").touch() and S.TOUCH or S.TARGET end

--- Whether this machine has any of `category`'s pages.
function M.has(model, category)
  local registry = book(model)
  for _, entry in ipairs(registry.category(category.id)) do
    if model.page_present(entry.key) then return true end
  end
  return false
end

--- Opens `category`: its one page, or the list of its pages.
function M.go(model, category)
  local registry = book(model)
  model.request(registry.entry and registry.entry(category) or category.key, registry.HOME)
end

--- A desk's way round the window, beside the page: the search over every page
--- and what each holds, then the categories, still and in one list, the one
--- holding the page on show marked. `model`: `detail` (the route), `request`,
--- `page_present`, `searching` (fn: the search takes focus while it holds).
function M.navigation(model, w, h)
  local row_h = nav_row()
  local registry, name, hint = book(model)
  local query = morf.signal("eva." .. name .. ".nav.query", "")
  local function route() return model.detail:get() end
  local function place(key) return M.place(key, registry) end
  local results = finder(model, registry, query)
  local function searching() return query:get():find("%S") ~= nil end
  local box, handle
  local function clear()
    query:set("")
    handle.text = ""
  end
  local function go(entry) clear() model.request(entry.key, registry.HOME) end
  box, handle = P.field { id = name .. "-search", kind = "search", width = w - S.s, placeholder = hint,
    on_changed = function(value) query:set(value) end,
    on_accepted = function() local first = results()[1] if first then go(first) end end,
    on_escape = clear }
  local found = hits(registry, name, w, results, go, false)

  -- The rows keep clear of the scroll bar at the right.
  local rw = w - S.s
  local function label(text, x, size, ink)
    return kit.menu_label { x = x, width = rw - x - S.xxl, anchors = { vertical_center = true }, elide = "right",
      text = text, font_size = size, color = ink }
  end
  local list = { id = name .. "-nav", width = rw, gap = S.xxs, visible = function() return not searching() end }
  local placed = {}
  for _, category in ipairs(registry.CATEGORIES) do
    local function chosen() return place(route()) == category.id end
    local ink = rows.ink(chosen)
    list[#list + 1] = rows.choice { id = name .. "-nav-" .. category.id, width = rw, height = row_h, on = chosen,
      group = name .. "-nav", visible = function() return M.has(model, category) end,
      on_clicked = function() M.go(model, category) end,
      kit.icon(category.icon, 20, ink, { x = S.m, anchors = { vertical_center = true } }),
      label(category.name, S.m + 20 + S.m, theme.size.normal, ink) }
    placed[category.id] = list[#list]
  end
  local body_h = function() return math.max(1, (type(h) == "function" and h() or h) - 36 - S.m) end
  local scroll, flick = kit.scroll { id = name .. "-nav-scroll", width = w, height = body_h, clip = true,
    ui.Column { width = w, gap = S.s, ui.Column(list),
      ui.Column { width = w, gap = P.ROW_GAP, visible = searching, found } } }
  -- The row the route marks scrolls into sight, where the window is too short
  -- for every category: its place counted from the rows above it.
  local function offset(id)
    local y = 0
    for _, category in ipairs(registry.CATEGORIES) do
      if category.id == id then return y end
      if M.has(model, category) then y = y + row_h + S.xxs end
    end
  end
  morf.effect("eva." .. name .. ".nav.reveal", function()
    local id = place(route())
    if not (id and placed[id] and flick) then return end
    morf.time.timer(theme.duration.small, function()
      local y, at = offset(id), flick.content_y or 0
      local view = flick.layout_height or body_h()
      if not y or view <= 0 then return end
      if y < at then flick.content_y = y
      elseif y + row_h > at + view then flick.content_y = y + row_h - view end
    end, false)
  end)
  -- (A turn later: a panel stepping aside hands focus back as it shuts.)
  morf.effect("eva." .. name .. ".nav.focus", function()
    local on = model.searching() == true
    if not on then clear() end
    morf.time.timer(1, function() handle.focus = model.searching() == true end, false)
  end)
  return ui.Item { id = name .. "-navigation", width = w, height = h, box,
    ui.Item { y = 36 + S.m, width = w, height = body_h, scroll } }
end

return M
