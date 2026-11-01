-- A Surface: a touchscreen, a pen, and a Type Cover that comes off. Its keyboard
-- counts while it is on, it is a desk with the cover on, off or folded back, and
-- gestures read all the same. /proc/bus/input/devices stands in as a fixture.
local test=morf.test
local ROOT=morf.fs.join(morf.env("PWD"),"")
local COVER=morf.fs.read(ROOT.."tests/fixtures/input-devices-surface")
local BARE=morf.fs.read(ROOT.."tests/fixtures/input-devices-surface-tablet")
local SOURCE=[[
  local heard={}
  morf.udev={subscribe=function(_,fn) heard[#heard+1]=fn end}
  local reloads=0
  morf.reload=function() reloads=reloads+1 end
  require("init")
  morf.ipc.plug=function() for _,fn in ipairs(heard) do fn() end end
  morf.ipc.machine=function()
    local responsive=require("responsive")
    local keyboards=require("lib.services.keyboards")
    local names={}
    for i,device in ipairs(keyboards.list(morf.env("EVA_INPUT_DEVICES"))) do names[i]=device.name end
    return {form=responsive.form(),touch=responsive.touch(),keyboards=names,reloads=reloads,
      attached=require("models.keyboards").attached(),external=keyboards.external(morf.env("EVA_INPUT_DEVICES")),
      screens=#require("models.touchscreens").list()}
  end
]]
local loads=0
local function load(devices,extra)
  loads=loads+1
  local path=morf.fs.join(morf.env("XDG_CACHE_HOME"),"surface-devices-"..loads)
  morf.fs.write(path,devices)
  test.stub_run("task",{code=0,stdout="[]"})
  local env={EVA_DRY_RUN="1",EVA_WALLPAPER="",EVA_FAKE_TOUCH="1",EVA_FAKE_LOGIND="{}",EVA_INPUT_DEVICES=path,
    EVA_SETTINGS=morf.fs.join(morf.env("XDG_CACHE_HOME"),"surface-"..loads..".json")}
  for name,value in pairs(extra or {}) do env[name]=value end
  test.load("../shell/init.lua",{source=SOURCE,size={1368,912},env=env})
  test.settle(1000)
  return path
end
local function machine() return test.ipc("machine") end

test.it("counts the Type Cover as a keyboard, and only its keyboard",function()
  load(COVER)
  test.eq(machine().keyboards,{"Microsoft Surface Type Cover"})
end)
test.it("counts a Type Cover with no caps lock light",function()
  load((COVER:gsub("sysrq kbd leds event4","sysrq kbd event4")))
  test.eq(machine().keyboards,{"Microsoft Surface Type Cover"})
end)
test.it("with the cover on it is a desk, and the touchscreen still reads",function()
  load(COVER)
  local m=machine()
  test.eq(m.form,"desk") test.falsy(m.touch) test.eq(m.screens,1)
  local touch=test.ipc("touch")
  test.eq(touch.state,"running") test.eq(touch.reading,true)
end)
test.it("with the cover off it is a desk, the touchscreen its main input",function()
  load(BARE)
  local m=machine()
  test.eq(m.form,"desk") test.truthy(m.touch)
  test.eq(#m.keyboards,0)
  test.eq(test.ipc("touch").state,"running")
end)
test.it("rebuilds as the cover detaches, told by udev, and back as it clips on, a desk throughout",function()
  local path=load(COVER)
  test.eq(machine().form,"desk")
  morf.fs.write(path,BARE)
  test.ipc("plug") test.settle(400)
  local off=machine()
  test.eq(off.form,"desk") test.truthy(off.touch) test.eq(off.reloads,1)
  test.eq(test.ipc("touch").reading,true)
  morf.fs.write(path,COVER)
  test.ipc("plug") test.settle(400)
  local on=machine()
  test.eq(on.form,"desk") test.falsy(on.touch) test.eq(on.reloads,2)
end)
test.it("with the cover folded behind the screen it is a desk too",function()
  load(COVER,{EVA_FAKE_TABLET="on"})
  test.ipc("tablet","pin","on") test.settle(800)
  local m=machine()
  test.falsy(m.external) test.falsy(m.attached)
  test.eq(m.form,"desk") test.truthy(m.touch)
end)
test.it("a keyboard plugged in from outside still counts, folded",function()
  local usb=[[I: Bus=0003 Vendor=046d Product=c31c Version=0110
N: Name="Logitech USB Keyboard"
P: Phys=usb-0000:00:14.0-1/input0
S: Sysfs=/devices/pci0000:00/0000:00:14.0/usb1/1-1/input/input20
U: Uniq=
H: Handlers=sysrq kbd leds event20
B: PROP=0
B: EV=120013
B: KEY=1000000000007 ff9f207ac14057ff febeffdfffefffff fffffffffffffffe
B: MSC=10
B: LED=7

]]
  load(usb..BARE,{EVA_FAKE_TABLET="on"})
  test.ipc("tablet","pin","on") test.settle(800)
  test.truthy(machine().external)
  test.eq(machine().form,"desk")
end)
test.it("finds the touchscreen iptsd makes, Virtual in its name",function()
  local virtual=[[I: Bus=0003 Vendor=045e Product=099f Version=0000
N: Name="IPTSD Virtual Touchscreen 045E:099F"
P: Phys=
S: Sysfs=/devices/virtual/input/input30
U: Uniq=
H: Handlers=mouse4 event30
B: PROP=2
B: EV=b
B: KEY=400 0 0 0 0 0
B: ABS=263800000000003

I: Bus=0003 Vendor=045e Product=099f Version=0000
N: Name="IPTSD Virtual Stylus 045E:099F"
P: Phys=
S: Sysfs=/devices/virtual/input/input31
U: Uniq=
H: Handlers=mouse5 event31
B: PROP=2
B: EV=1b
B: KEY=1c03 0 0 0 0 0
B: ABS=1800000003
B: MSC=1
]]
  load(virtual)
  test.eq(machine().screens,1)
end)
