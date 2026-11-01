-- The normalised battery status: every UPower state a machine can be in, read
-- the one way, and the stand-in the harness draws with.
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  local status=require("battery_status_model")
  ui.Item {width=10,height=10}
  local function rows(list)
    return {len=function() return #list end,get=function(_,i) return list[i] end}
  end
  local function service(display,root,limit)
    local state={available=true,on_battery=root.on_battery,display=display,
      devices=root.devices,profiles=root.profiles}
    return {state=state,charge_limit=function() return limit,root.start end}
  end
  local CASES={
    discharging=service({present=true,percentage=64,state="discharging",charging=false},{on_battery=true}),
    charging_low=service({present=true,percentage=12,state="charging",charging=true},{on_battery=false}),
    pending_charge=service({present=true,percentage=70,state="pending_charge",charging=true},{on_battery=false}),
    limit_reached=service({present=true,percentage=80,state="pending_charge",charging=true},{on_battery=false},80),
    limit_window=service({present=true,percentage=77,state="pending_discharge",charging=false},{on_battery=false,start=75},80),
    limit_below=service({present=true,percentage=60,state="pending_charge",charging=true},{on_battery=false},80),
    limit_full=service({present=true,percentage=100,state="fully_charged",charging=false},{on_battery=false},100),
    full=service({present=true,percentage=100,state="fully_charged",charging=false},{on_battery=false}),
    bypass=service({present=true,percentage=55,state="discharging",charging=false},{on_battery=false}),
    unknown_mains=service({present=true,percentage=44,state="unknown",charging=false},{on_battery=false}),
    low=service({present=true,percentage=20,state="discharging",charging=false},{on_battery=true}),
    critical=service({present=true,percentage=10,state="discharging",charging=false},{on_battery=true}),
    empty=service({present=true,percentage=0,state="empty",charging=false},{on_battery=true}),
    low_plugged=service({present=true,percentage=9,state="pending_charge",charging=true},{on_battery=false}),
    rounded=service({present=true,percentage=63.5,state="discharging",charging=false},{on_battery=true}),
    saver=service({present=true,percentage=64,state="discharging",charging=false},
      {on_battery=true,profiles={available=true,active="power-saver"}}),
    saver_charging=service({present=true,percentage=64,state="charging",charging=true},
      {on_battery=false,profiles={available=true,active="power-saver"}}),
    no_profiles=service({present=true,percentage=64,state="discharging",charging=false},
      {on_battery=true,profiles={available=false,active="power-saver"}}),
    no_battery=service({present=false,percentage=0},{on_battery=false}),
    device_row=service({present=false,percentage=0},{on_battery=true,
      devices=rows {{kind="line_power",present=true},{kind="battery",present=true,percentage=41,state="discharging"}}}),
    no_state=service({present=true,percentage=84,charging=true},{}),
  }
  CASES.unavailable={state={available=false,display={present=true,percentage=50}}}
  morf.ipc.read=function(name) return status.read(CASES[name]) end
  morf.ipc.describe=function(name) return status.describe(status.read(CASES[name])) end
  morf.ipc.fake=function(spec)
    local stand_in=status.stand_in(spec)
    morf.ipc.fake_read=function() return status.read(stand_in) end
    return status.read(stand_in)
  end
]]
local function load() test.load("../shell/init.lua",{source=HOST,size={100,100}}) end
local function read(name) return test.ipc("read",name) end
test.it("reads a discharging battery as nothing but its level",function()
  load()
  local s=read("discharging")
  test.truthy(s.present) test.eq(s.level,64)
  test.falsy(s.charging) test.falsy(s.plugged) test.falsy(s.full) test.falsy(s.saver)
  test.falsy(s.limited) test.falsy(s.low) test.falsy(s.critical)
  test.eq(s.mark,"") test.eq(s.tone,"ink")
end)
test.it("tells charging from plugged in and not charging",function()
  load()
  local c=read("charging_low")
  test.truthy(c.charging) test.truthy(c.plugged) test.eq(c.mark,"bolt") test.eq(c.tone,"ok")
  local p=read("pending_charge")
  test.falsy(p.charging) test.truthy(p.plugged) test.eq(p.mark,"plug")
  for _,name in ipairs {"bypass","unknown_mains"} do
    local s=read(name)
    test.falsy(s.charging) test.truthy(s.plugged) test.eq(s.mark,"plug")
  end
end)
test.it("treats fully charged on mains as full and plugged, not as discharging",function()
  load()
  local s=read("full")
  test.truthy(s.full) test.truthy(s.plugged) test.falsy(s.charging) test.eq(s.level,100) test.eq(s.mark,"plug")
end)
test.it("sees a charge limit only where the battery is held at it",function()
  load()
  local at=read("limit_reached")
  test.truthy(at.limited) test.falsy(at.charging) test.eq(at.mark,"shield")
  test.truthy(read("limit_window").limited)
  test.falsy(read("limit_below").limited)
  test.falsy(read("limit_full").limited)
  test.falsy(read("discharging").limited)
end)
test.it("alarms at 20% and 10% on battery only",function()
  load()
  local low=read("low") test.truthy(low.low) test.falsy(low.critical) test.eq(low.tone,"warn") test.eq(low.mark,"")
  local critical=read("critical") test.truthy(critical.low) test.truthy(critical.critical)
  test.eq(critical.tone,"alert") test.eq(critical.mark,"alert")
  test.truthy(read("empty").critical) test.eq(read("empty").level,0)
  local plugged=read("low_plugged") test.falsy(plugged.low) test.falsy(plugged.critical)
  test.eq(plugged.tone,"ink")
end)
test.it("carries the power profile beside every other state",function()
  load()
  local s=read("saver") test.truthy(s.saver) test.eq(s.tone,"extra") test.eq(s.mark,"")
  local both=read("saver_charging") test.truthy(both.saver) test.eq(both.mark,"bolt") test.eq(both.tone,"ok")
  test.falsy(read("no_profiles").saver)
end)
test.it("rounds the level, falls back to a battery row and absent means absent",function()
  load()
  test.eq(read("rounded").level,64)
  test.eq(read("device_row").level,41)
  test.falsy(read("no_battery").present)
  test.falsy(read("unavailable").present)
  test.eq(read("no_state").level,84) test.truthy(read("no_state").charging)
end)
test.it("says each state in words",function()
  load()
  test.eq(test.ipc("describe","no_battery"),"On mains power")
  test.eq(test.ipc("describe","discharging"),"64%")
  test.eq(test.ipc("describe","charging_low"),"12%, charging")
  test.eq(test.ipc("describe","limit_reached"),"80%, limit reached")
  test.eq(test.ipc("describe","full"),"100%, full")
  test.eq(test.ipc("describe","pending_charge"),"70%, plugged in")
  test.eq(test.ipc("describe","saver_charging"),"64%, charging, power saver")
end)
test.it("gives the harness a stand-in it can move",function()
  load()
  local s=test.ipc("fake","57,charging,saver")
  test.eq(s.level,57) test.truthy(s.charging) test.truthy(s.saver)
  test.ipc("fake-battery","80,limited") test.advance(50)
  local held=test.ipc("fake_read")
  test.eq(held.level,80) test.truthy(held.limited) test.falsy(held.charging) test.falsy(held.saver)
  test.ipc("fake-battery","100,full") test.advance(50)
  test.truthy(test.ipc("fake_read").full)
  test.ipc("fake-battery","15") test.advance(50)
  test.truthy(test.ipc("fake_read").low)
end)
