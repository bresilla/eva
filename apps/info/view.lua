-- eva-info's window: the machine's name over a card for each kind of fact.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local fit = require("themes.layouts.fit")
local controls = require("common.controls")
local model = require("model")
local S = theme.space

local M = {}

local WIDE = 860
local ROW_H = 28
local HEAD_H = 72
local GUTTER = S.m

local function card(section, width)
  local inner = width - 2 * P.PAD
  local rows = {}
  for index, row in ipairs(section.rows) do rows[index] = { row[1], row[2] } end
  return P.section {
    id = "info-" .. section.key, title = section.title, width = width,
    kit.facts(rows, inner, ROW_H, math.min(math.floor(inner * 0.42), 180)),
  }
end

-- Cards in `across` columns, each going to the shorter one.
local function cards(width)
  local across = width >= WIDE and 2 or 1
  local each = across == 2 and math.floor((width - P.GAP) / 2) or width
  local columns, heights = {}, {}
  for index = 1, across do
    columns[index] = { width = each, gap = P.GAP }
    heights[index] = 0
  end
  for _, section in ipairs(model.sections(model.facts:get())) do
    local shortest = 1
    for index = 2, across do
      if heights[index] < heights[shortest] then shortest = index end
    end
    local column = columns[shortest]
    column[#column + 1] = card(section, each)
    heights[shortest] = heights[shortest] + #section.rows * ROW_H + 2 * P.PAD + L.CAPTION_H + P.GAP
  end
  local row = { width = width, gap = P.GAP }
  for index = 1, across do row[index] = ui.Column(columns[index]) end
  return ui.Row(row)
end

local function body(whole, h)
  return (kit.scroll { id = "info-scroll", width = whole, height = h, clip = true, cards(whole - GUTTER) })
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local copy = 136
  local function text_w() return math.max(1, w() - copy - S.m) end
  local function system() return model.facts:get().system or {} end
  local function body_h() return math.max(1, h() - HEAD_H - S.s) end
  return ui.Item {
    id = "info-root", width = w, height = h,
    ui.Item {
      width = w, height = HEAD_H,
      ui.Column {
        width = text_w, gap = S.xxs, anchors = { vertical_center = true },
        L.heading {
          id = "info-host", width = text_w, elide = "right",
          text = function() return system().hostname or "This machine" end,
        },
        kit.text {
          id = "info-os", width = text_w, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
          text = function() return system().os or "" end,
        },
        ui.Item { width = text_w, height = L.lh(theme.size.small),
          controls.note { id = "info-note", width = text_w, text = function() return model.message:get() end } },
      },
      ui.Item {
        anchors = { right = true, vertical_center = true }, width = copy, height = P.BUTTON_H,
        P.button { id = "info-copy", label = "Copy all", icon = "content_copy", width = copy, on_clicked = model.copy },
      },
    },
    ui.Item {
      y = HEAD_H + S.s, width = w, height = body_h,
      fit.width {
        id = "info-cards", width = w, height = body_h, build = function(width) return body(width, body_h) end,
        key = function() return tostring(model.revision:get()) end,
      },
    },
  }
end

return M
