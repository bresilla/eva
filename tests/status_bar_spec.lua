-- The status bar: the collapse order, each indicator from its source and live,
-- nothing shown for hardware that is not there, and the bar's own geometry.
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  local W,H=tonumber(morf.env("TEST_WIDTH")),tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height=H
  morf.time.now=function() return 1790584200 end
  local prefs=morf.state {enabled="on",side="top",titles="on"}
  local original=require("config")
  package.loaded.config={get=function(key)
    local name=key:match("^edgebar%.(.+)$")
    if name then return prefs[name] end
    return original.get(key)
  end,set=function(key,value) prefs[key:gsub("^edgebar%.","")]=value end}
  package.loaded["lib.services.vpns"]={links=function() return {} end}
  local data=morf.state {present=morf.env("TEST_NO_BATTERY")~="1",percentage=64,state="discharging",
    charging=false,available=true,on_battery=true,mode="sound",wifi_connected=false,strength=0,
    time_to_empty=0,time_to_full=0,
    bluetooth=0,dnd=false,vpn=false,hotspot=false,modem=false,signal=70,tor=false,alarm=false,night=false,saver=false}
  local function rows(fn) return {len=function() return #fn() end,get=function(_,i) return fn()[i] end} end
  local net={state=setmetatable({},{__index=function(_,key)
    if key=="available" then return true end
    if key=="wifi" then return {connected=data.wifi_connected,strength=data.strength} end
    if key=="wired" then return {connected=false} end
    if key=="access_points" then return rows(function() return {} end) end
    if key=="vpn_connections" then return rows(function() return data.vpn and {{active=true}} or {} end) end
  end})}
  local function device(field)
    return function()
      return {present=function() return true end,on=function() return data[field] end}
    end
  end
  package.loaded.quick_hardware={hotspot=device("hotspot"),nightlight=device("night")}
  local upower={state=setmetatable({},{__index=function(_,key)
    if key=="display" then return data end
    if key=="profiles" then return {available=true,active=data.saver and "power-saver" or "balanced"} end
    if key=="devices" then return rows(function() return {} end) end
    return data[key]
  end}),charge_limit=function() return nil end}
  local modem={state=setmetatable({},{__index=function(_,key)
    if key=="available" then return data.modem end
    if key=="registered" then return true end
    if key=="locked" then return false end
    if key=="technology" then return "5G" end
    return data[key]
  end})}
  package.loaded.services={net=net,upower=upower,modem=modem,ringer={state=data},
    bt={state=setmetatable({},{__index=function(_,key)
      if key=="available" then return true end
      if key=="connected_count" then return data.bluetooth end
    end})},
    tor={on=function() return data.tor end},
    alarm={armed=function() return data.alarm end},
    hyprland=nil,workspace={active=function() return 1 end}}
  package.loaded.apps={icon=function() return nil end}
  local function drawer(key)
    local open=morf.signal("status.fixture."..key,false)
    return {open=open,set=function(on) open:set(on) end}
  end
  package.loaded.launcher={drawer=drawer("launcher")}
  package.loaded.dashboard={drawer=drawer("dashboard")}
  local tab=morf.signal("status.fixture.tab","")
  package.loaded.sidebar={drawer=drawer("sidebar"),select=function(key) tab:set(key) end}
  package.loaded.utilities={detail=morf.signal("status.fixture.detail","")}
  local model
  local models=require("bar_model")
  local create=models.new
  models.new=function(...) model=create(...) return model end
  local bar=require("bar")
  ui.Item {width=W,height=H,ui.Rect {anchors={fill=true},color=function() return require("theme").color.surface end},bar.build()}
  morf.ipc.set=function(key,value)
    if value=="true" then value=true elseif value=="false" then value=false else value=tonumber(value) or value end
    data[key]=value
  end
  morf.ipc.side=function(value) bar.set_side(value) end
  morf.ipc.dnd=function(on) require("themes.session").keep("eva.notifications.dnd",false):set(on=="true") end
  morf.ipc.awake=function(on) require("themes.session").keep("eva.utilities.awake",false):set(on=="true") end
  morf.ipc.state=function()
    local keys={}
    for _,item in ipairs(model.reading:get().indicators) do keys[#keys+1]=item.key end
    return {keys=keys,reading=model.reading:get(),tab=tab:get(),settings=package.loaded.sidebar.drawer.open:get(),
      form=require("responsive").form()}
  end
  local status=require("status_model")
  morf.ipc.arrange=function(room,level)
    local active={}
    for _,row in ipairs {{"awake",1},{"ring",1},{"bluetooth",2},{"vpn",3},{"dnd",3},{"mic",0},{"camera",0}} do
      active[#active+1]={key=row[1],tier=row[2]}
    end
    return status.arrange(active,tonumber(room),{icon=24,dot=8,fixed=100,percent=40,level=tonumber(level)})
  end
]]
local DEVICES=morf.env("EVA_INPUT_DEVICES")
local function load(style,w,h,env)
  env=env or {}
  env.EVA_STYLE,env.EVA_DRY_RUN,env.TEST_WIDTH,env.TEST_HEIGHT=style,"1",tostring(w),tostring(h)
  env.EVA_INPUT_DEVICES=env.EVA_INPUT_DEVICES or DEVICES.."-touch"
  test.load("../shell/init.lua",{source=HOST,size={w,h},env=env})
  test.advance(900)
end
local function state() return test.ipc("state") end
local function up(id)
  local node=test.find {id=id,visible=true}
  return node~=nil and node.width>0.5 and node.height>0.5
end

test.describe("the collapse order",function()
  local function hidden(plan,key) return plan.hidden[key]==true end
  test.it("keeps everything while it fits",function()
    test.load("../shell/init.lua",{source=HOST,size={868,1932},env={EVA_DRY_RUN="1",TEST_WIDTH="868",TEST_HEIGHT="1932",
      EVA_INPUT_DEVICES=DEVICES.."-touch"}})
    local p=test.ipc("arrange",400,64)
    test.falsy(p.dot) test.truthy(p.percent)
  end)
  test.it("gives up the rare statuses first, into the dot",function()
    local p=test.ipc("arrange",300,64)
    test.truthy(hidden(p,"awake")) test.truthy(p.dot)
    test.falsy(hidden(p,"bluetooth")) test.truthy(p.percent)
  end)
  test.it("then Bluetooth",function()
    local p=test.ipc("arrange",260,64)
    test.truthy(hidden(p,"awake")) test.truthy(hidden(p,"ring")) test.truthy(hidden(p,"bluetooth"))
    test.falsy(hidden(p,"vpn")) test.truthy(p.percent)
  end)
  test.it("then VPN and Do not disturb",function()
    local p=test.ipc("arrange",200,64)
    test.truthy(hidden(p,"vpn")) test.truthy(hidden(p,"dnd")) test.truthy(p.percent)
  end)
  test.it("then the percentage",function()
    local p=test.ipc("arrange",190,64)
    test.truthy(hidden(p,"dnd")) test.falsy(p.percent)
  end)
  test.it("keeps the percentage at 20% and below, however tight",function()
    test.truthy(test.ipc("arrange",100,20).percent)
    test.truthy(test.ipc("arrange",100,5).percent)
    test.falsy(test.ipc("arrange",100,21).percent)
  end)
  test.it("never collapses a microphone or camera in use",function()
    local p=test.ipc("arrange",10,5)
    test.falsy(hidden(p,"mic")) test.falsy(hidden(p,"camera"))
  end)
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." puts the clock at the left and the status at the right, in the Android order",function()
    load(style,868,1932)
    for _,kv in ipairs {{"modem","true"},{"wifi_connected","true"},{"strength","80"}} do test.ipc("set",kv[1],kv[2]) end
    test.advance(900)
    local clock=test.get("bar-clock") local status=test.get("bar-status")
    test.truthy(clock.x<200) test.truthy(status.x+status.width>700)
    local mobile=test.get("bar-mobile") local wifi=test.get("bar-network") local battery=test.get("bar-battery")
    test.truthy(mobile.x<wifi.x) test.truthy(wifi.x<battery.x)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." gives the sheet a finger's height and icons a 24 px band",function()
    load(style,868,1932)
    test.eq(test.get("bar-status").height,48) test.eq(test.get("bar-clock").height,48)
    test.eq(test.get("bar-network").height,24)
    test.click("bar-status") test.truthy(state().settings) test.eq(state().tab,"settings")
  end)
  test.it(style.." presses the clock for the notifications",function()
    load(style,868,1932)
    test.click("bar-clock") test.truthy(state().settings) test.eq(state().tab,"notifications")
  end)
  test.it(style.." shows nothing for what the machine lacks",function()
    load(style,868,1932,{TEST_NO_BATTERY="1"})
    test.ipc("set","available","true") test.advance(900)
    test.eq(state().reading.mobile_icon,"") test.eq(state().reading.network_icon,"")
    test.falsy(up("bar-mobile")) test.falsy(up("bar-network"))
    test.falsy(up("bar-battery")) test.falsy(up("bar-percent"))
    test.eq(state().keys,{})
    test.truthy(up("bar-status"))
  end)
  test.it(style.." follows every indicator live",function()
    load(style,868,1932)
    local CASES={
      {"bluetooth","1","0","bluetooth"},{"vpn","true","false","vpn"},{"hotspot","true","false","hotspot"},
      {"mode","vibrate","sound","ring"},{"tor","true","false","tor"},{"alarm","true","false","alarm"},
      {"night","true","false","night"},
    }
    for _,case in ipairs(CASES) do
      test.ipc("set",case[1],case[2]) test.advance(900)
      test.eq(state().keys,{case[4]},case[1])
      test.truthy(up("bar-"..case[4]),case[1].." comes up")
      test.ipc("set",case[1],case[3]) test.advance(900)
      test.eq(state().keys,{},case[1])
      test.falsy(up("bar-"..case[4]),case[1].." goes")
    end
    test.ipc("dnd","true") test.advance(900) test.truthy(up("bar-dnd"))
    test.ipc("dnd","false") test.advance(900) test.falsy(up("bar-dnd"))
    test.ipc("awake","true") test.advance(900) test.truthy(up("bar-awake"))
    test.ipc("awake","false") test.advance(900) test.falsy(up("bar-awake"))
  end)
  test.it(style.." follows the battery live and keeps its glyph",function()
    load(style,868,1932)
    test.truthy(up("bar-battery"))
    test.ipc("set","percentage","15") test.advance(100)
    test.eq(state().reading.percentage,"15%") test.truthy(state().reading.battery.low)
    test.ipc("set","state","charging") test.ipc("set","on_battery","false") test.advance(100)
    test.truthy(state().reading.battery.charging) test.eq(state().reading.battery.mark,"bolt")
    test.ipc("set","saver","true") test.advance(100) test.truthy(state().reading.battery.saver)
    test.ipc("set","state","fully_charged") test.ipc("set","percentage","100") test.advance(100)
    test.truthy(state().reading.battery.full) test.falsy(state().reading.battery.charging)
    test.truthy(state().reading.battery.plugged)
  end)
  test.it(style.." collapses on a small phone and never loses the battery or clock",function()
    load(style,412,915)
    for _,kv in ipairs {{"modem","true"},{"wifi_connected","true"},{"bluetooth","1"},{"vpn","true"},
      {"hotspot","true"},{"mode","vibrate"},{"tor","true"},{"alarm","true"},{"night","true"}} do test.ipc("set",kv[1],kv[2]) end
    test.ipc("dnd","true") test.ipc("awake","true") test.advance(900)
    test.truthy(up("bar-dot"),"the dot stands for what went")
    test.truthy(up("bar-battery")) test.truthy(up("bar-clock"))
    test.falsy(up("bar-alarm"))
    local clock=test.get("bar-clock") local status=test.get("bar-status")
    test.truthy(clock.x+clock.width<=status.x+1,"the status runs into the clock")
    test.truthy(status.x+status.width<=412)
    test.ipc("dnd","false") test.ipc("awake","false")
  end)
  test.it(style.." keeps the percentage when the battery is low, in a tight bar",function()
    load(style,300,600)
    for _,kv in ipairs {{"modem","true"},{"wifi_connected","true"},{"bluetooth","1"},{"vpn","true"}} do test.ipc("set",kv[1],kv[2]) end
    test.ipc("set","percentage","12") test.advance(900)
    test.truthy(up("bar-percent"))
  end)
  test.it(style.." splits the row round a cutout",function()
    load(style,868,1932,{EVA_FAKE_CUTOUT="400,68,34"})
    test.ipc("set","wifi_connected","true") test.advance(900)
    local status=test.get("bar-status")
    test.truthy(status.x>=476,"the status sits in the cutout")
    test.eq(status.x+status.width,829)
  end)
  test.it(style.." keeps a side bar's status clear of its clock",function()
    load(style,868,1932)
    test.ipc("side","left") test.advance(900)
    local bar=test.get("bar")
    local status=test.get {id="bar-status-v",visible=true}
    test.truthy(status.x>=bar.x and status.x+status.width<=bar.x+bar.width)
    test.truthy(up("bar-clock-v"))
  end)
end
test.it("a tablet's bar has the date, its windows' lane and the status at a finger's height",function()
  load("material",1280,800)
  test.eq(state().form,"tablet")
  test.truthy(up("bar-logo")) test.truthy(test.find {id="bar-windows",visible=true}~=nil)
  test.eq(test.get("bar-status").height,48)
end)
test.it("a landscape phone keeps its status bar",function()
  load("material",1932,868)
  test.eq(state().form,"phone")
  test.truthy(up("bar-clock")) test.truthy(up("bar-status")) test.falsy(up("bar-logo"))
end)
