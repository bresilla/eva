-- The emoji pane, in place of the keys: a grid of the chosen set scrolled by a
-- finger, and along its foot the way back, the search, the sets and backspace.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local S = theme.space
local V = {}

local PREFIX = "eva.keyboard.emoji-"
local CELL = 44

function V.build(parts)
  local model, state, W = parts.model, parts.state, parts.width()
  local emoji = require("lib.shell.emoji")
  local groups = emoji.GROUPS
  local chosen = morf.signal("eva.keyboard.emoji.group", groups[1].id)
  local rows = morf.list_model({})
  local FOOT = S.TARGET
  local columns = math.max(6, math.floor((W - 2 * S.s) / CELL))
  local cell = math.floor((W - 2 * S.s) / columns)
  local function view_height() return math.max(1, parts.board_height() - FOOT - S.s) end

  local function list()
    local id = chosen:get()
    if id == "recent" then return model.recent_emoji() end
    return emoji.group(id)
  end
  local function grid_height()
    return math.ceil(#list() / columns) * cell
  end

  local grid = ui.GridView {
    id = PREFIX .. "grid", width = W - 2 * S.s, height = view_height, cell_width = cell, cell_height = cell,
    columns = columns, overscan = 2, model = rows,
    delegate = function(row)
      local text = ui.Text { anchors = { center_in = true }, text = row.char, font_size = math.floor(cell * .6),
        font_family = theme.emoji_font, color = kit.ink("hi") }
      return ui.Item { width = cell, height = cell, text }, function(next_row) text.text = next_row.char end
    end,
  }
  local hit = ui.MouseArea {
    id = PREFIX .. "cells", width = W - 2 * S.s, height = grid_height,
    on_clicked = function(_, _, x, y)
      local column = math.min(columns - 1, math.floor((x or 0) / cell))
      local at = math.floor((y or 0) / cell) * columns + column + 1
      local row = list()[at]
      if row then model.type_emoji(row.char) end
    end,
  }
  local scroller, flick = kit.scroll { id = PREFIX .. "scroll", width = W - 2 * S.s, height = view_height, clip = true, hit }
  morf.effect("eva.keyboard.emoji.rows", function()
    rows:replace(list(), "char")
  end, { owner = grid })
  morf.effect("eva.keyboard.emoji.sync", function()
    morf.sync_view(grid, flick.content_y or 0)
  end, { owner = grid })

  -- The foot: back to the letters, search, each set, backspace.
  local tabs = { { id = "recent", icon = "history", name = "Recent" } }
  for _, group in ipairs(groups) do tabs[#tabs + 1] = group end
  local spare = W - 2 * S.s
  local wide = math.floor(spare / (#tabs + 4))
  local foot = { id = PREFIX .. "foot", x = S.s, y = view_height, width = spare, height = FOOT }
  local x = 0
  local function button(id, icon, name, span, run, on)
    local node = L.icon_button { id = PREFIX .. id, x = x, width = span, height = FOOT, icon = icon, size = 20,
      name = name, on = on, on_clicked = run }
    x = x + span
    foot[#foot + 1] = node
  end
  button("letters", "keyboard", "Letters", wide * 2, function() state.show_pane("keys") end)
  button("search", "search", "Search emoji", wide, model.start_search)
  for _, tab in ipairs(tabs) do
    button("tab-" .. tab.id, tab.icon, tab.name, wide, function()
      chosen:set(tab.id)
      flick.content_y = 0
    end, function() return chosen:get() == tab.id end)
  end
  button("delete", "backspace", "Delete", spare - x, function() model.strike { key = "backspace" } end)

  return ui.Item {
    id = "eva.keyboard.emoji", width = W, height = parts.board_height,
    ui.Item { x = S.s, width = W - 2 * S.s, height = view_height, clip = true, grid, scroller },
    ui.Item(foot),
  }
end

return V
