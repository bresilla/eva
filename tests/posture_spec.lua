-- A convertible's hinge: the switch found among the input devices, read through
-- a stand-in for evtest, never believed from one event; and what the shell does
-- with it: the form flips, the keyboard offers itself, rotation follows.
--
--     morf test --no-dbus tests/posture_spec.lua
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=10,height=10}
  local posture=require("models.posture")
  local rig={asks=0,kernel=false,dead=false,resume=nil,stream=nil,ended=nil,changes={}}
  local p
  local function build(device)
    p=posture.new {
      find=function() return device end,
      ask=function(_,done)
        rig.asks=rig.asks+1
        if rig.dead then done(nil) else done(rig.kernel) end
      end,
      listen=function(_,changed,ended) rig.stream,rig.ended=changed,ended rig.streams=(rig.streams or 0)+1 end,
      resumed=function(heard) rig.resume=heard end,
      changed=function(value) rig.changes[#rig.changes+1]=value end,
    }
    p.start()
  end
  morf.ipc.build=function(none) build(none~="none" and {name="switch",node="/dev/input/event1"} or nil) return true end
  morf.ipc.folded=function() return p.folded() end
  morf.ipc.present=function() return p.present() end
  morf.ipc.report=function(on) p.report(on=="on") end
  morf.ipc.kernel=function(on) rig.kernel=on=="on" end
  morf.ipc.dead=function(on) rig.dead=on=="yes" end
  morf.ipc.event=function(on) rig.stream(on=="on") end
  morf.ipc.ended=function() rig.ended() end
  morf.ipc.resume=function() rig.resume() end
  morf.ipc.pin=function(on) if on=="none" then p.pin(nil) else p.pin(on=="on") end end
  morf.ipc.asks=function() return rig.asks end
  morf.ipc.streams=function() return rig.streams or 0 end
  morf.ipc.changes=function() return rig.changes end
  morf.ipc.find=function(path) return posture.find(path) end
  morf.ipc.ask=function()
    rig.answer="waiting"
    posture.ask({node="/dev/input/event12"},function(value) rig.answer=value==nil and "none" or value end)
  end
  morf.ipc.answer=function() return rig.answer end
  morf.ipc.listen=function(program)
    rig.heard={}
    posture.EVTEST=program
    posture.listen({node="/dev/input/event12"},function(on) rig.heard[#rig.heard+1]=on end,
      function() rig.heard[#rig.heard+1]="ended" end)
  end
  morf.ipc.heard=function() return rig.heard end
]]
local ROOT=morf.fs.join(morf.env("PWD"),"")
local CONVERTIBLE=ROOT.."tests/fixtures/input-devices-convertible"
local function load(env)
  test.load("../shell/init.lua",{source=HOST,size={100,100},env=env})
end
local SETTLE,RECHECK=700,20000

test.it("finds the tablet switch by its bit, past switches that are not it",function()
  load()
  local device=test.ipc("find",CONVERTIBLE)
  test.eq(device.name,"Intel HID switches")
  test.eq(device.node,"/dev/input/event12")
  test.eq(test.ipc("find",morf.env("EVA_INPUT_DEVICES")),nil)
  test.eq(test.ipc("find","/nonexistent/devices"),nil)
end)
test.it("reads evtest's exit status: ten is on, nought is off, anything else no answer",function()
  load()
  test.stub_run("evtest",{code=10})
  test.ipc("ask") test.advance(20)
  test.eq(test.ipc("answer"),true)
  local ran=test.runs()
  test.eq(ran[#ran],{"evtest","--query","/dev/input/event12","EV_SW","SW_TABLET_MODE"})
  test.stub_run("evtest",{code=0})
  test.ipc("ask") test.advance(20)
  test.eq(test.ipc("answer"),false)
  test.stub_run("evtest",{code=1})
  test.ipc("ask") test.advance(20)
  test.eq(test.ipc("answer"),"none")
  test.clear_stubs()
end)
test.it("hears the switch from evtest's stream, and only the switch",function()
  local dir=morf.env("XDG_CACHE_HOME").."/posture-bin"
  morf.fs.mkdir(dir)
  morf.fs.write(dir.."/evtest",[[#!/bin/sh
echo 'Event code 1 (SW_TABLET_MODE) state 1'
echo 'Event: time 1.0, type 5 (EV_SW), code 0 (SW_LID), value 1'
echo 'Event: time 2.0, type 5 (EV_SW), code 1 (SW_TABLET_MODE), value 1'
echo 'Event: time 3.0, type 5 (EV_SW), code 1 (SW_TABLET_MODE), value 0'
]],{mode=493})
  load()
  test.ipc("listen",dir.."/evtest")
  local heard=test.wait(function()
    local h=test.ipc("heard")
    return h[#h]=="ended" and h
  end,3000,"the stream ended")
  test.eq(heard,{true,false,"ended"})
end)
test.it("a machine without a switch runs nothing",function()
  load()
  test.ipc("build","none")
  test.falsy(test.ipc("present"))
  test.advance(RECHECK*2)
  test.eq(test.ipc("asks"),0)
  test.eq(test.ipc("streams"),0)
end)
test.it("asks at the start, so a machine booted folded starts folded",function()
  load()
  test.ipc("kernel","on")
  test.ipc("build")
  test.truthy(test.ipc("present"))
  test.truthy(test.ipc("folded"))
  test.eq(test.ipc("asks"),1)
end)
test.it("an event the kernel does not bear out changes nothing",function()
  load()
  test.ipc("build")
  test.ipc("event","on") test.advance(SETTLE+20)
  test.falsy(test.ipc("folded"),"one event was believed")
  test.ipc("kernel","on")
  test.ipc("event","on") test.advance(SETTLE-100)
  test.falsy(test.ipc("folded"),"it did not wait to settle")
  test.advance(120)
  test.truthy(test.ipc("folded"))
end)
test.it("a hinge that bounces is one change",function()
  load()
  test.ipc("build")
  local before=test.ipc("asks")
  test.ipc("kernel","on")
  for i=1,6 do
    test.ipc("event",i%2==0 and "off" or "on")
    test.advance(100)
  end
  test.ipc("event","on") test.advance(SETTLE+20)
  test.eq(test.ipc("asks"),before+1)
  test.eq(test.ipc("changes"),{true})
end)
test.it("without evtest's answer a hint stands, once it has settled",function()
  load()
  test.ipc("dead","yes")
  test.ipc("build")
  test.falsy(test.ipc("folded"))
  test.ipc("report","on") test.advance(SETTLE+20)
  test.truthy(test.ipc("folded"))
  test.ipc("report","off") test.advance(100)
  test.ipc("report","on") test.advance(SETTLE+20)
  test.truthy(test.ipc("folded"),"the last hint counts")
  test.ipc("report","off") test.advance(SETTLE+20)
  test.falsy(test.ipc("folded"))
end)
test.it("a way out with no event is caught by the next look, and only while folded",function()
  load()
  test.ipc("kernel","on")
  test.ipc("build")
  test.truthy(test.ipc("folded"))
  test.ipc("kernel","off")
  test.advance(RECHECK+20)
  test.falsy(test.ipc("folded"),"it stayed folded")
  local asks=test.ipc("asks")
  test.advance(RECHECK*3)
  test.eq(test.ipc("asks"),asks,"it kept looking while open")
end)
test.it("asks again after a resume",function()
  load()
  test.ipc("build")
  test.ipc("kernel","on")
  test.ipc("resume")
  test.truthy(test.ipc("folded"))
end)
test.it("a stream that ends is started again, waiting longer each time",function()
  load()
  test.ipc("build")
  test.eq(test.ipc("streams"),1)
  test.ipc("ended") test.advance(30020)
  test.eq(test.ipc("streams"),2)
  test.ipc("ended") test.advance(30020)
  test.eq(test.ipc("streams"),2,"it did not back off")
  test.advance(30020)
  test.eq(test.ipc("streams"),3)
end)
test.it("a pin holds the posture whatever the switch says, until it is let go",function()
  load()
  test.ipc("kernel","on")
  test.ipc("build")
  test.ipc("pin","off")
  test.falsy(test.ipc("folded"))
  test.ipc("event","on") test.advance(SETTLE+20) test.advance(RECHECK+20)
  test.falsy(test.ipc("folded"),"the pin gave way")
  test.ipc("pin","none")
  test.truthy(test.ipc("folded"))
end)

-- ---------------------------------------------------------------- the shell --

local SHELL=[[
  local kit=require("kit")
  require("init")
  local R=require("responsive")
  morf.ipc.q_form=function()
    return {form=R.form(),touch=R.touch(),sheets=R.sheets(),target=R.target(),layout=R.layout()}
  end
  morf.ipc.q_keyboard=function() return require("models.keyboards").attached() end
  morf.ipc.q_rotation=function()
    local r=require("quick_hardware").rotation()
    return {on=r.on(),status=r.status()}
  end
  morf.ipc.q_lock=function(value) require("config").set("rotation.lock",value) end
  morf.ipc.q_drawer=function() return require("sidebar").drawer.edge end
]]
local serial=0
local function shell(env,size,devices)
  serial=serial+1
  test.stub_run("task",{code=0,stdout="[]"})
  local all={EVA_DRY_RUN="1",EVA_SETTINGS=morf.env("XDG_CACHE_HOME").."/posture-"..serial..".json",EVA_STYLE="material",
    EVA_WALLPAPER="",EVA_FONT_FILE="",LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME"),
    EVA_FAKE_HARDWARE="1",EVA_INPUT_DEVICES=devices or CONVERTIBLE}
  for k,v in pairs(env or {}) do all[k]=v end
  test.load("../shell/init.lua",{source=SHELL,size=size or {1920,1200},env=all})
  test.settle(1500)
end

test.it("a convertible open as a laptop is a desk with its keyboard in reach",function()
  shell({EVA_FAKE_TABLET="off"})
  local f=test.ipc("q_form")
  test.eq(f.form,"desk") test.falsy(f.touch) test.eq(f.target,40)
  test.truthy(test.ipc("q_keyboard"))
end)
test.it("folded with its keyboard still attached it is a tablet, in every way a tablet is",function()
  shell({EVA_FAKE_TABLET="off"})
  local before=test.ipc("q_form").layout
  test.ipc("tablet","on")
  test.advance(SETTLE+50)
  local f=test.ipc("q_form")
  test.eq(f.form,"tablet","the form did not flip")
  test.truthy(f.touch) test.truthy(f.sheets)
  test.eq(f.target,48,"the targets stayed a pointer's")
  test.truthy(f.layout~=before,"the layout the shell rebuilds on did not change")
  test.falsy(test.ipc("q_keyboard"),"the keyboard behind the screen counts")
  test.eq(#test.logs("error"),0)
end)
test.it("a machine booted folded starts as a tablet",function()
  shell({EVA_FAKE_TABLET="on"})
  test.eq(test.ipc("q_form").form,"tablet")
  test.eq(test.ipc("q_drawer"),"top")
end)
test.it("opening it again brings the desk back",function()
  shell({EVA_FAKE_TABLET="on"})
  test.ipc("tablet","off")
  test.advance(SETTLE+50)
  test.eq(test.ipc("q_form").form,"desk")
  test.truthy(test.ipc("q_keyboard"))
end)
test.it("a real change is written down, and what runs apart from the shell reads it",function()
  local run=morf.env("XDG_CACHE_HOME").."/posture-run"
  morf.fs.remove(run,{recursive=true})
  shell({XDG_RUNTIME_DIR=run},nil,morf.env("EVA_INPUT_DEVICES"))
  test.ipc("tablet","on") test.advance(SETTLE+50)
  test.eq(morf.fs.read(run.."/eva/posture"),"folded\n")
  test.ipc("tablet","off") test.advance(SETTLE+50)
  test.eq(morf.fs.read(run.."/eva/posture"),"open\n")
  test.ipc("tablet","on") test.advance(SETTLE+50)
  shell({XDG_RUNTIME_DIR=run},nil,CONVERTIBLE)
  test.falsy(test.ipc("q_keyboard"),"a lock started folded would wait for keys that cannot come")
end)
test.it("a stand-in leaves nothing for a real session to read",function()
  local run=morf.env("XDG_CACHE_HOME").."/posture-sealed"
  morf.fs.remove(run,{recursive=true})
  shell({XDG_RUNTIME_DIR=run,EVA_FAKE_TABLET="off"})
  test.ipc("tablet","on") test.advance(SETTLE+50)
  test.falsy(morf.fs.exists(run.."/eva/posture"))
end)
test.it("a keyboard plugged in still counts while folded",function()
  local devices=morf.env("XDG_CACHE_HOME").."/posture-usb"
  morf.fs.write(devices,morf.fs.read(CONVERTIBLE)..[[
I: Bus=0003 Vendor=046d Product=c31c Version=0110
N: Name="Logitech USB Keyboard"
H: Handlers=sysrq kbd leds event20
B: EV=120013

]])
  shell({EVA_FAKE_TABLET="on"},nil,devices)
  test.truthy(test.ipc("q_keyboard"),"a real keyboard in the hand was ignored")
  test.eq(test.ipc("q_form").form,"desk")
end)
test.it("no touchscreen means no tablet, folded or not",function()
  local devices=morf.env("XDG_CACHE_HOME").."/posture-bare"
  morf.fs.write(devices,(morf.fs.read(CONVERTIBLE):gsub("B: PROP=2","B: PROP=0")))
  shell({EVA_FAKE_TABLET="on"},nil,devices)
  test.eq(test.ipc("q_form").form,"desk")
end)
test.it("the hinge holds the rotation in laptop posture, even with the lock off",function()
  shell({EVA_FAKE_TABLET="off"})
  test.ipc("q_lock","off") test.advance(50)
  local r=test.ipc("q_rotation")
  test.truthy(r.on) test.eq(r.status,"Held by the hinge")
  test.ipc("tablet","on") test.advance(SETTLE+50)
  r=test.ipc("q_rotation")
  test.falsy(r.on,"folded, it should follow the accelerometer") test.eq(r.status,"Auto")
end)
test.it("a machine with no hinge keeps its lock as it was",function()
  shell({},nil,morf.env("EVA_INPUT_DEVICES"))
  test.ipc("q_lock","off") test.advance(50)
  test.falsy(test.ipc("q_rotation").on)
end)
test.it("the tablet verb says what it holds and refuses what it does not know",function()
  shell({EVA_FAKE_TABLET="off"})
  local s=test.ipc("tablet","state")
  test.falsy(s.folded) test.truthy(s.present) test.eq(s.device,"Stand-in tablet switch")
  test.ipc("tablet","pin","on")
  test.truthy(test.ipc("tablet").folded)
  test.ipc("tablet","auto")
  test.falsy(test.ipc("tablet").folded)
  test.raises(function() test.ipc("tablet","sideways") end,"sideways")
end)
test.it("the rebuild the fold causes keeps it folded",function()
  shell({EVA_FAKE_TABLET="off"})
  test.ipc("tablet","on") test.advance(SETTLE+50)
  test.truthy(test.reload {source=SHELL})
  test.settle(1500)
  test.truthy(test.ipc("tablet","state").folded,"a reload forgot the fold")
end)
