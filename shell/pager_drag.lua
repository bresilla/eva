-- Pages slide as one track under the finger, on every form. Selection changes
-- only on release, leaving actions and keyboard navigation on a committed page.
--
--     local pager = require("pager_drag").new {
--       id = "panel", track = row, tab = tab, count = #tabs,
--       offset = function(i) return (i - 1) * width end,
--     }
--     node.on_panned = pager.on_panned
--
-- The track's `translate_x` is the pager's: a view leaves it unset. `shown`
-- (a signal, `tab` by default) is the page it rests on, `spring` how it gets
-- there on its own, `instant` (fn) when it jumps instead, `prepare` runs as a
-- drag starts, `peeking(on)` as neighbours come on show and go.
local morf=require("morf")
local theme=require("theme")
local motion=require("gesture_motion")
local rubber=require("themes.rubber_band")
local M={}
function M.new(spec)
  local p={}
  local held
  local shown=spec.shown or spec.tab
  local slid=false
  local function peek(on) if spec.peeking then spec.peeking(on) end end
  local axis=require("themes.drawer_axis").new {
    node=spec.track,property="translate_x",name="eva.pager."..spec.id,
    spring=spec.spring or theme.spring.spatial,instant=spec.instant,
    out=function() return false end,
    away=function() return -spec.offset(shown:get()) end,
    landed=function() end,
  }
  --- Whether a page lies beside the one on show, the way a drag of `dx` goes.
  function p.can(dx)
    local next_page=spec.tab:get()+(dx<0 and 1 or -1)
    return next_page>=1 and next_page<=spec.count
  end
  function p.begin()
    held={x=axis.grab(),index=spec.tab:get(),dx=0}
    peek(true)
    if spec.prepare then spec.prepare() end
    return true
  end
  function p.update(dx)
    if not held then return end
    held.dx=dx
    held.at=rubber.between(held.x+dx,-spec.offset(spec.count),0)
    axis.drag(held.at)
  end
  --- Whether a finger brought on the selection the track rests on: asked once.
  function p.slid()
    local was=slid
    slid=false
    return was
  end
  function p.finish(vx,canceled)
    if not held then return end
    local index,at=held.index,held.at or held.x
    if not canceled then
      local closest=math.huge
      for i=1,spec.count do
        local distance=math.abs(at+spec.offset(i))
        if distance<closest then index,closest=i,distance end
      end
      if motion.fling(held.dx,vx) then
        -- A reversal heads back to the page under the finger; it must not
        -- skip a whole page just because the drag began on another one.
        if vx<0 then
          for i=1,spec.count do if -spec.offset(i)<at then
            index=math.max(index,i) break end end
        else
          for i=spec.count,1,-1 do if -spec.offset(i)>at then
            index=math.min(index,i) break end end
        end
        index=math.max(1,math.min(spec.count,index))
      end
    end
    if index~=held.index then
      slid=true
      require("haptics").fire("commit")
    end
    held=nil
    spec.tab:set(index)
    axis.release(canceled and 0 or vx,function() peek(false) end)
  end
  --- A handler for a node that only pages: sideways drags are the track's.
  function p.on_panned(phase,dx,dy,vx)
    if phase=="begin" then return math.abs(dx)>math.abs(dy) and p.begin() end
    if phase=="update" then p.update(dx) else p.finish(vx,phase=="cancel") end
  end
  return p
end
return M
