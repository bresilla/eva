-- One seam for touch feedback: kit presses reach it by themselves, moments
-- reach feedbackd by their event names, and the one setting stops it all.
local test=morf.test
local FEEDBACK=[[
  local fake=require("lib.testing.dbus")
  fake.object("session","org.sigxcpu.Feedback","/org/sigxcpu/Feedback","org.sigxcpu.Feedback",{Profile="full"},{
    TriggerFeedback=function(args) return {7} end,
    EndFeedback=function() end,
  })
  local ring=require("lib.shell.audio.ringer").connect{dbus=fake.dbus}
  local got
  morf.ipc.ring=function(event,timeout)
    ring.trigger(event,{timeout=tonumber(timeout),important=true},function(id) got=id end)
    return true
  end
  morf.ipc.stop=function() return ring.stop(got) end
  morf.ipc.state=function()
    local out={}
    for _,call in ipairs(fake.calls) do
      if call.method=="TriggerFeedback" then
        out[#out+1]={method=call.method,app=call.args[1],event=call.args[2],
          hints=call.args[3].signature,important=call.args[3].value.important==true,
          timeout=call.args[4].signature,seconds=call.args[4].value}
      elseif call.method=="EndFeedback" then
        out[#out+1]={method=call.method,id=call.args[1].value,signature=call.args[1].signature}
      end
    end
    return {calls=out,got=got or 0}
  end
]]
test.it("feedback events go out typed as feedbackd declares them",function()
  test.load("feedback-fixture.lua",{source=FEEDBACK,size={20,20}})
  test.truthy(test.ipc("ring","phone-incoming-call",0))
  test.advance(20)
  local state=test.ipc("state")
  test.eq(state.got,7)
  test.eq(state.calls[1].event,"phone-incoming-call")
  test.eq(state.calls[1].hints,"a{sv}")
  test.truthy(state.calls[1].important)
  test.eq(state.calls[1].timeout,"i")
  test.eq(state.calls[1].seconds,0)
  test.truthy(test.ipc("stop"))
  test.advance(20)
  state=test.ipc("state")
  test.eq(state.calls[2].method,"EndFeedback")
  test.eq(state.calls[2].signature,"u")
  test.eq(state.calls[2].id,7)
end)

local KIT=[[
  local ui=require("morf.ui")
  local kit=require("kit")
  local haptics=require("haptics")
  local on=morf.signal("fixture.on",false)
  ui.Item {width=400,height=400,
    kit.action {id="fixture-press",x=0,y=0,width=100,height=100,on_clicked=function() end},
    kit.switch {id="fixture-switch",x=0,y=120,width=80,height=40,on=function() return on:get() end,
      on_toggled=function(v) on:set(v) end},
  }
  morf.ipc.read=function() return {last=haptics.last:get(),count=haptics.count:get()} end
  morf.ipc.fire=function(kind) return haptics.fire(kind) end
  morf.ipc.set=function(v) haptics.set(v) end
  morf.ipc.present=function() return haptics.present() end
]]
local function kit_host(env)
  env=env or {}
  env.EVA_DRY_RUN="1"
  test.load("../shell/init.lua",{source=KIT,size={400,400},env=env})
end

test.it("a press of any kit control buzzes without the view asking",function()
  kit_host()
  test.click("fixture-press")
  test.advance(20)
  test.eq(test.ipc("read").last,"tap")
  test.eq(test.ipc("read").count,1)
  test.advance(60)
  test.click("fixture-switch")
  test.advance(60)
  test.eq(test.ipc("read").last,"toggle")
end)

test.it("the one setting stops every moment",function()
  kit_host()
  test.ipc("set",false)
  test.click("fixture-press")
  test.advance(60)
  test.eq(test.ipc("fire","commit"),false)
  test.eq(test.ipc("read").count,0)
  test.ipc("set",true)
  test.truthy(test.ipc("fire","commit"))
  test.eq(test.ipc("read").last,"commit")
end)

test.it("a moment it does not know is refused, a burst of one kind is one",function()
  kit_host()
  test.eq(test.ipc("fire","nonsense"),false)
  test.truthy(test.ipc("fire","key"))
  test.eq(test.ipc("fire","key"),false)
  test.advance(60)
  test.truthy(test.ipc("fire","key"))
  test.eq(test.ipc("read").count,2)
end)

test.it("EVA_FAKE_HAPTICS stands in where there is no feedbackd",function()
  kit_host()
  test.eq(test.ipc("present"),false)
  kit_host{EVA_FAKE_HAPTICS="1"}
  test.truthy(test.ipc("present"))
end)

test.it("a tile toggles with a buzz",function()
  test.load("../shell/init.lua",{size={868,1932},env={EVA_WALLPAPER="",EVA_DRY_RUN="1",EVA_FAKE_HARDWARE="1",
    EVA_SETTINGS=morf.env("XDG_CACHE_HOME").."/haptics-tile.json"},source=[[
    require("config")
    local model=require("settings_model")
    local haptics=require("haptics")
    morf.ipc.toggle=function(id)
      for _,t in ipairs(model.TOGGLES) do if t.id==id then t.set(true) end end
      return {last=haptics.last:get(),count=haptics.count:get()}
    end
  ]]})
  local read=test.ipc("toggle","flashlight")
  test.eq(read.last,"toggle")
  test.eq(read.count,1)
end)

test.it("a panel pulled past halfway buzzes as it commits, a pull let go does not",function()
  test.load("../shell/init.lua",{size={400,800},env={EVA_DRY_RUN="1"},source=[[
    local ui=require("morf.ui")
    local haptics=require("haptics")
    local d=require("drawer").new {name="fixture",edge="top",width=300,height=200,content=ui.Item {}}
    ui.Item {width=400,height=800,d.panel}
    morf.ipc.pull=function(distance,canceled)
      d.begin_drag()
      d.drag_by(tonumber(distance))
      d.end_drag(0,canceled==true)
      return {open=d.open:get(),count=haptics.count:get(),last=haptics.last:get()}
    end
  ]]})
  test.advance(20)
  local short=test.ipc("pull",40)
  test.eq(short.open,false)
  test.eq(short.count,0)
  test.settle()
  local canceled=test.ipc("pull",190,true)
  test.eq(canceled.open,false)
  test.eq(canceled.count,0)
  test.settle()
  local far=test.ipc("pull",190)
  test.truthy(far.open)
  test.eq(far.count,1)
  test.eq(far.last,"commit")
end)
