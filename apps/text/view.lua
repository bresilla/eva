-- eva-text's window: the pad over pages of what can be done to it. A press replaces
-- the pad's text, and Undo brings it back.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("apps.common.controls")
local transforms = require("apps.text.transforms")
local model = require("apps.text.model")
local S = theme.space

local M = {}

local COLUMNS = 3
local ROWS = 4
local ICON = S.TARGET

local function grid(group, w)
  local function cell_w() return math.max(1, math.floor((w() - S.s * (COLUMNS - 1)) / COLUMNS)) end
  local cells = { width = w, columns = COLUMNS, gap = S.s, id = "text-" .. group.key .. "-grid" }
  for _, item in ipairs(group.items) do
    cells[#cells + 1] = P.button {
      id = "text-do-" .. item.id, label = item.name, width = cell_w, on_clicked = function() model.apply(item.id) end,
    }
  end
  return ui.Grid(cells)
end

local function make_page(w)
  local lengths = {}
  for index, length in ipairs(model.LENGTHS) do lengths[index] = tostring(length) end
  local function line_w() return math.max(1, w() - ICON - S.s) end
  local line = kit.text {
    id = "text-secret", width = line_w, elide = "middle", font_family = theme.mono, font_size = theme.size.normal,
    color = kit.ink("hi"), text = "", anchors = { vertical_center = true },
  }
  model.on_secret(function(value) line.text = value end)
  return ui.Column {
    width = w, gap = S.s,
    P.buttons {
      width = w,
      { id = "text-make-password", label = "Password", tone = "primary", on_clicked = model.make_password },
      { id = "text-make-passphrase", label = "Passphrase", tone = "primary", on_clicked = model.make_passphrase },
    },
    controls.segments {
      id = "text-length", width = w, items = lengths, current = function() return model.length:get() end,
      on_changed = function(index) model.length:set(index) end,
    },
    ui.Item {
      width = w, height = S.TARGET,
      ui.Item { width = line_w, height = S.TARGET, clip = true, line },
      L.icon_button {
        id = "text-secret-copy", icon = "content_copy", name = "Copy the secret", width = ICON, height = ICON,
        x = line_w, on_clicked = model.copy_secret,
      },
    },
    controls.note { id = "text-made", width = w, text = function() return model.made:get() end },
    P.buttons {
      width = w,
      { id = "text-make-uuid", label = "UUID", on_clicked = model.uuid },
      { id = "text-make-lorem", label = "Lorem", on_clicked = model.lorem },
    },
  }
end

local function tool_button(id, icon, name, action, enabled)
  return L.icon_button { id = id, icon = icon, name = name, width = ICON, height = ICON, on_clicked = action, ignored = enabled }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local tabs = {}
  for _, group in ipairs(transforms.GROUPS) do
    tabs[#tabs + 1] = { key = group.key, name = group.name, icon = group.icon,
      build = function(page_w) return grid(group, page_w) end }
  end
  tabs[#tabs + 1] = { key = "make", name = "Make", icon = "casino", build = function(page_w) return make_page(page_w) end }
  local page_h = ROWS * (P.BUTTON_H + S.s) + L.lh(theme.size.small) + S.xl
  local bar = S.TARGET + S.s
  local foot = controls.TABS_H + S.s + page_h + L.lh(theme.size.small) + S.s
  local function pad_h() return math.max(S.TARGET * 3, h() - foot - bar - S.s) end
  local pages = controls.pages {
    id = "text", width = w, tab = model.tab, height = controls.TABS_H + S.s + page_h, tabs = tabs,
  }
  return ui.Item {
    id = "text-root", width = w, height = h,
    ui.Column {
      width = w, gap = S.s,
      (kit.text_field("text_area", {
        id = "text-pad", width = w, height = pad_h, placeholder = "Paste text here", focus = true,
        color = kit.ink("hi"), placeholder_color = kit.ink("lo"), inset = { S.s, S.s, S.s, S.s },
        text = function() return model.text:get() end,
        on_text_changed = function(value) model.text:set(value) end,
      })),
      ui.Item {
        width = w, height = S.TARGET,
        controls.note {
          id = "text-counts", width = function() return math.max(1, w() - 4 * (ICON + S.xs)) end,
          text = function()
            local c = transforms.counts(model.text:get())
            return ("%d lines · %d words · %d chars"):format(c.lines, c.words, c.characters)
          end,
        },
        ui.Row {
          anchors = { right = true }, gap = S.xs, align = "center",
          tool_button("text-undo", "undo", "Undo", model.undo, function() return model.undoing:get() == 0 end),
          tool_button("text-paste", "content_paste", "Paste", model.paste),
          tool_button("text-copy", "content_copy", "Copy", model.copy),
          tool_button("text-clear", "delete", "Clear", model.clear),
        },
      },
      pages,
      controls.note { id = "text-note", width = w, text = function() return model.message:get() end },
    },
  }
end

return M
