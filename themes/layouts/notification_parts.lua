-- The parts a notification card is made of, drawn alike in the popups and the
-- history: its picture, its body, its buttons, a reply field and its tools. Each
-- takes `n` (a fn giving the notification, or nil) and calls only the model
-- it is handed.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local text_of = require("themes.notification_text")
local C = theme.color

local N = {}

N.ROW_H = P.BUTTON_H + theme.space.xs
N.PREVIEW_H = 132
local SLOTS = 3

--- The rows of buttons `n` needs.
function N.button_rows(x, model)
  if not model.buttons_on() then return 0 end
  local count = #text_of.buttons(x)
  return count == 0 and 0 or math.min(2, (count - 1) // SLOTS + 1)
end

--- Whether a code or link chip shows.
function N.chips_of(x, model)
  local out = {}
  if not x or not model.smart_on() then return out end
  local code = text_of.otp(x)
  if code then out[#out + 1] = { label = "Copy " .. code, icon = "content_copy", code = code } end
  -- A link in the body's own markup can already be pressed.
  local link = not tostring(x.body or ""):find("<%s*[aA]%s") and text_of.link(x) or nil
  if link then out[#out + 1] = { label = "Open link", icon = "open_in_new", link = link } end
  return out
end

local function apps() return require("apps") end

-- A sender's icon, resolved once: `{ name }`, `{ path }` or false.
local resolved = {}
local function icon_of(x)
  if not x or x.own then return nil end
  local key = tostring(x.icon) .. "\n" .. tostring(x.desktop_entry) .. "\n" .. tostring(x.app)
  if resolved[key] ~= nil then return resolved[key] or nil end
  local name = tostring(x.icon or ""):gsub("^file://", "")
  local hit = apps().icon(name)
  if not hit and (x.desktop_entry or "") ~= "" then hit = apps().icon(x.desktop_entry) end
  if not hit and (x.app or "") ~= "" then hit = apps().icon(x.app:lower()) end
  resolved[key] = hit or false
  return hit
end

--- A card's picture: the image it came with, its app's icon, or the kind's
--- emblem. `id`, `x`, `y`, `size`, `n`, `kind` (fn), `hidden` (fn: nothing to
--- be read off it).
function N.avatar(spec)
  local size = spec.size
  local function hidden() return spec.hidden ~= nil and spec.hidden() end
  local function picture()
    local x = spec.n()
    return (x and not hidden()) and text_of.image_of(x) or ""
  end
  local function icon() local x = spec.n() return (x and not hidden()) and icon_of(x) or nil end
  local function symbol()
    local x = spec.n()
    return x and x.own and x.icon ~= "" and not hidden() and x.icon or nil
  end
  local image
  image = ui.Image { id = spec.id and spec.id .. "-image", anchors = { fill = true }, fill_mode = "preserve_aspect_crop",
    source = picture, visible = function() return picture() ~= "" and image.status ~= "error" end }
  local function shows_image() return picture() ~= "" and image.status ~= "error" end
  local function themed() local hit = icon() return hit and hit.name or "" end
  local function file() local hit = icon() return hit and hit.path or "" end
  local app_file
  app_file = ui.Image { id = spec.id and spec.id .. "-file", anchors = { fill = true, margins = 4 }, fill_mode = "preserve_aspect_fit",
    source = file, visible = function() return not shows_image() and file() ~= "" and app_file.status ~= "error" end }
  local inset = math.floor(size * .8)
  return ui.Item { id = spec.id, x = spec.x, y = spec.y, anchors = spec.anchors, width = size, height = size,
    ui.Item { anchors = { fill = true },
      visible = function() return not shows_image() and themed() == "" and file() == "" and not symbol() end,
      kit.emblem { size = size, kind = spec.kind } },
    ui.Item { anchors = { fill = true }, visible = function() return symbol() ~= nil end,
      kit.surface { anchors = { fill = true }, radius = kit.round(L.control_round(size)),
        color = function() return kit.signal(spec.kind())():alpha(.16) end },
      kit.icon(function() return symbol() or "" end, math.floor(size * .55), function() return kit.signal(spec.kind())() end,
        { anchors = { center_in = true }, fill = true }),
    },
    ui.Item { anchors = { fill = true }, visible = function() return not shows_image() and themed() ~= "" end,
      ui.Icon { anchors = { center_in = true }, width = inset, height = inset, name = themed,
        source_width = size * 2, source_height = size * 2 },
    },
    ui.Item { anchors = { fill = true }, visible = function() return not shows_image() and file() ~= "" end,
      mask = ui.Sdf { anchors = { fill = true },
        ui.SdfShape { shape = "box", anchors = { fill = true }, radius = L.control_round(size) } },
      app_file },
    ui.Item { anchors = { fill = true }, visible = shows_image,
      mask = ui.Sdf { anchors = { fill = true },
        ui.SdfShape { shape = "box", anchors = { fill = true }, radius = L.control_round(size) } },
      image },
  }
end

--- A card's body in the sender's markup, its `text` plain for what reads it.
--- `n`, `raw` (fn of the notification: what to show, its body without one),
--- `live` (fn: whether it is the body on show; one that is not keeps no links,
--- so a press goes through it), then a Text's props.
function N.body(spec)
  local of, pick, live = spec.n, spec.raw or function(x) return x.body end, spec.live
  local function raw() local x = of() return x and pick(x) or "" end
  local props = {}
  for key, value in pairs(spec) do
    if key ~= "n" and key ~= "raw" and key ~= "live" then props[key] = value end
  end
  props.text = function() return text_of.plain(raw()) end
  props.markup = function()
    if live and not live() then return (text_of.plain(raw()):gsub("&", "&amp;"):gsub("<", "&lt;")) end
    return text_of.markup(raw())
  end
  props.on_link = text_of.open_link
  props.link_color = props.link_color or kit.ink("accent")
  return kit.text(props)
end

-- Each part below the body takes `glide`, the motion it moves to a new `y` on
-- as the body above it opens or shuts.
local function glide(spec) return spec.glide and { y = spec.glide } or nil end

--- A picture at full width: `id`, `y` (fn), `width`, `n`, `shown` (fn).
function N.preview(spec)
  local function source() local x = spec.n() return x and text_of.image_of(x) or "" end
  local image = ui.Image { anchors = { fill = true }, fill_mode = "preserve_aspect_fit", source = source }
  return ui.Item { id = spec.id, x = spec.x, y = spec.y, width = spec.width, height = N.PREVIEW_H - theme.space.s,
    visible = spec.shown, clip = true, behavior = glide(spec),
    mask = ui.Sdf { anchors = { fill = true },
      ui.SdfShape { shape = "box", anchors = { fill = true }, radius = L.control_round(N.PREVIEW_H) } },
    kit.surface { anchors = { fill = true }, color = function() return C.surfaceContainerHighest end },
    image }
end

--- The buttons of a sender: `id`, `x`, `y`, `width`, `n`, `model`, `shown` (fn).
function N.buttons(spec)
  local function list()
    local x = spec.n()
    return x and spec.model.buttons_on() and text_of.buttons(x) or {}
  end
  local function press(slot)
    local x, button = spec.n(), list()[slot]
    if not (x and button) then return end
    if button.reply then spec.model.begin_reply(x.id) else spec.model.invoke(x.id, button.key) end
  end
  local function row(first)
    local items = { width = spec.width }
    for slot = first, first + SLOTS - 1 do
      items[#items + 1] = { id = spec.id .. "-" .. slot, height = P.BUTTON_H,
        label = function() local b = list()[slot] return b and b.label or "" end,
        visible = function() return list()[slot] ~= nil end,
        on_clicked = function() press(slot) end }
    end
    return P.buttons(items)
  end
  local second = row(SLOTS + 1)
  second.visible = function() return #list() > SLOTS end
  return ui.Column { id = spec.id, x = spec.x, y = spec.y, width = spec.width, gap = theme.space.xs, visible = spec.shown,
    behavior = glide(spec), row(1), second }
end

--- A media card's controls: `id`, `x`, `y`, `n`, `model`, `shown`.
function N.transport(spec)
  local SIZE = P.BUTTON_H
  local function list() local x = spec.n() return x and text_of.transport(x) or {} end
  local row = { id = spec.id, x = spec.x, y = spec.y, gap = theme.space.s, align = "center", visible = spec.shown,
    behavior = glide(spec) }
  for slot = 1, 4 do
    local button = L.icon_button { id = spec.id .. "-" .. slot, width = SIZE, height = SIZE,
      icon = function() local item = list()[slot] return item and item.icon or "play_arrow" end,
      name = function() local item = list()[slot] return item and item.name or "" end,
      on_clicked = function()
        local x, item = spec.n(), list()[slot]
        if x and item then spec.model.invoke(x.id, item.key) end
      end }
    button.visible = function() return list()[slot] ~= nil end
    row[#row + 1] = button
  end
  return ui.Row(row)
end

--- Code and link chips: `id`, `x`, `y`, `width`, `n`, `model`, `shown`.
function N.chips(spec)
  local function list() return N.chips_of(spec.n(), spec.model) end
  local items = { width = spec.width }
  for slot = 1, 2 do
    items[#items + 1] = { id = spec.id .. "-" .. slot, height = P.BUTTON_H,
      label = function() local chip = list()[slot] return chip and chip.label or "" end,
      visible = function() return list()[slot] ~= nil end,
      on_clicked = function()
        local chip = list()[slot]
        if not chip then return end
        if chip.code then pcall(morf.clipboard.set, chip.code) else text_of.open_link(chip.link) end
      end }
  end
  local row = P.buttons(items)
  return ui.Item { x = spec.x, y = spec.y, width = spec.width, height = P.BUTTON_H, visible = spec.shown,
    behavior = glide(spec), row }
end

--- The reply field: `id`, `x`, `y`, `width`, `n`, `model`, `shown`.
function N.reply(spec)
  local draft = morf.signal("eva.notifications.draft." .. spec.id, "")
  local SEND = P.BUTTON_H
  local function send()
    local x, words = spec.n(), draft:get()
    if not x or words == "" then return end
    draft:set("")
    spec.model.reply(x.id, words)
  end
  local function cancel()
    local x = spec.n()
    draft:set("")
    if x then spec.model.cancel_reply(x.id) end
  end
  local node, input = kit.text_field("entry", { id = spec.id, x = theme.space.s, width = spec.width - SEND - 3 * theme.space.s,
    height = 30, anchors = { vertical_center = true }, font_family = theme.font, font_size = theme.size.small,
    placeholder = function() return text_of.reply_prompt(spec.n()) end,
    color = function() return C.onSurface end, placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(.3) end,
    focus = spec.shown, on_text_changed = function(value) draft:set(value) end, on_accepted = send, on_escape = cancel })
  morf.effect("eva.notifications.reply." .. spec.id, function()
    local words = draft:get()
    if input.text ~= words then input.text = words end
  end, { owner = node })
  return ui.Item { x = spec.x, y = spec.y, width = spec.width, height = P.BUTTON_H, visible = spec.shown,
    behavior = glide(spec),
    kit.surface { width = spec.width - SEND - theme.space.s, height = P.BUTTON_H, radius = kit.round(10),
      color = function() return C.surfaceContainerHighest end, node },
    L.icon_button { id = spec.id .. "-send", x = spec.width - SEND, width = SEND, height = SEND, icon = "send",
      name = "Send", on_clicked = send },
  }
end

--- A card's tools: snooze, mute, its rules. `id`, `x`, `y`, `width`, `n`, `model`,
--- `shown`, `extra` (a button spec's fields for the fourth slot of the first row).
function N.tools(spec)
  local page = morf.signal("eva.notifications.tools.page." .. spec.id, "")
  local model = spec.model
  local function close() page:set("") end
  local function done()
    local x = spec.n()
    close()
    if x and model.tools:get() == x.id then model.toggle_tools(x.id) end
  end
  local function key() local x = spec.n() return x and (x.key or x.app) or nil end
  local first = {
    { "Snooze", function() page:set("snooze") end },
    { "Mute", function() page:set("mute") end },
    { "Rules", function() local k = key() done() if k then model.rules_of(k) end end },
    { "Clear app", function() local k = key() done() if k then model.clear_app(k) end end },
  }
  local function slots()
    local chosen = page:get()
    if chosen == "snooze" then
      local out = {}
      for i, preset in ipairs(model.SNOOZE) do
        out[i] = { preset[2], function()
          local x = spec.n()
          close()
          if x then model.snooze(x.id, preset[1]) end
        end }
      end
      return out
    elseif chosen == "mute" then
      local out = {}
      for i, preset in ipairs(model.MUTES) do
        out[i] = { preset[2], function() local k = key() done() if k then model.mute_app(k, preset[1]) end end }
      end
      out[#out + 1] = { "Back", close }
      return out
    end
    return first
  end
  local items = { width = spec.width }
  for slot = 1, 4 do
    items[#items + 1] = { id = spec.id .. "-" .. slot, height = P.BUTTON_H,
      label = function() local item = slots()[slot] return item and item[1] or "" end,
      on_clicked = function() local item = slots()[slot] if item then item[2]() end end }
  end
  local row = P.buttons(items)
  return ui.Item { x = spec.x, y = spec.y, width = spec.width, height = P.BUTTON_H, visible = spec.shown,
    behavior = glide(spec), row }
end

return N
