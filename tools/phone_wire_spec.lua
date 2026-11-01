-- Sends every typed call of the phone layer through the engine's real encoder,
-- to names `dbus-test-tool echo` owns. tools/phone-wire.sh runs it on a private
-- bus and reads the types back off the wire with dbus-monitor.
local test=morf.test
local HOST=[[
  local db=require("lib.services.dbus")
  local standin_path="/org/freedesktop/ModemManager1/Modem/0"
  local system=db.new{bus="system"}
  local dry=function() return false end
  local voice=require("lib.services.modem_voice").attach(system,{dry=dry})
  local sms=require("lib.services.modem_messaging").attach(system,{dry=dry})
  local cell=require("lib.services.modem_cell").attach(system,{dry=dry})
  local ring=require("lib.shell.audio.ringer").connect{mode="sound"}
  local audio=require("lib.services.callaudio").connect()
  local mobile=require("lib.services.modem").connect()
  local call="/org/freedesktop/ModemManager1/Call/1"
  morf.ipc.run=function()
    voice.bind(standin_path,{})
    sms.bind(standin_path)
    cell.bind(standin_path)
    voice.dial("+3161234")
    voice.accept(call)
    voice.hangup(call)
    voice.deflect(call,"+3199")
    voice.join(call)
    voice.leave(call)
    voice.tones(call,"5")
    voice.hold()
    voice.hangup_and_accept()
    voice.hangup_all()
    voice.transfer()
    voice.waiting(true)
    voice.forget(call)
    sms.send("+3161234","hello",{report=true})
    sms.delete("/org/freedesktop/ModemManager1/SMS/1")
    cell.channels({{4370,4383}})
    cell.delete("/org/freedesktop/ModemManager1/Cbm/1")
    mobile.sim_call("/org/freedesktop/ModemManager1/SIM/0","SendPin",{"1234"},function() end)
    mobile.sim_call("/org/freedesktop/ModemManager1/SIM/0","SendPuk",{"12345678","1234"},function() end)
    mobile.sim_call("/org/freedesktop/ModemManager1/SIM/0","EnablePin",{"1234",true},function() end)
    mobile.sim_call("/org/freedesktop/ModemManager1/SIM/0","ChangePin",{"1234","4321"},function() end)
    audio.call(true)
    audio.speaker(true)
    audio.mute(true)
    ring.state.feedbackd=true
    ring.trigger("phone-incoming-call",{timeout=0,important=true})
    ring.stop(7)
    return true
  end
]]
test.it("every typed call goes out",function()
  test.load("../shell/init.lua",{source=HOST,size={20,20},env={EVA_DRY_RUN="0"}})
  test.truthy(test.ipc("run"))
  local deadline=morf.time.now_ms()+1500
  test.wait(function() return morf.time.now_ms()>deadline end,3000)
end)
