-- eva-update: what waits on this machine, and on NixOS a rebuild with its log.
-- `--check` writes how many to the file EVA_UPDATE_OUT names, with no window, and
-- ends.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")

if (morf.options or {}).check then
  frame.quiet()
  model.start(function()
    local out = morf.env("EVA_UPDATE_OUT")
    if out then morf.fs.write(out, ("%d\n"):format(model.pending()), { mode = 384 }) end
    morf.quit()
  end)
  return
end

local view = require("view")

model.start()

frame.open {
  id = "update", title = "Updates", width = 840, height = 720,
  on_close = function() model.cancel() end,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  local log = {}
  for index = 1, math.min(model.rows:len(), 60) do log[index] = model.rows:get(index).text end
  return { nixos = model.nixos:get(), flake = model.flake:get(), inputs = model.inputs:get(), managers = model.managers:get(),
    state = model.state:get(), message = model.message:get(), lines = model.lines:get(), log = log, argv = model.argv(),
    pending = model.pending(), tab = model.TABS[model.tab:get()] }
end
morf.ipc.tab = function(name) return model.select_tab(name) end
morf.ipc.rebuild = function() return model.rebuild() end
morf.ipc.cancel = function() return model.cancel() end
morf.ipc.check = function() model.start() return true end
