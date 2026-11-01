local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  local W,H=tonumber(morf.env("TEST_WIDTH")),tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height=H
  local here=morf.signal("test.notifications.here",true)
  package.loaded.services={here=function() return here:get() end}
  package.loaded.bar={desk=function() return 10,10,W-20,H-20 end}
  local change,remote={},{}
  local dismissed={}
  package.loaded["lib.services.notifications"]={serve=function(options)
    change=options.on_change
    return {open=function(id) return remote[id]~=nil end,
      dismiss=function(id)
        dismissed[#dismissed+1]=id remote[id]=nil
        local list={} for _,entry in pairs(remote) do list[#list+1]=entry end
        change(list)
      end}
  end}
  local notifications=require("notifs")
  local C=require("theme").color
  ui.Item {width=W,height=H,
    ui.Rect {width=W,height=H,color=function() return C.surface end},
    ui.Item {x=10,y=10,width=W-20,height=H-20,
      ui.Sdf {anchors={fill=true},fill_color=function() return C.surfaceContainer end,notifications.drawer.shape},
      notifications.drawer.panel},
  }
  morf.ipc.push=function(summary,body,urgency,timeout)
    return notifications.push {summary=summary,body=body,urgency=tonumber(urgency),timeout_ms=tonumber(timeout),app=summary}
  end
  morf.ipc.state=function()
    local ids={} for _,entry in ipairs(notifications.shown()) do ids[#ids+1]=entry.id end
    return {ids=ids,history=#notifications.history:get(),open=notifications.drawer.open:get(),dismissed=dismissed}
  end
  morf.ipc.remote=function(id)
    id=tonumber(id)
    remote[id]={id=id,app="Remote app",summary="Remote notification",body="From the server",urgency=2}
    local list={} for _,entry in pairs(remote) do list[#list+1]=entry end
    change(list)
  end
  morf.ipc.dnd=function(on) notifications.dnd:set(on=="yes") end
  morf.ipc.cover=function(on) notifications.covered:set(on=="yes") end
  morf.ipc.here=function(on) here:set(on=="yes") end
  morf.ipc.expand=function(id) notifications.toggle(tonumber(id)) end
  morf.ipc.expanded=function(id) return notifications.expanded(tonumber(id)) end
  morf.ipc.forget=function(id) notifications.forget(tonumber(id)) end
  morf.ipc.clear=notifications.clear
  morf.ipc.place=function(position) require("config").set("osd.notifications",position) end
]]
local loads=0
-- `position`, a top or bottom anchor, is written before the shell starts.
local function load(style,w,h,position)
  loads=loads+1
  local settings=morf.fs.join(morf.env("XDG_CACHE_HOME"),"notification-spec-"..loads..".json")
  if position then morf.fs.write(settings,morf.json.encode {osd={notifications=position}}) end
  test.load("../shell/init.lua",{source=HOST,size={w or 1100,h or 750},env={
    EVA_STYLE=style,TEST_WIDTH=tostring(w or 1100),TEST_HEIGHT=tostring(h or 750),EVA_SETTINGS=settings}})
end
local function snapshot(name)
  if morf.env("EVA_THEME_SNAPSHOTS")=="1" then test.snapshot(name..".png") end
end
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." popups preserve expansion, identity during dismissal, and history",function()
    load(style)
    local first=test.ipc("push","Build complete","<b>All checks</b> passed &amp; artifacts are ready.","1","20000")
    test.advance(2400)
    test.truthy(test.ipc("state").open)
    test.eq(test.get("notification-body-1").text,"All checks passed & artifacts are ready.")
    local h=test.get("notification-1").height
    test.click("notification-expand-1") test.advance(400)
    test.truthy(test.ipc("expanded",tostring(first)))
    test.truthy(test.get("notification-1").height>h)
    snapshot(style.."-notification-expanded")
    local card=test.get("notification-1")
    test.click(card.x+20,card.y+20) test.advance(60)
    local second=test.ipc("push","New arrival","Must survive the previous dismissal.","2")
    test.advance(2500)
    test.eq(test.ipc("state").ids,{second})
    test.eq(test.ipc("state").history,2)
    test.falsy(test.ipc("expanded",tostring(first)))
    test.near(test.get("notification-1").opacity,1,0.001)
    test.ipc("forget",tostring(first)) test.eq(test.ipc("state").history,1)
    test.ipc("clear") test.advance(1100)
    test.falsy(test.ipc("state").open)
    test.eq(test.ipc("state").history,0)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." popup expiry, DND, history coverage and focused output stay shared",function()
    load(style)
    test.ipc("dnd","yes")
    test.ipc("push","Quiet notification","Saved in history","1","900")
    test.advance(400) test.falsy(test.ipc("state").open)
    test.eq(test.ipc("state").history,1)
    test.advance(600) test.eq(#test.ipc("state").ids,0)
    test.eq(test.ipc("state").history,1)
    test.ipc("push","Critical notification","Stays until dismissed","2")
    test.advance(6000) test.eq(#test.ipc("state").ids,1)
    test.ipc("dnd","no") test.advance(2200)
    test.truthy(test.ipc("state").open)
    snapshot(style.."-notification-critical")
    test.ipc("cover","yes") test.advance(1000) test.falsy(test.ipc("state").open)
    test.ipc("cover","no") test.advance(2200) test.truthy(test.ipc("state").open)
    test.ipc("here","no") test.advance(1000) test.falsy(test.ipc("state").open)
    test.ipc("here","yes") test.advance(2200) test.truthy(test.ipc("state").open)
    if style=="tsugumori" then test.eq(test.get("notification-summary-1-text").text,"CRITICAL NOTIFICATION") end
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." stands at a bottom anchor with the newest card nearest the edge",function()
    load(style,1100,750,"bottom_center")
    test.ipc("push","Older","First in","2") test.advance(200)
    test.ipc("push","Newer","Second in","2") test.advance(2400)
    local panel=test.get("drawer-notifications")
    test.near(panel.y+panel.height,740,1,"it does not hang from the bottom edge")
    test.near(panel.x+panel.width/2,550,12,"it is not in the middle")
    test.truthy(test.get("notification-1").y>test.get("notification-2").y,"the newest is not nearest the edge")
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." moves along its edge as its setting changes",function()
    load(style)
    test.ipc("push","Moving","Along the top","2") test.advance(2400)
    local right=test.get("notification-1").x
    test.ipc("place","top_left") test.advance(32)
    local moving=test.get("notification-1").x
    test.truthy(moving<right,"it did not start for the left")
    test.advance(900)
    local left=test.get("notification-1").x
    test.truthy(left<moving and left<100,"it did not reach the left")
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." a swipe sends a card sideways or away from its edge, again and again",function()
    load(style,1100,750,"top_center")
    local function card()
      test.ipc("push","Swipe me","Somewhere","2") test.advance(2400)
      local node=test.get("notification-1")
      return node.x+node.width/2,node.y+node.height/2
    end
    local function gone() return #test.ipc("state").ids==0 end
    -- Sideways, either way, on the same slot.
    for _,side in ipairs {200,-200} do
      local x,y=card()
      test.drag({x,y},{x+side/2,y},{steps=6})
      test.advance(40)
      test.drag({x,y},{x+side,y},{steps=6})
      test.advance(600)
      test.truthy(gone(),"a sideways swipe did not dismiss it")
    end
    -- Away from the top edge.
    local x,y=card()
    test.press(x,y) test.move(x,y+20) test.move(x,y+60)
    test.truthy(test.get("notification-1").y>y-200,"it did not follow the finger")
    test.move(x,y+120) test.release(x,y+120)
    test.advance(600)
    test.truthy(gone(),"a swipe away from the edge did not dismiss it")
    -- Into the edge there is no room: it stays and springs back.
    x,y=card()
    test.drag({x,y},{x,y-120},{steps=6}) test.advance(500)
    test.falsy(gone(),"a swipe into the edge dismissed it")
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." a short pull springs back and a card follows the finger after a dismissal",function()
    load(style)
    test.ipc("push","First","Goes","2") test.advance(2400)
    local node=test.get("notification-1")
    local x,y=node.x+node.width/2,node.y+node.height/2
    test.drag({x,y},{x-200,y},{steps=6}) test.advance(600)
    test.ipc("push","Second","Stays","2") test.advance(2400)
    local before=test.get("notification-1").x
    test.press(x,y) test.move(x-20,y) test.move(x-50,y) test.advance(320)
    test.near(test.get("notification-1").x,before-50,6,"the slot lost the finger after its first dismissal")
    test.move(x-40,y) test.release(x-40,y) test.advance(1200)
    test.near(test.get("notification-1").x,before,1,"a short pull did not spring back")
    test.eq(#test.ipc("state").ids,1)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." dismisses server-owned notifications through the server",function()
    load(style) test.ipc("remote","19") test.advance(2400)
    test.click("notification-1") test.advance(1300)
    test.eq(test.ipc("state").dismissed,{19})
    test.eq(test.ipc("state").history,1)
    test.falsy(test.ipc("state").open)
  end)
end
test.it("Tsugumori acquires new notifications after the panel reveals without marking older slots",function()
  load("tsugumori")
  test.ipc("push","New message","Registration waits for the curtain.","2")
  test.advance(280) test.advance(220) test.advance(60)
  test.falsy(test.get("drawer-notifications-curtain").visible)
  test.truthy(test.get("notification-1-register-1").opacity>0)
  snapshot("tsugumori-notification-registration")
  test.advance(500)
  test.ipc("push","Another message","The older one should not flash.","2")
  test.advance(80)
  test.truthy(test.get("notification-1-register-1").opacity>0)
  test.near(test.get("notification-2-register-1").opacity,0,.001)
  test.eq(#test.logs("error"),0)
end)
test.it("Tsugumori notification stack stays within a compact output when expanded",function()
  load("tsugumori",800,480)
  local body=string.rep("An expanded notification with more detail. ",8)
  for i=1,6 do local id=test.ipc("push","Notification "..i,body,"2") test.ipc("expand",tostring(id)) end
  test.advance(2400)
  local panel=test.get("drawer-notifications")
  test.truthy(panel.x>=0 and panel.x+panel.width<=800)
  test.truthy(panel.y>=0 and panel.y+panel.height<=480)
  test.truthy(test.get("notification-stack").height<5*test.get("notification-1").height)
  snapshot("tsugumori-notifications-compact")
  test.wheel(0,1000,{x=panel.x+80,y=panel.y+80}) test.advance(600)
  local last,viewport=test.get("notification-5"),test.get("notification-stack")
  test.truthy(last.y>=viewport.y and last.y+last.height<=viewport.y+viewport.height+1,
    "the last displayed notification cannot be reached by scrolling")
  test.eq(#test.logs("warn"),0)
  test.eq(#test.logs("error"),0)
end)
