-- Controllers supply one cached audio model per presented Settings page, live
-- while the page shows or the launcher lists its devices.
local models=require("sound_model")
local presentation=require("presentation")
local view=require("themes").view("sound_page")
local M,instances={},{}
local function shared(kind,key)
  if not instances[kind] then
    local page,mode=presentation.active("settings."..key),presentation.active("launcher."..key)
    instances[kind]=models.new(kind,function() return page() or mode() end)
  end
  return instances[kind]
end
function M.output_model() return shared("output","sound") end
function M.input_model()
  local model=shared("input","microphone")
  if not model.cards then require("sound_extras_model").extend(model) end
  return model
end
function M.output_page(w,h)
  local model=M.output_model()
  model.open_equalizer=function() require("utilities").request("sound/equalizer") end
  model.open_more=function() require("utilities").request("sound/more") end
  return view.build(model,w,h)
end
-- What restarting the sound server last said, "" before it is asked.
local restarted=require("morf").signal("eva.sound.restarted","")
--- Restarts the sound server, for what only that fixes.
function M.restart()
  restarted:set("Restarting…")
  require("lib.services.host").act({"systemctl","--user","restart","wireplumber","pipewire","pipewire-pulse"},
    function(out,why) restarted:set(out and "Restarted" or ("Could not restart: "..tostring(why))) end)
end
function M.more_page(w,h)
  local model=models.new("output",presentation.active("settings.sound/more"),"sound/more")
  model.restart,model.restarted=M.restart,function() return restarted:get() end
  return view.more(require("sound_extras_model").extend(model),w,h)
end
function M.input_page(w,h)
  return view.build(M.input_model(),w,h)
end
return M
