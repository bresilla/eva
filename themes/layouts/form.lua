-- The controls a settings page is written with, over the page template
-- (themes/layouts/page.lua): a switch row, a stepped slider, a set of choices,
-- a row that leads somewhere, a note, a searchable list. They hold no state
-- of their own but what a field is typing.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local C = theme.color
local S = theme.space

local F = {}

local function get(v) if type(v) == "function" then return v() end return v end

--- A row with a switch: `id`, `width`, `icon`, `title`, `subtitle`, `on`
--- (fn), `set(on)`, `enabled`, `visible`.
function F.toggle(spec)
  return P.row { id = spec.id, width = spec.width, icon = spec.icon, title = spec.title, subtitle = spec.subtitle,
    on = spec.on, visible = spec.visible,
    trailing = P.switch { id = spec.id .. "-switch", name = spec.name or get(spec.title), on = spec.on,
      enabled = spec.enabled, on_toggled = spec.set } }
end

--- A row that opens something: `id`, `width`, `icon`, `title`, `subtitle`,
--- `go`, `visible`.
function F.link(spec)
  return P.row { id = spec.id, width = spec.width, icon = spec.icon, title = spec.title, subtitle = spec.subtitle,
    trailing = P.chevron(), on_clicked = spec.go, visible = spec.visible }
end

--- A row to another Settings page, named, drawn and summed up as the page
--- itself is: `id`, `width`, `key`, `go`, `visible`; `subtitle` overrides.
function F.page(spec)
  local page = require("settings_registry").BY_KEY[spec.key] or {}
  return F.link { id = spec.id, width = spec.width, icon = page.icon, title = page.name or spec.key,
    subtitle = spec.subtitle or page.summary, go = spec.go, visible = spec.visible }
end

--- A line of facts: icon, title and a reading, nothing to press.
function F.fact(spec)
  return P.row { id = spec.id, width = spec.width, icon = spec.icon, title = spec.title, subtitle = spec.subtitle,
    on = function() return false end, trailing = spec.trailing, visible = spec.visible }
end

--- Words under a section's controls, wrapped to `width`: `id`, `text`,
--- `color`, `visible`.
-- A note of one sentence reads as a caption, without its full stop; one of
-- several keeps every stop.
local function caption_of(text)
  if type(text) ~= "string" or text:find("[%.!?] ") or text:find("%.%.%.$") then return text end
  return (text:gsub("%.$", ""))
end

function F.note(width, text, spec)
  spec = spec or {}
  local said = caption_of(text)
  local node = kit.subtitle { id = spec.id, width = width, wrap = true, font_size = P.SUB, text = said,
    color = spec.color or kit.ink("lo") }
  if spec.visible then node.visible = spec.visible end
  return node
end

--- A field under its name: `id`, `width`, `label`, then P.field's `kind`,
--- `text`, `placeholder`, `on_changed`, `on_accepted`, `on_escape`, `visible`.
--- Returns the node and the input.
function F.field(spec)
  local box, input = P.field { id = spec.id, width = spec.width, kind = spec.kind, text = spec.text,
    placeholder = spec.placeholder, name = spec.name or spec.label, on_changed = spec.on_changed,
    on_accepted = spec.on_accepted, on_escape = spec.on_escape }
  return ui.Column { width = spec.width, gap = S.xs, visible = spec.visible, F.note(spec.width, spec.label), box }, input
end

--- `node` dimmed while the switch it serves, `on` (fn), is off: it still sets
--- what the feature takes up once on.
function F.waiting(node, on, visible)
  return ui.Column { visible = visible, opacity = function() return on() and 1 or 0.45 end,
    behavior = { opacity = { duration = theme.duration.small } }, node }
end

--- What the last action said, in the error colour when it failed. `model`
--- has `message` and `failed` signals.
function F.status(id, width, model)
  return F.note(width, function() return model.message:get() or "" end, { id = id,
    visible = function() return (model.message:get() or "") ~= "" end,
    color = function() return model.failed:get() and C.error or C.onSurfaceVariant end })
end

--- A slider over a numeric range under its name: `id`, `width`, `icon`,
--- `name`, `from`, `to`, `step`, `value` (fn), `set(v)`, `format(v)`.
function F.slider(spec)
  local from, to, step = spec.from, spec.to, spec.step or 0
  local span = to - from
  local function snapped(position)
    local v = from + position * span
    if step > 0 then v = from + math.floor((v - from) / step + 0.5) * step end
    return math.max(from, math.min(to, v))
  end
  local node = kit.slider { id = spec.id, accessible_name = spec.name, width = spec.width, height = spec.height,
    icon = spec.icon,
    value = function() return math.max(0, math.min(1, ((tonumber(get(spec.value)) or from) - from) / span)) end,
    set = function(position) spec.set(snapped(position)) end,
    reading = function(position)
      local v = snapped(position)
      return spec.format and spec.format(v) or tostring(v)
    end }
  return ui.Column { width = spec.width, gap = S.xs, visible = spec.visible,
    F.note(spec.width, spec.name, { id = spec.id .. "-name" }), node }
end

--- Choices sharing `width`, `per_row` to a row: `id` (each is `<id>-<key>`),
--- `items` ({ key, icon, name }), `now` (fn), `pick(key)`, `enabled`,
--- `visible`.
function F.choices(spec)
  -- One count across every row, so no row wraps on its own.
  local labels = {}
  for i, item in ipairs(spec.items) do labels[i] = item[3] end
  local wanted = math.min(spec.per_row or 4, #spec.items)
  local per_row = P.fit(spec.width, labels, wanted)
  if per_row < wanted then
    for f = per_row, 2, -1 do if #spec.items % f == 0 then per_row = f break end end
  end
  local lines = { width = spec.width, gap = S.s, visible = spec.visible }
  local row
  for index, item in ipairs(spec.items) do
    if (index - 1) % per_row == 0 then
      row = { width = spec.width }
      lines[#lines + 1] = row
    end
    row[#row + 1] = { id = spec.id .. "-" .. tostring(item[1]):gsub("[^%w_%-]", "-"), icon = item[2], label = item[3],
      group = spec.id, enabled = spec.enabled, accessible_name = item[3],
      selected = function() return spec.now() == item[1] end, on_clicked = function() spec.pick(item[1]) end }
  end
  for index, each in ipairs(lines) do lines[index] = P.buttons(each) end
  return ui.Column(lines)
end

--- Up to `max` rows, each shown while `count()` reaches it; `row(i, width)`
--- makes one, and `none` is what shows while there are none.
function F.list(width, prefix, count, row, none, max)
  local column = { width = width, gap = P.ROW_GAP }
  for index = 1, max or 32 do
    column[#column + 1] = ui.Item { id = prefix .. index, width = width, height = P.ROW_H,
      visible = function() return index <= count() end, row(index, width) }
  end
  if none then
    column[#column + 1] = P.row { width = width, icon = "info", on = function() return false end, title = none,
      visible = function() return count() == 0 end }
  end
  return ui.Column(column)
end

--- The kit's file chooser, built the first time `open` (fn) holds and laid out
--- only while it does: `id`, `width`, `height`, `path`, `filters`,
--- `on_accepted(path)`, `on_cancelled`.
function F.chooser(spec)
  local height = spec.height or 420
  local node
  local function make()
    node = node or require("themes.kit.composites").file_chooser { id = spec.id, width = spec.width, height = height,
      path = spec.path or "~", filters = spec.filters, on_accepted = spec.on_accepted, on_cancelled = spec.on_cancelled }
    return node
  end
  return ui.Item { width = spec.width, height = function() return spec.open() and height or 0 end, clip = true,
    visible = spec.open,
    ui.Loader { anchors = { fill = true }, keep = true, active = spec.open, source = make } }
end

--- A searchable list: a field over the rows that match, `max` at most.
--- `items` (fn): rows with `name`, and `words` to search. `row(item, i,
--- width)` is what a row presses as: `{ icon, title, subtitle, on, pick }`.
--- `searched`: nothing lists until something is typed, for a long list.
--- Returns the node and a function that clears the search.
function F.picker(spec)
  local width, max = spec.width, spec.max or 8
  local typed = morf.signal("eva.settings.picker." .. spec.id, "")
  local function matching()
    local query, out = typed:get():lower(), {}
    local words = {}
    for word in query:gmatch("%S+") do words[#words + 1] = word end
    if spec.searched and #words == 0 then return out end
    for _, item in ipairs(spec.items() or {}) do
      local hay, hit = (tostring(item.name or "") .. " " .. tostring(item.words or "")):lower(), true
      for _, word in ipairs(words) do
        if not hay:find(word, 1, true) then hit = false break end
      end
      if hit then
        out[#out + 1] = item
        if #out >= max then break end
      end
    end
    return out
  end
  local box, handle = P.field { id = spec.id .. "-search", kind = "search", width = width,
    placeholder = spec.placeholder or "Search", on_changed = function(value) typed:set(value) end }
  local rows = F.list(width, spec.id .. "-row-", function() return #matching() end, function(index, row_w)
    local function item() return matching()[index] end
    local function shape() local it = item() return it and spec.row(it, index, row_w) or {} end
    return P.row { id = spec.id .. "-item-" .. index, width = row_w,
      icon = function() return shape().icon or "radio_button_unchecked" end,
      title = function() return shape().title or "" end,
      subtitle = function() return shape().subtitle or "" end,
      on = function() return shape().on == true end,
      on_clicked = function() local go = shape().pick if go then go() end end }
  end, nil, max)
  local none = P.row { width = width, icon = "info", on = function() return false end, title = spec.none or "Nothing matches",
    visible = function() return #matching() == 0 and not (spec.searched and typed:get():find("%S") == nil) end }
  local node = ui.Column { id = spec.id, width = width, gap = S.s, visible = spec.visible, box, rows, none }
  return node, function() typed:set("") handle.text = "" end
end

return F
