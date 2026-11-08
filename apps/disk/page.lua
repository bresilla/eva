-- eva-disk's page in the Tools window: what takes the room under a folder, as
-- a treemap. A scan under way stops when the page goes from show, and starts
-- again when it comes back.
local model = require("apps.disk.model")

local M = {}

local started, visible, folder, interrupted = false, false, nil, false
local function ready()
  if started then return end
  started = true
  model.start(folder)
end

--- The page, `w` by `h`.
function M.build(w, h)
  ready()
  return require("apps.disk.view").build(function() return w end, function() return h end)
end

--- `eva-disk FOLDER`: the page on that folder.
function M.open(args)
  if not args[1] or args[1] == "" then return end
  if started then model.open(args[1]) else folder = args[1] end
end

function M.shown(on)
  if on == visible then return end
  visible = on
  if not started then return end
  if not on and model.scanning:get() then
    model.stop()
    interrupted = true
  elseif on and interrupted then
    interrupted = false
    model.refresh()
  end
end

-- `morf ipc call tool disk VERB`.
M.verbs = {
  state = function()
    ready()
    local names = {}
    for index, entry in ipairs(model.entries:get()) do
      if index > 40 then break end
      names[index] = { name = entry.name, size = entry.size, dir = entry.dir }
    end
    return { path = model.path:get(), entries = names, total = model.total:get(), scanning = model.scanning:get(),
      message = model.message:get(), boxes = model.boxes:get(), crumbs = model.crumbs(model.path:get()),
      moving = model.moving:get(), tab = model.TABS[model.tab:get()], mounts = model.mounts() }
  end,
  open = function(path) ready() return model.open(path) end,
  up = function() return model.up() end,
  press = function(index) return model.press(tonumber(index)) end,
  refresh = function() return model.refresh() end,
  reveal = function() return model.reveal() end,
  tab = function(name) return model.select_tab(name) end,
}

return M
