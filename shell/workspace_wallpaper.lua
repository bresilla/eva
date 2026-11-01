-- Keep file decoding and SVG rasterization off the gesture/render thread.
local morf=require("morf")
local M={}
local serial=0

--- This screen's size in logical pixels and its scale in 120ths.
function M.screen_size()
  local screen=(morf.screens or {})[1]
  local _,_,w,h=require("bar").desk()
  w=math.max(1,math.ceil(screen and screen.width or w))
  h=math.max(1,math.ceil(screen and screen.height or h))
  local scale=math.max(1,math.floor((screen and screen.density_scale or 1)*120+.5))
  return w,h,scale
end

--- Prepares `source` to cover `w` x `h` on a worker. `done(path)` hears the
--- `memory:` source, or nil when it cannot be prepared. Returns a function
--- that lets it go, or nil when nothing was started.
function M.prepare(source,w,h,scale,done)
  local ok,preview=pcall(morf.image.preview,source)
  if not ok or not preview then return nil end
  local live=true
  local queued,accepted=pcall(preview.cover,w,h,scale,function(success,result)
    if not live then return end
    done(success and result and result.path or nil)
  end)
  if not queued or not accepted then pcall(preview.close) return nil end
  return function()
    live=false
    pcall(preview.close)
  end
end

function M.new()
  serial=serial+1
  local state=morf.state {source=""}
  local release,key,effect
  local revision=0
  local closed=false
  local function retire()
    revision=revision+1
    state.source=""
    if release then release() release=nil end
  end
  local function sync()
    if closed then return end
    local source=require("wallpaper").current:get()
    local w,h,scale=M.screen_size()
    local next_key=source.."\n"..w.."x"..h.."@"..scale
    if key==next_key then return end
    key=next_key retire()
    if source=="" then return end
    local token=revision
    release=M.prepare(source,w,h,scale,function(path)
      if closed or token~=revision then return end
      if path then state.source=path else retire() end
    end)
  end
  effect=morf.effect("phone.workspace.wallpaper."..serial,sync)
  return {
    source=function() return state.source end,
    sync=sync,
    close=function()
      if closed then return end
      closed=true
      effect:dispose()
      retire()
    end,
  }
end
return M
