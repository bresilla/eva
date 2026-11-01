-- eva-clipboard's window: a search field over the history, each entry copied by
-- a press, with a pin and a delete at its end.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local L = require("themes.layouts.parts")
local P = require("themes.layouts.page")
local model = require("model")
local S = theme.space

local M = {}

local ROWS = 60
local ROW_H = 56
local THUMB = 40

local function row(index, w, found)
  local function item() return found()[index] end
  local function image() local it = item() return it ~= nil and it.kind == "image" end
  local actions = S.TARGET * 2 + S.s
  local press = kit.action {
    id = "clipboard-row-" .. index, width = function() return math.max(1, w() - actions - S.s) end, height = ROW_H,
    cursor = "pointer", on_clicked = function() local it = item() if it then model.copy(it.id) end end,
    ui.Image {
      id = "clipboard-thumb-" .. index, width = THUMB, height = THUMB, x = S.xs,
      anchors = { vertical_center = true }, fill_mode = "preserve_aspect_crop", source_width = 96,
      visible = image, source = function() local it = item() return it and it.path or "" end,
    },
    kit.text {
      id = "clipboard-text-" .. index, anchors = { vertical_center = true }, elide = "right",
      x = function() return image() and THUMB + S.m or S.xs end,
      width = function() return math.max(1, w() - actions - THUMB - S.xl) end,
      font_size = theme.size.normal, color = kit.ink("hi"),
      text = function()
        local it = item()
        if not it then return "" end
        if it.kind == "image" then return "Picture" end
        return (it.text:gsub("%s+", " "))
      end,
    },
  }
  return ui.Item {
    id = "clipboard-entry-" .. index, width = w, height = ROW_H,
    visible = function() return item() ~= nil end,
    press,
    ui.Row {
      anchors = { right = true, vertical_center = true }, gap = S.s,
      L.icon_button {
        id = "clipboard-pin-" .. index, icon = "keep", name = "Pin", width = S.TARGET, height = S.TARGET,
        on = function() local it = item() return it ~= nil and it.pinned == true end,
        on_clicked = function() local it = item() if it then model.toggle_pin(it.id) end end,
      },
      L.icon_button {
        id = "clipboard-delete-" .. index, icon = "delete", name = "Delete", width = S.TARGET, height = S.TARGET,
        on_clicked = function() local it = item() if it then model.remove(it.id) end end,
      },
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local function found() return model.found() end
  local clear = 120
  local field = kit.text_field("entry", {
    id = "clipboard-search", width = function() return math.max(1, w() - clear - S.s) end, height = S.TARGET,
    placeholder = "Search the history", color = kit.ink("hi"), placeholder_color = kit.ink("lo"),
    focus = true,
    text = function() return model.query:get() end,
    on_text_changed = function(value) model.query:set(value) end,
  })
  local list = { gap = S.xxs, width = w }
  for index = 1, ROWS do list[index] = row(index, w, found) end
  local foot = S.TARGET + S.m
  local function body() return math.max(1, h() - foot) end
  return ui.Item {
    id = "clipboard-root", width = w, height = h,
    ui.Row {
      gap = S.s, align = "center", field,
      P.button { id = "clipboard-clear", label = "Clear", width = clear, on_clicked = model.clear },
    },
    ui.Item {
      y = foot, width = w, height = body,
      P.empty {
        id = "clipboard-empty", icon = "content_paste", title = "Nothing copied yet",
        text = "What you copy shows here. Passwords are skipped.", width = w,
        visible = function() return #found() == 0 end,
      },
      (kit.scroll { id = "clipboard-list", width = w, height = body, clip = true, ui.Column(list) }),
    },
  }
end

return M
