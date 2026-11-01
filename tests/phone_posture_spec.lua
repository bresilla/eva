-- What a call does to the machine: the proximity sensor through the real
-- client, and the hold on suspend through the shell.
local test=morf.test
local SENSOR=[[
  local fake=require("lib.testing.dbus")
  local NAME,PATH="net.hadess.SensorProxy","/net/hadess/SensorProxy"
  fake.object("system",NAME,PATH,NAME,{HasAccelerometer=false,HasProximity=true,ProximityNear=false},
    {ClaimProximity=function() end,ReleaseProximity=function() end})
  local sensors=require("lib.services.sensors").connect{dbus=fake.dbus}
  morf.ipc.claim=function() return sensors.claim_proximity() end
  morf.ipc.release=function() return sensors.release_proximity() end
  morf.ipc.near=function(on)
    fake.emit("system",NAME,PATH,"org.freedesktop.DBus.Properties","PropertiesChanged",{NAME,{ProximityNear=on},{}})
  end
  morf.ipc.read=function()
    return {present=sensors.state.proximity,near=sensors.state.near,
      claims=#fake.calls_to("ClaimProximity"),releases=#fake.calls_to("ReleaseProximity")}
  end
]]
local function read() return test.ipc("read") end

test.it("near only counts while the sensor is claimed, and claims do not stack",function()
  test.load("sensor-fixture.lua",{source=SENSOR,size={20,20}})
  test.advance(20)
  test.truthy(read().present)
  test.ipc("near",true)
  test.advance(20)
  test.eq(read().near,false)
  test.ipc("claim") test.ipc("claim")
  test.advance(20)
  test.eq(read().claims,1)
  test.ipc("near",true)
  test.advance(20)
  test.truthy(read().near)
end)

test.it("letting go of the sensor reads as far, whatever it said last",function()
  test.load("sensor-fixture.lua",{source=SENSOR,size={20,20}})
  test.advance(20)
  test.ipc("claim")
  test.advance(20)
  test.ipc("near",true)
  test.advance(20)
  test.ipc("release") test.ipc("release")
  test.advance(20)
  test.eq(read().near,false)
  test.eq(read().releases,1)
end)

local run=0
local function load()
  run=run+1
  local dir=morf.env("XDG_CACHE_HOME").."/phone-posture-"..run
  test.load("../shell/init.lua",{size={868,1932},env={EVA_WALLPAPER="",EVA_DRY_RUN="1",EVA_FAKE_MODEM="1",
    EVA_FAKE_PROXIMITY="1",EVA_CONTACTS="tests/fixtures/contacts",EVA_SETTINGS=dir..".json",XDG_STATE_HOME=dir}})
  test.advance(20)
end
local function state() return test.ipc("phone","state") end
local function fake(...) return test.ipc("phone","fake",...) end

test.it("suspend is held from the first ring to the end of the call, and let go",function()
  load()
  test.eq(state().held,false)
  fake("ring","+31612345678")
  test.advance(40)
  test.eq(state().held,true)
  test.ipc("phone","answer")
  test.advance(40)
  test.eq(state().held,true)
  test.ipc("phone","hangup")
  test.advance(40)
  test.eq(state().held,false)
end)

test.it("a call that is never answered lets go of suspend too",function()
  load()
  fake("ring","+31612345678")
  test.advance(40)
  fake("hangup")
  test.advance(40)
  test.eq(state().held,false)
end)
