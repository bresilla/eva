-- eva-info: about this machine. `--json` and `--text` write the facts to the file
-- EVA_INFO_OUT names, with no window, and end.
local morf = require("morf")
local frame = require("common.frame")
local model = require("model")

local options = morf.options or {}
if options.json or options.text then
  frame.quiet()
  model.gather(function(facts)
    local ok, text = pcall(function()
      return options.json and morf.json.encode(facts) .. "\n" or model.text(facts)
    end)
    local out = morf.env("EVA_INFO_OUT")
    if out then morf.fs.write(out, ok and text or ("eva-info: " .. tostring(text) .. "\n"), { mode = 384 }) end
    morf.quit()
  end)
  return
end

local view = require("view")

model.gather()

frame.open {
  id = "info", title = "About this machine", width = 960, height = 760,
  build = function(w, h) return view.build(w, h) end,
}

morf.ipc.state = function()
  return { facts = model.facts:get(), sections = model.sections(model.facts:get()), message = model.message:get() }
end
morf.ipc.text = function() return model.text() end
morf.ipc.copy = function() return model.copy() end
