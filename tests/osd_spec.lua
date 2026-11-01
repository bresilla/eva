-- The on-screen displays: where each stands, what shows it, what keeps it, and
-- what a person can do to it, in both themes.
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  local W,H=tonumber(morf.env("TEST_WIDTH")),tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height=H
  morf.screens[1].width=W morf.screens[1].height=H
  local volume,muted=morf.signal("test.volume",.42),morf.signal("test.muted",false)
  local source=morf.signal("test.source",{id=7,muted=false})
  local absent=morf.env("TEST_ABSENT")=="1"
  morf.audio={available=function() return not absent end,
    default_sink=function() return {id=1,volume=volume:get(),muted=muted:get()} end,
    default_source=function() return source:get() end,
    set_volume=function(_,value) volume:set(value) end,
    set_mute=function(_,on) muted:set(on) end}
  local brightness=morf.signal("test.brightness",.68)
  package.loaded["lib.services.sysinfo"]={backlight=function() if absent then return nil end return {percent=brightness:get()*100} end,
    set_brightness=function(value) brightness:set(value/100) end}
  package.loaded.bar={desk=function() return 0,0,W,H end}
  package.loaded.rail={geometry=function() return {w=W,h=H,item=60,gap=12} end}
  local here=morf.signal("test.here",true)
  local devices,device_list={},nil
  local service_state=morf.state {profile="balanced",ring="sound",layout="English (US)",revision=0,
    title="",artist="",art="",playing=true,available=true}
  local function device_model()
    service_state.revision=service_state.revision
    return {len=function() return #devices end,get=function(_,i) return devices[i] end}
  end
  local services={here=function() return here:get() end}
  if not absent then
    services.upower={state=setmetatable({},{__index=function(_,k)
      if k=="available" then return true end
      if k=="profiles" then return {available=true,active=service_state.profile} end
    end})}
    services.ringer={state=setmetatable({},{__index=function(_,k) if k=="mode" then return service_state.ring end end})}
    services.hyprland={available=function() return true end,state=setmetatable({},{__index=function(_,k)
      if k=="keyboard_layout" then return service_state.layout end end})}
    services.bt={state=setmetatable({},{__index=function(_,k)
      if k=="available" then return true end
      if k=="devices" then return device_model() end end})}
    services.media={state=setmetatable({},{__index=function(_,k)
      if k=="available" then return true end
      if k=="active" then return {title=service_state.title,artist={service_state.artist},album="An album",
        art_url=service_state.art,playing=service_state.playing} end end})}
  end
  package.loaded.services=services
  local theme=require("theme")
  local sidebar={drawer=require("drawer").new {name="sidebar",edge="right",width=430,height=360,content=ui.Item {}},
    showing=function(page) return page=="settings" end}
  package.loaded.sidebar=sidebar
  local dnd=morf.signal("test.dnd",false)
  package.loaded.notifs={dnd=dnd}
  local awake=morf.signal("test.awake",false)
  package.loaded.settings_model={awake=awake}
  local config=require("config")
  local levels=require("levels")
  local root=levels.build()
  local osd=require("osd")
  ui.Item {width=W,height=H,
    ui.Rect {width=W,height=H,color=function() return theme.color.surface end},
    ui.Sdf {id="frame",anchors={fill=true},fill_color=function() return theme.color.surfaceContainer end,levels.shape,sidebar.drawer.shape},
    root,sidebar.drawer.panel}
  morf.ipc.flash=function(kind,forced) return osd.flash(kind,forced=="forced") end
  morf.ipc.set=function(key,value)
    if value=="true" then value=true elseif value=="false" then value=false end
    config.set(key,tonumber(value) or value)
  end
  morf.ipc.volume=function(v) volume:set(tonumber(v)) end
  morf.ipc.source=function(id,on) source:set {id=tonumber(id),muted=on=="yes"} end
  morf.ipc.field=function(key,value)
    if value=="yes" then value=true elseif value=="no" then value=false end
    service_state[key]=value
  end
  morf.ipc.connect=function(alias,icon)
    devices[#devices+1]={path="/bt/"..alias,alias=alias,icon=icon or "",connected=true}
    service_state.revision=service_state.revision+1
  end
  morf.ipc.dnd=function(on) dnd:set(on=="yes") end
  morf.ipc.awake=function(on) awake:set(on=="yes") end
  morf.ipc.state=function() return {shown=levels.shown:get(),active=levels.active:get(),volume=osd.volume(),muted=select(2,osd.volume())} end
  morf.ipc.spot=function(kind) return levels.spot(kind) end
  morf.ipc.present=function(kind) return osd.present(kind) end
]]
local loads=0
local function load(style,env)
  local w,h=env and env.w or 1280,env and env.h or 800
  loads=loads+1
  -- Settings of its own: a test's places are no other test's.
  local settings=morf.fs.join(morf.env("XDG_CACHE_HOME"),"osd-spec-"..loads..".json")
  local e={EVA_STYLE=style,TEST_WIDTH=tostring(w),TEST_HEIGHT=tostring(h),EVA_DRY_RUN="0",EVA_SETTINGS=settings}
  for k,v in pairs(env or {}) do if k~="w" and k~="h" then e[k]=v end end
  test.load("../shell/init.lua",{source=HOST,size={w,h},env=e})
  test.advance(400)
end
-- Past the moment services report in at, and everything settled.
local function armed(style,env) load(style,env) test.advance(2600) end
local function shown() return test.ipc("state").shown end
local POSITIONS={"top_left","top_center","top_right","center_left","center","center_right",
  "bottom_left","bottom_center","bottom_right"}

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." puts a display at each of the nine places, swelling from its edge or floating free",function()
    load(style)
    for _,position in ipairs(POSITIONS) do
      test.ipc("set","osd.kinds.volume.position",position)
      test.ipc("flash","volume") test.advance(900)
      local panel,bud=test.get("levels-swell"),test.get("levels-bud")
      local edge=position:match("^top") or position:match("^bottom") or position:match("_(%a+)$")
      if position=="center" then edge=nil end
      if edge=="right" or edge=="left" then
        test.truthy(test.get("levels-meter").visible,position.." is not upright")
      elseif edge then
        test.truthy(test.get("levels-bar").visible,position.." does not lie down")
      end
      local background=test.get("levels-swell-background")
      local float=test.get("levels-float-shape")
      if edge then
        test.near(background.opacity,1,.02,position.." is not a layer of the frame")
        test.near(float.opacity,0,.02,position.." floats at an edge")
      else
        test.near(background.opacity,0,.02,"the centre joined the frame")
        test.near(float.opacity,1,.02,"the centre has no field of its own")
      end
      -- It reaches under the frame at its edge, and shows inside it.
      if edge=="top" then test.truthy(panel.y<10 and bud.y>=10-.5,position)
      elseif edge=="bottom" then test.truthy(panel.y+panel.height>790 and bud.y+bud.height<=790+.5,position)
      elseif edge=="left" then test.truthy(panel.x<10 and bud.x>=10-.5,position)
      elseif edge=="right" then test.truthy(panel.x+panel.width>1270 and bud.x+bud.width<=1270+.5,position)
      else test.near(bud.x+bud.width/2,640,1,position) test.near(bud.y+bud.height/2,400,1,position) end
      test.advance(3000)
      test.eq(shown(),"")
      test.falsy(test.get("levels-swell").visible,position.." stayed")
    end
    test.eq(#test.logs("error"),0)
  end)

  test.it(style.." moves a display on show along its rail and between edges",function()
    load(style)
    test.ipc("set","osd.kinds.volume.position","top_left")
    test.ipc("set","osd.kinds.volume.hold","9000")
    test.ipc("flash","volume") test.advance(1200)
    local start=test.get("levels-swell").x
    test.ipc("set","osd.kinds.volume.position","top_right")
    test.advance(48)
    local moving=test.get("levels-swell").x
    test.truthy(moving>start and moving<test.ipc("spot","volume").x-1,"it jumped along the rail")
    test.advance(1400)
    -- (On the right it rides with the sidebar, shut here, a few px either way.)
    test.near(test.get("levels-swell").x,test.ipc("spot","volume").x,4)
    test.ipc("set","osd.kinds.volume.position","center_right")
    test.advance(48)
    local spot=test.ipc("spot","volume")
    test.truthy(test.get("levels-swell").x<spot.x,"it jumped between edges")
    test.advance(1400)
    test.near(test.get("levels-swell").x,spot.x,4)
    test.truthy(test.get("levels-meter").visible)
  end)

  test.it(style.." honours each kind's switches, hold and percentage",function()
    load(style)
    test.ipc("set","osd.kinds.volume.enabled","false")
    test.falsy(test.ipc("flash","volume"))
    test.eq(shown(),"")
    test.truthy(test.ipc("flash","volume","forced"))
    test.advance(700) test.eq(shown(),"volume")
    test.advance(3000) test.eq(shown(),"")
    test.ipc("set","osd.kinds.volume.enabled","true")
    test.ipc("set","osd.kinds.volume.hold","4000")
    test.ipc("flash","volume") test.advance(3500) test.truthy(test.ipc("state").active)
    test.advance(1000) test.falsy(test.ipc("state").active)
    test.advance(800)
    test.ipc("set","osd.kinds.volume.percent","false")
    test.ipc("flash","volume") test.advance(800)
    test.falsy(test.get("levels-value").visible,"the percentage stayed")
  end)

  test.it(style.." takes the phone's default place and never leaves resting pills there",function()
    load(style,{w=868,h=1932})
    local spot=test.ipc("spot","volume")
    test.eq(spot.edge,"top")
    test.falsy(test.get("levels-volume").visible)
    test.ipc("flash","brightness") test.advance(800)
    test.near(test.get("levels-bud").x+test.get("levels-bud").width/2,434,1)
  end)

  test.it(style.." a level follows a drag, mutes on a click and waits under the pointer",function()
    load(style)
    test.ipc("flash","volume") test.advance(800)
    local bud=test.get("levels-bud")
    local x,y=bud.x+bud.width/2,bud.y+bud.height/2
    test.click(x,y) test.advance(100)
    test.truthy(test.ipc("state").muted,"a click did not mute")
    test.click(x,y) test.advance(100)
    test.falsy(test.ipc("state").muted,"a click did not bring it back")
    test.near(test.ipc("state").volume,.42,.001,"a click moved the level")
    test.drag({x,y},{x,y-100},{steps=6}) test.advance(60)
    test.truthy(test.ipc("state").volume>.65,"a drag up did not raise it")
    test.falsy(test.ipc("state").muted,"a drag muted it")
    -- Over it, the hold waits for as long as the pointer stays.
    test.move(x,y) test.advance(6000)
    test.truthy(test.ipc("state").active,"it left from under the pointer")
    test.leave() test.advance(1500)
    test.truthy(test.ipc("state").active,"the hold did not start over")
    test.advance(1200)
    test.falsy(test.ipc("state").active)
    test.eq(#test.logs("error"),0)
  end)

  test.it(style.." a horizontal level follows a touch along it",function()
    load(style,{w=868,h=1932})
    test.ipc("flash","volume") test.advance(800)
    local bud=test.get("levels-bud")
    local y=bud.y+bud.height/2
    test.swipe({bud.x+120,y},{bud.x+240,y},{duration=240,steps=8}) test.advance(100)
    test.truthy(test.ipc("state").volume>.6,"a touch along it did not raise it")
    test.falsy(test.ipc("state").muted)
  end)

  test.it(style.." shows short kinds as a pill and a track with its details",function()
    load(style)
    test.ipc("field","title","Blue in Green") test.ipc("field","artist","Miles Davis")
    test.truthy(test.ipc("flash","profile")) test.advance(800)
    local bud=test.get("levels-bud")
    test.truthy(bud.height<100 and bud.width<300,"a status is not short")
    test.eq(test.get("levels-pill-detail").text,"Balanced")
    test.advance(3000)
    test.truthy(test.ipc("flash","media")) test.advance(800)
    test.eq(test.get("levels-media-artist").text,"Miles Davis")
    test.eq(#test.logs("error"),0)
  end)

  test.it(style.." never shows a kind whose service is absent",function()
    load(style,{TEST_ABSENT="1"})
    for _,kind in ipairs {"volume","brightness","mic","layout","profile","ring","bluetooth","media","night"} do
      test.falsy(test.ipc("present",kind),kind.." claims to be here")
      test.falsy(test.ipc("flash",kind),kind.." appeared")
    end
    test.eq(shown(),"")
  end)
end

test.it("fires each kind on a real change, once, and stays quiet at start",function()
  armed("material")
  local function fires(kind,change)
    change() test.advance(120)
    test.eq(shown(),kind,kind.." did not fire")
    test.advance(4500)
    test.eq(shown(),"",kind.." stayed")
  end
  fires("mic",function() test.ipc("source","7","yes") end)
  fires("profile",function() test.ipc("field","profile","performance") end)
  fires("layout",function() test.ipc("field","layout","Deutsch") end)
  fires("ring",function() test.ipc("field","ring","silent") end)
  fires("dnd",function() test.ipc("dnd","yes") end)
  fires("awake",function() test.ipc("awake","yes") end)
  fires("bluetooth",function() test.ipc("connect","Keyboard","input-keyboard") end)
  test.eq(test.ipc("present","night"),false)
end)

test.it("takes what it reads at start for how things are",function()
  load("material")
  test.ipc("field","profile","performance") test.ipc("dnd","yes") test.ipc("connect","Keyboard")
  test.ipc("source","7","yes")
  test.advance(2000)
  test.eq(shown(),"")
end)

test.it("a device change of the default input is no mute",function()
  armed("material")
  test.ipc("source","9","yes") test.advance(200)
  test.eq(shown(),"")
end)

test.it("leaves a headset to the headphones display",function()
  armed("material")
  test.ipc("connect","Buds","audio-headset") test.advance(200)
  test.eq(shown(),"")
  test.ipc("connect","Mouse","input-mouse") test.advance(200)
  test.eq(shown(),"bluetooth")
  test.eq(test.get("levels-pill-detail").text,"Mouse")
end)

test.it("shows a new track once, when its art has come, and ignores the same metadata again",function()
  armed("material")
  test.ipc("field","title","First") test.ipc("field","artist","An artist") test.advance(100)
  test.advance(100) test.eq(shown(),"","the first reading fired")
  test.ipc("field","title","Second") test.advance(200)
  test.eq(shown(),"","it did not wait for the art")
  test.ipc("field","art","file:///cover.png") test.advance(60)
  test.eq(shown(),"media")
  test.advance(4500)
  test.eq(shown(),"")
  test.ipc("field","art","file:///other.png")
  test.ipc("field","artist","An artist") test.advance(1000)
  test.eq(shown(),"","the same track fired again")
  -- A cover that never comes does not hold the track back for ever.
  test.ipc("field","title","Third") test.advance(1000)
  test.eq(shown(),"media")
end)

test.it("reads the lock keys from their lights",function()
  local dir=morf.fs.join(morf.env("XDG_CACHE_HOME"),"osd-leds")
  morf.fs.mkdir(morf.fs.join(dir,"input3::capslock"),{recursive=true})
  morf.fs.mkdir(morf.fs.join(dir,"input3::numlock"),{recursive=true})
  local caps,num=morf.fs.join(dir,"input3::capslock/brightness"),morf.fs.join(dir,"input3::numlock/brightness")
  morf.fs.write(caps,"0\n") morf.fs.write(num,"1\n")
  armed("material",{EVA_LEDS=dir})
  test.truthy(test.ipc("present","caps"))
  test.eq(shown(),"")
  morf.fs.write(caps,"1\n") test.advance(400)
  test.eq(shown(),"caps")
  test.advance(4000)
  morf.fs.write(num,"0\n") test.advance(400)
  test.eq(shown(),"num")
end)

test.it("keeps its layers out of the frame's field while hidden, and within the budget while shown",function()
  load("material")
  local function layers()
    local count=0
    for _,node in ipairs(test.find_all(function(n) return n.id and n.id:match("^levels%-swell.*%-background$") end)) do
      if node.visible and node.opacity>0 then count=count+1 end
    end
    return count
  end
  test.eq(layers(),0)
  test.ipc("flash","volume") test.ipc("flash","mic") test.ipc("flash","profile") test.advance(800)
  test.eq(layers(),2,"kinds at one place share a bud")
  test.ipc("set","osd.kinds.mic.position","top_center")
  test.ipc("set","osd.kinds.layout.position","top_left")
  test.ipc("set","osd.kinds.ring.position","bottom_left")
  test.ipc("flash","mic") test.ipc("flash","layout") test.ipc("flash","ring") test.advance(800)
  test.eq(layers(),3,"there are three buds at most")
  test.advance(4000)
  test.eq(layers(),0)
end)

test.it("leaves the settings to show what they change themselves",function()
  armed("material")
  test.ipc("field","layout","Deutsch")
  test.advance(100) test.eq(shown(),"layout")
end)
