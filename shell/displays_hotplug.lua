-- The shell's side of eva-displays: a set of monitors that changes brings its
-- saved profile, and each output's runtime draws that output's name on request.
local morf = require("morf")
local displays = require("lib.shell.displays")

local M = {}

M.SETTLE = 800

local function primary() return not morf.window.primary or morf.window.primary() end

--- Starts following hotplug on the primary output's runtime.
function M.start()
  morf.ipc["displays-identify"] = function()
    require("themes").view("displays_identify").show()
    return true
  end
  local known, settle
  displays.read(function(outputs) known = outputs and displays.key(outputs) or nil end)
  morf.effect("eva.displays.hotplug", function()
    morf.window.screens_revision()
    if settle then settle:cancel() end
    settle = morf.time.timer(M.SETTLE, function()
      settle = nil
      if not primary() then return end
      displays.read(function(outputs)
        if not outputs then return end
        local key = displays.key(outputs)
        if key == known then return end
        known = key
        displays.auto_apply()
      end)
    end, false)
  end)
end

return M
