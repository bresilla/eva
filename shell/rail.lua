-- Workspace model and preferences. Themes own the rail's layout and motion.
local config=require("config")
local workspace=require("services").workspace
local V=require("themes").view("rail")
-- Nine workspaces per output, retaining Hyprland's decade-based IDs.
local M={COUNT=9,STRIDE=10}
local model={count=M.COUNT,active=workspace.active,occupied=workspace.occupied,
  enabled=function() return config.get("rail.enabled")~=false end,
  hold=function() return config.get("rail.hold") or 800 end,
  desk_size=function() local _,_,w,h=require("bar").desk() return w,h end,
  -- Under a finger the rail runs along the bottom edge: its y, in the rail's
  -- own space (which starts where the desk does), and where the edge starts.
  bottom=require("responsive").sheets(),
  edge=function() local _,_,_,h=require("bar").desk() return h end,
  start=function() return 0 end,
  base=function(id) return id-((id-1)%M.STRIDE) end,
  go=function(id) workspace.go(id) end,
  turn=function(steps) require("workspace_turn")(steps) end}
function M.geometry()
  local g=V.geometry(model)
  g.count,g.enabled=M.COUNT,model.enabled()
  return g
end
--- The span the rail takes along its edge, from and to, or nil with it off.
function M.span()
  local g=M.geometry()
  if not g.enabled then return nil end
  return g.top-g.gap/2,g.top+M.COUNT*(g.item+g.gap)-g.gap/2
end
--- A tap at `x` along the bottom edge: the workspace under it. False where
--- the rail is not there.
function M.tap(x)
  local g=M.geometry()
  if not (model.bottom and g.enabled) then return false end
  local desk_x=require("bar").desk()
  local slot=math.floor((x-desk_x-g.top+g.gap/2)/(g.item+g.gap))+1
  if slot<1 or slot>M.COUNT then return false end
  model.go(model.base(model.active())+slot-1)
  return true
end
function M.build()
  model.leftbar=require("leftbar")
  -- A pointer's way in. A finger's is the bottom strip's (phone_gestures.lua),
  -- which has the swipes that start on the rail as well.
  local targets
  if not require("responsive").touch() then
    M.hits,targets=require("themes.layouts.rail_hits").build(model,function() return V.geometry(model) end)
    model.hovered=function(slot) return targets[slot].hovered end
  end
  local view=V.build(model)
  M.shape=view.shape
  if M.hits and not model.bottom then
    require("kit").ride("rail-hits",M.hits,model.leftbar.drawer,
      function() local theme=require("theme") return theme.SIDE_W+theme.STRIP/2+theme.LEFT/2 end)
  end
  return view.node
end
return M
