-- Blocks of lib/shell/markup.lua as nodes, in the theme's type and colours:
-- headings, paragraphs, lists, quotes, code with its copy button.
--
--     local blocks = morf.list_model(markup.blocks(text))
--     local node = M.view { id = "note", width = w, blocks = blocks,
--       on_link = open, on_copy = function(id, text) end }
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local C = theme.color
local S = theme.space
local M = {}

local function get(v) if type(v) == "function" then return v() end return v end

--- `spans` of markup, as a Text's runs.
function M.runs(spans)
  local out = {}
  for i, span in ipairs(spans or {}) do
    if type(span) ~= "table" then
      out[i] = span
    else
      local run = { text = span.text, bold = span.bold, italic = span.italic, strike = span.strike, link = span.link }
      if span.code then run.family, run.color = theme.mono, C.primary:hex() end
      out[i] = run
    end
  end
  return out
end

local function words(block, width, size, weight, on_link)
  return kit.text { width = width, wrap = true, font_size = size, font_weight = weight, color = kit.ink("hi"),
    link_color = function() return C.primary end, on_link = on_link, cursor = "pointer",
    spans = function() return M.runs(block.spans) end }
end

local function code_block(block, spec, id)
  local text = kit.text { text = block.text, wrap = true, font_family = theme.mono, font_size = L.SIZE.body,
    color = kit.ink("hi"), x = S.m, y = S.s, width = function() return get(spec.width) - 2 * S.m end }
  local language = kit.text { text = block.language or "", font_size = L.SIZE.label, color = kit.ink("lo"),
    x = S.m, y = S.s }
  local copy = spec.on_copy and kit.action { id = id .. "-copy", accessible_name = "Copy the code", width = 32, height = 32,
    cursor = "pointer", anchors = { right = true, top = true }, on_clicked = function() spec.on_copy(id, block.text) end,
    kit.icon("content_copy", 16, kit.ink("lo"), { anchors = { center_in = true } }) } or nil
  local header = ui.Item { width = spec.width, height = 32, language, copy }
  local body = ui.Item { width = spec.width, height = function() return (text.layout_height or 0) + 2 * S.s end, text }
  local column = ui.Column { width = spec.width, header, body }
  local node = kit.surface { id = id, width = spec.width, radius = kit.round(S.s),
    height = function() return column.layout_height or 0 end,
    color = function() return C.surfaceContainerHighest end, column }
  return node, function(next)
    text.text = next.text
    language.text = next.language or ""
    block = next
  end
end

local function block_node(block, spec, id)
  local width = spec.width
  if block.kind == "code" then return code_block(block, spec, id) end
  if block.kind == "table" then
    local text = kit.text { text = block.text, wrap = false, font_family = theme.mono, font_size = L.SIZE.label,
      color = kit.ink("hi"), width = width, clip = true }
    return text, function(next) text.text = next.text end
  end
  if block.kind == "rule" then
    return ui.Rect { width = width, height = 1, color = function() return C.outlineVariant end }
  end
  local node
  if block.kind == "heading" then
    local size = block.level == 1 and L.SIZE.title or theme.size.normal + (block.level == 2 and 2 or 0)
    node = words(block, width, size, 600, spec.on_link)
  elseif block.kind == "item" then
    local indent = S.m * (block.depth or 0)
    local mark = kit.text { text = block.mark, font_size = theme.size.normal, color = kit.ink("lo"), x = indent }
    node = words(block, function() return get(width) - indent - S.xl end, theme.size.normal, 400, spec.on_link)
    local inner = node
    node = ui.Item { width = width, height = function() return inner.layout_height or 0 end, mark, inner }
    inner.x = indent + S.xl
    return node, function(next)
      mark.text = next.mark
      inner.spans = function() return M.runs(next.spans) end
    end
  elseif block.kind == "quote" then
    local inner = words(block, function() return get(width) - S.m end, theme.size.normal, 400, spec.on_link)
    inner.x = S.m
    local box = ui.Item { width = width, height = function() return inner.layout_height or 0 end,
      ui.Rect { width = 2, height = function() return inner.layout_height or 0 end, color = function() return C.primary end },
      inner }
    return box, function(next) inner.spans = function() return M.runs(next.spans) end end
  else
    node = words(block, width, theme.size.normal, 400, spec.on_link)
  end
  return node, function(next) node.spans = function() return M.runs(next.spans) end end
end

--- The blocks in a column: `id`, `width`, `blocks` (a list model keyed by
--- `key`), `on_link(href)`, `on_copy(id, text)`.
function M.view(spec)
  return ui.Repeater { as = "column", gap = S.s, width = spec.width, model = spec.blocks,
    delegate = function(block)
      return block_node(block, spec, spec.id .. "-" .. block.key:gsub(":", "-"))
    end }
end

return M
