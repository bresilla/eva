-- Controllers supply one cached audio model per presented Settings page.
local models=require("sound_model")
local presentation=require("presentation")
local view=require("themes").view("sound_page")
local M={}
function M.output_page(w,h)
  local model=models.new("output",presentation.active("settings.sound"))
  model.open_equalizer=function() require("utilities").request("sound/equalizer") end
  model.open_more=function() require("utilities").request("sound/more") end
  return view.build(model,w,h)
end
function M.more_page(w,h)
  local model=models.new("output",presentation.active("settings.sound/more"),"sound/more")
  return view.more(require("sound_extras_model").extend(model),w,h)
end
function M.input_page(w,h)
  return view.build(require("sound_extras_model").extend(models.new("input",presentation.active("settings.microphone"))),w,h)
end
return M
