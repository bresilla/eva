-- A host for the command-line specs: runs an argv and hands back its result.
local morf = require("morf")
local ui = require("morf.ui")
local result
morf.ipc.run = function(...)
  result = nil
  morf.process.run({ ... }, {}, function(done) result = done end)
  return true
end
morf.ipc.result = function() return result end
ui.Item { width = 1, height = 1 }
