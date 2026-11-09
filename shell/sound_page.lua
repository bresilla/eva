-- Controllers supply one cached audio model per presented Settings page, live
-- while the page shows, in the Settings window or the quick controls' panel,
-- or the launcher lists its devices.
local models=require("sound_model")
local presentation=require("presentation")
local view=require("themes").view("sound_page")
local M,instances={},{}
local function shared(kind,key)
  if not instances[kind] then
    local page,quick,mode=presentation.active("settings."..key),presentation.active("quick."..key),
      presentation.active("launcher."..key)
    instances[kind]=models.new(kind,function() return page() or quick() or mode() end)
  end
  return instances[kind]
end
function M.output_model() return shared("output","sound") end
function M.input_model()
  local model=shared("input","microphone")
  if not model.cards then require("sound_extras_model").extend(model) end
  return model
end
--- The Sound page on `host` (the Settings window or the panel): Microphone
--- opens where Sound is on show, the rest in the window.
function M.output_page(w,h,host)
  local function settings() return require("utilities") end
  local page=setmetatable({
    open_equalizer=function() settings().request("sound/equalizer") end,
    open_more=function() settings().request("sound/more") end,
    open_input=function() (host or settings()).request("microphone","sound") end,
  },{__index=M.output_model()})
  return view.build(page,w,h)
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
