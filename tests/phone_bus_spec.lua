-- The modem layer through the real client, against a bus that only knows what
-- ModemManager's XML declares (tests/fixtures/phone-bus.txt).
local test=morf.test
local HOST=[[
  local standin=require("lib.services.modem_standin").start()
  local mobile=require("lib.services.modem").connect{dbus=standin.dbus}
  local fake=standin.fake
  local heard,alerts,last={}, {}, {}
  mobile.messaging.on_received(function(row) heard[#heard+1]=row end)
  mobile.cell.on_alert(function(row) alerts[#alerts+1]=row end)
  local function reply(name) return function(ok,why,path) last[name]={ok=ok,why=why or "",path=path or ""} end end
  morf.ipc.ring=function(n) return standin.ring(n) end
  morf.ipc.text=function(n,t,parts) return standin.text(n,t,tonumber(parts)) end
  morf.ipc.finish=function(p,t) standin.finish(p,t) end
  morf.ipc.alert=function(c,t,code) return standin.alert(tonumber(c),t,tonumber(code)) end
  morf.ipc.report=function(p,v) standin.report(p,tonumber(v)) end
  morf.ipc.hang=function(p) standin.hang_up(p) end
  morf.ipc.lock=function(w) standin.lock(w) end
  morf.ipc.dial=function(n) return mobile.voice.dial(n,reply("dial")) end
  morf.ipc.accept=function(p) return mobile.voice.accept(p,reply("accept")) end
  morf.ipc.hangup=function(p) return mobile.voice.hangup(p,reply("hangup")) end
  morf.ipc.hold=function() return mobile.voice.hold(reply("hold")) end
  morf.ipc.join=function(p) return mobile.voice.join(p) end
  morf.ipc.tones=function(p,t) return mobile.voice.tones(p,t,reply("tones")) end
  morf.ipc.forget=function(p) return mobile.voice.forget(p) end
  morf.ipc.send=function(n,t) return mobile.messaging.send(n,t,{report=true},reply("send")) end
  morf.ipc.delete=function(p) return mobile.messaging.delete(p) end
  morf.ipc.channels=function() return mobile.cell.channels({{4370,4383}},reply("channels")) end
  morf.ipc.levels=function() mobile.watch_levels(5,reply("levels")) return mobile.levels() end
  morf.ipc.pin=function(pin) mobile.sim_call(mobile.sim_path(),"SendPin",{pin},reply("pin")) end
  morf.ipc.puk=function(puk,pin) mobile.sim_call(mobile.sim_path(),"SendPuk",{puk,pin},reply("puk")) end
  morf.ipc.emergency=function() return mobile.emergency_numbers() end
  morf.ipc.sent=function(method)
    local out={}
    for _,call in ipairs(fake.calls_to(method)) do out[#out+1]=call.args[1] or false end
    return out
  end
  morf.ipc.read=function()
    return {calls=mobile.voice.calls:get(),sms=mobile.messaging.list:get(),heard=heard,alerts=alerts,last=last,
      unlock=mobile.state.unlock,pin=mobile.state.tries_pin,puk=mobile.state.tries_puk,number=mobile.state.number,
      available=mobile.state.available,voice=mobile.voice.present:get(),locked=mobile.state.locked}
  end
  morf.ipc.unknown=function(extra)
    local names={}
    for line in morf.fs.read("tests/fixtures/phone-bus.txt"):gmatch("[^\n]+") do
      local interface,kind,member=line:match("^(%S+) (%S+) (%S+)")
      if kind=="method" then names[interface.." "..member]=true end
    end
    if extra then fake.calls[#fake.calls+1]={iface="org.freedesktop.ModemManager1.Modem.Voice",method=extra} end
    return standin.unknown_calls(names)
  end
  morf.ipc.declared=function()
    local names,out={}, {}
    for line in morf.fs.read("tests/fixtures/phone-bus.txt"):gmatch("[^\n]+") do
      local interface,kind,member=line:match("^(%S+) (%S+) (%S+)")
      if kind=="method" then names[interface.."|"..member]=true end
    end
    for key,methods in pairs(fake.methods) do
      local interface=key:match("^[^|]*|[^|]*|[^|]*|(.*)$")
      for method in pairs(methods) do
        if interface:match("^org%.freedesktop%.ModemManager1") and not names[interface.."|"..method] then
          out[#out+1]=interface.." "..method
        end
      end
    end
    return out
  end
]]
local function load() test.load("phone-bus-fixture.lua",{source=HOST,size={20,20},env={EVA_DRY_RUN="0"}}) test.advance(20) end
local function read() return test.ipc("read") end
local function state_of(path)
  for _,call in ipairs(read().calls) do if call.path==path then return call.state end end
end

test.it("a call comes in, is answered and is hung up, in ModemManager's states",function()
  load()
  test.truthy(read().voice)
  local path=test.ipc("ring","+31612345678")
  test.advance(20)
  local row=read().calls[1]
  test.eq(row.state,"ringing-in")
  test.eq(row.direction,"incoming")
  test.eq(row.number,"+31612345678")
  test.truthy(test.ipc("accept",path))
  test.advance(20)
  test.eq(state_of(path),"active")
  test.truthy(test.ipc("hangup",path))
  test.advance(20)
  test.eq(state_of(path),"terminated")
  test.eq(read().calls[1].reason,"terminated")
  test.ipc("forget",path)
  test.advance(20)
  test.eq(#read().calls,0)
end)

test.it("dialling creates the call and starts it",function()
  load()
  test.truthy(test.ipc("dial","112"))
  test.advance(200)
  local row=read().calls[1]
  test.eq(row.number,"112")
  test.eq(row.direction,"outgoing")
  test.eq(row.state,"active")
  test.eq(read().last.dial.ok,true)
end)

test.it("hold swaps, a waiting call waits, and a held call joins",function()
  load()
  test.ipc("dial","+3161")
  test.advance(200)
  local first=read().calls[1].path
  test.ipc("hold")
  test.advance(20)
  test.eq(state_of(first),"held")
  test.ipc("hold")
  test.advance(20)
  test.eq(state_of(first),"active")
  local second=test.ipc("ring","+3162")
  test.advance(20)
  test.eq(state_of(second),"waiting")
  test.ipc("hold")
  test.advance(20)
  test.eq(state_of(first),"held")
  test.eq(state_of(second),"active")
  test.ipc("join",first)
  test.advance(20)
  test.eq(state_of(first),"active")
  test.truthy(read().calls[1].multiparty)
end)

test.it("tones go one at a time, the comma waiting here",function()
  load()
  test.ipc("dial","+3161")
  test.advance(200)
  local path=read().calls[1].path
  test.ipc("tones",path,"1,#")
  test.advance(3000)
  test.eq(test.ipc("sent","SendDtmf"),{"1","#"})
  test.eq(read().last.tones.ok,true)
end)

test.it("a long text is heard only once it is whole",function()
  load()
  local path=test.ipc("text","+3161","first part",2)
  test.advance(20)
  test.eq(read().sms[1].state,"receiving")
  test.eq(#read().heard,0)
  test.ipc("finish",path,"first part second part")
  test.advance(20)
  test.eq(#read().heard,1)
  test.eq(read().heard[1].text,"first part second part")
  test.ipc("finish",path,"first part second part")
  test.advance(20)
  test.eq(#read().heard,1)
end)

test.it("a text is sent and its delivery report read",function()
  load()
  test.truthy(test.ipc("send","+3161","hello"))
  test.advance(100)
  local last=read().last.send
  test.eq(last.ok,true)
  test.eq(read().sms[1].state,"sent")
  test.eq(read().sms[1].pdu,"submit")
  test.ipc("report",last.path,0)
  test.advance(20)
  test.eq(read().sms[1].delivery,"delivered")
  test.ipc("report",last.path,0x41)
  test.advance(20)
  test.eq(read().sms[1].delivery,"failed")
  test.ipc("delete",last.path)
  test.advance(20)
  test.eq(#read().sms,0)
end)

test.it("a repeated alert is heard once, a new update again",function()
  load()
  test.ipc("alert",4370,"Flood warning",7)
  test.ipc("alert",4370,"Flood warning",7)
  test.advance(20)
  test.eq(#read().alerts,1)
  test.eq(read().alerts[1].text,"Flood warning")
  test.ipc("alert",4370,"All clear",8)
  test.advance(20)
  test.eq(#read().alerts,2)
  test.truthy(test.ipc("channels"))
  test.advance(20)
  test.eq(read().last.channels.ok,true)
end)

test.it("the SIM's lock reads as PIN, then PUK once the tries run out",function()
  load()
  test.ipc("lock","sim-pin")
  test.advance(20)
  test.eq(read().unlock,"sim-pin")
  test.truthy(read().locked)
  test.eq(read().pin,3)
  test.eq(read().puk,10)
  for left=2,0,-1 do
    test.ipc("pin","0000")
    test.advance(20)
    test.eq(read().last.pin.ok,false)
    test.eq(read().pin,left)
  end
  test.eq(read().unlock,"sim-puk")
  test.ipc("puk","12345678","1234")
  test.advance(20)
  test.eq(read().last.puk.ok,true)
  test.eq(read().unlock,"")
  test.eq(read().locked,false)
end)

test.it("the SIM's emergency numbers and the radio's levels are read",function()
  load()
  test.eq(test.ipc("emergency"),{"112","911"})
  local levels=test.ipc("levels")
  test.eq(levels.radio,"5G")
  test.eq(levels.rsrp,-92.0)
  test.advance(20)
  test.eq(read().last.levels.ok,true)
  test.eq(read().number,"+31600000001")
end)

test.it("nothing is called that ModemManager does not declare",function()
  load()
  local path=test.ipc("ring","+3161")
  test.advance(20)
  test.ipc("accept",path) test.ipc("hold") test.ipc("join",path) test.ipc("tones",path,"1")
  test.ipc("hangup",path) test.ipc("forget",path)
  test.ipc("send","+3161","hi")
  test.ipc("channels") test.ipc("levels") test.ipc("pin","1234")
  test.advance(300)
  test.eq(test.ipc("unknown"),{})
  test.eq(test.ipc("declared"),{})
end)

test.it("the contract catches a name the XML does not have",function()
  load()
  test.eq(test.ipc("unknown","Added"),{"org.freedesktop.ModemManager1.Modem.Voice Added"})
end)
