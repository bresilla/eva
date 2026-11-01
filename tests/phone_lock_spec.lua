-- What a locked phone can do: take a call, unlock its SIM, dial for help.
local test=morf.test
local run=0
local state
local function load(modem)
  run=run+1
  state=morf.env("XDG_CACHE_HOME").."/phone-lock-"..run
  test.load("../lock/init.lua",{size={868,1932},args={"window","preview"},env={EVA_DRY_RUN="1",
    EVA_FAKE_MODEM=modem and "1" or "0",EVA_CONTACTS="tests/fixtures/contacts",XDG_STATE_HOME=state}})
  test.settle(1500)
end
local function shown(id)
  local node=test.find(id)
  return node~=nil and node.visible==true
end
local function ring() test.ipc("phone","ring","+31612345678") test.advance(60) end

test.it("a machine with no modem builds none of it",function()
  load(false)
  test.eq(test.find("call-screen"),nil)
  test.eq(test.find("sim-prompt"),nil)
  test.eq(test.find("lock-emergency"),nil)
  test.eq(test.ipc("stage"),"rest")
end)

test.it("an incoming call shows over the lock, by name",function()
  load(true)
  test.eq(shown("lock-call"),false)
  ring()
  test.truthy(shown("lock-call"))
  test.eq(test.get("call-name").text,"Ann Veldman")
  test.eq(test.ipc("phone","state").stage,"incoming")
end)

test.it("a call is answered and ended from the lock",function()
  load(true)
  ring()
  test.click("call-answer")
  test.advance(60)
  test.eq(test.ipc("phone","state").stage,"talking")
  test.click("call-end")
  test.advance(60)
  test.eq(test.ipc("phone","state").stage,"ended")
  test.advance(2000)
  test.eq(shown("lock-call"),false)
end)

test.it("the lock leaves the history and the ringing to the shell",function()
  load(true)
  ring()
  test.ipc("phone","hang_up")
  test.advance(60)
  test.eq(test.ipc("phone","state").stage,"ended")
  test.eq(morf.fs.exists(state.."/eva/phone/calls.jsonl"),false)
end)

test.it("the SIM's PIN goes in on the lock, a wrong one says so",function()
  load(true)
  test.ipc("phone","lock","sim-pin")
  test.advance(40)
  test.truthy(shown("lock-sim"))
  test.eq(test.get("sim-title").text,"Enter SIM PIN")
  test.eq(test.get("sim-tries").text,"3 tries left")
  for _,key in ipairs{"0","0","0","0"} do test.click("sim-key-"..key) end
  test.click("sim-go")
  test.advance(60)
  test.eq(test.get("sim-tries").text,"Wrong PIN")
  for _,key in ipairs{"1","2","3","4"} do test.click("sim-key-"..key) end
  test.click("sim-go")
  test.advance(60)
  test.eq(shown("lock-sim"),false)
end)

test.it("a PUK asks for a new PIN twice",function()
  load(true)
  test.ipc("phone","lock","sim-puk")
  test.advance(40)
  test.eq(test.get("sim-title").text,"Enter PUK")
  for _=1,8 do test.click("sim-key-1") end
  test.click("sim-go")
  test.advance(20)
  test.eq(test.get("sim-title").text,"Choose a new PIN")
  for _,key in ipairs{"1","2","3","4"} do test.click("sim-key-"..key) end
  test.click("sim-go")
  test.advance(20)
  test.eq(test.get("sim-title").text,"Confirm the new PIN")
  for _,key in ipairs{"9","9","9","9"} do test.click("sim-key-"..key) end
  test.click("sim-go")
  test.advance(20)
  test.eq(test.get("sim-title").text,"Choose a new PIN")
  test.eq(test.get("sim-tries").text,"The PINs did not match")
  for _,key in ipairs{"1","2","3","4"} do test.click("sim-key-"..key) end
  test.click("sim-go")
  test.advance(20)
  for _,key in ipairs{"1","2","3","4"} do test.click("sim-key-"..key) end
  test.click("sim-go")
  test.advance(60)
  test.eq(shown("lock-sim"),false)
end)

test.it("the PIN is never in a signal or on the screen as digits",function()
  load(true)
  test.ipc("phone","lock","sim-pin")
  test.advance(40)
  for _,key in ipairs{"1","2","3","4"} do test.click("sim-key-"..key) end
  test.eq(test.find{text="1234"},nil)
end)

test.it("Later leaves the SIM locked and the lock usable",function()
  load(true)
  test.ipc("phone","lock","sim-pin")
  test.advance(40)
  test.click("sim-later")
  test.advance(40)
  test.eq(shown("lock-sim"),false)
  test.truthy(shown("lock-emergency-button"))
end)

test.it("an emergency number dials from the lock, any other is refused",function()
  load(true)
  test.click("lock-emergency")
  test.advance(40)
  test.truthy(shown("lock-emergency-pad"))
  for _,key in ipairs{"5","5","5"} do test.click("emergency-key-"..key) end
  test.click("emergency-call")
  test.advance(40)
  test.eq(test.ipc("phone","state").stage,"idle")
  test.contains(test.get("emergency-note").text,"Only emergency")
  test.click("emergency-back") test.click("emergency-back") test.click("emergency-back")
  for _,key in ipairs{"1","1","2"} do test.click("emergency-key-"..key) end
  test.click("emergency-call")
  test.advance(200)
  test.eq(test.ipc("phone","state").stage,"talking")
  test.truthy(shown("lock-call"))
end)
