-- What feeds the battery: the kernel's power supplies read from a fixture tree,
-- the charge limit written back to it, adaptive charging's decision, UPower's
-- switch against a stand-in bus, and all of it on the Power page.
--
--     morf test --no-dbus tests/charging_spec.lua
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=10,height=10}
  local charger=require("lib.services.charger")
  local dir=morf.env("XDG_CACHE_HOME").."/charging-tree"
  local function eq(a,b)
    if a~=b then error(("expected %s, got %s"):format(tostring(b),tostring(a)),2) end
  end
  local function truthy(v,what) if not v then error("expected "..tostring(what or "a true value"),2) end end
  local function falsy(v,what) if v then error("expected no "..tostring(what or "value"),2) end end
  local function tree(spec)
    morf.fs.remove(dir,{recursive=true})
    charger.fixture(dir,spec)
    return dir
  end
  local function write(path,text) morf.fs.write(dir.."/"..path,text.."\n") end

  morf.ipc.pd=function()
    local f=charger.read(tree {level=40,status="Charging",watts=24,
      input={type="USB",usb_type="Unknown SDP DCP CDP [PD_PPS] PD",volts=9,amps=3}})
    truthy(f.present) eq(f.kind,"usb") eq(f.protocol,"PD_PPS") eq(f.watts,24) eq(f.offered,27)
    truthy(f.fast,"fast") falsy(f.slow,"slow") falsy(f.wireless,"wireless")
    return true
  end
  morf.ipc.wireless=function()
    local f=charger.read(tree {level=40,status="Charging",watts=9,input={type="Wireless",volts=9,amps=1.11}})
    eq(f.kind,"wireless") truthy(f.wireless) falsy(f.fast,"fast")
    return true
  end
  morf.ipc.slow=function()
    local f=charger.read(tree {level=40,status="Charging",watts=2.5,input={type="USB",usb_type="[SDP] DCP",volts=5,amps=.5}})
    truthy(f.slow,"slow") falsy(f.fast,"fast") eq(f.protocol,"SDP")
    return true
  end
  morf.ipc.mains=function()
    local f=charger.read(tree {level=40,status="Charging",watts=45,input={type="Mains",volts=20,amps=3}})
    eq(f.kind,"mains") falsy(f.fast,"a fast mark on a laptop's brick")
    return true
  end
  morf.ipc.on_battery=function()
    local f=charger.read(tree {level=40,status="Discharging",watts=6})
    eq(f.kind,nil) eq(f.watts,nil) falsy(f.fast,"fast") falsy(f.slow,"slow")
    return true
  end
  morf.ipc.current=function()
    tree {level=40,status="Charging",input={type="USB",volts=9,amps=2}}
    morf.fs.remove(dir.."/BAT0/power_now")
    write("BAT0/current_now","-2000000")
    write("BAT0/voltage_now","4000000")
    eq(charger.read(dir).watts,8,"a negative current is still a current")
    return true
  end
  morf.ipc.flow_unknown=function()
    tree {level=40,status="Charging",watts=0,input={type="USB",volts=9,amps=2}}
    local f=charger.read(dir)
    eq(f.watts,nil) truthy(f.fast,"what is offered stands in for what flows")
    return true
  end
  morf.ipc.charge_size=function()
    tree {level=40,status="Charging",watts=10,input={type="USB",volts=9,amps=2}}
    morf.fs.remove(dir.."/BAT0/energy_full")
    write("BAT0/charge_full","4000000")
    write("BAT0/voltage_now","4000000")
    eq(charger.read(dir).capacity,16)
    return true
  end
  morf.ipc.best_input=function()
    tree {level=40,status="Charging",watts=20,input={type="USB",usb_type="[PD]",volts=9,amps=3}}
    morf.fs.mkdir(dir.."/ac")
    write("ac/type","Mains") write("ac/online","1")
    eq(charger.read(dir).kind,"usb")
    write("usb/online","0")
    eq(charger.read(dir).kind,"mains")
    return true
  end
  morf.ipc.peripheral=function()
    tree {level=40,status="Discharging"}
    morf.fs.mkdir(dir.."/AAA")
    write("AAA/type","Battery") write("AAA/scope","Device") write("AAA/status","Charging")
    eq(charger.read(dir).name,"BAT0")
    return true
  end
  morf.ipc.none=function()
    morf.fs.remove(dir,{recursive=true})
    local f=charger.read(dir)
    falsy(f.present,"a battery") eq(charger.limit_file(dir),nil)
    local ok,why=charger.set_limit(80,dir)
    falsy(ok,"a set") truthy(why,"a reason")
    return true
  end
  morf.ipc.seconds=function()
    eq(charger.seconds_to(50,100,18,18),1800)
    eq(charger.seconds_to(50,80,20,12),1800)
    eq(charger.seconds_to(90,80,18,18),0)
    eq(charger.seconds_to(50,100,nil,18),0)
    eq(charger.seconds_to(50,100,18,0),0)
    return true
  end
  morf.ipc.limit=function()
    tree {level=40,status="Charging",limit=100,start=95}
    truthy(charger.set_limit(80,dir))
    eq(charger.read(dir).limit,80)
    eq(charger.read(dir).start,75,"a start above the new end would be refused")
    charger.set_limit(20,dir)
    eq(charger.read(dir).limit,charger.LOWEST)
    charger.set_limit(140,dir)
    eq(charger.read(dir).limit,100)
    return true
  end
  morf.ipc.no_limit=function()
    tree {level=40,status="Charging"}
    eq(charger.limit_file(dir),nil)
    local ok=charger.set_limit(80,dir)
    falsy(ok,"a set")
    return true
  end
  morf.ipc.writable=function(kind)
    tree {level=40,status="Charging",limit=100}
    morf.ipc.can=nil
    charger.writable(function(ok) morf.ipc.can=function() return ok end end,dir)
  end
  morf.ipc.adaptive=function()
    local model=require("charge_limit_model")
    local base={limit=100,adaptive=true,plugged=true,ready=420,size=18,watts=9}
    local function at(hour,minute,over)
      local c={}
      for k,v in pairs(base) do c[k]=v end
      for k,v in pairs(over or {}) do c[k]=v end
      c.now=hour*60+(minute or 0)
      return model.target(c)
    end
    -- Twenty per cent of 18 Wh at 9 W is 24 minutes.
    eq(at(23,30),80,"held overnight") eq(at(3),80) eq(at(6,30),80)
    eq(at(6,36),100,"released in time to finish") eq(at(6,50),100)
    eq(at(14),100,"the day is left alone") eq(at(22,59),100)
    eq(at(23,0),80)
    eq(at(1,0,{adaptive=false}),100) eq(at(1,0,{plugged=false}),100)
    eq(at(1,0,{limit=75}),75,"a lower limit of the person's stands")
    eq(at(1,0,{limit=90}),80)
    eq(at(5,59,{watts=false}),80) eq(at(6,0,{watts=false}),100,"an hour's lead without a rate")
    return true
  end
]]
local function load() test.load("../shell/init.lua",{source=HOST,size={100,100}}) end
for _,name in ipairs {"pd","wireless","slow","mains","on_battery","current","flow_unknown","charge_size","best_input",
  "peripheral","none","seconds","limit","no_limit","adaptive"} do
  test.it(name:gsub("_"," "),function()
    load()
    test.eq(test.ipc(name),true)
  end)
end
test.it("asks the kernel's permissions with test -w",function()
  load()
  test.stub_run("test",{code=0})
  test.ipc("writable") test.advance(20)
  test.truthy(test.ipc("can"))
  local ran=test.runs()
  test.eq(ran[#ran][1],"test") test.eq(ran[#ran][2],"-w")
  test.contains(ran[#ran][3],"charge_control_end_threshold")
  test.stub_run("test",{code=1})
  test.ipc("writable") test.advance(20)
  test.falsy(test.ipc("can"))
  test.clear_stubs()
end)

-- ------------------------------------------------------------- the status --

local STATUS=[[
  local ui=require("morf.ui")
  local status=require("battery_status_model")
  ui.Item {width=10,height=10}
  local stand_in
  morf.ipc.fake=function(spec)
    stand_in=status.stand_in(spec)
    return status.read(stand_in)
  end
  morf.ipc.read=function() return status.read(stand_in) end
  morf.ipc.say=function() return status.describe(status.read(stand_in)) end
]]
test.it("the status carries the marks, and says them",function()
  test.load("../shell/init.lua",{source=STATUS,size={100,100}})
  local s=test.ipc("fake","57,charging,fast")
  test.truthy(s.fast) test.falsy(s.wireless) test.truthy(s.watts>15)
  test.eq(s.mark,"bolt")
  test.eq(test.ipc("say"),"57%, fast charging")
  test.ipc("fake-battery","57,charging,wireless") test.advance(50)
  test.truthy(test.ipc("read").wireless)
  test.eq(test.ipc("say"),"57%, wireless charging")
  test.ipc("fake-battery","57,charging,wireless,fast") test.advance(50)
  test.eq(test.ipc("say"),"57%, fast wireless charging")
  test.ipc("fake-battery","57,charging,slow") test.advance(50)
  test.eq(test.ipc("say"),"57%, slow charging")
  test.ipc("fake-battery","57,charging") test.advance(50)
  test.eq(test.ipc("say"),"57%, charging")
  test.ipc("fake-battery","57,discharging") test.advance(50)
  local off=test.ipc("read")
  test.falsy(off.fast) test.falsy(off.wireless) test.eq(off.watts,0)
end)
test.it("no marks while plugged in and not charging",function()
  test.load("../shell/init.lua",{source=STATUS,size={100,100}})
  local s=test.ipc("fake","80,limited,fast")
  test.truthy(s.limited) test.falsy(s.fast)
  test.eq(test.ipc("say"),"80%, limit reached")
end)

-- ---------------------------------------------------------------- the page --

local SHELL=[[
  require("init")
  local charge=require("charge_limit_model")
  morf.ipc.q_limit=function() return require("lib.services.charger").read(require("services").upower.power_supply).limit end
  morf.ipc.q_saved=function() return charge.limit() end
  morf.ipc.q_set=function(value) charge.set_limit(tonumber(value)) end
  morf.ipc.q_route=function() return charge.route() end
  morf.ipc.q_adaptive=function() return charge.adaptive() end
]]
local serial=0
local function shell(fake,style,size)
  serial=serial+1
  test.stub_run("task",{code=0,stdout="[]"})
  test.load("../shell/init.lua",{source=SHELL,size=size or {868,1932},env={EVA_DRY_RUN="1",
    EVA_SETTINGS=morf.env("XDG_CACHE_HOME").."/charging-"..serial..".json",EVA_STYLE=style or "material",
    EVA_WALLPAPER="",EVA_FONT_FILE="",LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME"),
    EVA_FAKE_BATTERY=fake,EVA_INPUT_DEVICES=morf.env("EVA_INPUT_DEVICES").."-touch"}})
  test.settle(1500)
  test.ipc("settings","power")
  test.settle(2500)
end
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." says how it is charging, with its marks and the time left",function()
    shell("57,charging,fast,watts=18,limit=100",style)
    test.eq(test.get("power-charger-title").text,"Fast charging")
    test.contains(test.get("power-charger-subtitle").text,"18.0 W")
    test.contains(test.get("power-charger-subtitle").text,"USB PD")
    test.contains(test.get("power-charger-subtitle").text,"Full in 26m")
    test.truthy(test.find {id="power-mark-fast",visible=true})
    test.falsy(test.find {id="power-mark-wireless",visible=true})
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." sets a limit, the time left runs to it, and adaptive charging opens",function()
    shell("60,charging,watts=18,limit=100",style)
    test.eq(test.ipc("q_route"),"file")
    test.falsy(test.find {id="power-adaptive-switch",visible=false})
    test.click("power-limit-switch") test.settle(600)
    test.eq(test.ipc("q_saved"),80)
    test.eq(test.ipc("q_limit"),80,"the limit did not reach the kernel's file")
    test.contains(test.get("power-charger-subtitle").text,"80% in")
    test.eq(test.get("power-limit-state-subtitle").text,"Stops at 80%")
    test.falsy(test.find {id="power-adaptive",visible=true},"a limit at the hold leaves nothing to wait for")
    test.ipc("q_set","90") test.settle(600)
    test.truthy(test.find {id="power-adaptive",visible=true})
    test.click("power-adaptive-switch") test.settle(600)
    test.truthy(test.ipc("q_adaptive"))
    test.truthy(test.find {id="power-ready-time",visible=true})
    test.click("power-ready-later") test.settle(300)
    test.eq(test.get("power-adaptive-subtitle").text,"Waits at 80%, done by 07:30")
    test.eq(#test.logs("error"),0)
  end)
end
test.it("a wireless charger shows as one",function()
  shell("57,charging,wireless")
  test.eq(test.get("power-charger-title").text,"Wireless charging")
  test.truthy(test.find {id="power-mark-wireless",visible=true})
  test.falsy(test.find {id="power-mark-fast",visible=true})
end)
test.it("a weak charger is named",function()
  shell("57,charging,slow")
  test.eq(test.get("power-charger-title").text,"Slow charging")
  test.truthy(test.find {id="power-mark-slow",visible=true})
  test.contains(test.get("power-charger-note").text,"stronger one")
  test.ipc("fake-battery","57,charging,fast") test.settle(1500)
  test.falsy(test.find {id="power-charger-note",visible=true})
end)
test.it("held at its limit it says so, and a limit nobody set here is left alone",function()
  shell("80,limited,fast")
  test.eq(test.get("power-charger-title").text,"Held at 80%")
  test.eq(test.ipc("q_limit"),80,"the kernel's limit was overwritten")
end)
test.it("a battery with no limit offers none, and shows no Charging card unplugged",function()
  shell("64")
  test.eq(test.ipc("q_route"),"")
  test.falsy(test.find {id="power-charging",visible=true})
  test.ipc("fake-battery","64,charging") test.settle(1500)
  test.truthy(test.find {id="power-charging",visible=true})
  test.falsy(test.find {id="power-limit-state",visible=true})
  test.eq(#test.logs("error"),0)
end)
