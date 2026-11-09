-- The one template every page of a panel is drawn with -- a settings page,
-- a panel's tab, a page one level in -- so all of them read alike: the same
-- title, the same cards, the same gaps, the same rows and buttons, in the
-- theme's colours (THEMING.md: the kit draws, this only places).
--
--     local P = require("themes.layouts.page")
--     return P.page { id = "sound", width = w, height = h, title = "Sound",
--       subtitle = "Output and volume", actions = { P.button { ... } },
--       P.section { title = "Output",
--         P.row { id = "sound-mute", icon = "volume_off", title = "Mute",
--           trailing = P.switch { ... } },
--       },
--       P.empty { icon = "headphones", title = "No device", text = "..." },
--     }
--
-- A page: a header (title, a subtitle under it, actions at its right), then
-- its blocks one under the other, `GAP` apart, each the page's width; the
-- whole of it scrolls in `height`. A section: a caption over one card that
-- holds its rows (or anything else), `PAD` inside. A row: an icon, a title
-- and a line under it, and a control at the right; the whole row presses
-- when it opens something. A button fits its label.
local morf = require("morf")
local ui = require("morf.ui")
local unicase = require("lib.util.unicase")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local C = theme.color

local P = {}
local S = theme.space

P.GAP = S.m             -- between blocks, and between a caption and its card
P.PAD = S.l             -- inside a card
P.ROW_H = 64          -- a row
P.ROW_GAP = S.s         -- between rows in a card
P.RADIUS = S.l          -- a card's rounding, where the theme rounds
P.ICON_ROOM = 132       -- a button's width with room for an icon by its label
-- A button: a finger's height where one is the main input.
do
  local ok, responsive = pcall(require, "responsive")
  P.BUTTON_H = ok and responsive.target() or S.TARGET
end

local function get(v) if type(v) == "function" then return v() end return v end

--- The width a card `w` wide leaves its rows.
function P.inner(w) return get(w) - 2 * P.PAD end

--- Children of `spec`'s array part, nil holes closed.
local function children(spec)
  local out = {}
  for _, c in ipairs(L.compact(spec)) do out[#out + 1] = c end
  return out
end

-- ------------------------------------------------------------------ text --

local TITLE = L.SIZE.title
local SUB = L.SIZE.body
P.SUB = SUB           -- a row's second line, a note

--- A button that fits its label (and icon): `id`, `label`, `icon`,
--- `on_clicked`, `width` (leave it out: the label's), `selected` (fn),
--- `group`, `short` (the label in a narrow row of buttons), `tone` ("primary",
--- or a fn giving it, is filled), `color` and
--- `ink` (fns: a colour of its own, an alert's), `visible`.
function P.button(spec)
  local label = spec.label or ""
  -- Measured the way the theme's pill sets its caption: a menu face in
  -- capitals where the theme has one, its body text where not.
  local menu = theme.typography and theme.typography.menu
  local caption = menu and function() return unicase.upper(tostring(get(label) or "")) end or label
  local size = menu or theme.size.normal
  local measure = menu and kit.menu_label { text = caption, font_size = size, height = 18, opacity = 0 }
    or kit.text { text = caption, font_size = size, opacity = 0 }
  local function natural()
    local text = measure.layout_width or (utf8.len(tostring(get(caption))) * size * 0.62)
    return math.ceil(text + 40 + (spec.icon and 26 or 0))
  end
  local width = spec.width
  if width == nil then width = natural end
  local function primary()
    local tone = get(spec.tone)
    return tone == "primary"
  end
  local pill = kit.pill { id = spec.id, label = label, icon = spec.icon, width = width, height = spec.height or P.BUTTON_H,
    enabled = spec.enabled, accessible_name = spec.accessible_name,
    opacity = function() return get(spec.enabled)==false and .45 or 1 end,
    checkable = spec.group ~= nil or nil, group = spec.group, checked = spec.group and spec.selected or nil,
    on_clicked = spec.on_clicked,
    -- A button that cannot be pressed loses its tone with the rest of it.
    color = spec.color or function()
      if get(spec.enabled) == false then return C.surfaceContainerHighest end
      if (spec.selected and spec.selected()) or primary() then return C.primary end
      return C.surfaceContainerHighest
    end,
    ink = spec.ink or function()
      if get(spec.enabled) == false then return C.onSurface end
      if (spec.selected and spec.selected()) or primary() then return C.onPrimary end
      return C.onSurface
    end }
  if spec.visible then pill.visible = spec.visible end
  return ui.Item { id = spec.id and spec.id .. "-box", width = width, height = spec.height or P.BUTTON_H,
    visible = spec.visible, ui.Item { width = 1, height = 1, clip = true, measure }, pill }
end

--- A row of buttons sharing `width` evenly: `width`, then the buttons'
--- specs in the array part (each P.button's, `width` left out).
--- How wide `text` sets in the body face at `size`, near enough to know
--- whether it fits: each character's advance in ems.
local ADVANCE = { i = .28, l = .28, I = .3, j = .38, f = .42, r = .42, t = .43, [" "] = .23, ["1"] = .47, T = .49,
  m = .91, w = .82, M = .81, W = .81 }
function P.text_width(text, size)
  local ems = 0
  for _, code in utf8.codes(tostring(text or "")) do
    local ch = utf8.char(code)
    ems = ems + (ADVANCE[ch] or ch:match("%u") and .68 or ch:match("%d") and .64 or .58)
  end
  return ems * (size or theme.size.normal)
end

--- How many of buttons labelled `labels` stand side by side in `width`, at
--- most `most`, with none of the labels cut.
function P.fit(width, labels, most)
  local menu = theme.typography and theme.typography.menu
  local widest = 0
  for _, label in ipairs(labels) do
    local text = tostring(get(label) or "")
    local set = menu and utf8.len(text) * menu * 0.62 or P.text_width(text)
    widest = math.max(widest, set + (menu and 32 or 28))
  end
  local fit, room = most, tonumber(get(width)) or 0
  if room <= 0 then return most end
  while fit > 1 and (room - 8 * (fit - 1)) / fit < widest do fit = fit - 1 end
  return fit
end

function P.buttons(spec)
  local items = children(spec)
  local gap = 8
  -- Where the longest label would be cut, the buttons wrap into even rows.
  local labels = {}
  for i, item in ipairs(items) do labels[i] = item.label end
  local fit, room = P.fit(spec.width, labels, #items), tonumber(get(spec.width)) or 0
  if fit < #items and room > 0 then
    local even = nil
    for f = fit, 2, -1 do if #items % f == 0 then even = f break end end
    fit = even or (#items <= 3 and 1 or fit)
    local column = { id = spec.id, width = spec.width, gap = S.s, visible = spec.visible }
    for first = 1, #items, fit do
      local part = { width = spec.width }
      for i = first, math.min(#items, first + fit - 1) do part[#part + 1] = items[i] end
      column[#column + 1] = P.buttons(part)
    end
    return ui.Column(column)
  end
  -- Too narrow for an icon beside each label: the labels alone, short ones
  -- where a button has one.
  local each = ((tonumber(get(spec.width)) or 0) - gap * (#items - 1)) / math.max(1, #items)
  if each < P.ICON_ROOM then
    for _, item in ipairs(items) do
      if item.label and item.icon then item.icon = nil end
      if item.short then item.label = item.short end
    end
  end
  local row = { id = spec.id, gap = gap, align = "center" }
  for i, item in ipairs(items) do
    item.width = function()
      local n, position=0,0
      for j, candidate in ipairs(items) do
        if get(candidate.visible)~=false then
          n=n+1
          if j<=i then position=position+1 end
        end
      end
      if get(item.visible)==false or n==0 then return 1e-3 end
      local total=math.max(0,get(spec.width)-gap*(n-1))
      return math.max(1e-3,math.floor(total*position/n)-math.floor(total*(position-1)/n))
    end
    row[i] = P.button(item)
  end
  -- With none of its buttons on show, the row takes no room in its card.
  row.visible = spec.visible or function()
    for _, item in ipairs(items) do if get(item.visible) ~= false then return true end end
    return false
  end
  return ui.Row(row)
end

--- The theme's switch, at a row's right.
function P.switch(spec)
  return kit.switch { id = spec.id, accessible_name = spec.name, enabled = spec.enabled,
    on = spec.on, on_toggled = spec.on_toggled }
end

--- An arrow at a row's right: the row opens something. Its box is the
--- glyph's ink, so the arrow ends where a switch beside it ends.
P.CHEVRON_BEARING = 7
function P.chevron()
  return ui.Item { width = 22 - P.CHEVRON_BEARING, height = 22, kit.icon("chevron_right", 22, kit.ink("lo")) }
end

--- An icon button `size` square with a `glyph` icon, for a row's right: held
--- by its glyph, so the glyph ends where a switch beside it ends.
function P.flush(button, size, glyph)
  if theme.icon_box then return ui.Item { width = size, height = size, button } end
  return ui.Item { width = size - math.floor((size - glyph) / 2), height = size, button }
end

--- A one-line text field `width` wide: `id`, `kind` ("entry", "password",
--- "search", "numeric_entry"), `text` (a string or fn), `placeholder`,
--- `name` (what a reader calls it), `on_changed`, `on_accepted`, `on_escape`.
--- Returns the box to place and the input in it.
function P.field(spec)
  local w, h = get(spec.width), P.BUTTON_H
  local search = spec.kind == "search"
  local node, handle = kit.text_field(spec.kind or "entry", { id = spec.id, width = w, text = spec.text,
    height = h, font_family = theme.font, font_size = theme.size.normal, placeholder = spec.placeholder, accessible_name = spec.name,
    reveal = spec.kind == "password" and false or nil,
    -- A search field's magnifier stands at its left; it draws its own ground.
    icon = search and "search" or nil,
    inset = search and { S.xl + S.l, 0, S.l, 0 } or { S.l, 0, S.l, 0 },
    color = function() return C.onSurface end, placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(0.25) end,
    on_text_changed = spec.on_changed, on_accepted = spec.on_accepted, on_escape = spec.on_escape })
  -- The field draws its own ground; the box only holds its place.
  return ui.Item { width = w, height = h, visible = spec.visible, node }, handle
end

--- A caption across `w`, held to it: a long note is cut at the card's edge,
--- never run on over a neighbour's.
local function caption(id, w, text, note)
  return ui.Item { width = w, height = L.CAPTION_H, clip = true,
    L.caption { id = id, width = get(w), text = text, note = note } }
end

-- ------------------------------------------------------------------ rows --

--- A row: `id`, `width`, `icon` (a name or fn), `title`, `subtitle` (a
--- string or fn), `trailing` (a node at the right), `on_clicked` (the
--- whole row presses), `on` (fn: the icon lights while true), `height`,
--- `visible`, `enter` and `exit` (`kit.enter()`, `kit.leave()`).
--- Its icon and trailing part stand on the card's content edges, as every
--- other block in the card does; a pressable row's ground reaches past them.
P.ROW_REACH = 10
P.ROW_TEXT_X = 36
function P.row(spec)
  local w, h = spec.width, spec.height or P.ROW_H
  local trailing = spec.trailing
  local function trailing_w()
    if not trailing or get(trailing.visible) == false then return 0 end
    return (trailing.layout_width or 0) > 0 and trailing.layout_width or get(trailing.width) or 0
  end
  local text_x = spec.icon and P.ROW_TEXT_X or 0
  local text_w = function()
    local room = trailing_w()
    return math.max(1e-3, get(w) - text_x - (room > 0 and room + 16 or 0))
  end
  local lit = spec.on or function() return false end
  local text = ui.Column { x = text_x, width=text_w,clip=true,anchors = { vertical_center = true }, gap = 2,
    kit.text { id = spec.id and spec.id .. "-title", text = spec.title, width = text_w, wrap = true, max_lines = 2,
      font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi") },
    spec.subtitle and kit.text { id = spec.id and spec.id .. "-subtitle", text = spec.subtitle, width = text_w,
      wrap = true, max_lines = 3, font_size = SUB, color = kit.ink("lo") } or nil,
  }
  -- A title that wraps takes the room it needs.
  local fixed = h
  h = function() return math.max(get(fixed), text.layout_height or 0) end
  local body = {
    id = spec.id, width = w, height = h, enter = spec.enter, exit = spec.exit,
    spec.icon and kit.icon(spec.icon, 22, function() return lit() and kit.ink("accent")() or kit.ink("lo")() end,
      { x = 0, anchors = { vertical_center = true } }) or nil,
    text,
  }
  if trailing then
    body[#body + 1] = ui.Item { anchors = { right = true, vertical_center = true },
      -- (Never 0x0, though its control be hidden: it holds a place.)
      width = function() return math.max(1, trailing_w()) end,
      height = function() return math.max(1, trailing.layout_height or get(trailing.height) or 0) end,
      trailing }
  end
  body.visible = spec.visible
  local node = L.item(body)
  if spec.on_clicked then
    node.x = P.ROW_REACH
    local press = kit.action { id = spec.id and spec.id .. "-press", x = -P.ROW_REACH, height = h, cursor = "pointer",
      width = function() return get(w) + 2 * P.ROW_REACH end, on_clicked = spec.on_clicked, node }
    return ui.Item { width = w, height = h, visible = spec.visible, press }
  end
  return node
end

-- -------------------------------------------------------------- sections --

--- A caption over one card: `id`, `title` (the caption; none, no caption),
--- `caption_id`, `note`, `width`, `visible`, then what the card holds in the array part (rows, or
--- any nodes the card's width less its padding), one under the other.
function P.section(spec)
  local w = spec.width
  local items = children(spec)
  local col = { x = P.PAD, y = P.PAD, gap = P.ROW_GAP }
  for i, item in ipairs(items) do col[i] = item end
  local column = ui.Column(col)
  local card = kit.card { id = spec.id and spec.id .. "-card", width = w, radius = kit.round(P.RADIUS),
    height = function() return (column.layout_height or 0) + 2 * P.PAD end,
    column }
  local parts = { id = spec.id, width = w, gap = P.GAP / 2 }
  if spec.title then
    parts[#parts + 1] = caption(spec.caption_id or (spec.id and spec.id .. "-caption"), w, spec.title, spec.note)
  end
  parts[#parts + 1] = card
  parts.visible = spec.visible
  return ui.Column(parts)
end

--- A tile of a grid (the dashboard's): a section a fixed `height` tall,
--- caption included -- `id`, `title`, `note`, `width`, `height`, `visible`,
--- `clip`; what it holds in the array part, placed in its card's inner box
--- (P.tile_inner(w, h) big, at the card's padding). Without a title it is
--- the card alone.
P.CAPTION_H = L.CAPTION_H + P.GAP / 2
function P.tile_inner(w, h, titled)
  return get(w) - 2 * P.PAD, get(h) - 2 * P.PAD - (titled == false and 0 or P.CAPTION_H)
end
function P.tile(spec)
  local w, h = spec.width, spec.height
  local titled = spec.title ~= nil
  local card_h = function() return get(h) - (titled and P.CAPTION_H or 0) end
  local inner = { x = P.PAD, y = P.PAD, width = function() return get(w) - 2 * P.PAD end,
    height = function() return card_h() - 2 * P.PAD end, clip = spec.clip }
  for i, c in ipairs(children(spec)) do inner[i] = c end
  local card = kit.card { id = spec.id and spec.id .. "-card", width = w, height = card_h,
    radius = kit.round(P.RADIUS), ui.Item(inner) }
  local parts = { id = spec.id, width = w, height = h, gap = P.GAP / 2 }
  if titled then
    parts[#parts + 1] = caption(spec.caption_id or (spec.id and spec.id .. "-caption"), w, spec.title, spec.note)
  end
  parts[#parts + 1] = card
  parts.visible = spec.visible
  return ui.Column(parts)
end

--- `n` widths sharing `w` with `P.GAP` between them, the last taking what
--- rounding leaves: P.cols(w, 3) -> a, b, c; or with `weights` ({2, 1}).
function P.cols(w, n, weights)
  local total, out = get(w) - P.GAP * (n - 1), {}
  local sum = 0
  for i = 1, n do sum = sum + (weights and weights[i] or 1) end
  local used = 0
  for i = 1, n do
    if i == n then out[i] = total - used
    else out[i] = math.floor(total * (weights and weights[i] or 1) / sum) used = used + out[i] end
  end
  return table.unpack(out)
end

--- What a page says when it has nothing to list: `id`, `width`,
--- `title`, `text`, `action` (a P.button spec: what to do about it),
--- `visible`.
--- It reads as any other row: its icon dim, its words beside it.
function P.empty(spec)
  local w = spec.width
  local inner = function() return get(w) - 2 * P.PAD end
  local text_w = function() return get(w) - 2 * P.PAD - P.ROW_TEXT_X end
  local words = ui.Column { x = P.ROW_TEXT_X, width = text_w, gap = 2, anchors = { vertical_center = true },
    kit.text { text = spec.title, font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi"),
      width = text_w, wrap = true, max_lines = 2 },
    spec.text and kit.text { text = spec.text, font_size = SUB, color = kit.ink("lo"), wrap = true, width = text_w } or nil }
  return P.section { id = spec.id, width = w, visible = spec.visible,
    ui.Item { width = inner, height = function() return math.max(P.ROW_H, (words.layout_height or 0) + 2 * S.s) end,
      kit.icon("info", 22, kit.ink("lo"), { anchors = { vertical_center = true } }), words },
    spec.action and P.button(spec.action.width and spec.action or setmetatable({ width = inner }, { __index = spec.action })) or nil }
end

-- ---------------------------------------------------------------- header --

P.HEADER_H = L.heading_h(TITLE) + L.lh(SUB) + 2
-- A title has no descenders mostly: set this low, it reads centred on its line.
P.TITLE_NUDGE = 2

--- Reserve only the lines and controls that are actually shown. Reading
--- the same metrics here and in the frame keeps its body flush below it.
-- The head's first line: the title, the way back and the actions on it,
-- at least `spec.line` tall.
local function line_height(spec)
  local line=math.max(L.heading_h(TITLE),get(spec.line) or 0)
  if spec.back and (spec.can_back==nil or get(spec.can_back)) then line=math.max(line,P.BUTTON_H) end
  for _,action in ipairs(children(spec.actions or {})) do
    if get(action.visible)~=false then
      line=math.max(line,action.layout_height or get(action.height) or 0)
    end
  end
  return line
end

function P.header_height(spec)
  spec=spec or {}
  local note=get(spec.subtitle)
  local line=line_height(spec)
  local below=note and note~="" and L.lh(SUB)+2 or 0
  return math.max(line,math.floor((line-L.heading_h(TITLE))/2)+P.TITLE_NUDGE+L.heading_h(TITLE)+below)
end

--- A page's head: `id`, `width`, `title` (string or fn), `subtitle`,
--- `back` (fn: an arrow at its left that calls it -- a page one level in),
--- `can_back` (fn: whether the arrow is there; always, without it),
--- `actions` (nodes at its right), `scope` (the heading's), `title_id`,
--- `line` (the first line's least height, so the title keeps its place).
--- The way back, the title and the actions share the first line; the
--- subtitle sits under the title.
function P.header(spec)
  local w = spec.width
  local actions = spec.actions and children(spec.actions) or {}
  local function line() return line_height(spec) end
  local row
  if #actions > 0 then
    local r = { anchors = { right = true }, gap = 8, align = "center" }
    for i, a in ipairs(actions) do r[i] = a end
    row = ui.Row(r)
    row.y = function() return math.floor((line() - (row.layout_height or 0)) / 2) end
  end
  local can_back = spec.can_back or function() return spec.back ~= nil end
  -- The arrow centres on the cards' row icons, or its square meets their
  -- edge, and the title's words start where the rows' do.
  local INSET = theme.heading_inset or 0
  local BACK_X = theme.icon_box and 0 or P.PAD + 11 - math.floor(P.BUTTON_H / 2)
  local function lead() return can_back() and P.PAD + P.ROW_TEXT_X - INSET or 0 end
  local function text_w() return math.max(1e-3, get(w) - lead() - (row and (row.layout_width or 0) + 12 or 0)) end
  local back
  if spec.back then
    back = kit.action { id = spec.back_id or (spec.id and spec.id .. "-back"), accessible_name = "Back",
      width = P.BUTTON_H, height = P.BUTTON_H, cursor = "pointer", x = BACK_X, y = function() return math.floor((line() - P.BUTTON_H) / 2) end,
      on_clicked = spec.back, visible = can_back,
      kit.icon("arrow_back", 22, kit.ink("hi"), { anchors = { center_in = true } }) }
    kit.hover(back, function(hovered) return hovered and C.onSurface:alpha(0.08) or C.onSurface:alpha(0) end, 20)
  end
  local text = ui.Column { x = lead, width=text_w,clip=true,behavior = { x = { duration = theme.duration.small } },
    y = function() return math.floor((line() - L.heading_h(TITLE)) / 2) + P.TITLE_NUDGE end, gap = 2,
    L.heading { id = spec.title_id or (spec.id and spec.id .. "-title"), scope = spec.scope, level = "title", text = spec.title,
      width = text_w, elide = "right", active = spec.active },
    spec.subtitle and kit.text { id = spec.id and spec.id .. "-subtitle", text = spec.subtitle, font_size = SUB,
      visible=function() local note=get(spec.subtitle) return note~=nil and note~=false and note~="" end,
      x = INSET, color = kit.ink("lo"), width = function() return math.max(1e-3, text_w() - INSET) end,
      height = L.lh(SUB), elide = "right" } or nil,
  }
  return L.item { id = spec.id, width = w, height = function() return P.header_height(spec) end, back, text, row }
end

-- ----------------------------------------------------------------- frame --

--- A panel's page as the panel shows it: the header, then the page's body
--- under it. `id`, `width`, `height` (fn), `title` (the tab's name),
--- `title_id`, `scope`, `active` (fn: the title is on show), `titled`
--- (the head shows: the tabs are icons alone), `build(w, h)` -- the body, `h` a fn -- which may
--- give back a second value with what the header says instead: `title`,
--- `subtitle`, `back`, `can_back`, `actions` (as P.header's), `keep` (fn:
--- the head shows even where the tabs name the page). `measured(read)` is
--- given a function: how tall the page stands whole, head and all, once the
--- first scroll in its body is laid out, for a panel that fits its page;
--- `measured(nil, read)` says that `read` has gone with its frame.
local measuring

--- Says how to read the height of what is being built, if something is
--- measuring and has not been told yet.
function P.report(read)
  if measuring and not measuring.read then measuring.read = read end
end

--- `build()`'s results, and how to read the height of the page in them.
function P.measure(build)
  local outer = measuring
  local measure = {}
  measuring = measure
  local node, extra = build()
  measuring = outer
  return node, extra, measure.read
end

function P.frame(spec)
  local w = spec.width
  local head
  -- Body builders may evaluate their height before returning the header's
  -- callbacks. A signal lets those first bindings follow the final header
  -- too, rather than keeping the space calculated during construction.
  local header_space=morf.signal("page.frame.header."..tostring(spec),0)
  -- The head is there where the tabs do not name the page (a phone's, icons
  -- alone: `titled`), on a page one level in, for its way back, and on a
  -- page that keeps something in it (`head.keep`).
  local function shown()
    if get(spec.titled) then return true end
    if head ~= nil and head.keep ~= nil and head.keep() == true then return true end
    return head ~= nil and head.can_back ~= nil and head.can_back() == true
  end
  local function top() return header_space:get() end
  local function body_h() return math.max(0, get(spec.height) - top()) end
  local body, read
  body, head, read = P.measure(function() return spec.build(w, body_h) end)
  head = head or {}
  local reader = spec.measured and read and function()
    local whole = read()
    return whole > 0 and top() + whole or nil
  end or nil
  if reader then spec.measured(reader) end
  local header = P.header { id = spec.id and spec.id .. "-head", width = w, title = head.title or spec.title,
    title_id = head.title_id or spec.title_id, scope = spec.scope, subtitle = head.subtitle, back = head.back,
    can_back = head.can_back, back_id = head.back_id, actions = head.actions, active = head.active or spec.active }
  header.visible = shown
  local frame=ui.Item { id = spec.id, width = w, height = spec.height,
    on_destroyed = reader and function() spec.measured(nil, reader) end or nil,
    header,
    ui.Item { y = top, width = w, height = body_h, body },
  }
  morf.effect("page.frame.header."..tostring(frame),function()
    header_space:set(shown() and P.header_height(head)+P.GAP or 0)
  end,{owner=frame})
  return frame
end

-- ------------------------------------------------------------------ page --

--- `run` as a scroll's `on_refresh`: the indicator holds a moment and goes.
function P.refreshing(run)
  if not run then return nil end
  return function(done)
    run()
    morf.time.timer(theme.duration.large * 2, done, false)
  end
end

--- A page: `id`, `width`, `height` (a number or fn), `title`, `subtitle`,
local holding, hold = false, nil

--- The next page to come on show stays where it was.
function P.hold_place()
  holding = true
  if hold then hold:cancel() end
  hold = morf.time.timer(800, function() holding, hold = false, nil end, false)
end

--- `actions` (nodes at the header's right), `scroll` (false: it does not
--- scroll, its blocks share the height), `active` (fn: on show -- it is
--- back at its top each time it comes on show, unless a person came back to
--- it), `on_refresh` (fn: a pull
--- past the top runs it); the blocks in the array part.
function P.page(spec)
  local w = spec.width
  local blocks = children(spec)
  local col = { width = w, gap = P.GAP }
  if spec.title then
    col[#col + 1] = P.header { id = spec.id and spec.id .. "-head", width = w, title = spec.title,
      subtitle = spec.subtitle, actions = spec.actions, back = spec.back, scope = spec.scope, active = spec.active }
  end
  for _, b in ipairs(blocks) do col[#col + 1] = b end
  -- A little room under the last block, so its card's foot is not the
  -- scroll's edge.
  col[#col + 1] = ui.Item { width = 1, height = P.GAP }
  local column = ui.Column(col)
  if spec.scroll == false then
    return ui.Item { id = spec.id, width = w, height = spec.height, column }
  end
  local node, flick = kit.scroll({ id = spec.id, width = w, height = spec.height, clip = true,
    on_refresh = P.refreshing(spec.on_refresh), column })
  -- Back at its top each time it comes on show, and where it was on the way back.
  if spec.active and flick then
    local was = false
    morf.effect("page.top." .. (spec.id or tostring(node)), function()
      local now = spec.active() == true
      if now and not was then
        if holding then holding = false else flick.content_y = 0 end
      end
      was = now
    end, { owner = node })
  end
  return node
end

return P
