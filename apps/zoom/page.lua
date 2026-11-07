-- eva-zoom's page in the Tools window: the factor on a slider, for touch, and a
-- control that opens the lens. On Hyprland the slider is its cursor zoom, live;
-- elsewhere it is the lens's factor. The lens is eva-zoom's own program, over a
-- frozen picture of the whole screen.
local model = require("apps.zoom.model")
local overlay = require("apps.common.overlay_page")

local M = {}

local function lens() overlay.start("zoom", { "lens" }) end

local loaded = false
local function load()
  if loaded then return end
  loaded = true
  model.load()
end

--- The page, `w` by `h`.
function M.build(w, h)
  load()
  return require("apps.zoom.view").build(function() return w end, function() return h end, lens)
end

function M.shown(on) if on and loaded and model.native() then model.read() end end

-- `morf ipc call tool zoom VERB`.
M.verbs = {
  state = function()
    load()
    return { factor = model.factor:get(), cursor = model.cursor:get(), native = model.native(),
      message = model.message:get() }
  end,
  set = function(value) load() model.set(tonumber(value)) return true end,
  lens = function() lens() return true end,
}

return M
