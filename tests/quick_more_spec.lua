-- The phone tiles beyond the first board: what each speaks to, against a
-- stand-in bus or process, and each of them on the real board.
--
--     morf test --no-dbus tests/quick_more_spec.lua
local test=morf.test
local HOST=[[
  local dbus_client=require("lib.services.dbus")
  local function eq(a,b)
    if a~=b then error(("expected %s, got %s"):format(tostring(b),tostring(a)),2) end
  end
  local function truthy(v,what) if not v then error("expected "..tostring(what or "a true value"),2) end end
  local function falsy(v,what) if v then error("expected no "..tostring(what or "value"),2) end end
  local function fake_client(overrides)
    local c={calls={},sets={},owned=true,props={}}
    function c.has_owner() return c.owned end
    function c.get_all() return c.props end
    function c.get(_,_,_,name) return c.props[name] end
    function c.watch_name(_,fn) c.watched=fn end
    function c.on_properties(_,_,fn) c.changed=fn return {close=function() end} end
    function c.call_async(destination,path,interface,method,arguments,_,done)
      c.calls[#c.calls+1]={destination=destination,path=path,interface=interface,method=method,arguments=arguments}
      if c.hold then c.held=done return true end
      if c.fail then done(nil,c.fail) else done(c.reply or true) end
      return true
    end
    function c.set_async(destination,path,interface,property,value,_,done)
      c.sets[#c.sets+1]={path=path,interface=interface,property=property,value=value}
      if c.fail then done(nil,c.fail) else done(true) end
      return true
    end
    for k,v in pairs(overrides or {}) do c[k]=v end
    dbus_client.new=function() return c end
    return c
  end
  local function folder(entries)
    local dir=morf.env("XDG_CACHE_HOME").."/more-"..tostring(math.random(1,1e9))
    for _,name in ipairs(entries) do morf.fs.mkdir(dir.."/"..name) end
    return dir
  end
  local function leds(max,value)
    local dir=folder {"white:torch"}
    morf.fs.write(dir.."/white:torch/max_brightness",tostring(max).."\n")
    morf.fs.write(dir.."/white:torch/brightness",tostring(value or 0).."\n")
    return dir
  end

  -- ---------------------------------------------------------- flashlight --
  morf.ipc.torch_level=function()
    local c=fake_client{}
    local t=require("lib.services.torch").new{dir=leds(255)}
    eq(t.level(),1)
    t.set_level(0.4)
    eq(#c.calls,0,"an unlit torch stays dark")
    t.set(true)
    eq(c.calls[1].arguments[3].value,102)
    t.set_level(0.1)
    eq(c.calls[2].arguments[3].value,26,"a lit torch follows")
    t.set(false)
    eq(c.calls[3].arguments[3].value,0)
    t.set(true)
    eq(c.calls[4].arguments[3].value,26,"it comes back at its strength")
    t.set_level(0)
    eq(c.calls[5].arguments[3].value,1,"it stays on its lowest step")
    return true
  end
  morf.ipc.torch_burst=function()
    local c=fake_client{hold=true}
    local t=require("lib.services.torch").new{dir=leds(100,50)}
    t.set_level(.2) t.set_level(.3) t.set_level(.4) t.set_level(.5)
    eq(#c.calls,1,"a drag is one call at a time")
    c.hold=false
    c.held(true)
    eq(#c.calls,2) eq(c.calls[2].arguments[3].value,50,"the latest went next")
    return true
  end
  morf.ipc.torch_lit=function()
    fake_client{}
    local t=require("lib.services.torch").new{dir=leds(255,51)}
    truthy(t.on()) eq(t.level(),0.2,"it reads the strength it was left at")
    return true
  end

  -- ----------------------------------------------------------------- NFC --
  morf.ipc.nfc=function()
    local c=fake_client{props={Powered=false}}
    local n=require("lib.services.nfc").connect{dir=folder{"nfc0"}}
    truthy(n.state.available) falsy(n.state.powered)
    n.set(true)
    eq(c.sets[1].path,"/org/neard/nfc0") eq(c.sets[1].property,"Powered") eq(c.sets[1].value,true)
    eq(c.sets[1].interface,"org.neard.Adapter")
    truthy(n.state.powered)
    c.changed("org.neard.Adapter",{Powered=false})
    falsy(n.state.powered)
    return true
  end
  morf.ipc.nfc_absent=function()
    local c=fake_client{props={Powered=true}}
    local lib=require("lib.services.nfc")
    falsy(lib.connect{dir=folder{}}.state.available,"NFC with no adapter")
    c.owned=false
    local late=lib.connect{dir=folder{"nfc0"}}
    falsy(late.state.available,"NFC with no neard")
    c.owned=true
    c.watched()
    truthy(late.state.available,"a neard that came late")
    eq(lib.adapter(folder{"nfc3","other"}),"nfc3")
    return true
  end

  -- ------------------------------------------------------------- tethering --
  local function net_with(known,active,devices)
    local rows=active or {}
    return {snapshot=function() return {known=known or {},devices=devices or {}} end,refresh=function() end,
      state={active_connections={len=function() return #rows end,get=function(_,i) return rows[i] end}}}
  end
  local USB={{type="wifi",path="/dev/wlan0",interface="wlan0",managed=true},
    {type="ethernet",path="/dev/usb0",interface="usb0",managed=false}}
  morf.ipc.tether_first=function()
    local c=fake_client{reply={"/settings/9"}}
    local known={}
    local net=net_with(known,nil,USB)
    net.refresh=function() known[1]={id="eva-usb-tether",path="/settings/9"} end
    local t=require("lib.services.hotspot").usb(net)
    eq(t.device().interface,"usb0")
    local heard
    truthy(t.start(function(path) heard=path end))
    eq(c.sets[1].property,"Managed") eq(c.sets[1].value,true) eq(c.sets[1].path,"/dev/usb0")
    eq(c.calls[1].method,"AddConnection")
    local sent=c.calls[1].arguments[1].value
    eq(sent.ipv4.method,"shared") eq(sent.connection["interface-name"],"usb0") eq(sent.connection.autoconnect,false)
    truthy(sent.connection.uuid,"a uuid")
    eq(c.calls[2].method,"ActivateConnection")
    eq(c.calls[2].arguments[2].value,"/dev/usb0")
    truthy(heard,"it did not say it came up")
    return true
  end
  morf.ipc.tether_again=function()
    local c=fake_client{}
    USB[2].managed=true
    local t=require("lib.services.hotspot").usb(net_with({{id="eva-usb-tether",path="/settings/4"}},
      {{id="eva-usb-tether",path="/active/2",state="activated"}},USB))
    t.start()
    eq(#c.sets,0,"a managed port was told again") eq(c.calls[1].method,"ActivateConnection")
    eq(t.active().path,"/active/2")
    t.stop()
    eq(c.calls[2].method,"DeactivateConnection")
    return true
  end
  morf.ipc.tether_absent=function()
    fake_client{}
    local t=require("lib.services.hotspot").usb(net_with({},nil,{{type="ethernet",interface="enp3s0",path="/dev/e"}}))
    eq(t.device(),nil)
    local ok,why=t.start()
    falsy(ok,"a start") truthy(why,"a reason")
    return true
  end

  -- ------------------------------------------------------------ data saver --
  local function argv_log()
    local ran={}
    return ran,function(argv,done) ran[#ran+1]=table.concat(argv," ") if done then done({ok=true}) end end
  end
  morf.ipc.saver=function()
    local ran,run=argv_log()
    local kept
    local s=require("lib.services.datasaver").new{run=run,marked={},remember=function(list) kept=list end}
    s.follow(true,{uuid="u-1",devices={"wlan0"}})
    eq(ran[1],"nmcli connection modify u-1 connection.metered yes")
    eq(ran[2],"nmcli device reapply wlan0")
    eq(kept[1],"u-1")
    s.follow(true,{uuid="u-1",devices={"wlan0"}})
    eq(#ran,2,"it marked one connection twice")
    s.follow(true,{uuid="u-2",devices={"wwan0"}})
    eq(ran[3],"nmcli connection modify u-2 connection.metered yes")
    s.follow(false,{uuid="u-2",devices={"wwan0"}})
    local joined=table.concat(ran,"\n")
    truthy(joined:find("modify u-1 connection.metered unknown",1,true),"u-1 put back")
    truthy(joined:find("modify u-2 connection.metered unknown",1,true),"u-2 put back")
    eq(#kept,0)
    return true
  end
  morf.ipc.saver_restart=function()
    local ran,run=argv_log()
    local s=require("lib.services.datasaver").new{run=run,marked={"u-9"}}
    s.follow(false,nil)
    eq(ran[1],"nmcli connection modify u-9 connection.metered unknown")
    return true
  end

  -- ----------------------------------------------------------------- units --
  local function runner(answers)
    local ran={}
    return ran,function(argv,done)
      local line=table.concat(argv," ")
      ran[#ran+1]=line
      local answer=answers[line] or {ok=false,stdout=""}
      done(answer)
    end
  end
  morf.ipc.unit_user=function()
    local ran,run=runner{["systemctl --user cat syncthing.service"]={ok=true},
      ["systemctl --user is-active syncthing.service"]={ok=true,stdout="active\n"},
      ["systemctl --user stop syncthing.service"]={ok=true}}
    local u=require("lib.services.unit").new{unit="syncthing.service",run=run}
    u.find()
    truthy(u.found:get()) truthy(u.on()) eq(u.status(),"On")
    u.set(false)
    falsy(u.on()) eq(ran[#ran],"systemctl --user stop syncthing.service")
    return true
  end
  morf.ipc.unit_system=function()
    local ran,run=runner{["systemctl cat sshd.service"]={ok=true},["systemctl is-active sshd.service"]={ok=false,stdout="inactive\n"},
      ["systemctl start sshd.service"]={ok=false,stderr="denied"}}
    local u=require("lib.services.unit").new{unit="sshd.service",run=run}
    u.find()
    truthy(u.found:get()) falsy(u.on()) eq(u.status(),"Off")
    u.set(true)
    eq(u.phase:get(),"failed") eq(u.status(),"Could not start")
    return true
  end
  morf.ipc.unit_absent=function()
    local _,run=runner{}
    local u=require("lib.services.unit").new{unit="none.service",run=run}
    u.find()
    falsy(u.found:get(),"a unit")
    u.set(true)
    eq(u.phase:get(),"off")
    return true
  end

  -- -------------------------------------------------------------- waydroid --
  morf.ipc.waydroid=function()
    local lib=require("lib.services.waydroid")
    eq(lib.parse("Session:\tRUNNING\nContainer:\tRUNNING\n"),"on")
    eq(lib.parse("Session:\tSTOPPED\nVendor type:\tMAINLINE\n"),"off")
    eq(lib.parse(nil),"off")
    local ran,run=runner{["waydroid status"]={ok=true,stdout="Session:\tSTOPPED\n"},["waydroid session stop"]={ok=true}}
    local spawned,ended
    local d=lib.new{run=run,spawn=function(argv,finished) spawned=table.concat(argv," ") ended=finished end}
    d.check()
    falsy(d.on()) eq(d.status(),"Off")
    d.set(true)
    eq(spawned,"waydroid session start") truthy(d.on()) eq(d.status(),"Starting…")
    ended()
    falsy(d.on(),"a session that ended")
    d.set(false)
    eq(ran[#ran],"waydroid session stop") eq(d.phase:get(),"off")
    return true
  end

  -- ------------------------------------------------------------ voice note --
  local voice_rig={}
  morf.ipc.voice=function()
    local dir=morf.env("XDG_CACHE_HOME").."/more-notes"
    voice_rig.saved=nil voice_rig.signal=nil
    voice_rig.recorder=require("lib.services.voice_recorder").new{folder=dir,name=function() return "note" end,
      saved=function(path) voice_rig.saved=path end,
      spawn=function(argv,ended)
        voice_rig.argv=argv
        return {kill=function(_,signal) voice_rig.signal=signal ended() end}
      end}
    voice_rig.recorder.set(true)
    truthy(voice_rig.recorder.running:get())
    eq(voice_rig.argv[1],"pw-record") eq(voice_rig.argv[#voice_rig.argv],dir.."/note.ogg")
    return true
  end
  morf.ipc.voice_seconds=function() return voice_rig.recorder.seconds:get() end
  morf.ipc.voice_stop=function()
    voice_rig.recorder.set(false)
    eq(voice_rig.signal,"INT","it must close the file")
    falsy(voice_rig.recorder.running:get())
    truthy(voice_rig.saved:match("note%.ogg$"),"the note's path")
    return true
  end

  -- ----------------------------------------------------- background sounds --
  local sound_rig={}
  local loop_step,loop
  morf.ipc.sound_make=function(kind)
    loop_step=require("lib.services.background_sounds").maker(kind,.1)
    loop=nil
  end
  morf.ipc.sound_step=function()
    loop=loop_step()
    return loop~=nil
  end
  morf.ipc.sound_loop=function()
    eq(#loop,2*math.floor(.1*require("lib.services.background_sounds").RATE))
    local peak,zeros=0,0
    local first,last=string.unpack("<i2",loop,1),string.unpack("<i2",loop,#loop-1)
    for i=1,#loop,8 do
      local value=string.unpack("<i2",loop,i)
      if value<0 then value=-value end
      if value>peak then peak=value end
      if value==0 then zeros=zeros+1 end
    end
    truthy(peak>200,"it is silent: "..peak)
    truthy(peak<=32000,"it clips")
    truthy(zeros<#loop/32,"mostly silence")
    return {seam=math.abs(last-first),peak=peak}
  end
  morf.ipc.sound_play=function()
    local lib=require("lib.services.background_sounds")
    sound_rig={writes=0,killed=0,spawns=0}
    sound_rig.sounds=lib.new{tick=1,spawn=function(argv,ended)
      sound_rig.spawns=sound_rig.spawns+1
      sound_rig.argv=argv sound_rig.ended=ended
      return {write=function() sound_rig.writes=sound_rig.writes+1 return true end,
        kill=function() sound_rig.killed=sound_rig.killed+1 end}
    end}
    sound_rig.sounds.play("noise",.25)
    truthy(sound_rig.sounds.running:get())
    return true
  end
  morf.ipc.sound_read=function()
    return {writes=sound_rig.writes,killed=sound_rig.killed,spawns=sound_rig.spawns,argv=sound_rig.argv,
      running=sound_rig.sounds.running:get()}
  end
  morf.ipc.sound_stop=function() sound_rig.sounds.stop() end
  morf.ipc.sound_died=function() sound_rig.ended() end
  morf.ipc.sound_again=function(kind) sound_rig.sounds.play(kind,.5) end

  -- --------------------------------------------------------- screen filters --
  morf.ipc.filter_source=function()
    local lib=require("lib.services.screen_filter")
    eq(lib.source{},nil)
    local gray=lib.source{grayscale=true}
    truthy(gray:find("#version 300 es",1,true)==1,"the version comes first")
    truthy(gray:find("c = vec3(dot(c, LUMA));",1,true),"grayscale")
    falsy(gray:find("1.0 - c",1,true),"invert")
    falsy(gray:find("correct(",1,true),"correction")
    local all=lib.source{grayscale=true,invert=true,extradim=true,reading=true,correction=true,dim=.3,correction_kind="tritanopia"}
    local a,b=all:find("vec3(dot(c, LUMA))",1,true),all:find("1.0 - c",1,true)
    truthy(a<b,"grayscale before invert")
    truthy(all:find("c *= 0.30;",1,true),"the dim")
    truthy(all:find("s = -0.395913",1,true),"tritanopia")
    truthy(lib.source{correction=true}:find("m = 0.494207",1,true),"deuteranopia by default")
    eq(lib.key{},"") eq(lib.key{invert=true,grayscale=true},"grayscale-invert")
    eq(lib.key{extradim=true,dim=.25},"extradim-25")
    return true
  end
  morf.ipc.filter_apply=function()
    local lib=require("lib.services.screen_filter")
    local evals,keywords,files={},{},{}
    local answer="ok"
    local f=lib.new{dir="/run/eva",write=function(path,text) files[path]=text end,
      hyprland={eval=function(chunk,done) evals[#evals+1]=chunk done(answer) end,
        keyword=function(name,value) keywords[#keywords+1]=name.." "..value end}}
    f.apply{}
    eq(#evals,0,"nothing on, nothing said")
    f.apply{grayscale=true}
    eq(evals[1],'hl.config({decoration={screen_shader="/run/eva/screen-grayscale.frag"}})')
    truthy(files["/run/eva/screen-grayscale.frag"],"the shader's file")
    f.apply{grayscale=true}
    eq(#evals,1,"the same filters said twice")
    f.again{grayscale=true}
    eq(#evals,2,"a compositor that forgot was not told again")
    answer="unknown request"
    f.apply{invert=true}
    eq(keywords[1],"decoration:screen_shader /run/eva/screen-invert.frag")
    answer="ok"
    f.apply{}
    eq(evals[#evals],'hl.config({decoration={screen_shader=""}})')
    return true
  end

  -- ---------------------------------------------------------------- light --
  morf.ipc.light=function()
    local c=fake_client{props={HasAmbientLight=true,LightLevel=120.5}}
    local s=require("lib.services.sensors").connect()
    truthy(s.state.light) eq(s.state.lux,120.5)
    s.claim_light() s.claim_light()
    eq(#c.calls,1) eq(c.calls[1].method,"ClaimLight")
    c.changed("net.hadess.SensorProxy",{LightLevel=3})
    eq(s.state.lux,3)
    s.release_light() s.release_light()
    eq(#c.calls,2) eq(c.calls[2].method,"ReleaseLight")
    return true
  end
  morf.ipc.light_curve=function()
    local lib=require("lib.services.sensors")
    local before=-1
    for _,lux in ipairs {0,1,10,100,1000,10000} do
      local level=lib.brightness_for(lux)
      truthy(level>before,"the curve fell at "..lux)
      before=level
    end
    eq(lib.brightness_for(100000),1,"past full")
    truthy(lib.brightness_for(0)>0,"a dark room keeps a lit screen")
    eq(lib.brightness_for(10000),1)
    return true
  end
]]
local serial=0
local function load()
  serial=serial+1
  local settings=morf.env("XDG_CACHE_HOME").."/quick-more-"..serial..".json"
  morf.fs.remove(settings)
  test.load("../shell/init.lua",{source=HOST,size={1600,1000},
    env={EVA_DRY_RUN="0",EVA_FAKE_HARDWARE="0",EVA_SETTINGS=settings}})
end
for _,name in ipairs {"torch_level","torch_burst","torch_lit","nfc","nfc_absent","tether_first","tether_again","tether_absent",
  "saver","saver_restart","unit_user","unit_system","unit_absent","waydroid","filter_source","filter_apply","light","light_curve"} do
  test.it(name:gsub("_"," "),function()
    load()
    test.eq(test.ipc(name),true)
  end)
end
test.it("a voice note counts its seconds, and SIGINT closes the file",function()
  load()
  test.eq(test.ipc("voice"),true)
  test.advance(3050)
  test.eq(test.ipc("voice_seconds"),3)
  test.eq(test.ipc("voice_stop"),true)
  test.advance(3000)
  test.eq(test.ipc("voice_seconds"),3,"the clock ran on")
end)
for _,kind in ipairs {"rain","ocean","noise"} do
  test.it(kind.." is a loop with sound in it, and each step stays in a handler's budget",function()
    load()
    test.ipc("sound_make",kind)
    local done=false
    for _=1,30 do
      done=test.ipc("sound_step")
      if done then break end
    end
    test.truthy(done,"it never finished")
    local loop=test.ipc("sound_loop")
    test.truthy(loop.seam<2*loop.peak,"a seam past the sound's reach: "..loop.seam)
  end)
end
test.it("background sounds feed pw-cat a loop at a time, and stop dead",function()
  load()
  test.ipc("sound_play")
  test.advance(600)
  local read=test.ipc("sound_read")
  test.eq(read.spawns,1)
  test.eq(read.argv[1],"pw-cat") test.contains(read.argv,"--raw") test.contains(read.argv,"--playback")
  test.contains(read.argv,"0.25") test.eq(read.argv[#read.argv],"-")
  test.eq(read.writes,2,"it should start with a loop in hand")
  test.advance(8000)
  test.eq(test.ipc("sound_read").writes,3,"one loop per loop played")
  test.advance(8000)
  test.eq(test.ipc("sound_read").writes,4)
  test.ipc("sound_stop")
  test.advance(20000)
  read=test.ipc("sound_read")
  test.eq(read.killed,1) test.eq(read.writes,4,"it kept writing to a dead pipe") test.falsy(read.running)
end)
test.it("a player that dies says so, and another sound takes over",function()
  load()
  test.ipc("sound_play")
  test.advance(600)
  test.ipc("sound_died")
  test.falsy(test.ipc("sound_read").running)
  test.ipc("sound_again","noise")
  test.advance(50)
  local read=test.ipc("sound_read")
  test.eq(read.spawns,2,"a made loop needs no making") test.truthy(read.running)
end)

-- ---------------------------------------------------------------- the board --

local SOURCE=[[
  local fake_apps=morf.env("FAKE_APPS")
  if fake_apps then
    local rows={{id="org.gnome.Snapshot",name="Camera",categories={"AudioVideo"},keywords={}},
      {id="org.gnome.clocks",name="Clocks",categories={"Clock"},keywords={"alarm"}}}
    morf.apps.entries=function()
      return {applications=function() return rows end,refresh=function() return false end,launch=function() end}
    end
  end
  require("init")
  local utilities=require("utilities")
  local board=utilities.tiles
  local all=function()
    local out={}
    for _,item in ipairs(board.shown()) do out[item.id]=true end
    for _,item in ipairs(board.spare()) do out[item.id]=true end
    return out
  end
  morf.ipc.q_all=all
  morf.ipc.q_on=function(id) return utilities.CONTROLS[id].on()==true end
  morf.ipc.q_status=function(id) return utilities.CONTROLS[id].status() end
  morf.ipc.q_set=function(id,on) utilities.CONTROLS[id].set(on=="on") end
  morf.ipc.q_detail=function() return utilities.detail:get() end
  morf.ipc.q_query=function() return require("launcher").query:get() end
  morf.ipc.q_open=function(name) return require(name).drawer.open:get() end
  morf.ipc.q_config=function(key) return require("config").get(key) end
  morf.ipc.q_lux=function(value) require("quick_hardware").rotation().sensors.state.lux=tonumber(value) end
  morf.ipc.q_brightness=function() return (require("osd").brightness()) end
]]
local NEW={"nfc","usbtether","datasaver","autobrightness","grayscale","invert","extradim","reading","correction",
  "voicenote","sounds","waydroid","syncthing","ssh","onehanded"}
local shell_serial=0
local function shell(options)
  options=options or {}
  shell_serial=shell_serial+1
  local settings=morf.env("XDG_CACHE_HOME").."/quick-more-shell-"..shell_serial..".json"
  morf.fs.remove(settings)
  test.stub_run("task",{code=0,stdout="[]"})
  local env={EVA_DRY_RUN="1",EVA_SETTINGS=settings,EVA_STYLE=options.style or "material",EVA_WALLPAPER="",EVA_FONT_FILE="",
    LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME"),EVA_FAKE_HARDWARE=options.fake and "1" or "0",
    PATH="/nonexistent",FAKE_APPS=options.apps and "1" or nil,EVA_INPUT_DEVICES=morf.env("EVA_INPUT_DEVICES").."-touch"}
  test.load("../shell/init.lua",{source=SOURCE,size=options.size or {868,1932},env=env})
  test.settle(1500)
  test.ipc("settings") test.settle(2500)
end
test.it("a machine with none of it offers none of it",function()
  shell()
  local all=test.ipc("q_all")
  for _,id in ipairs(NEW) do test.falsy(all[id],id.." offered on a machine without it") end
  test.falsy(all.camera,"a camera tile with no camera app")
  test.truthy(all.calculator,"the calculator is the shell's own")
  test.truthy(all.reducemotion)
  test.eq(#test.logs("error"),0)
end)
test.it("with the hardware standing in every tile is offered, and answers",function()
  shell({fake=true})
  local all=test.ipc("q_all")
  for _,id in ipairs(NEW) do
    test.truthy(all[id],id.." is not offered")
    test.falsy(test.ipc("q_on",id),id.." starts on")
    test.ipc("q_set",id,"on") test.advance(30)
    test.truthy(test.ipc("q_on",id),id.." did not turn on")
    test.truthy(test.ipc("q_status",id)~="Off",id.." says it is off")
    test.ipc("q_set",id,"off") test.advance(30)
    test.falsy(test.ipc("q_on",id),id.." did not turn off")
    test.eq(test.ipc("q_status",id),"Off",id.." does not say off")
  end
  test.eq(#test.logs("error"),0)
end)
test.it("a tile for an application is there with the application, and opens it",function()
  shell({apps=true})
  local all=test.ipc("q_all")
  test.truthy(all.camera) test.truthy(all.alarm) test.falsy(all.cast) test.falsy(all.nearby)
  test.eq(test.ipc("q_status","camera"),"Camera")
  test.ipc("q_set","camera","on") test.settle(600)
  test.falsy(test.ipc("q_open","sidebar"),"the panel stayed over what it opened")
  test.falsy(test.ipc("q_on","camera"),"an opener never lights")
  test.eq(#test.logs("error"),0)
end)
test.it("the calculator tile opens the launcher on it",function()
  shell()
  test.ipc("q_set","calculator","on") test.settle(800)
  test.truthy(test.ipc("q_open","launcher"))
  test.eq(test.ipc("q_query"),">calc ")
end)
test.it("auto brightness follows the light once it holds still, and leaves small changes be",function()
  shell({fake=true})
  test.ipc("q_set","autobrightness","on") test.advance(1600)
  test.near(test.ipc("q_brightness"),.57,.03,"the screen did not follow")
  test.ipc("q_lux","2") test.advance(800)
  test.near(test.ipc("q_brightness"),.57,.03,"it moved before the light settled")
  test.advance(900)
  test.near(test.ipc("q_brightness"),.16,.03)
  local level=test.ipc("q_brightness")
  test.ipc("q_lux","2.2") test.advance(1600)
  test.eq(test.ipc("q_brightness"),level,"a flicker in the light moved the screen")
  test.ipc("q_set","autobrightness","off") test.advance(30)
  test.ipc("q_lux","5000") test.advance(1600)
  test.eq(test.ipc("q_brightness"),level,"it followed after being turned off")
end)
test.it("reduce motion reaches the shell's own setting",function()
  shell()
  test.ipc("q_set","reducemotion","on") test.advance(50)
  test.truthy(test.ipc("q_config","appearance.reduce_motion"))
end)
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." the flashlight has a strength, on its page",function()
    shell({fake=true,style=style})
    test.ipc("settings","flashlight") test.settle(1500)
    test.truthy(test.find {id="settings-flashlight-level",visible=true})
    test.falsy(test.find {id="settings-flashlight-note",visible=true})
    test.click("settings-flashlight-switch") test.settle(400)
    test.truthy(test.ipc("q_on","flashlight"))
    test.eq(test.ipc("q_status","flashlight"),"100%")
    local slider=test.get("settings-flashlight-level")
    test.click(slider.x+slider.width*.5,slider.y+slider.height/2) test.settle(400)
    test.near(test.ipc("q_config","flashlight.level"),.5,.08,"the slider set nothing")
    test.truthy(test.ipc("q_status","flashlight"):match("^%d+%%$"))
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." the colour filters share a page, and what each needs shows with it",function()
    shell({fake=true,style=style})
    test.ipc("settings","filters") test.settle(1500)
    test.falsy(test.find {id="settings-filters-dim",visible=true})
    test.falsy(test.find {id="settings-filters-kind-tritanopia",visible=true})
    test.click("settings-filters-grayscale-switch") test.settle(400)
    test.truthy(test.ipc("q_on","grayscale"))
    test.click("settings-filters-extradim-switch") test.settle(600)
    test.truthy(test.find {id="settings-filters-dim",visible=true})
    test.click("settings-filters-correction-switch") test.settle(600)
    test.truthy(test.find {id="settings-filters-kind-tritanopia",visible=true})
    test.click("settings-filters-kind-tritanopia") test.settle(400)
    test.eq(test.ipc("q_config","filters.correction_kind"),"tritanopia")
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." background sounds choose a sound and a level",function()
    shell({fake=true,style=style})
    test.ipc("settings","sounds") test.settle(1500)
    test.click("settings-sounds-ocean") test.settle(400)
    test.eq(test.ipc("q_config","sounds.kind"),"ocean")
    test.click("settings-sounds-switch") test.settle(400)
    test.truthy(test.ipc("q_on","sounds"))
    test.eq(test.ipc("q_status","sounds"),"Ocean")
    test.eq(#test.logs("error"),0)
  end)
end
