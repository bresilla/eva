-- The ScreenSaver name, against a stand-in bus: who asked, for how long, and what
-- happens when an app leaves without saying so.
local test=morf.test
local function rig()
  test.load("../lock/init.lua",{size={40,40},env={EVA_DRY_RUN="1"},source=[[
    local handler,replies,changes={}, {}, 0
    local owners
    local bus={
      serve=function(kind,name) return {
        on_call=function(_,fn) handler=fn end,
        reply=function(_,id,value) replies[id]=value==nil and "empty" or value end,
      },morf.env("TEST_OUTCOME") or "owned" end,
      proxy=function()
        return setmetatable({},{__index=function() return function() end end})
      end,
    }
    local saver,why=require("lib.services.screensaver").serve {dbus=bus,
      on_change=function() changes=changes+1 end}
    local serial=0
    morf.ipc.call=function(raw)
      local v=morf.json.decode(raw)
      serial=serial+1
      handler{id=serial,member=v.member,arguments=v.arguments,sender=v.sender}
      return replies[serial]
    end
    morf.ipc.holders=function()
      if not saver then return {why=why} end
      local out={}
      for i,row in ipairs(saver.holders()) do out[i]=row.app..":"..row.reason end
      return out
    end
    morf.ipc.changes=function() return changes end
  ]]})
end
local function call(member,arguments,sender)
  return test.ipc("call",morf.json.encode{member=member,arguments=arguments or {},sender=sender or ":1.1"})
end
test.it("Inhibit answers a cookie and lists the app; UnInhibit takes it off",function()
  rig()
  local first=call("Inhibit",{"firefox","Playing video"})
  test.eq(first.value,1)
  local second=call("Inhibit",{"mpv","Fullscreen"},":1.2")
  test.eq(second.value,2)
  test.eq(test.ipc("holders"),{"firefox:Playing video","mpv:Fullscreen"})
  test.eq(call("UnInhibit",{1}),"empty")
  test.eq(test.ipc("holders"),{"mpv:Fullscreen"})
  test.eq(test.ipc("changes"),3)
end)
test.it("an unknown cookie moves nothing",function()
  rig()
  call("Inhibit",{"firefox","x"})
  call("UnInhibit",{99})
  test.eq(test.ipc("holders"),{"firefox:x"})
  test.eq(test.ipc("changes"),1)
end)
test.it("another method answers and holds nothing",function()
  rig()
  test.eq(call("GetActive"),false)
  test.eq(call("Lock"),"empty")
  test.eq(test.ipc("holders"),{})
end)
