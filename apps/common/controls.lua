-- What a tool's window is built from, over the kit: pages that slide on the
-- theme's spring, a list that scrolls a pool of rows, a search field, a line of
-- news, and cards that are layers of one distance field, as the dashboard's are.
-- Nothing here chooses a look: the theme's kit draws all of it.
--
--     local controls = require("common.controls")
--     controls.pages { id = "clock", width = w, height = h, tabs = {
--       { key = "alarms", name = "Alarms", icon = "alarm",
--         build = function(page_w, page_h) return node end },
--     } }
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local L = require("themes.layouts.parts")
local S = theme.space

local M = {}

M.TABS_H = 64
M.ROW_H = 56

local function get(v) if type(v) == "function" then return v() end return v end

--- Tabs over pages side by side, the row of pages sliding on the theme's
--- spring: `id`, `width`, `height` (fns), `tab` (a signal, from 1), `tabs`
--- (`{ key, name, icon, build(w, h) }`). Returns the node, and the signal.
function M.pages(spec)
  local w, h = spec.width, spec.height
  local tab = spec.tab or morf.signal("eva.app." .. spec.id .. ".tab", 1)
  local function page_h() return math.max(1, get(h) - M.TABS_H - S.s) end
  local row = {
    id = spec.id .. "-pages", height = page_h,
    width = function() return get(w) * #spec.tabs end,
    x = function() return -(tab:get() - 1) * get(w) end,
    behavior = { x = theme.spring.slow },
  }
  for index, entry in ipairs(spec.tabs) do
    row[#row + 1] = ui.Item {
      id = spec.id .. "-page-" .. entry.key, width = w, height = page_h,
      x = function() return (index - 1) * get(w) end,
      opacity = function() return tab:get() == index and 1 or 0 end,
      behavior = { opacity = theme.spring.effects },
      entry.build(w, page_h),
    }
  end
  return ui.Item {
    id = spec.id .. "-paged", width = w, height = h,
    kit.tabs { id = spec.id, tabs = spec.tabs, tab = tab, width = w, height = M.TABS_H },
    ui.Item { y = M.TABS_H + S.s, width = w, height = page_h, clip = true, ui.Item(row) },
  }, tab
end

--- One choice of a few, the kit's segmented control, its mark travelling on the
--- theme's field: `id`, `width`, `items` (labels), `current` (fn, from 1),
--- `on_changed(index)`.
function M.segments(spec)
  local count = #get(spec.items)
  return kit.widgets.segmented {
    id = spec.id, items = spec.items, current = spec.current, width = spec.width, height = S.TARGET,
    item_width = function() return get(spec.width) / count end, item_height = S.TARGET,
    on_current_changed = spec.on_changed,
  }
end

--- A search field, or any line of text kept in `value` (a signal): `id`,
--- `width`, `placeholder`, `focus`, `on_accepted`.
function M.entry(spec)
  return kit.text_field(spec.kind or "entry", {
    id = spec.id, width = spec.width, height = S.TARGET, placeholder = spec.placeholder,
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"), focus = spec.focus,
    text = function() return spec.value:get() end,
    on_text_changed = function(value) spec.value:set(value) end,
    on_accepted = spec.on_accepted,
  })
end

--- A line of news under a tool's controls: `id`, `width`, `text` (fn).
function M.note(spec)
  return kit.text {
    id = spec.id, width = spec.width, height = L.lh(theme.size.small), font_size = theme.size.small,
    color = kit.ink("lo"), elide = "right", text = spec.text,
  }
end

--- A list that scrolls: `id`, `width`, `height`, `count` (the rows kept, the
--- most it shows), `row_height`, `gap`, `items` (fn: the list), `build(index,
--- item, row_w)` (a row, `item` a fn giving its entry or nil).
function M.list(spec)
  local column = { width = spec.width, gap = spec.gap or S.xxs }
  local row_h = spec.row_height or M.ROW_H
  for index = 1, spec.count do
    local function item() return spec.items()[index] end
    column[index] = ui.Item {
      id = spec.id .. "-row-" .. index, width = spec.width, height = row_h,
      visible = function() return item() ~= nil end,
      spec.build(index, item, spec.width),
    }
  end
  return (kit.scroll { id = spec.id, width = spec.width, height = spec.height, clip = true, ui.Column(column) })
end

--- Cards made inside `build()` as layers of one field, under what `build`
--- returns: as they touch or pass they join on the theme's seam. `id`, `width`,
--- `height`, `blend` (the seam, the theme's by default). Holds at most sixteen
--- cards, the engine's limit on a field.
function M.cards(spec, build)
  local list = {}
  kit.collect(list)
  local ok, content = pcall(build)
  kit.collect(nil)
  if not ok then error(content, 0) end
  local field = { id = spec.id .. "-cards", anchors = { fill = true }, blend = spec.blend or theme.SEAM / 2,
    blend_profile = "circular" }
  for index, entry in ipairs(list) do
    if index <= 16 then field[#field + 1] = entry.shape end
  end
  return ui.ClipRect {
    id = spec.id .. "-cards-clip", width = spec.width, height = spec.height, color = "transparent",
    ui.Sdf(field),
    content,
  }
end

return M
