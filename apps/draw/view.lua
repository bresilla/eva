-- eva-draw's overlay: strokes and words over everything, one `ui.Path` a stroke,
-- and a pill of the kit's controls at the screen's foot, a mark riding the
-- theme's spring onto the chosen pen.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local frame = require("common.frame")
local L = require("themes.layouts.parts")
local pill = require("themes.layouts.tool_pill")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

M.BUTTON = pill.CELL
M.SWATCH = S.l + S.xs

local INK = {}
for _, pen in ipairs(model.PENS) do INK[pen.key] = kit.signal(pen.signal) end

local function ink() return INK[model.pen:get()]() end

local function fade()
  local curve = theme.bounce.effects
  return { opacity = 0, duration = curve.duration, easing = curve.easing }
end

local function mark(row)
  if row.kind == "text" then
    return kit.text {
      id = "draw-mark-" .. row.key, x = row.x, y = row.y, text = row.text, font_size = row.size, font_weight = 600,
      color = INK[row.pen], exit = fade(),
    }
  end
  return ui.Path {
    id = "draw-mark-" .. row.key, x = row.x, y = row.y, width = row.w, height = row.h,
    view_box = { row.x, row.y, row.w, row.h }, fill_mode = "stretch", d = row.d, fill_color = "transparent",
    stroke_color = INK[row.pen], stroke_width = row.width, stroke_cap = "round", stroke_join = "round",
    exit = fade(),
  }
end

local function draft()
  local function now() return model.draft:get() or { x = 0, y = 0, w = 1, h = 1, d = "", width = 1 } end
  return ui.Path {
    id = "draw-draft", x = function() return now().x end, y = function() return now().y end,
    width = function() return now().w end, height = function() return now().h end,
    view_box = function() local d = now() return { d.x, d.y, d.w, d.h } end,
    fill_mode = "stretch", d = function() return now().d end, fill_color = "transparent",
    stroke_color = ink, stroke_width = function() return now().width end, stroke_cap = "round", stroke_join = "round",
    visible = function() return model.draft:get() ~= nil end,
  }
end

local function typing()
  local function now() return model.typing:get() end
  return ui.Row {
    id = "draw-typing", gap = S.xxs,
    x = function() local t = now() return t and t.x or 0 end,
    y = function() local t = now() return t and t.y or 0 end,
    visible = function() return now() ~= nil end,
    kit.text {
      id = "draw-typing-text", text = function() local t = now() return t and t.text or "" end,
      font_size = function() return model.WIDTHS[model.width:get()] * model.TEXT end, font_weight = 600, color = ink,
    },
    ui.Rect {
      width = S.xxs, height = function() return model.WIDTHS[model.width:get()] * model.TEXT end, color = ink,
    },
  }
end

local function swatch(pen)
  return kit.action {
    id = "draw-pen-" .. pen.key, accessible_name = pen.name, width = M.BUTTON, height = M.BUTTON, cursor = "pointer",
    on_clicked = function() model.pen:set(pen.key) end,
    ui.Rect {
      anchors = { center_in = true }, width = M.SWATCH, height = M.SWATCH, radius = kit.round(M.SWATCH / 2),
      color = INK[pen.key],
    },
  }
end

local function width_button()
  local function dot() return model.WIDTHS[model.width:get()] + S.xs end
  return kit.action {
    id = "draw-width", accessible_name = "Pen width", width = M.BUTTON, height = M.BUTTON, cursor = "pointer",
    on_clicked = function()
      model.width:set(model.width:get() % #model.WIDTHS + 1)
    end,
    ui.Rect {
      anchors = { center_in = true }, width = dot, height = dot, radius = kit.round(S.s), color = ink,
      behavior = { width = theme.spring.fast, height = theme.spring.fast },
    },
  }
end

local function tool(name, icon, label, press, on)
  return L.icon_button {
    id = "draw-" .. name, name = label, icon = icon, width = M.BUTTON, height = M.BUTTON, on = on, on_clicked = press,
  }
end

local function toolbar(finish)
  local cells = {}
  for _, pen in ipairs(model.PENS) do cells[#cells + 1] = swatch(pen) end
  cells[#cells + 1] = width_button()
  cells[#cells + 1] = tool("text", "title", "Write", model.toggle_writing, function() return model.writing:get() end)
  cells[#cells + 1] = tool("board", "rectangle", "Board", function() model.board:set(not model.board:get()) end,
    function() return model.board:get() end)
  cells[#cells + 1] = tool("undo", "undo", "Undo", model.undo)
  cells[#cells + 1] = tool("clear", "delete", "Clear", model.clear)
  cells[#cells + 1] = tool("end", "close", "End", finish)
  return pill.new {
    id = "draw-toolbar", cells = cells,
    chosen = function()
      for index, pen in ipairs(model.PENS) do
        if pen.key == model.pen:get() then return index end
      end
      return 1
    end,
    opacity = function() return model.drawing:get() and 0.35 or 1 end,
    behavior = { opacity = theme.spring.effects },
  }
end

-- What a key does outside words: true when it was one of the tool's.
local function command(text, modifiers, name, finish)
  if name == "Escape" then finish() return true end
  if modifiers and modifiers:find("ctrl", 1, true) then
    if name == "z" then model.undo() return true end
    return false
  end
  if text == "+" or text == "=" or text == "]" then model.widen(1) return true end
  if text == "-" or text == "[" then model.widen(-1) return true end
  if name == "u" then model.undo() return true end
  if name == "e" then model.clear() return true end
  if name == "t" then model.toggle_writing() return true end
  if name == "w" then model.board:set(not model.board:get()) return true end
  return model.choose(name)
end

local function on_key(finish)
  return function(_, text, modifiers, _, name)
    if model.typing:get() then
      if name == "Escape" then model.cancel_text()
      elseif name == "Return" then model.commit()
      elseif name == "BackSpace" then model.erase()
      elseif text and text ~= "" then model.type(text) end
      return true
    end
    return command(text, modifiers, name, finish)
  end
end

--- Builds the overlay; `finish()` ends the tool.
function M.overlay(finish)
  local root = ui.Item {
    anchors = { fill = true },
    ui.Rect {
      id = "draw-board", anchors = { fill = true }, color = function() return C.surface end,
      opacity = function() return model.board:get() and 1 or 0 end,
      visible = function() return model.board:get() end,
      behavior = { opacity = theme.spring.effects },
    },
    ui.Item { id = "draw-marks", anchors = { fill = true }, ui.Repeater { model = model.marks, delegate = mark } },
    draft(), typing(),
    ui.MouseArea {
      id = "draw-area", anchors = { fill = true }, focus = true,
      cursor = function() return model.writing:get() and "text" or "crosshair" end,
      on_pressed = function(x, y)
        if model.writing:get() then model.place(x, y) else model.begin(x, y) end
      end,
      on_position_changed = function(x, y) model.move(x, y) end,
      on_dragged = function(x, y) model.move(x, y) end,
      on_released = function() model.finish() end,
      on_wheel = function(_, _, _, _, _, step_y) model.widen(step_y > 0 and -1 or 1) end,
      on_key_pressed = on_key(finish),
    },
    toolbar(finish),
  }
  return frame.overlay { id = "draw", root = root, close = finish }
end

return M
