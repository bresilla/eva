-- All settings: a search box over every page and setting, and the pages by
-- category. The box takes focus as the page comes on show, Enter opens the
-- first result, and leaving the page clears it.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local registry = require("settings_registry")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local rows = require("themes.layouts.rows")
local S = theme.space

local M = {}

local RESULTS = 12
local NAMED = 3

--- The first pages of `category` this machine has, for its row.
function M.names(model, category)
  local names = {}
  for _, entry in ipairs(registry.category(category.id)) do
    if model.page_present(entry.key) then names[#names + 1] = entry.name end
    if #names >= NAMED then break end
  end
  return table.concat(names, ", ")
end

--- One category's pages.
function M.category(model, category, w, h)
  local inner = P.inner(w)
  local section = { id = "settings-pages-" .. category.id, width = w }
  for _, entry in ipairs(registry.category(category.id)) do
    section[#section + 1] = P.row { id = "settings-open-" .. entry.key:gsub("/", "-"), width = inner, icon = entry.icon,
      title = entry.name, subtitle = entry.summary, trailing = P.chevron(),
      visible = function() return model.page_present(entry.key) end,
      on_clicked = function() model.request(entry.key, category.key) end }
  end
  return ui.Item { id = "settings-category-page-" .. category.id, width = w, height = h,
    P.page { id = "settings-" .. category.id .. "-scroll", width = w, height = h, active = model.active,
      P.section(section) } }
end

function M.build(model, w, h)
  local inner = P.inner(w)
  local query = morf.signal("eva.settings.home.query", "")
  -- Each row reads the list: the search itself runs once for what is typed.
  local searched, found = nil, {}
  local function results()
    local typed = query:get()
    if typed ~= searched then searched, found = typed, registry.search(typed) end
    local out = {}
    for _, entry in ipairs(found) do
      if model.page_present(entry.present or entry.key) then out[#out + 1] = entry end
      if #out >= RESULTS then break end
    end
    return out
  end
  local function searching() return query:get():find("%S") ~= nil end
  local box, handle
  local function clear()
    query:set("")
    handle.text = ""
  end
  local function open(entry) model.request(entry.key, registry.HOME) end
  box, handle = P.field { id = "settings-search", kind = "search", width = w, placeholder = "Search settings",
    on_changed = function(value) query:set(value) end,
    on_accepted = function() local first = results()[1] if first then open(first) end end,
    on_escape = clear }

  local hits = F.list(inner, "settings-result-", function() return #results() end, function(index, width)
    local function entry() return results()[index] or {} end
    return P.row { id = "settings-hit-" .. index, width = width, icon = function() return entry().icon or "settings" end,
      title = function() return entry().name or "" end,
      subtitle = function()
        local e = entry()
        return e.page or (registry.BY_KEY[e.key or ""] or {}).summary or ""
      end,
      trailing = P.chevron(), on_clicked = function() open(entry()) end }
  end, "Nothing matches", RESULTS)

  local categories = { id = "settings-categories", width = w, visible = function() return not searching() end }
  for _, category in ipairs(registry.CATEGORIES) do
    categories[#categories + 1] = P.row { id = "settings-category-" .. category.id, width = inner, icon = category.icon,
      title = category.name, subtitle = function() return M.names(model, category) end, trailing = P.chevron(),
      on_clicked = function() open(category) end }
  end

  local page = { id = "settings-home-scroll", width = w, height = h, active = model.active,
    box,
    P.section { id = "settings-results", width = w, title = "Results", visible = searching, hits },
    P.section(categories),
  }

  morf.effect("eva.settings.home.focus", function()
    local on = model.active() == true
    if not on then clear() end
    handle.focus = on
  end)
  return ui.Item { id = "settings-home", width = w, height = h, P.page(page) }
end

--- Every page this machine has, by category: All settings beside a desk's
--- way round, where the categories already stand.
function M.index(model, w, h)
  local inner = P.inner(w)
  local page = { id = "settings-index-scroll", width = w, height = h, active = model.active }
  for _, category in ipairs(registry.CATEGORIES) do
    local section = { id = "settings-index-" .. category.id, width = w, title = category.name }
    for _, entry in ipairs(registry.category(category.id)) do
      section[#section + 1] = P.row { id = "settings-index-open-" .. entry.key:gsub("/", "-"), width = inner,
        icon = entry.icon, title = entry.name, subtitle = entry.summary, trailing = P.chevron(),
        visible = function() return model.page_present(entry.key) end,
        on_clicked = function() model.request(entry.key, category.key) end }
    end
    page[#page + 1] = P.section(section)
  end
  return ui.Item { id = "settings-index", width = w, height = h, P.page(page) }
end

--- The category `key` is filed under, and the page the way round marks for
--- it: the route itself, or the first of its parents a category holds. A
--- category's own page marks no page.
function M.place(key)
  local page = registry.BY_KEY[key]
  while page do
    if page.category then return page.category, page.key end
    for _, category in ipairs(registry.CATEGORIES) do
      if category.key == page.key then return category.id, nil end
    end
    page = page.parent and registry.BY_KEY[page.parent] or nil
  end
end

local NAV_ROW, NAV_PAGE = 40, 34

--- A desk's way round Settings, beside the page: the search over every page
--- and setting, then the categories, the one on show open on its pages.
--- `model`: `detail` (the route), `request`, `page_present`, `searching`
--- (fn: the search takes focus while it holds).
function M.navigation(model, w, h)
  local query = morf.signal("eva.settings.nav.query", "")
  local open = morf.signal("eva.settings.nav.open", "")
  local function route() return model.detail:get() end
  morf.effect("eva.settings.nav.follow", function()
    local category = M.place(route())
    if category then open:set(category) end
  end)
  local searched, found = nil, {}
  local function results()
    local typed = query:get()
    if typed ~= searched then searched, found = typed, registry.search(typed) end
    local out = {}
    for _, entry in ipairs(found) do
      if model.page_present(entry.present or entry.key) then out[#out + 1] = entry end
      if #out >= RESULTS then break end
    end
    return out
  end
  local function searching() return query:get():find("%S") ~= nil end
  local box, handle
  local function clear()
    query:set("")
    handle.text = ""
  end
  local function go(entry) clear() model.request(entry.key, registry.HOME) end
  box, handle = P.field { id = "settings-search", kind = "search", width = w, placeholder = "Search settings",
    on_changed = function(value) query:set(value) end,
    on_accepted = function() local first = results()[1] if first then go(first) end end,
    on_escape = clear }
  local hits = F.list(w, "settings-result-", function() return #results() end, function(index, width)
    local function entry() return results()[index] or {} end
    return P.row { id = "settings-hit-" .. index, width = width, icon = function() return entry().icon or "settings" end,
      title = function() return entry().name or "" end,
      subtitle = function()
        local e = entry()
        return e.page or (registry.BY_KEY[e.key or ""] or {}).summary or ""
      end,
      on_clicked = function() go(entry()) end }
  end, "Nothing matches", RESULTS)

  -- The rows keep clear of the scroll bar at the right.
  local rw = w - S.s
  local function label(text, x, size, ink)
    return kit.menu_label { x = x, width = rw - x - S.xxl, anchors = { vertical_center = true }, elide = "right",
      text = text, font_size = size, color = ink }
  end
  local list = { id = "settings-nav", width = rw, gap = S.xxs, visible = function() return not searching() end }
  local placed = {}
  for _, category in ipairs(registry.CATEGORIES) do
    local function chosen() return route() == category.key end
    local function unfolded() return open:get() == category.id end
    local ink = rows.ink(chosen)
    list[#list + 1] = rows.choice { id = "settings-nav-" .. category.id, width = rw, height = NAV_ROW, on = chosen,
      on_clicked = function()
        if unfolded() and chosen() then open:set("") return end
        open:set(category.id)
        model.request(category.key, registry.HOME)
      end,
      kit.icon(category.icon, 20, ink, { x = S.m, anchors = { vertical_center = true } }),
      label(category.name, S.m + 20 + S.m, theme.size.normal, ink),
      kit.icon(function() return unfolded() and "expand_less" or "expand_more" end, 20, kit.ink("lo"),
        { anchors = { right = true, right_margin = S.s, vertical_center = true } }) }
    placed[category.key] = list[#list]
    for _, entry in ipairs(registry.category(category.id)) do
      local function marked() local _, key = M.place(route()) return key == entry.key end
      local mark = rows.ink(marked)
      list[#list + 1] = rows.choice { id = "settings-nav-page-" .. entry.key:gsub("/", "-"), width = rw,
        height = NAV_PAGE, on = marked,
        visible = function() return unfolded() and model.page_present(entry.key) end,
        on_clicked = function() model.request(entry.key, category.key) end,
        kit.icon(entry.icon, 18, mark, { x = S.m + S.l, anchors = { vertical_center = true } }),
        label(entry.name, S.m + S.l + 18 + S.m, theme.size.small + 1, mark) }
      placed[entry.key] = list[#list]
    end
  end
  local body_h = function() return math.max(1, (type(h) == "function" and h() or h) - 36 - S.m) end
  local scroll, flick = kit.scroll { id = "settings-nav-scroll", width = w, height = body_h, clip = true,
    ui.Column { width = w, gap = S.s, ui.Column(list),
      ui.Column { width = w, gap = P.ROW_GAP, visible = searching, hits } } }
  -- The row the route marks scrolls into sight, once its category has opened.
  morf.effect("eva.settings.nav.reveal", function()
    local category, key = M.place(route())
    local row = placed[key or ""] or placed[category and (registry.HOME .. "/" .. category) or ""]
    if not (row and flick) then return end
    morf.time.timer(theme.duration.small, function()
      local y, rh, at = row.layout_y or 0, row.layout_height or 0, flick.content_y or 0
      if y < at then flick.content_y = y
      elseif y + rh > at + body_h() then flick.content_y = y + rh - body_h() end
    end, false)
  end)
  -- (A turn later: a panel stepping aside hands focus back as it shuts.)
  morf.effect("eva.settings.nav.focus", function()
    local on = model.searching() == true
    if not on then clear() end
    morf.time.timer(1, function() handle.focus = model.searching() == true end, false)
  end)
  return ui.Item { id = "settings-navigation", width = w, height = h, box,
    ui.Item { y = 36 + S.m, width = w, height = body_h, scroll } }
end

return M
