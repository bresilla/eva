-- The ringer against the real feedbackd: started by the bus, answering for its
-- events. tools/phone-daemons.sh runs it on a private session bus.
local test=morf.test
local HOST=[[
  local ring=require("lib.shell.audio.ringer").connect{mode="sound"}
  local got,ended=nil,false
  morf.ipc.state=function()
    return {up=ring.state.feedbackd,mode=ring.state.mode,id=got or -1}
  end
  morf.ipc.activate=function() return ring.activate()==true end
  morf.ipc.trigger=function(event,seconds)
    return ring.trigger(event,{timeout=tonumber(seconds)},function(id) got=id end)
  end
  morf.ipc.stop=function() return ring.stop(got) end
  morf.ipc.set=function(mode) return ring.set(mode)==true end
]]
local function wait_up()
  test.wait(function() return test.ipc("state").up==true end,8000,"feedbackd came up")
end

test.it("the bus starts feedbackd when asked, and not before",function()
  test.load("../shell/init.lua",{source=HOST,size={20,20},env={EVA_DRY_RUN="0"}})
  test.eq(test.ipc("state").up,false)
  test.eq(test.ipc("trigger","button-pressed",-1),false)
  test.truthy(test.ipc("activate"))
  wait_up()
end)

test.it("an event gets an id back, and an endless one can be ended",function()
  test.load("../shell/init.lua",{source=HOST,size={20,20},env={EVA_DRY_RUN="0"}})
  test.ipc("activate")
  wait_up()
  test.truthy(test.ipc("trigger","phone-incoming-call",0))
  test.wait(function() return test.ipc("state").id>=0 end,4000,"an event id came back")
  test.truthy(test.ipc("stop"))
end)

test.it("the ring modes are feedbackd's profiles",function()
  test.load("../shell/init.lua",{source=HOST,size={20,20},env={EVA_DRY_RUN="0"}})
  test.ipc("activate")
  wait_up()
  test.truthy(test.ipc("set","vibrate"))
  test.wait(function() return test.ipc("state").mode=="vibrate" end,4000,"the profile reads back")
  test.truthy(test.ipc("set","sound"))
end)
