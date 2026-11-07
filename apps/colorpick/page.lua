-- eva-colorpick's page in the Tools window: the colour last picked in each
-- format, the recent colours, and a control that picks another. The pick is
-- eva-colorpick's own program, the frozen screen with its magnifier.
local model = require("apps.colorpick.model")
local overlay = require("apps.common.overlay_page")

local M = {}

local function pick() overlay.start("colorpick", { "--pick" }) end

-- What the pick wrote: the recent colours, the newest the one on show.
local function reload()
  model.load()
  local newest = model.recent:get()[1]
  if newest and newest ~= model.picked:get() then model.picked:set(newest) end
end

--- The page, `w` by `h`.
function M.build(w, h)
  reload()
  return require("apps.colorpick.view").build(function() return w end, function() return h end, pick)
end

function M.shown(on) if on then reload() end end

-- `morf ipc call tool colorpick VERB`.
M.verbs = {
  state = function()
    return { picked = model.picked:get(), format = model.format:get(), recent = model.recent:get(),
      message = model.message:get() }
  end,
  format = function(name) model.format:set(name) return true end,
  lule = function(hex) model.send_to_lule(hex) return true end,
  pick = function() pick() return true end,
}

return M
