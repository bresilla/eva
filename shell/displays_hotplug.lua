-- Monitors coming and going: a set that changes brings its saved profile, each
-- output's runtime draws that output's name on request, and `displays VERB`
-- drives the Displays page's arrangement (displays_model.lua) for scripts.
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
  -- `displays state|refresh|select NAME|place NAME X Y|set NAME FIELD VALUE|apply|keep|revert|identify|save-profile NAME`.
  morf.ipc.displays = function(how, a, b, c)
    local model = require("displays_model")
    if how == "state" or how == nil then
      return { outputs = model.outputs:get(), selected = model.selected:get(), message = model.message:get(),
        countdown = model.countdown:get(), dirty = model.dirty:get(), profiles = model.profiles:get() }
    end
    if how == "refresh" then model.refresh() model.load_profiles() return true end
    if how == "select" then model.selected:set(a) return true end
    if how == "place" then model.place(a, tonumber(b), tonumber(c)) model.settle() return true end
    if how == "set" then
      if b == "scale" or b == "transform" then c = tonumber(c)
      elseif b == "enabled" or b == "vrr" then c = c == "true" end
      model.set(a, b, c)
      return true
    end
    if how == "apply" then return model.apply() end
    if how == "keep" then model.keep() return true end
    if how == "revert" then model.revert() return true end
    if how == "identify" then model.identify() return true end
    if how == "save-profile" then return model.save_profile(a) end
    error("`" .. tostring(how) .. "`: state, refresh, select, place, set, apply, keep, revert, identify or save-profile")
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
