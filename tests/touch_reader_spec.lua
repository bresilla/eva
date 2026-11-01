-- The reader: libinput's lines as a real libinput 1.31 printed them, the
-- touchscreens found among the input devices, positions through rotation and on
-- the right panel, and a process that runs only when it can and should.
local test=morf.test
local ROOT=morf.fs.join(morf.env("PWD"),"")
local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=10,height=10}
  local service=require("lib.services.touch_reader")
  local rig={heard={},spawned={},states={}}
  local screen={name="eDP-1",width=1368,height=912,transform="normal"}
  local reader
  local devices={{name="Stand-in",node="/dev/input/event9"}}
  local function sink()
    local out={}
    for _,kind in ipairs {"down","move","up","frame","cancel"} do
      out[kind]=function(...) rig.heard[#rig.heard+1]={kind,...} end
    end
    return out
  end
  local function fake(spec)
    local child={spec=spec,alive=true,kill=function(self) self.alive=false return true end,
      close=function(self) self.closed=true end,pid=function() return nil end}
    rig.spawned[#rig.spawned+1]=child
    return child
  end
  morf.ipc.parse=function(line) return service.parse(line) end
  morf.ipc.place=function(transform,w,h,x,y) return {service.place({width=w,height=h,transform=transform},x,y)} end
  morf.ipc.panel=function(text,chosen)
    local found=service.panel(morf.json.decode(text),chosen,require("auto_rotate").built_in)
    return found and found.name or "none"
  end
  morf.ipc.list=function(path)
    morf.env=(function(env) return function(name)
      if name=="EVA_INPUT_DEVICES" then return path end
      return env(name)
    end end)(morf.env)
    return require("models.touchscreens").list()
  end
  morf.ipc.build=function(how)
    rig.heard,rig.spawned,rig.states={},{},{}
    reader=service.new {
      screen=function() return screen end,sink=sink(),
      find=function() return devices end,
      installed=function() return how~="missing" end,
      spawn=how=="real" and morf.process.spawn or how=="refused" and function() return nil,"no such file" end or fake,
      changed=function(state) rig.states[#rig.states+1]=state end,
    }
    return true
  end
  morf.ipc.devices=function(text) devices=morf.json.decode(text) if reader then reader.refresh() end end
  morf.ipc.start=function() reader.start() return reader.state() end
  morf.ipc.stop=function() reader.stop() return reader.state() end
  morf.ipc.state=function() return {state=reader.state(),reading=reader.reading()} end
  morf.ipc.spawned=function()
    local out={}
    for i,child in ipairs(rig.spawned) do out[i]={command=child.spec.command,alive=child.alive,closed=child.closed==true} end
    return out
  end
  morf.ipc.say=function(index,line) rig.spawned[index].spec.on_stdout(line) end
  morf.ipc.ended=function(index) rig.spawned[index].spec.on_exit(1) end
  morf.ipc.heard=function() return rig.heard end
  morf.ipc.states=function() return rig.states end
  morf.ipc.program=function(path) service.LIBINPUT=path end
  morf.ipc.turn=function(transform,w,h) screen.transform,screen.width,screen.height=transform,w,h end
]]
local function load() test.load("../shell/init.lua",{source=HOST,size={100,100}}) end

-- What real libinput printed for two fingers, as `cat -A` showed it.
local LINES={
  "-event2   DEVICE_ADDED                 QEMU Virtio MultiTouch            seat0 default group1  cap:pt ntouches 11 left scroll-nat calib",
  " event2   TOUCH_DOWN                   +0.000s\t0 (0) 50.00/90.00 (16384.00/29490.00mm)",
  " event2   TOUCH_DOWN                   +0.000s\t1 (1) 60.00/85.00 (19660.00/27852.00mm)",
  " event2   TOUCH_FRAME                  +0.000s\t",
  " event2   TOUCH_MOTION                 +0.012s\t0 (0) 50.00/85.00 (16384.00/27852.00mm)",
  " event2   TOUCH_MOTION              2  +0.012s\t1 (1) 60.00/80.00 (19660.00/26214.00mm)",
  " event2   TOUCH_FRAME                  +0.012s\t",
  " event2   TOUCH_UP                     +0.161s\t0 (0)",
  " event2   TOUCH_UP                     +0.161s\t1 (1)",
  " event2   TOUCH_FRAME                  +0.161s\t",
}

test.it("reads each line real libinput prints",function()
  load()
  test.eq(test.ipc("parse",LINES[1]).kind,"added")
  local down=test.ipc("parse",LINES[2])
  test.eq(down.kind,"down") test.eq(down.node,"event2") test.eq(down.seat,0) test.eq(down.x,50) test.eq(down.y,90)
  test.eq(down.ms,0)
  local repeated=test.ipc("parse",LINES[6])
  test.eq(repeated.kind,"move") test.eq(repeated.seat,1) test.eq(repeated.y,80) test.eq(repeated.ms,12)
  local frame=test.ipc("parse",LINES[10])
  test.eq(frame.kind,"frame") test.eq(frame.ms,161)
  local up=test.ipc("parse",LINES[8])
  test.eq(up.kind,"up") test.eq(up.seat,0) test.eq(up.x,nil)
end)
test.it("reads a small number padded to its width, and a cancel",function()
  load()
  local line=test.ipc("parse"," event2   TOUCH_MOTION                 +3.125s\t2 (2)  5.25/ 7.50 (5.00/6.00mm)")
  test.eq(line.x,5.25) test.eq(line.y,7.5) test.eq(line.seat,2)
  test.eq(test.ipc("parse"," event2   TOUCH_CANCEL                 +3.200s\t0 (0)").kind,"cancel")
end)
test.it("takes nothing from a line that is not about touch",function()
  load()
  test.eq(test.ipc("parse"," event3   POINTER_MOTION               +0.100s\t 1.00/ 0.00"),nil)
  test.eq(test.ipc("parse","Failed to open /dev/input/event2 (Permission denied)"),nil)
  test.eq(test.ipc("parse",""),nil)
end)

test.it("places a finger through every transform the panel can have",function()
  load()
  local CASES={
    {"normal",1280,800,{1000,720}},
    {"90",800,1280,{80,1000}},
    {"180",1280,800,{280,80}},
    {"270",800,1280,{720,280}},
    {"flipped",1280,800,{280,720}},
    {"flipped_90",800,1280,{720,1000}},
    {"flipped_180",1280,800,{1000,80}},
    {"flipped_270",800,1280,{80,280}},
  }
  for _,case in ipairs(CASES) do
    local at=test.ipc("place",case[1],case[2],case[3],78.125,90)
    test.near(at[1],case[4][1],.01,case[1])
    test.near(at[2],case[4][2],.01,case[1])
  end
end)
test.it("follows a scale: positions are the screen's own logical pixels",function()
  load()
  test.eq(test.ipc("place","normal",1368,912,50,50),{684,456})
  test.eq(test.ipc("place","normal",2736,1824,50,50),{1368,912})
end)

test.it("maps a touchscreen to its own panel on a machine with several",function()
  load()
  local DOCKED='[{"name":"DP-1","width":2560,"height":1440},{"name":"eDP-1","width":1368,"height":912},{"name":"HDMI-A-1","width":1920,"height":1080}]'
  test.eq(test.ipc("panel",DOCKED),"eDP-1")
  test.eq(test.ipc("panel",'[{"name":"DSI-1"},{"name":"DP-2"}]'),"DSI-1")
  test.eq(test.ipc("panel",'[{"name":"Virtual-1"}]'),"Virtual-1")
  test.eq(test.ipc("panel",'[{"name":"DP-1"},{"name":"DP-2"}]'),"none")
  test.eq(test.ipc("panel",'[{"name":"DP-1"},{"name":"DP-2"}]',"DP-2"),"DP-2")
  test.eq(test.ipc("panel",DOCKED,"HDMI-A-1"),"HDMI-A-1")
  test.eq(test.ipc("panel",DOCKED,"gone"),"none")
end)

test.it("finds the touchscreen, not the pen beside it, on a Surface",function()
  load()
  local found=test.ipc("list",ROOT.."tests/fixtures/input-devices-surface")
  test.eq(#found,1)
  test.eq(found[1].name,"IPTS 045E:099F Touchscreen")
  test.eq(found[1].node,"/dev/input/event9")
  test.eq(found[1].multi,true)
end)
test.it("finds none on a desk",function()
  load()
  test.eq(#test.ipc("list",ROOT.."tests/fixtures/input-devices"),0)
end)
test.it("finds the touchscreen of a phone and of the VM's device",function()
  load()
  local phone=test.ipc("list",ROOT.."tests/fixtures/input-devices-touch")
  test.eq(phone[1].node,"/dev/input/event5")
  local path=morf.env("XDG_CACHE_HOME").."/vm-devices"
  morf.fs.write(path,[[I: Bus=0006 Vendor=0627 Product=0003 Version=0001
N: Name="QEMU Virtio MultiTouch"
P: Phys=virtio8/input0
S: Sysfs=/devices/pci0000:00/0000:00:0a.0/virtio8/input/input3
U: Uniq=
H: Handlers=event2
B: PROP=2
B: EV=b
B: KEY=30400 1f0000 0 0 0 0
B: ABS=260800000000000
]])
  local vm=test.ipc("list",path)
  test.eq(vm[1].node,"/dev/input/event2")
  test.eq(vm[1].multi,true)
end)

test.it("opens the device with libinput and passes on what it says",function()
  load()
  test.ipc("build","fake")
  test.eq(test.ipc("start"),"starting")
  local spawned=test.ipc("spawned")
  test.eq(spawned[1].command,{"libinput","debug-events","--device","/dev/input/event9"})
  for _,line in ipairs(LINES) do test.ipc("say",1,line) end
  test.eq(test.ipc("state").state,"running")
  local heard=test.ipc("heard")
  test.eq(heard[1][1],"down") test.eq(heard[1][2],"1:0")
  test.near(heard[1][3],684,.01) test.near(heard[1][4],820.8,.01) test.near(heard[1][5],0,.01)
  test.eq(heard[3][1],"frame")
  test.eq(heard[4][1],"move") test.near(heard[4][3],684,.01) test.near(heard[4][4],775.2,.01)
  test.eq(heard[#heard-1][1],"up") test.eq(heard[#heard-1][2],"1:1") test.near(heard[#heard-1][3],161,.01)
  test.eq(heard[#heard][1],"frame") test.near(heard[#heard][2],161,.01)
end)
test.it("reads a real process line by line, and turns with the screen",function()
  local dir=morf.env("XDG_CACHE_HOME").."/reader-bin"
  morf.fs.mkdir(dir)
  local script={"#!/bin/sh"}
  for _,line in ipairs(LINES) do script[#script+1]="printf '%b\\n' '"..line:gsub("\t","\\t").."'" end
  morf.fs.write(dir.."/libinput",table.concat(script,"\n").."\n",{mode=493})
  load()
  test.ipc("program",dir.."/libinput")
  test.ipc("turn","90",912,1368)
  test.ipc("build","real")
  test.ipc("start")
  local heard=test.wait(function()
    local h=test.ipc("heard")
    return #h>=9 and h
  end,3000,"the lines came")
  test.near(heard[1][3],912*.1,.01)
  test.near(heard[1][4],1368*.5,.01)
end)

test.it("spawns nothing with no touchscreen",function()
  load()
  test.ipc("build","fake")
  test.ipc("devices","[]")
  test.ipc("start")
  test.eq(#test.ipc("spawned"),0)
  test.eq(test.ipc("state").state,"none")
end)
test.it("spawns nothing without libinput",function()
  load()
  test.ipc("build","missing")
  test.ipc("start")
  test.eq(#test.ipc("spawned"),0)
  test.eq(test.ipc("state").state,"missing")
end)
test.it("is quiet when the program cannot be started",function()
  load()
  test.ipc("build","refused")
  test.ipc("start")
  test.eq(test.ipc("state"),{state="missing",reading=false})
  test.eq(#test.logs("error"),0)
end)
test.it("says it may not read, and tries again, when libinput dies before a device",function()
  load()
  test.ipc("build","fake")
  test.ipc("start")
  test.ipc("ended",1)
  test.eq(test.ipc("state").state,"denied")
  test.advance(2100)
  test.eq(#test.ipc("spawned"),2)
  test.ipc("say",2,LINES[1])
  test.eq(test.ipc("state").state,"running")
end)

test.it("ends the process when stopped and hears nothing after",function()
  load()
  test.ipc("build","fake")
  test.ipc("start")
  test.ipc("say",1,LINES[1])
  test.eq(test.ipc("stop"),"off")
  local spawned=test.ipc("spawned")
  test.eq(spawned[1].alive,false)
  test.eq(spawned[1].closed,true)
  test.eq(test.ipc("state").reading,false)
  local before=#test.ipc("heard")
  test.ipc("say",1,LINES[2])
  test.eq(#test.ipc("heard"),before)
end)
test.it("follows plug and unplug",function()
  load()
  test.ipc("build","fake")
  test.ipc("devices","[]")
  test.ipc("start")
  test.ipc("devices",'[{"name":"plugged","node":"/dev/input/event7"}]')
  test.eq(test.ipc("spawned")[1].command[4],"/dev/input/event7")
  test.ipc("devices","[]")
  test.eq(test.ipc("spawned")[1].alive,false)
  test.eq(test.ipc("state").state,"none")
end)
