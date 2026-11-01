-- Content the kit draws at a number: its meters, charts and facts take a width,
-- a window's width moves. `fit.width` builds it again when the width changes.
--
--     fit.width { id = "monitor-resources", width = w, height = h,
--       build = function(number) return node end }
local morf = require("morf")
local ui = require("morf.ui")

local M = {}

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

return M
