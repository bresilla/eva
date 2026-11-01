-- The Notes page, in the page template (themes/layouts/page.lua): the notes
-- and a field to find or start one, then the note itself, written or read.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local widgets = require("planner_widgets")
local markup = require("themes.layouts.markup")
local mirror = require("themes.layouts.mirror")
local parse = require("lib.shell.markup")
local C = theme.color
local S = theme.space
local M = {}

local function get(v) if type(v) == "function" then return v() end return v end

function M.build(model, active, w, h)
  local inner = P.inner(w)
  local reading = morf.signal("eva.notes.reading." .. tostring({}), false)
  local function open() return model.selected:get() ~= "" end

  -- ------------------------------------------------------------- the list --
  local search_node, search = widgets.field("notes-search", "Find or start a note", "A name", inner,
    function(text) model.search(text) end,
    function(text)
      if text ~= "" then
        model.create(text)
        search.text = ""
        model.search("")
      end
    end)
  local keeper = ui.Item { width = 1, height = 1 }
  local list = ui.Repeater { as = "column", gap = P.ROW_GAP, width = inner, model = mirror.new(model.rows, "id", keeper),
    delegate = function(row)
      return P.row { id = "notes-row-" .. row.id:gsub("[^%w]", "-"), width = inner, icon = "description",
        title = row.name, subtitle = row.when, trailing = P.chevron(),
        on_clicked = function() model.open(row.id) end }
    end }
  local empty = P.empty { id = "notes-empty", width = w, icon = "sticky_note_2", title = "Nothing written yet",
    text = function() return "Notes are plain files in " .. model.folder() .. "." end,
    visible = function() return model.rows:len() == 0 end }
  local browse = P.page { id = "notes-list", width = w, height = h,
    P.section { id = "notes-find", width = w, search_node,
      P.button { id = "notes-new", label = "New note", icon = "add", tone = "primary", width = inner,
        on_clicked = function()
          model.create(search.text or "")
          search.text = ""
          model.search("")
        end } },
    P.section { id = "notes-all", width = w, title = "Notes", visible = function() return model.rows:len() > 0 end,
      note = function() return tostring(model.rows:len()) end, list },
    empty,
  }
  browse.visible = function() return not open() end

  -- -------------------------------------------------------------- the note --
  local bar_h = P.BUTTON_H
  local body_h = function() return math.max(0, get(h) - bar_h - P.GAP - 24) end
  local input_node, input = kit.text_field("text_area", {
    id = "notes-text", x = S.m, y = S.s, width = function() return get(w) - 2 * S.m end,
    height = function() return body_h() - 2 * S.s end,
    font_family = theme.font, font_size = theme.size.normal, color = function() return C.onSurface end,
    placeholder = "Write here. It saves itself.", placeholder_color = function() return C.onSurfaceVariant end,
    caret_color = function() return C.primary end, selection_color = function() return C.primary:alpha(0.3) end,
    on_text_changed = function(text) model.edited(text) end,
  })
  local well = kit.surface { id = "notes-well", width = w, height = body_h, radius = kit.round(S.s),
    color = function() return C.surfaceContainerHighest end, visible = function() return not reading:get() end, input_node }

  local blocks = morf.list_model({})
  local preview, flick = kit.scroll { id = "notes-preview", width = w, height = body_h, clip = true,
    visible = function() return reading:get() end,
    ui.Column { width = w, gap = S.s,
      markup.view { id = "notes-read", width = w, blocks = blocks,
        on_link = function(href) morf.process.detach { "xdg-open", href } end,
        on_copy = function(_, text) pcall(morf.clipboard.set, text) end } } }

  morf.effect("notes.follow", function()
    model.revision:get()
    local text = model.text:get()
    if input.text ~= text then input.text = text end
    if reading:get() then blocks:replace(parse.blocks(text), "key") end
  end, { owner = input_node })

  local back = P.button { id = "notes-back", label = "Notes", icon = "arrow_back", on_clicked = model.close }
  local tools = ui.Row { anchors = { right = true }, gap = S.s, align = "center",
    P.button { id = "notes-read-toggle", label = function() return reading:get() and "Edit" or "Read" end,
      icon = function() return reading:get() and "edit" or "visibility" end,
      on_clicked = function() reading:set(not reading:get()) end },
    P.button { id = "notes-delete",
      label = function() return model.deleting:get() == model.selected:get() and "Confirm" or "Delete" end,
      icon = "delete", on_clicked = function() model.delete(model.selected:get()) end },
  }
  local status = kit.text { id = "notes-said", width = w, height = 20, font_size = L.SIZE.label, elide = "right",
    color = kit.ink("lo"), text = function()
      local said = model.said:get()
      return model.selected:get() .. (said ~= "" and ("  ·  " .. said) or "")
    end }
  local editor = ui.Column { id = "notes-editor", width = w, height = h, gap = S.xs,
    visible = open,
    ui.Item { width = w, height = bar_h, back, tools }, status, well, preview }

  return ui.Item { id = "notes-page", width = w, height = h, keeper, browse, editor }
end
return M
