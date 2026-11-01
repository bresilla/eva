-- Calls through the whole shell, against ModemManager on a stand-in bus.
local test=morf.test
local run=0
local function load(w,h,env)
  run=run+1
  local settings=morf.env("XDG_CACHE_HOME").."/phone-calls-"..run
  env=env or {}
  env.EVA_WALLPAPER="" env.EVA_DRY_RUN="1" env.EVA_FAKE_MODEM="1" env.EVA_FAKE_HAPTICS="1"
  env.EVA_FAKE_PROXIMITY="1"
  env.EVA_CONTACTS="tests/fixtures/contacts" env.EVA_SETTINGS=settings..".json"
  env.XDG_STATE_HOME=settings
  test.load("../shell/init.lua",{size={w or 868,h or 1932},env=env})
  test.advance(20)
end
local function fake(...) return test.ipc("phone","fake",...) end
local function state() return test.ipc("phone","state") end
local function call_surface()
  for _,s in ipairs(test.surfaces()) do
    if (s.name or s.label or ""):find("eva-call",1,true) or tostring(s.label):find("eva-call",1,true) then return s end
  end
end
local function ring(number) fake("ring",number or "+31612345678") test.advance(40) end
local function press(id) test.click(id,{surface=call_surface().label}) test.advance(40) end
local function history()
  local rows=morf.fs.read(morf.env("XDG_CACHE_HOME").."/phone-calls-"..run.."/eva/phone/calls.jsonl")
  local out={}
  for line in rows:gmatch("[^\n]+") do out[#out+1]=morf.json.decode(line) end
  return out
end

test.it("no modem, no surface and no call state",function()
  test.load("../shell/init.lua",{size={868,1932},env={EVA_WALLPAPER="",EVA_DRY_RUN="1",EVA_FAKE_MODEM="0"}})
  test.advance(20)
  test.eq(call_surface(),nil)
end)

test.it("an incoming call rings, names the caller and shows over everything",function()
  load()
  test.eq(state().stage,"idle")
  test.eq(call_surface(),nil)
  ring()
  local s=state()
  test.eq(s.stage,"incoming")
  test.eq(s.rung,"phone-incoming-call")
  test.eq(s.calls[1].label,"Ann Veldman")
  test.truthy(call_surface())
  test.truthy(test.find("call-orb"))
end)

test.it("answering stops the ring, routes the sound and starts the clock",function()
  load()
  ring()
  press("call-answer")
  local s=state()
  test.eq(s.stage,"talking")
  test.eq(s.rung,"")
  test.advance(2100)
  test.truthy(state().seconds>=0)
  test.truthy(test.find("call-mute"))
end)

test.it("declining turns the call away and logs it as declined, not missed",function()
  load()
  ring()
  press("call-decline")
  test.eq(state().stage,"ended")
  test.advance(40)
  test.eq(history()[1].outcome,"declined")
  test.advance(2000)
  test.eq(state().stage,"idle")
  test.eq(call_surface(),nil)
end)

test.it("a call let ring out is missed: logged, noticed and unseen",function()
  load()
  test.eq(test.ipc("drawers"):find("notifications",1,true),nil)
  ring("+3199887766")
  fake("hangup")
  test.advance(60)
  local row=history()[1]
  test.eq(row.outcome,"missed")
  test.eq(row.seen,false)
  test.eq(row.number,"+3199887766")
  test.contains(test.ipc("drawers"),"notifications")
end)

test.it("mute, speaker and the keypad act on the call",function()
  load()
  ring()
  press("call-answer")
  press("call-mute")
  test.truthy(state().muted)
  press("call-speaker")
  test.truthy(state().speaker)
  press("call-keypad-toggle")
  test.truthy(test.find("call-key-5"))
  press("call-key-5")
  press("call-end")
  test.eq(state().stage,"ended")
  test.advance(60)
  test.eq(state().muted,false)
  test.eq(state().speaker,false)
  local row=history()[1]
  test.eq(row.outcome,"answered")
  test.eq(row.direction,"incoming")
end)

test.it("a second call waits, and answering holds the first",function()
  load()
  ring()
  press("call-answer")
  ring("+3161111111")
  test.truthy(test.find("call-waiting-name"))
  test.eq(state().stage,"talking")
  press("call-waiting-answer")
  local calls=state().calls
  test.eq(calls[1].state,"held")
  test.eq(calls[2].state,"active")
  press("call-merge")
  test.truthy(state().calls[1].multiparty)
end)

test.it("pulling the orb past the rail's end answers, a short pull does not",function()
  load()
  ring()
  local surface=call_surface().label
  local orb=test.get("call-orb")
  local rail=test.get("call-rail")
  local x,y=orb.x+orb.width/2,orb.y+orb.height/2
  test.swipe({x,y},{x+60,y},{surface=surface,duration=400,steps=12})
  test.advance(600)
  test.eq(state().stage,"incoming")
  test.swipe({x,y},{rail.x+rail.width-8,y},{surface=surface,duration=400,steps=12})
  test.advance(60)
  test.eq(state().stage,"talking")
end)

test.it("pulling the orb the other way declines",function()
  load()
  ring()
  local surface=call_surface().label
  local orb=test.get("call-orb")
  local rail=test.get("call-rail")
  local x,y=orb.x+orb.width/2,orb.y+orb.height/2
  test.swipe({x,y},{rail.x+8,y},{surface=surface,duration=400,steps=12})
  test.advance(60)
  test.eq(state().stage,"ended")
  test.advance(40)
  test.eq(history()[1].outcome,"declined")
end)

test.it("a blocked number never rings",function()
  load()
  test.ipc("phone","state")
  test.load("../shell/init.lua",{source=[[
    local standin=require("lib.services.modem_standin").start()
    local mobile=require("lib.services.modem").connect{dbus=standin.dbus}
    local book=require("lib.services.contacts").open{folder="tests/fixtures/contacts",
      state=morf.env("XDG_CACHE_HOME").."/blocked-marks.json",watch=false}
    book.block("+3161234",true)
    local rang={}
    local log=require("lib.services.journal").open{name="blocked",dir=morf.env("XDG_CACHE_HOME").."/blocked-log"}
    log.clear()
    local phone=require("models.phone_calls").new{mobile=mobile,book=book,owner=true,log=log,
      ring={trigger=function(e) rang[#rang+1]=e end,stop=function() end}}
    morf.ipc.ring=function(n) standin.ring(n) end
    morf.ipc.read=function() return {rang=#rang,stage=phone.stage:get(),rows=#log.rows:get(),
      outcome=(log.rows:get()[1] or {}).outcome or ""} end
  ]],size={20,20}})
  test.advance(20)
  test.ipc("ring","+3161234")
  test.advance(60)
  local read=test.ipc("read")
  test.eq(read.rang,0)
  test.eq(read.stage,"idle")
  test.eq(read.outcome,"blocked")
end)

test.it("a blocked number that arrives after the ring is still turned away",function()
  test.load("../shell/init.lua",{source=[[
    local standin=require("lib.services.modem_standin").start()
    local mobile=require("lib.services.modem").connect{dbus=standin.dbus}
    local book=require("lib.services.contacts").open{folder="tests/fixtures/contacts",
      state=morf.env("XDG_CACHE_HOME").."/late-marks.json",watch=false}
    book.block("+3161234",true)
    local rang,stopped=0,0
    local phone=require("models.phone_calls").new{mobile=mobile,book=book,owner=true,
      ring={trigger=function(_,_,done) rang=rang+1 if done then done(1) end end,stop=function() stopped=stopped+1 end}}
    local path
    morf.ipc.ring=function() path=standin.ring("") end
    morf.ipc.number=function(n) standin.number(path,n) end
    morf.ipc.read=function() return {rang=rang,stopped=stopped,stage=phone.stage:get()} end
  ]],size={20,20}})
  test.advance(20)
  test.ipc("ring")
  test.advance(40)
  test.eq(test.ipc("read").stage,"incoming")
  test.eq(test.ipc("read").rang,1)
  test.ipc("number","+3161234")
  test.advance(60)
  local read=test.ipc("read")
  test.eq(read.stage,"idle")
  test.eq(read.stopped,1)
end)

test.it("a phone screen is the whole screen, a desk gets a card",function()
  load(868,1932,{EVA_INPUT_DEVICES="tests/fixtures/input-devices-touch"})
  ring()
  local s=call_surface()
  test.eq(s.width,868)
  load(1920,1080)
  ring()
  s=call_surface()
  test.eq(s.width,440)
end)

test.it("something near blanks the panel in a call, and the speaker stops it",function()
  load()
  ring()
  press("call-answer")
  fake("near","on")
  test.advance(20)
  test.truthy(state().near)
  test.truthy(test.find("call-shield"))
  fake("near","off")
  press("call-speaker")
  test.eq(state().near,false)
end)

test.it("a call can be left running and gone back to",function()
  load()
  ring()
  press("call-answer")
  press("call-minimise")
  test.eq(call_surface().width,240)
  test.eq(state().stage,"talking")
  test.contains(test.get("call-chip-text").text,"Ann Veldman")
  press("call-chip")
  test.eq(call_surface().width,868)
  test.truthy(test.find("call-mute"))
end)

test.it("the chip goes with the call",function()
  load()
  ring()
  press("call-answer")
  press("call-minimise")
  fake("hangup")
  test.advance(2000)
  test.eq(call_surface(),nil)
end)

test.it("unknown callers can be kept from ringing, and still show",function()
  run=run+1
  local dir=morf.env("XDG_CACHE_HOME").."/phone-calls-"..run
  morf.fs.write(dir..".json",morf.json.encode{phone={silence_unknown=true}},{parents=true})
  test.load("../shell/init.lua",{size={868,1932},env={EVA_WALLPAPER="",EVA_DRY_RUN="1",EVA_FAKE_MODEM="1",
    EVA_CONTACTS="tests/fixtures/contacts",EVA_SETTINGS=dir..".json",XDG_STATE_HOME=dir}})
  test.advance(20)
  ring("+49123456789")
  test.eq(state().stage,"incoming")
  test.eq(state().rung,"")
  fake("hangup")
  test.advance(40)
  ring("+31612345678")
  test.eq(state().rung,"phone-incoming-call")
end)

test.it("a phone verb that does not exist says so",function()
  load()
  local ok=pcall(test.ipc,"phone","nonsense")
  test.eq(ok,false)
end)
