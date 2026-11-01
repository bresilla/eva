-- The system tray: its rows from a stand-in bus, in the bar with the theme's
-- skin, activation behind the dry run, and the wheel over the bar.
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  local W,H=tonumber(morf.env("TEST_WIDTH")),tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height=H
  local prefs=morf.state {enabled=morf.env("TEST_BAR") or "on",side="top",titles="on",tray="on",
    tray_limit=8,wheel_volume=false,wheel_workspace=false}
  local arranged=morf.signal("tray.fixture.items",{})
  local original=require("config")
  package.loaded.config={get=function(key)
    if key=="edgebar.tray_items" then return arranged:get() end
    local name=key:match("^edgebar%.(.+)$")
    if name then return prefs[name] end
    return original.get(key)
  end,set=function(key,value)
    if key=="edgebar.tray_items" then arranged:set(value) return end
    prefs[key:gsub("^edgebar%.","")]=value
  end}
  package.loaded["lib.services.vpns"]={links=function() return {} end}
  local calls,subscribed,served,closed={},nil,0,0
  local volume,sets,steps=0.5,{},{}
  local items={}
  local PIXELS=string.rep("\255\10\20\30",16*16)
  items[":1.5/StatusNotifierItem"]={Id="notes",Title="Notes",IconName="accessories-text-editor",Status="Active"}
  items[":1.6/StatusNotifierItem"]={Id="chat",Title="",IconName="",Status="NeedsAttention",
    IconPixmap={{16,16,PIXELS}},AttentionIconName=""}
  items[":1.7/StatusNotifierItem"]={Id="idle",Title="Idle",IconName="x",Status="Passive"}
  local fake_bus={call_async=function(bus,destination,path,interface,method,arguments,options,done)
    calls[#calls+1]={destination=destination,path=path,method=method,interface=interface}
    if method=="GetAll" then
      local props=items[destination..path]
      morf.time.timer(1,function() done(true,{props}) end,false)
    end
  end,proxy=function()
    return {subscribe=function() return {close=function() end} end}
  end}
  package.loaded["lib.services.tray"]={serve=function() served=served+1 return {close=function() closed=closed+1 end} end}
  local menu_for
  package.loaded["lib.services.tray_menu"]={for_item=function(address)
    menu_for=address
    return {click=function() end,entries=function() return {{id="1",text="Open",enabled=true,visible=true}} end}
  end}
  morf.ipc.menu_for=function() return menu_for end
  local tray_model=require("tray_model")
  local new_tray=tray_model.new
  tray_model.new=function(opts)
    local model=new_tray({dbus=fake_bus,host={subscribe=function(fn) subscribed=fn end},watcher=package.loaded["lib.services.tray"]})
    return model
  end
  local service={state=setmetatable({},{__index=function(_,key)
    if key=="available" then return true end
  end})}
  package.loaded.services={net=nil,upower=nil,modem=nil,hyprland=nil,
    workspace={active=function() return 1 end,step=function(delta) steps[#steps+1]=delta end}}
  package.loaded.osd={volume=function() return volume end}
  package.loaded.settings_model={levels={set_volume=function(v) sets[#sets+1]=v volume=v end}}
  package.loaded.apps={icon=function() return nil end}
  local function drawer(key)
    local open=morf.signal("tray.fixture."..key,false)
    return {open=open,set=function(on) open:set(on) end}
  end
  package.loaded.launcher={drawer=drawer("launcher")}
  package.loaded.dashboard={drawer=drawer("dashboard")}
  package.loaded.sidebar={drawer=drawer("sidebar"),select=function() end}
  package.loaded.utilities={detail=morf.signal("tray.fixture.detail","")}
  local model
  local models=require("bar_model")
  local create=models.new
  models.new=function(...) model=create(...) return model end
  local bar=require("bar")
  ui.Item {width=W,height=H,bar.build()}
  morf.ipc.items=function(which)
    local list={}
    for word in tostring(which):gmatch("[^,]+") do list[#list+1]={service=":1."..word,path="/StatusNotifierItem"} end
    if subscribed then subscribed(list) end
  end
  morf.ipc.set=function(key,value)
    if value=="true" then value=true elseif value=="false" then value=false end
    prefs[key]=value
  end
  morf.ipc.state=function()
    local rows={}
    if model.tray then for i=1,model.tray.rows:len() do rows[i]=model.tray.rows:get(i) end end
    return {has=model.tray~=nil,served=served,closed=closed,rows=rows,calls=calls,sets=sets,steps=steps,volume=volume}
  end
  morf.ipc.activate=function(address) return model.tray.activate(address) end
  morf.ipc.turn=function(notches) model.wheel_workspace(tonumber(notches)) end
  local tray=require("tray_model")
  morf.ipc.place=function(id,place) model.tray.place(id,place) end
  morf.ipc.move=function(id,by) model.tray.move(id,tonumber(by)) end
  morf.ipc.room_for=function(given,step,count) return tray.room_for(tonumber(given),tonumber(step),tonumber(count)) end
  morf.ipc.more=function()
    local out={}
    for i=1,model.tray.more:len() do out[i]=model.tray.more:get(i).id end
    return out
  end
  morf.ipc.arrange=function()
    local rows={{id="a"},{id="b"},{id="new"},{id="quiet",passive=true},{id="gone"}}
    local order,bar,more=tray.arrange(rows,{{id="b",place="bar"},{id="a",place="more"},{id="gone",place="hide"}},8)
    local function ids(list) local out={} for i,row in ipairs(list) do out[i]=row.id end return out end
    return {order=ids(order),bar=ids(bar),more=ids(more)}
  end
  morf.ipc.rgba=function() return {tray.rgba("\1\2\3\4"):byte(1,4)} end
  morf.ipc.nearest=function()
    local big,small=string.rep("x",4*48*48),string.rep("x",4*16*16)
    return tray.nearest({{16,16,small},{48,48,big},{32,32,""}},44)[1]
  end
]]
local DEVICES=morf.env("EVA_INPUT_DEVICES")
local function load(style,w,h,dry,env)
  env=env or {}
  env.EVA_STYLE,env.EVA_DRY_RUN,env.TEST_WIDTH,env.TEST_HEIGHT=style,dry and "1" or "0",tostring(w),tostring(h)
  env.EVA_INPUT_DEVICES=env.EVA_INPUT_DEVICES or DEVICES
  test.load("../shell/init.lua",{source=HOST,size={w,h},env=env})
  test.advance(500)
end
local function state() return test.ipc("state") end
local function item(n) return test.find {id="bar-tray-item-:1."..n.."/StatusNotifierItem",visible=true} end

test.it("turns an item's ARGB pixels to RGBA and picks the nearest size",function()
  load("material",1920,1080)
  test.eq(test.ipc("rgba"),{2,3,4,1})
  test.eq(test.ipc("nearest"),48)
end)
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." serves a watcher and lists what registers, passive items aside",function()
    load(style,1920,1080)
    test.truthy(state().has) test.eq(state().served,1)
    test.ipc("items","5,6,7") test.advance(100)
    local rows=state().rows
    test.eq(#rows,2)
    test.eq(rows[1].title,"Notes") test.eq(rows[1].icon,"accessories-text-editor")
    test.eq(rows[2].title,"chat") test.truthy(rows[2].pixmap~=nil)
    test.truthy(item(5)~=nil) test.truthy(item(6)~=nil)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." sets the tray beside the status, clear of the clock",function()
    load(style,1920,1080)
    test.ipc("items","5,6") test.advance(500)
    local status=test.get("bar-status") local clock=test.get("bar-clock")
    local node=item(6)
    test.truthy(node.x+node.width<=status.x+1,"over the status")
    test.truthy(item(5).x>=clock.x+clock.width)
  end)
  test.it(style.." opens an item's menu on a right press, in the theme's popup",function()
    load(style,1920,1080)
    test.ipc("items","5") test.advance(100)
    local node=item(5)
    test.click(node.x+node.width/2,node.y+node.height/2,{button="right"}) test.advance(500)
    test.eq(test.ipc("menu_for"),":1.5/StatusNotifierItem")
    test.truthy(test.find {id="bar-tray-item-:1.5/StatusNotifierItem-menu"}~=nil)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." forgets an item that leaves",function()
    load(style,1920,1080)
    test.ipc("items","5,6") test.advance(100)
    test.ipc("items","6") test.advance(100)
    test.eq(#state().rows,1) test.eq(item(5),nil)
  end)
  test.it(style.." activates an item, and a dry run only says so",function()
    load(style,1920,1080)
    test.ipc("items","5") test.advance(100)
    test.click(item(5))
    local last=state().calls[#state().calls]
    test.eq(last.method,"Activate") test.eq(last.destination,":1.5")
    load(style,1920,1080,true)
    test.ipc("items","5") test.advance(100)
    local before=#state().calls
    test.truthy(test.ipc("activate",":1.5/StatusNotifierItem"))
    test.eq(#state().calls,before)
  end)
  test.it(style.." hides where it does not fit, and on a phone",function()
    load(style,1000,700)
    test.ipc("items","5,6") test.advance(100)
    local fits=test.find {id="bar-tray",visible=true}
    test.truthy(fits==nil or fits.x+fits.width<=test.get("bar-status").x+1)
    load(style,868,1932,false,{EVA_INPUT_DEVICES=DEVICES.."-touch"})
    test.falsy(state().has) test.eq(test.find {id="bar-tray",visible=true},nil)
    load(style,1280,800,false,{EVA_INPUT_DEVICES=DEVICES.."-touch"})
    test.truthy(state().has,"a wide touchscreen is a desk, with a desk's tray")
  end)
  test.it(style.." follows its setting, and serves no watcher while it is down",function()
    load(style,1920,1080)
    test.ipc("items","5") test.advance(100)
    test.truthy(item(5)~=nil)
    test.ipc("set","tray","off") test.advance(100)
    test.eq(test.find {id="bar-tray",visible=true},nil)
    test.eq(#state().rows,0) test.eq(state().closed,1)
    test.ipc("set","tray","on") test.advance(100)
    test.eq(state().served,2)
    test.ipc("set","enabled","off") test.advance(100)
    test.eq(state().closed,2)
  end)
  test.it(style.." serves no watcher on a desk with its bar down",function()
    load(style,1920,1080,false,{TEST_BAR="off"})
    test.eq(state().served,0)
  end)
  test.it(style.." hides an item, tucks one behind the arrow, and shows what is there",function()
    load(style,1920,1080)
    test.ipc("items","5,6") test.advance(100)
    test.truthy(item(5)~=nil) test.truthy(item(6)~=nil)
    test.eq(test.find {id="bar-tray-more",visible=true},nil,"nothing is tucked away yet")
    test.ipc("place","chat","hide") test.advance(100)
    test.eq(item(6),nil) test.truthy(item(5)~=nil)
    test.eq(#state().rows,1,"a hidden item is not shown anywhere")
    test.ipc("place","chat","more") test.advance(100)
    test.eq(item(6),nil)
    test.truthy(test.find {id="bar-tray-more",visible=true},"the arrow shows")
    test.eq(test.ipc("more"),{"chat"})
    test.ipc("place","chat","bar") test.advance(100)
    test.truthy(item(6)~=nil)
    test.eq(test.find {id="bar-tray-more",visible=true},nil)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." keeps a person's order, whichever way items arrive",function()
    load(style,1920,1080)
    test.ipc("items","5,6") test.advance(100)
    test.eq(state().rows[1].id,"notes")
    test.ipc("move","chat",-1) test.advance(100)
    test.eq(state().rows[1].id,"chat")
    test.ipc("items","6,5") test.advance(100)
    test.eq(state().rows[1].id,"chat")
    test.ipc("items","5,6") test.advance(100)
    test.eq(state().rows[1].id,"chat")
  end)
  test.it(style.." puts what is past its limit behind the arrow",function()
    load(style,1920,1080)
    test.ipc("items","5,6") test.advance(100)
    test.ipc("set","tray_limit",1) test.advance(100)
    test.truthy(item(5)~=nil) test.eq(item(6),nil)
    test.eq(test.ipc("more"),{"chat"})
    test.truthy(test.find {id="bar-tray-more",visible=true})
  end)
end
test.it("what does not fit gives its place to the arrow",function()
  load("material",1920,1080)
  test.eq(test.ipc("room_for",128,32,5),3)
  test.eq(test.ipc("room_for",32,32,3),1)
  test.eq(test.ipc("room_for",96,32,3),1024)
  test.eq(test.ipc("room_for",0,32,3),1)
end)
test.it("an item goes by its own name, the same each run",function()
  load("material",1920,1080)
  test.ipc("items","5") test.advance(100)
  test.eq(state().rows[1].id,"notes")
  test.eq(state().rows[1].address,":1.5/StatusNotifierItem")
end)
test.it("arranges by a person's list, new items last and passive ones away",function()
  load("material",1920,1080)
  local out=test.ipc("arrange")
  test.eq(out.order,{"b","a","new"})
  test.eq(out.bar,{"b","new"})
  test.eq(out.more,{"a"})
end)
test.it("the wheel over the status changes the volume, with its setting",function()
  load("material",1920,1080)
  local status=test.get("bar-status")
  local at={x=status.x+status.width/2,y=status.y+status.height/2}
  test.wheel(0,1,at) test.advance(50)
  test.eq(#state().sets,0,"off by default")
  test.ipc("set","wheel_volume","true") test.advance(100)
  test.wheel(0,-1,at) test.advance(50)
  test.eq(#state().sets,1) test.near(state().volume,0.55,0.001)
  test.wheel(0,1,at) test.wheel(0,1,at) test.advance(50)
  test.near(state().volume,0.45,0.001)
end)
test.it("the wheel over the clock changes the workspace, with its setting, notch by notch",function()
  load("material",1920,1080)
  local clock=test.get("bar-clock")
  local at={x=clock.x+clock.width/2,y=clock.y+clock.height/2}
  test.wheel(0,1,at) test.advance(50)
  test.eq(#state().steps,0,"off by default")
  test.ipc("set","wheel_workspace","true") test.advance(100)
  test.wheel(0,1,at) test.advance(50)
  test.eq(state().steps,{1})
  test.wheel(0,-1,at) test.advance(50)
  test.eq(state().steps,{1,-1})
  test.ipc("turn",0.4)
  test.eq(#state().steps,2,"a fraction of a notch is not a workspace")
  test.ipc("turn",0.7)
  test.eq(#state().steps,3)
end)
test.it("a dry run leaves the workspace alone",function()
  load("material",1920,1080,true)
  test.ipc("set","wheel_workspace","true") test.advance(100)
  local clock=test.get("bar-clock")
  test.wheel(0,1,{x=clock.x+clock.width/2,y=clock.y+clock.height/2}) test.advance(50)
  test.eq(#state().steps,0)
end)
test.it("a phone has no wheel over its bar",function()
  load("material",868,1932,false,{EVA_INPUT_DEVICES=DEVICES.."-touch"})
  test.eq(test.find {id="bar-wheel-volume",visible=true},nil)
end)
