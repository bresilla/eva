-- The compositor binding that opens the capture panel. The editor's settings
-- change it; the shell restores it after a compositor reload.
local morf=require("morf")
local backend=require("lib.shell.capture")

local M={}

local live="Print"

--- Binds `binding` in place of the live one and saves it: `done(ok, why)`.
function M.apply(config,binding,done)
  if binding==live then return end
  backend.rebind(binding,live,config.get("capture.keybind_file"),function(ok,why)
    if ok then live=binding config.set("capture.hotkey",binding) end
    if done then done(ok,why) end
  end)
end

--- The saved binding on the compositor from now on, on the primary output.
function M.follow(config)
  local hypr=require("lib.compositor.hyprland")
  local function primary() return not morf.window.primary or morf.window.primary() end
  if hypr.on then
    local function restore()
      if primary() then live="Print" M.apply(config,config.get("capture.hotkey")) end
    end
    hypr.on("connected",restore) hypr.on("configreloaded",restore)
  end
  morf.effect("eva.capture.hotkey",function()
    local binding=config.get("capture.hotkey")
    if primary() and hypr.available and hypr.available() then M.apply(config,binding)
    elseif not primary() then live=binding end
  end)
end

return M
