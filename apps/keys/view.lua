-- eva-keys' window: a search field over the list of bindings.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local model = require("model")
local S = theme.space

local M = {}

local ROWS = 200
local KEYS = 280
local NARROW = 620

local function row(index, w, found)
  local function item() return found()[index] end
  local function narrow() return w() < NARROW end
  local function keys_w() return narrow() and w() * 0.45 or KEYS end
  return ui.Item {
    id = "keys-row-" .. index, width = w, height = S.TARGET,
    visible = function() return item() ~= nil end,
    kit.text {
      id = "keys-row-" .. index .. "-keys", width = keys_w, anchors = { vertical_center = true }, elide = "right",
      font_size = theme.size.normal, color = kit.ink("accent"),
      text = function() local it = item() return it and it.keys or "" end,
    },
    kit.text {
      id = "keys-row-" .. index .. "-what", x = function() return keys_w() + S.m end,
      width = function() return math.max(1, w() - keys_w() - S.m) end,
      anchors = { vertical_center = true }, elide = "right",
      font_size = theme.size.normal, color = kit.ink("hi"),
      text = function() local it = item() return it and it.what or "" end,
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local found_list, found_query, found_rows
  local function found()
    local query, rows = model.query:get(), model.rows:get()
    if query ~= found_query or rows ~= found_rows then
      found_query, found_rows = query, rows
      found_list = model.found()
    end
    return found_list
  end
  local field = kit.text_field("search", {
    id = "keys-search", width = w, height = S.TARGET, placeholder = "Search the bindings",
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"), focus = true, inset = S.m,
    text = function() return model.query:get() end,
    on_text_changed = function(value) model.query:set(value) end,
  })
  local list = { gap = S.xxs, width = w }
  for index = 1, ROWS do list[index] = row(index, w, found) end
  local foot = S.TARGET + S.m
  local scroll = kit.scroll {
    id = "keys-list", width = w, clip = true,
    height = function() return math.max(1, h() - foot) end,
    ui.Column(list),
  }
  return ui.Item {
    id = "keys-root", width = w, height = h,
    field,
    ui.Item { y = foot, width = w, height = function() return math.max(1, h() - foot) end, scroll },
    kit.text {
      id = "keys-count", z = 2, anchors = { right = true, bottom = true, bottom_margin = S.xs },
      font_size = theme.size.small, color = kit.ink("lo"),
      text = function()
        local shown = #found()
        return shown == 1 and "1 binding" or (shown .. " bindings")
      end,
    },
  }
end

return M
