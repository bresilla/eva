-- Touch gestures belong to the whole frame, including touches that start
-- on its bar or workspace rail. Only the edge strips claim new input area;
-- the middle of the desktop continues to belong to application windows.
local ui = require("morf.ui")
local M = {}
-- Dotfiles can update before the installed engine. Older Morf releases
-- keep their completed-swipe handling until continuous pans are available.
local probe = ui.Item {}
M.continuous = pcall(function() probe.on_panned = function() end end)
ui.destroy(probe)
local attached = {}
local EDGE = 20 -- Matches the runtime's on_edge_swiped recognition zone.
local SIDE = 2 * EDGE -- How far in from a side a drag along it starts.
local CATCH = require("themes.keyboard").CATCH -- How far above the bottom strip a second finger may land.
-- A pull up this far, resting this long within this much, is a hold.
local HOLD_RISE, HOLD_MS, HOLD_SLOP = 64, 220, 6
local function native_enabled()
  local gate=rawget(_G,"__morf_global_recognizers_enabled")
  return type(gate)~="function" or gate()==true
end
local global_enabled=morf.signal("eva.global.recognizers",native_enabled())
local cancel_global={}
local cancel_surface={}
function M.global_allowed() local enabled=global_enabled:get() return enabled and native_enabled() end
local function regions_visible() return global_enabled:get() end
function M.handoff(enabled)
  if global_enabled:get()~=enabled then
    global_enabled:set(enabled)
    if not enabled then
      for _,cancel in ipairs(cancel_global) do cancel() end
    end
  end
  return enabled or morf.env("EVA_GESTURE_DRIVER")~="lisgd"
end

-- The drawer a pull from `edge` drags: the one hanging from that edge in
-- this layout, the one hovering the edge opens on a desk. Sheets leave the
-- side edges to the launcher.
local function drawer_at(edge)
  local names=require("responsive").sheets() and {"sidebar","dashboard"}
    or {"dashboard","bottom","sidebar","leftbar"}
  for _,name in ipairs(names) do
    local drawer=require(name).drawer
    if drawer.edge==edge then return drawer end
  end
end

local function pulls_sidebar(edge,drawer)
  return edge=="top" and drawer==require("sidebar").drawer
end

-- `own`: the drawer asking, which does not block its own pull.
local function blocked(own)
  for _, name in ipairs { "polkit", "keyring", "authsteps", "session" } do
    local controller = package.loaded[name]
    if name ~= own and controller and controller.drawer and controller.drawer.open:get() then return true end
  end
  local capture = package.loaded.capture
  return capture and capture.editor and capture.editor.active:get()
end

M.blocked=blocked

local function close_other_panels(keep)
  for _, drawer in ipairs(require("drawer").all) do
    if drawer ~= keep and drawer.name~="keyboard" then drawer.set(false) end
  end
end
M.close_panels=close_other_panels

-- The global driver reads the touchscreen: two fingers are its, and the strip
-- has no need to reach for a second one.
local function driven()
  local driver=package.loaded.touch_driver
  return driver~=nil and driver.owns()
end

-- Two fingers landed together, read by the driver: no strip begins on one of them.
local function together()
  local driver=package.loaded.touch_driver
  return driver~=nil and driver.owns() and driver.together()
end

--- Lets go of whatever an edge strip holds: two fingers landed together. With
--- `panels`, what a panel's own pan holds as well: a global gesture has begun.
function M.yield(panels)
  for _,cancel in ipairs(cancel_global) do cancel() end
  if not panels then return end
  for _,cancel in ipairs(cancel_surface) do cancel() end
  for _,drawer in ipairs(require("drawer").all) do drawer.end_drag(0,true) end
end

local function top_page(x)
  local width=(morf.screens[1] or {}).width or morf.surface.width
  return (tonumber(x) or 0)>=width/2 and "settings" or "notifications"
end

local function select_top(sidebar,x)
  local page=top_page(x)
  sidebar.select(page)
  if page=="settings" then require("utilities").request("") end
end

function M.swipe(edge,x)
  if not M.global_allowed() or blocked() then return end
  local drawer=drawer_at(edge)
  if drawer then
    close_other_panels(drawer)
    if pulls_sidebar(edge,drawer) then select_top(require("sidebar"),x) end
    drawer.set(true)
  elseif edge == "left" or edge == "right" then
    local launcher = require("launcher")
    close_other_panels(launcher.drawer)
    require("menus").open(edge == "left" and "apps" or "web")
    launcher.set_query("")
    launcher.drawer.set(true)
  end
end

-- Horizontal navigation belongs to a panel, not a fullscreen gesture
-- overlay. The runtime bubbles a swipe past passive content, retaining a
-- slider's drag and a notification's own dismissal. A swipe turns the tab
-- while a page lies that way; toward the edge the panel hangs from (`dismiss`)
-- with none left, it shuts it.
function M.panel(spec)
  return function(direction)
    if blocked() then return end
    local step = ({ left = 1, right = -1 })[direction]
    local next_tab = step and spec.tab:get() + step
    if next_tab and next_tab >= 1 and next_tab <= spec.count then
      spec.tab:set(next_tab)
    elseif direction == spec.dismiss and spec.close and
        (not spec.can_dismiss or spec.can_dismiss()) then
      spec.close()
    end
  end
end

-- The open panel over (`x`, `y`), if there is one.
local function over_panel(x, y)
  if not (x and y) then return nil end
  local drawers = package.loaded.drawer
  for _, drawer in ipairs(drawers and drawers.all or {}) do
    local panel = drawer.panel
    if drawer.name ~= "keyboard" and drawer.open:get()
      and x >= (panel.layout_x or 0) and x < (panel.layout_x or 0) + (panel.layout_width or 0)
      and y >= (panel.layout_y or 0) and y < (panel.layout_y or 0) + (panel.layout_height or 0) then
      return drawer
    end
  end
end

--- Whether an open panel lies under (`x`, `y`).
function M.on_panel(x, y) return over_panel(x, y) ~= nil end

--- Whether a pull `direction` from (`x`, `y`) drags an open panel shut, so a
--- list under the finger leaves it to the panel.
function M.pulls_shut(direction, x, y)
  local drawer = over_panel(x, y)
  return drawer ~= nil and drawer.pulled == direction
end

-- Each recognizer owns one contact; its begin can decline to a parent. A
-- page beside the one on show takes a sideways drag first; past the last, or
-- with none, a drag toward the edge the panel hangs from pulls it shut under
-- the finger, and the pager's ends take the rest on their rubber band. On
-- the panel's `grip` (fn of the start point: its tab row) it always shuts.
function M.pan(spec)
  if not M.continuous then return nil end
  local drawer, pager
  cancel_surface[#cancel_surface+1]=function()
    if pager then pager.finish(0,true) pager=nil end
    drawer=nil
  end
  return function(phase, dx, dy, vx, vy, x, y)
    if phase == "begin" then
      if blocked(spec.drawer) then return false end
      local dismiss = type(spec.dismiss) == "function" and spec.dismiss() or spec.dismiss
      local across = dismiss == "left" or dismiss == "right"
      local horizontal = math.abs(dx) >= math.abs(dy)
      local toward = ({ up = -dy, down = dy, left = -dx, right = dx })[dismiss or ""]
      local shuts = toward and toward > 0 and horizontal == across
        and (not spec.can_dismiss or spec.can_dismiss())
      local gripped = shuts and spec.grip and spec.grip(x, y)
      if horizontal and spec.pager and not gripped and (not shuts or spec.pager.can(dx)) then
        pager = spec.pager
        return pager.begin()
      end
      if shuts then
        drawer = require(spec.drawer).drawer
        return drawer.begin_drag()
      end
      return false
    elseif (pager or drawer) and blocked(spec.drawer) then
      if pager then pager.finish(0,true) pager=nil end
      if drawer then drawer.end_drag(0,true) drawer=nil end
    elseif pager then
      if phase=="update" then pager.update(dx)
      else pager.finish(vx,phase=="cancel") pager=nil end
    elseif drawer then
      local travel, velocity = dy, vy
      if drawer.edge == "left" or drawer.edge == "right" then travel, velocity = dx, vx end
      if phase == "update" then drawer.drag_by(travel)
      else drawer.end_drag(velocity,phase=="cancel") drawer=nil end
    end
  end
end

local edge_drawer, edge_across, side_edge
cancel_global[#cancel_global+1]=function()
  if edge_drawer then edge_drawer.end_drag(0,true) edge_drawer=nil end
  side_edge=nil
end
function M.edge_pan(edge,phase,dx,dy,vx,vy,start_x,start_y)
  if not M.global_allowed() then return false end
  if phase == "begin" then
    edge_drawer,side_edge=nil,nil
    if blocked() or together() then return false end
    local inward = ({top=dy,bottom=-dy,left=dx,right=-dx})[edge]
    if not inward or inward <= 0 then return false end
    edge_across = edge == "left" or edge == "right"
    -- On an open panel its own gestures come first.
    if edge_across and over_panel(start_x,start_y) then return false end
    if edge_across then
      local height=(morf.screens[1] or {}).height or morf.surface.height
      local bottom=height-require("themes.keyboard").inset:get()-EDGE
      if math.abs(dx)<=math.abs(dy)*1.2 or not start_y or start_y<EDGE or start_y>=bottom then
        return false
      end
    end
    local drawer=drawer_at(edge)
    if not drawer then
      if not edge_across then return false end
      side_edge=edge
      return true
    end
    -- Choose from where the finger landed, even if it crosses the middle
    -- during the pull. Repeated pulls from the same side keep that page.
    if pulls_sidebar(edge,drawer) then select_top(require("sidebar"),start_x) end
    edge_drawer=drawer
    close_other_panels(edge_drawer)
    return edge_drawer.begin_drag()
  elseif side_edge then
    if blocked() or phase=="cancel" then side_edge=nil
    elseif phase=="end" then
      local origin=side_edge
      side_edge=nil
      local sign=origin=="left" and 1 or -1
      local distance,velocity=dx*sign,(vx or 0)*sign
      local motion=require("gesture_motion")
      -- Finish on release so a short pull, reversal or second finger can
      -- cancel before the centered launcher takes keyboard focus.
      if distance>math.abs(dy)*1.2 and velocity>-motion.FLING and
        (distance>=80 or (distance>=motion.TRAVEL and velocity>=motion.FLING)) then
        M.swipe(origin)
      end
    end
  elseif edge_drawer and blocked() then
    edge_drawer.end_drag(0,true) edge_drawer=nil
  elseif edge_drawer then
    local travel,velocity=dy,vy
    if edge_across then travel,velocity=dx,vx end
    if phase == "update" then edge_drawer.drag_by(travel)
    else edge_drawer.end_drag(velocity,phase=="cancel") edge_drawer=nil end
  end
end

local context_attached={}
local function attach_context(root)
  if context_attached[root] then return end
  context_attached[root]=true
  -- Semantic geometry remains laid out while duplicated native recognizers
  -- are inhibited. These Items take no input and cannot grant ownership.
  local function height() return root.layout_height or 0 end
  local function inset() return require("themes.keyboard").inset:get() end
  local function side_height() return math.max(0,height()-inset()-2*EDGE) end
  local function half_width() return (root.layout_width or 0)/2 end
  local function context(role,props)
    props.id="phone-context-"..role
    props.input_context={role=role}
    return ui.Item(props)
  end
  ui.reparent(ui.Item {id="phone-context",anchors={fill=true},z=-2,
    context("top_left",{height=EDGE,width=half_width,anchors={top=true,left=true}}),
    context("top_right",{height=EDGE,width=half_width,anchors={top=true,right=true}}),
    context("side_left",{width=EDGE,y=EDGE,height=side_height,anchors={left=true}}),
    context("side_right",{width=EDGE,y=EDGE,height=side_height,anchors={right=true}}),
    context("content_bottom",{height=EDGE,anchors={left=true,right=true},
      y=function() return height()-inset()-EDGE end}),
    context("physical_bottom",{height=EDGE,anchors={bottom=true,left=true,right=true}}),
  },root)
end

function M.attach(root)
  attach_context(root)
  if attached[root] then return end
  attached[root] = true
  if morf.env("EVA_GESTURE_DRIVER")=="lisgd" then
    local clear=require("lisgd_gestures").attach(root,{blocked=blocked,allowed=M.global_allowed,visible=regions_visible,
      swipe=M.swipe,close_panels=close_other_panels})
    cancel_global[#cancel_global+1]=clear
    return
  end
  local preview=require("workspace_gesture").new(root)
  M.workspace_controller=preview
  M.workspace_preview=preview.state
  local mode,drawer
  -- A pull up from the bottom that stops and holds is recents, not the panel.
  local waiting,held_at
  local function stop_waiting()
    if waiting then waiting:cancel() waiting=nil end
    held_at=nil
  end
  local function recents_amount(dy)
    local height=(morf.screens[1] or {}).height or morf.surface.height
    return .4+.6*math.min(1,-dy/math.max(1,height*.4))
  end
  local function watch_hold(dy)
    if held_at and math.abs(dy-held_at)<=HOLD_SLOP then return end
    stop_waiting()
    held_at=dy
    if -dy<HOLD_RISE or #require("windows_model").list()==0 then return end
    waiting=morf.time.timer(HOLD_MS,function()
      waiting=nil
      if mode~="dashboard" or not drawer then return end
      drawer.end_drag(0,true)
      drawer=nil
      mode="recents"
      require("overview").follow(recents_amount(held_at))
    end,false)
  end
  -- The bottom edge walks the apps on a phone, and the workspaces elsewhere.
  local function by_apps()
    return require("responsive").phone() and require("config").get("windows.scrub")~="workspaces"
      and #require("windows_model").list()>1
  end
  local function single(phase,dx,dy,vx,vy)
    if phase=="begin" then
      mode,drawer=nil,nil
      stop_waiting()
      return
    end
    if phase=="cancel" then
      stop_waiting()
      if mode=="workspace" then preview.cancel()
      elseif mode=="recents" then require("overview").settle(false)
      elseif drawer then drawer.end_drag(0,true) end
      mode,drawer=nil,nil
      return
    end
    if phase=="update" then
      if not mode and math.max(math.abs(dx),math.abs(dy))>=8 then
        if math.abs(dx)>math.abs(dy)*1.2 then
          close_other_panels(nil)
          preview.begin("x",by_apps()) mode="workspace"
        elseif -dy>math.abs(dx)*1.2 and drawer_at("bottom") then
          drawer=drawer_at("bottom")
          close_other_panels(drawer)
          drawer.begin_drag() mode="dashboard"
        elseif math.abs(dy)>math.abs(dx)*1.2 then mode="ignored" end
      end
      if mode=="workspace" then preview.update(dx)
      elseif mode=="recents" then require("overview").follow(recents_amount(dy))
      elseif drawer then drawer.drag_by(dy) watch_hold(dy) end
    elseif phase=="end" then
      stop_waiting()
      if mode=="workspace" then preview.update(dx) preview.finish(false,vx,M.global_allowed)
      elseif mode=="recents" then require("overview").settle(true)
      elseif drawer then
        drawer.drag_by(dy) drawer.end_drag(vy or 0,false)
      end
      mode,drawer=nil,nil
    end
  end
  local gestures=require("keyboard_gestures")
  local contacts=gestures.contacts("bottom",function() return M.global_allowed() and not blocked() end,
    function(phase,dx,dy,x)
      if phase=="end" and not mode and math.max(math.abs(dx),math.abs(dy))<8 then require("rail").tap(x) end
      single(phase,dx,dy,0,0)
    end)
  cancel_global[#cancel_global+1]=function()
    contacts.cancel() single("cancel") preview.cancel()
    mode="ignored"
  end
  -- The bottom strip owns the gesture so a second finger can cancel
  -- an in-progress panel/workspace pull before choosing the keyboard.
  if M.continuous then root.on_edge_panned=function(edge,...)
    if edge~="bottom" then return M.edge_pan(edge,...) end
    return false
  end
  else root.on_edge_swiped=function(edge) if edge~="bottom" then M.swipe(edge) end end end
  -- On a desk a drag up or down along either side scrolls the workspaces.
  if M.continuous then
    local rail
    cancel_global[#cancel_global+1]=function() if rail then rail.cancel() rail=nil end end
    root.on_panned=function(phase,dx,dy,vx,vy,x)
      if phase=="begin" then
        rail=nil
        if not M.global_allowed() or blocked() or together() or require("responsive").sheets() then return false end
        if math.abs(dy)<=math.abs(dx)*1.2 or not x then return false end
        -- From the rail itself, or a finger's width in from a bare side.
        local width=(morf.screens[1] or {}).width or morf.surface.width
        local insets=require("bar").insets()
        if x>math.max(SIDE,insets.left) and x<width-math.max(SIDE,insets.right) then return false end
        for _,drawer in ipairs(require("drawer").all) do
          if drawer.open:get() and drawer.name~="keyboard" then return false end
        end
        rail=preview
        return rail.begin("y")
      elseif rail then
        if phase=="update" then rail.update(dy)
        elseif phase=="end" then rail.update(dy) rail.finish(false,vy,M.global_allowed) rail=nil
        else rail.cancel() rail=nil end
      end
    end
  end
  -- Under the existing controls: tapping the bar/rail still reaches them.
  -- An Item, rather than a fullscreen MouseArea, leaves apps interactive.
  ui.reparent(ui.Item {
    id = "phone-gesture-edges", anchors = { fill = true }, z = -1,visible=regions_visible,
    ui.MouseArea { id = "phone-gesture-top", height = EDGE,
      anchors = { top = true, left = true, right = true } },
    ui.MouseArea { id = "phone-gesture-left", width = EDGE, y = EDGE,
      anchors = { left = true }, height = function()
        return math.max(0,((morf.screens[1] or {}).height or morf.surface.height)
          -require("themes.keyboard").inset:get()-2*EDGE)
      end },
    ui.MouseArea { id = "phone-gesture-right", width = EDGE, y = EDGE,
      anchors = { right = true }, height = function()
        return math.max(0,((morf.screens[1] or {}).height or morf.surface.height)
          -require("themes.keyboard").inset:get()-2*EDGE)
      end },
  }, root)
  -- A finger resting on the strip lets it reach higher (themes.keyboard).
  local reach=gestures.reach("eva.gesture.bottom.held")
  local stretch=reach.hold
  function reach.hold(on) stretch(on and not driven()) end
  local hold=reach.hold
  local function floor()
    return ((morf.screens[1] or {}).height or morf.surface.height)-require("themes.keyboard").inset:get()
  end
  local bottom={id="phone-gesture-bottom",height=reach.height,z=200,visible=regions_visible,
    anchors={left=true,right=true},y=function() return floor()-reach.height() end}
  if M.continuous then
    -- A touch no pan took is a tap: the workspace under it, on the rail.
    local tapped
    bottom.on_touch_pressed=function(_,x) hold(true) tapped=x end
    bottom.on_touch_released=function()
      hold(false)
      if tapped and M.global_allowed() and not blocked() then require("rail").tap(tapped) end
      tapped=nil
    end
    bottom.on_panned=function(phase,dx,dy,vx,vy)
      if phase=="begin" then
        tapped=nil
        if not M.global_allowed() or blocked() or together() then return false end
        single("begin") single("update",dx,dy,vx,vy)
        return mode=="workspace" or mode=="dashboard"
      end
      if phase~="update" then hold(false) end
      if not M.global_allowed() or blocked() then single("cancel") return end
      single(phase,dx,dy,vx,vy)
    end
    bottom.on_two_finger_panned=function(phase,dx1,dy1,dx2,dy2,x1,y1,x2,y2)
      if phase=="begin" then
        if driven() or not M.global_allowed() or blocked() or require("keyboard").active() then return false end
        -- One finger from the edge itself, the other from it or the band above.
        return math.max(y1,y2)>=floor()-EDGE and math.min(y1,y2)>=floor()-EDGE-CATCH
      end
      if phase~="update" then hold(false) end
      if phase=="end" and M.global_allowed() and not blocked() and dy1<=-48 and dy2<=-48
        and -dy1>math.abs(dx1)*1.2 and -dy2>math.abs(dx2)*1.2 then
        require("keyboard").show("full")
      end
    end
    ui.reparent(ui.MouseArea(bottom),root)
  else ui.reparent(gestures.strip(contacts,reach,floor,bottom),root) end
end

return M
