-- All settings: a search box over every page and setting, and the pages by
-- category. The box takes focus as the page comes on show, Enter opens the
-- first result, and leaving the page clears it.
local morf = require("morf")
local ui = require("morf.ui")
local registry = require("settings_registry")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")

local M = {}

local RESULTS = 12

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
      if model.page_present(entry.key) then out[#out + 1] = entry end
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

  local page = { id = "settings-home-scroll", width = w, height = h, active = model.active,
    box,
    P.section { id = "settings-results", width = w, title = "Results", visible = searching, hits },
  }
  for _, category in ipairs(registry.CATEGORIES) do
    local section = { id = "settings-category-" .. category.id, caption_id = "settings-category-title-" .. category.id,
      width = w, title = category.name, visible = function() return not searching() end }
    for _, entry in ipairs(registry.category(category.id)) do
      section[#section + 1] = P.row { id = "settings-open-" .. entry.key:gsub("/", "-"), width = inner, icon = entry.icon,
        title = entry.name, subtitle = entry.summary, trailing = P.chevron(),
        visible = function() return model.page_present(entry.key) end,
        on_clicked = function() open(entry) end }
    end
    page[#page + 1] = P.section(section)
  end

  morf.effect("eva.settings.home.focus", function()
    local on = model.active() == true
    if not on then clear() end
    handle.focus = on
  end)
  return ui.Item { id = "settings-home", width = w, height = h, P.page(page) }
end

return M
