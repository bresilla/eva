-- The pure parts of quick settings: the tile grid and what speaks to the
-- machine's hardware, each against a stand-in bus or process.
--
--     morf test --no-dbus tests/quick_services_spec.lua
local test=morf.test
local HOST=[[
  local dbus_client=require("lib.services.dbus")
  local real_new=dbus_client.new
  local function eq(a,b)
    if a~=b then error(("expected %s, got %s"):format(tostring(b),tostring(a)),2) end
  end
  local function truthy(v,what) if not v then error("expected "..tostring(what or "a true value"),2) end end
  local function falsy(v,what) if v then error("expected no "..tostring(what or "value"),2) end end
  local function fake_client(overrides)
    local c={calls={},owned=true,props={}}
    function c.has_owner() return c.owned end
    function c.get_all() return c.props end
    function c.get(_,_,_,name) return c.props[name] end
    function c.watch_name(_,fn) c.watched=fn end
    function c.on_properties(_,_,fn) c.changed=fn return {close=function() end} end
    function c.call_async(destination,path,interface,method,arguments,_,done)
      c.calls[#c.calls+1]={destination=destination,path=path,interface=interface,method=method,arguments=arguments}
      if c.fail then done(nil,c.fail) else done(c.reply or true) end
      return true
    end
    for k,v in pairs(overrides or {}) do c[k]=v end
    dbus_client.new=function() return c end
    return c
  end

  morf.ipc.grid_flow=function()
    local grid=require("tile_grid")
    local cells,rows=grid.flow({{id="a"},{id="b",small=true},{id="c",small=true},{id="d"}},2)
    eq(cells.a.column,0) eq(cells.a.span,2) eq(cells.a.row,0)
    eq(cells.b.column,2) eq(cells.b.span,1) eq(cells.c.column,3)
    eq(cells.d.row,1) eq(rows,2)
    local _,none=grid.flow({},2)
    eq(none,0)
    return true
  end
  morf.ipc.grid_small_pack=function()
    local grid=require("tile_grid")
    local cells=grid.flow({{id="a",small=true},{id="b"},{id="c",small=true}},2)
    eq(cells.a.column,0) eq(cells.b.column,1) eq(cells.c.column,3)
    local one=grid.flow({{id="a",small=true},{id="b"}},1)
    eq(one.b.row,1)
    local m={half=100,gap=8,height=60}
    local x,y,w,h=grid.box({column=2,row=1,span=1},m)
    eq(x,216) eq(y,68) eq(w,100) eq(h,60)
    local _,_,fw=grid.box({column=0,row=0,span=2},m)
    eq(fw,208)
    return true
  end
  morf.ipc.grid_nearest=function()
    local grid=require("tile_grid")
    local m={half=100,gap=8,height=60}
    local items={{id="a"},{id="b"},{id="c"},{id="d"}}
    eq(grid.nearest(items,"a",320,30,2,m),2,"second slot")
    eq(grid.nearest(items,"a",320,100,2,m),4,"last slot")
    eq(grid.nearest(items,"d",100,30,2,m),1,"first slot")
    eq(grid.nearest(items,"zz",100,30,2,m),nil,"a tile not listed")
    return true
  end

  morf.ipc.hotspot_profile=function()
    local hotspot=require("lib.services.hotspot")
    local s=hotspot.settings("Pocket","hunter2hunter2","u-1")
    eq(s.connection.id,"eva-hotspot") eq(s.connection.type,"802-11-wireless")
    eq(s.connection.autoconnect,false)
    eq(s["802-11-wireless"].mode,"ap") eq(s.ipv4.method,"shared")
    eq(s["802-11-wireless-security"].psk,"hunter2hunter2")
    eq(s["802-11-wireless-security"]["key-mgmt"],"wpa-psk")
    falsy(hotspot.settings("Pocket",nil,"u-1")["802-11-wireless-security"].psk,"psk without a password")
    falsy(hotspot.settings("Pocket","","u-1")["802-11-wireless-security"].psk,"psk for an empty password")
    return true
  end
  morf.ipc.hotspot_check=function()
    local hotspot=require("lib.services.hotspot")
    truthy(hotspot.check("","hunter2hunter2"),"a refusal of an empty name")
    truthy(hotspot.check(("x"):rep(33),"hunter2hunter2"),"a refusal of a long name")
    truthy(hotspot.check("Pocket","short"),"a refusal of a short password")
    truthy(hotspot.check("Pocket",("x"):rep(64)),"a refusal of a long password")
    truthy(hotspot.check("Pocket",""),"a refusal of no password on a new profile")
    falsy(hotspot.check("Pocket","",true),"a refusal when the saved secret stands")
    falsy(hotspot.check("Pocket","hunter2hunter2"),"a refusal of a good pair")
    return true
  end
  local function net_with(known,active)
    local rows=active or {}
    return {snapshot=function()
        return {known=known or {},devices={{type="wifi",path="/dev/wlan0",interface="wlan0",managed=true}}}
      end,
      refresh=function() end,
      state={active_connections={len=function() return #rows end,get=function(_,i) return rows[i] end}}}
  end
  morf.ipc.hotspot_first_save=function()
    local c=fake_client{reply={"/settings/9"}}
    local h=require("lib.services.hotspot").new(net_with())
    local path
    truthy(h.save("Pocket","hunter2hunter2",function(p) path=p end))
    eq(#c.calls,1) eq(c.calls[1].method,"AddConnection") eq(path,"/settings/9")
    local sent=c.calls[1].arguments[1]
    eq(sent.signature,"a{sa{sv}}")
    eq(sent.value["802-11-wireless-security"].psk,"hunter2hunter2")
    truthy(sent.value.connection.uuid,"a uuid: AddConnection does not make one")
    return true
  end
  morf.ipc.hotspot_update=function()
    local c=fake_client{}
    local row={id="eva-hotspot",path="/settings/3",uuid="u-3",ssid="Old"}
    local h=require("lib.services.hotspot").new(net_with({row}))
    truthy(h.save("New","",function() end))
    eq(c.calls[1].method,"Update") eq(c.calls[1].path,"/settings/3")
    local sent=c.calls[1].arguments[1].value
    eq(sent.connection.uuid,"u-3")
    falsy(sent["802-11-wireless-security"].psk,"a secret sent back")
    return true
  end
  morf.ipc.hotspot_refuses=function()
    local c=fake_client{}
    local h=require("lib.services.hotspot").new(net_with())
    local ok,why=h.save("Pocket","short")
    falsy(ok,"a save") truthy(why,"a reason") eq(#c.calls,0)
    return true
  end
  morf.ipc.hotspot_start_stop=function()
    local c=fake_client{props={WirelessCapabilities=0x47},reply={"/active/1"}}
    local row={id="eva-hotspot",path="/settings/3",uuid="u-3"}
    local active={{id="eva-hotspot",path="/active/1",state="activated"}}
    local h=require("lib.services.hotspot").new(net_with({row},active))
    truthy(h.device(),"an AP-capable radio")
    truthy(h.start(function() end))
    eq(c.calls[1].method,"ActivateConnection")
    eq(c.calls[1].arguments[1].value,"/settings/3") eq(c.calls[1].arguments[2].value,"/dev/wlan0")
    eq(h.active().path,"/active/1")
    truthy(h.stop(function() end))
    eq(c.calls[2].method,"DeactivateConnection") eq(c.calls[2].arguments[1].value,"/active/1")
    return true
  end
  morf.ipc.hotspot_no_ap=function()
    fake_client{props={WirelessCapabilities=0x07}}
    local h=require("lib.services.hotspot").new(net_with({{id="eva-hotspot",path="/s"}}))
    falsy(h.device(),"a radio without AP mode")
    local ok,why=h.start()
    falsy(ok,"a start") truthy(why,"a reason")
    return true
  end

  morf.ipc.sensors=function()
    local c=fake_client{props={HasAccelerometer=true,AccelerometerOrientation="normal"}}
    local s=require("lib.services.sensors").connect()
    truthy(s.state.available) truthy(s.state.accelerometer) eq(s.state.orientation,"normal")
    s.claim() s.claim()
    eq(#c.calls,1) eq(c.calls[1].method,"ClaimAccelerometer")
    c.changed("net.hadess.SensorProxy",{AccelerometerOrientation="left-up"})
    eq(s.state.orientation,"left-up")
    s.release() s.release()
    eq(#c.calls,2) eq(c.calls[2].method,"ReleaseAccelerometer")
    return true
  end
  morf.ipc.sensors_absent=function()
    local c=fake_client{owned=false}
    local s=require("lib.services.sensors").connect()
    falsy(s.state.available) falsy(s.state.accelerometer) eq(#c.calls,0)
    c.owned=true c.props={HasAccelerometer=true,AccelerometerOrientation="right-up"}
    c.watched()
    truthy(s.state.accelerometer,"a sensor that came late")
    return true
  end

  local function leds(names)
    local dir=morf.env("XDG_CACHE_HOME").."/leds-"..tostring(math.random(1,1e9))
    for name,values in pairs(names) do
      morf.fs.mkdir(dir.."/"..name)
      morf.fs.write(dir.."/"..name.."/max_brightness",tostring(values[1]).."\n")
      morf.fs.write(dir.."/"..name.."/brightness",tostring(values[2]).."\n")
    end
    return dir
  end
  morf.ipc.torch=function()
    local c=fake_client{}
    local dir=leds {["white:flash"]={1000,0},["white:torch"]={255,0},["input0::capslock"]={1,0}}
    local t=require("lib.services.torch").new{dir=dir}
    eq(t.device().name,"white:torch") falsy(t.on())
    truthy(t.set(true))
    eq(c.calls[1].method,"SetBrightness") eq(c.calls[1].interface,"org.freedesktop.login1.Session")
    eq(c.calls[1].arguments[1],"leds") eq(c.calls[1].arguments[2],"white:torch")
    eq(c.calls[1].arguments[3].value,255) eq(c.calls[1].arguments[3].signature,"u")
    truthy(t.on())
    t.set(false)
    eq(c.calls[2].arguments[3].value,0) falsy(t.on())
    return true
  end
  morf.ipc.torch_flash=function()
    fake_client{}
    eq(require("lib.services.torch").find(leds{["led0:flash"]={100,0}}).name,"led0:flash")
    return true
  end
  morf.ipc.torch_none=function()
    local c=fake_client{}
    local t=require("lib.services.torch").new{dir=leds{["input0::numlock"]={1,0}}}
    eq(t.device(),nil)
    local ok,why=t.set(true)
    falsy(ok,"a set") truthy(why,"a reason") eq(#c.calls,0)
    eq(require("lib.services.torch").find("/nonexistent/leds"),nil)
    return true
  end
  morf.ipc.torch_refused=function()
    fake_client{fail="not active"}
    local t=require("lib.services.torch").new{dir=leds{["white:torch"]={255,0}}}
    local heard
    t.set(true,function(ok,err) heard={ok,err} end)
    falsy(t.on(),"a lit torch logind refused") eq(heard[2],"not active")
    return true
  end

  local rotate
  local function rotation_rig()
    local hypr=require("lib.compositor.hyprland")
    rotate={calls={},evals={},keywords={},lua=true}
    hypr.available=function() return true end
    hypr.eval=function(chunk,done)
      rotate.evals[#rotate.evals+1]=chunk
      if done then done(rotate.lua and "ok" or "unknown request") end
    end
    hypr.keyword=function(name,value) rotate.keywords[#rotate.keywords+1]=name.." "..tostring(value) end
    hypr.monitor=function(name)
      return {name=name,width=1080,height=2400,refresh_rate=60,x=0,y=0,scale=2,transform=0}
    end
    local locked=morf.signal("test.rotate.locked",false)
    local state=morf.state{accelerometer=true,orientation="normal"}
    rotate.locked,rotate.state=locked,state
    rotate.device={sensors={state=state,
        claim=function() rotate.calls[#rotate.calls+1]="claim" end,
        release=function() rotate.calls[#rotate.calls+1]="release" end},
      present=function() return state.accelerometer end,
      on=function() return locked:get() end}
    return require("auto_rotate")
  end
  morf.ipc.rotate_edge=function()
    local auto=rotation_rig()
    truthy(auto.built_in("eDP-1"),"eDP built in") truthy(auto.built_in("DSI-1"),"DSI built in")
    falsy(auto.built_in("DP-3"),"DP built in") falsy(auto.built_in("HDMI-A-1"),"HDMI built in")
    eq(auto.start{rotation=rotate.device,name="HDMI-A-1"},false)
    eq(#rotate.calls,0)
    eq(auto.apply("undefined","eDP-1"),false)
    return true
  end
  morf.ipc.rotate_start=function()
    rotation_rig().start{rotation=rotate.device,name="eDP-1"}
    return true
  end
  morf.ipc.rotate_legacy=function()
    rotation_rig()
    rotate.lua=false
    require("auto_rotate").apply("left-up","eDP-1")
    return rotate.keywords
  end
  morf.ipc.rotate_turn=function(to) rotate.state.orientation=to end
  morf.ipc.rotate_lock=function(on) rotate.locked:set(on=="yes") end
  morf.ipc.rotate_read=function() return {calls=rotate.calls,evals=rotate.evals} end

  local night_runs={}
  morf.ipc.night_start=function()
    night_runs={}
    local started
    local n=require("lib.services.nightlight")
    eq(n.clamp(1000),2500) eq(n.clamp(9000),6000) eq(n.clamp(4449),4400)
    night=n.new{delay=50,
      run=function(argv,done) night_runs[#night_runs+1]=argv done{ok=not morf.env("NIGHT_DOWN")} end,
      start=function(k) started=k end}
    night.apply(true,4000) night.apply(true,3800) night.apply(true,3500)
    return true
  end
  morf.ipc.night_read=function() return night_runs end
  morf.ipc.night_off=function() night.apply(false,3500) return true end
]]
local function load() test.load("../shell/init.lua",{source=HOST,size={320,240}}) end
for _,name in ipairs {"grid_flow","grid_small_pack","grid_nearest","hotspot_profile","hotspot_check",
  "hotspot_first_save","hotspot_update","hotspot_refuses","hotspot_start_stop","hotspot_no_ap",
  "sensors","sensors_absent","torch","torch_flash","torch_none","torch_refused","rotate_edge"} do
  test.it(name:gsub("_"," "),function()
    load()
    test.eq(test.ipc(name),true)
  end)
end
test.it("auto-rotate turns the output and the touchscreen, and the lock stops it",function()
  load()
  test.ipc("rotate_start") test.advance(50)
  local read=test.ipc("rotate_read")
  test.eq(read.calls,{"claim"})
  test.eq(read.evals[1],'hl.monitor({output="eDP-1", transform=0})')
  test.ipc("rotate_turn","left-up") test.advance(50)
  read=test.ipc("rotate_read")
  test.eq(read.evals[3],'hl.monitor({output="eDP-1", transform=1})')
  test.eq(read.evals[4],"hl.config({input={touchdevice={transform=1},tablet={transform=1}}})")
  test.ipc("rotate_lock","yes") test.advance(50)
  read=test.ipc("rotate_read")
  test.eq(read.calls,{"claim","release"})
  local evals=#read.evals
  test.ipc("rotate_turn","bottom-up") test.advance(50)
  test.eq(#test.ipc("rotate_read").evals,evals,"a lock did not stop it")
  test.ipc("rotate_lock","no") test.advance(50)
  read=test.ipc("rotate_read")
  test.eq(read.calls,{"claim","release","claim"})
  test.eq(read.evals[evals+1],'hl.monitor({output="eDP-1", transform=2})')
end)
test.it("on a Hyprland without Lua it falls back to keywords",function()
  load()
  test.eq(test.ipc("rotate_legacy"),{"monitor eDP-1,1080x2400@60.000,0x0,2,transform,1",
    "input:touchdevice:transform 1","input:tablet:transform 1"})
end)
test.it("night light debounces a drag to one command and speaks hyprsunset",function()
  load()
  test.ipc("night_start") test.advance(100)
  local runs=test.ipc("night_read")
  test.eq(#runs,1)
  test.eq(runs[1],{"hyprctl","hyprsunset","temperature","3500"})
  test.ipc("night_off") test.advance(100)
  runs=test.ipc("night_read")
  test.eq(runs[2],{"hyprctl","hyprsunset","identity"})
end)
