-- Desktop bindings for the keyboard gestures shared with lock and greet.
local shared=require("themes.keyboard")
local M={area=shared.area,strip=shared.strip,reach=shared.reach}
function M.contacts(region,allowed,single)
  local function keyboard() return require("keyboard") end
  -- With the touch driver reading, it acts on these gestures, once.
  local function driven()
    local driver=package.loaded.touch_driver
    return driver~=nil and driver.owns()
  end
  return shared.contacts(region,{
    allowed=function() return (region~="bottom" or require("phone_gestures").global_allowed())
      and (not allowed or allowed()) end,
    active=function() return keyboard().active() end,
    show=function(mode) if not driven() then return keyboard().show(mode) end end,
    hide=function() if not driven() then return keyboard().set(false) end end,
    mode=function() return keyboard().keys.mode:get() end,
    cancel=function()
      local kb=package.loaded.keyboard
      if kb and kb.keys then kb.keys.cancel() end
    end,
    height=function() return (((morf.screens or {})[1] or {}).height or morf.surface.height)-shared.inset:get() end,
  },single)
end
return M
