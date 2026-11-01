-- Content that follows a window's shape. `fit.width`: the kit's meters, charts
-- and facts take a number, a window's width moves, so it builds them again when
-- the width changes. `fit.sheet`: what a list's chosen row opens, a column at the
-- side of a wide window and a sheet from the foot of a narrow one.
--
--     fit.width { id = "monitor-resources", width = w, height = h,
--       build = function(number) return node end }
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local S = theme.space

local M = {}

-- How wide a side column is, how tall a sheet may be, and the window width from
-- which a sheet becomes a column.
M.SIDE = 360
M.TALL = 520
M.WIDE = 860

local function get(v) if type(v) == "function" then return v() end return v end

--- `build(width)` under an item `width` by `height` (fns), made again when the
--- width or `key()` changes. `key` is optional: a string for what else it
--- depends on.
function M.width(spec)
  local rows = morf.list_model({})
  morf.effect("eva.fit." .. spec.id, function()
    local name = ("%d:%s"):format(math.floor(get(spec.width)), spec.key and spec.key() or "")
    if rows:len() == 0 or rows:get(1).key ~= name then
      rows:replace({ { key = name, width = math.floor(get(spec.width)) } }, "key")
    end
  end)
  return ui.Item {
    id = spec.id, width = spec.width, height = spec.height,
    ui.Repeater { model = rows, delegate = function(row) return spec.build(math.floor(row.width)) end },
  }
end

--- The width a list keeps beside a sheet of a window `width` (fn) wide, while
--- `open()`.
function M.beside(width, open)
  return function()
    local w = get(width)
    return math.max(1, w - ((w >= M.WIDE and open()) and M.SIDE + S.m or 0))
  end
end

--- What the chosen row opens: `id`, `width`, `height` (fns: the room it has),
--- `open` (fn), `build(w, h)` (the card, `w` and `h` fns). It rises on the theme's
--- spring, down the right of a wide window, from the foot of a narrow one.
function M.sheet(spec)
  local w, h, open = spec.width, spec.height, spec.open
  local function wide() return get(w) >= M.WIDE end
  local function sheet_w() return wide() and M.SIDE or get(w) end
  local function sheet_h() return wide() and get(h) or math.min(get(h), M.TALL) end
  return ui.Item {
    id = spec.id, width = sheet_w, height = sheet_h,
    x = function() return wide() and get(w) - M.SIDE or 0 end,
    y = function() return get(h) - sheet_h() end,
    translate_y = function() return open() and 0 or sheet_h() + S.xl end,
    opacity = function() return open() and 1 or 0 end,
    visible = open,
    behavior = { translate_y = theme.spring.spatial, opacity = theme.spring.effects },
    spec.build(sheet_w, sheet_h),
  }
end

return M
