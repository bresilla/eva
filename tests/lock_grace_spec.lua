-- The moment after an idle lock in which any key opens it: every way it must
-- stay shut, on the model with its clock and sleep witnesses in hand.
local test=morf.test
local function rig(values)
  test.load("../lock/init.lua",{size={40,40},env={EVA_DRY_RUN="1",EVA_STYLE="material"},source=[[
    local grace=require("models.lock_grace")
    local now,total=100,0
    local sleep_fns,lock_fns={},{}
    local preparing,lid,reachable=false,false,true
    local clock_ok,count_ok=true,true
    local g
    morf.ipc.make=function(raw)
      local v=morf.json.decode(raw)
      g=grace.new {seconds=v.seconds or 15,reason=v.reason or "idle",phone=v.phone==true,
        guard=v.no_guard~=true and {
          available=function() return reachable end,
          preparing=function() return preparing end,
          lid_closed=function() return lid end,
          on_sleep=function(fn) sleep_fns[#sleep_fns+1]=fn end,
          on_lock=function(fn) lock_fns[#lock_fns+1]=fn end,
        } or nil,
        clock=function() return clock_ok and now or nil end,
        suspends=function() return count_ok and total or nil end,
        timer=function() return {cancel=function() end} end}
      return true
    end
    morf.ipc.arm=function() return g.arm() end
    morf.ipc.take=function() return g.take() end
    morf.ipc.why=function() return g.why end
    morf.ipc.at=function(t) now=now+t return now end
    morf.ipc.set=function(name,value)
      value=value=="true"
      if name=="preparing" then preparing=value elseif name=="lid" then lid=value
      elseif name=="reachable" then reachable=value elseif name=="clock" then clock_ok=value
      elseif name=="count" then count_ok=value end
    end
    morf.ipc.slept=function() total=total+1 end
    morf.ipc.fire=function(kind)
      for _,fn in ipairs(kind=="sleep" and sleep_fns or lock_fns) do fn() end
    end
    morf.ipc.revoke=function(why) g.revoke(why) end
  ]]})
  test.ipc("make",morf.json.encode(values or {}))
end
local function step(seconds) test.ipc("at",seconds) end

test.it("an idle lock opens on a key inside the window, once",function()
  rig() test.truthy(test.ipc("arm"))
  step(1) test.eq(test.ipc("take"),true)
  test.eq(test.ipc("take"),false,"it opens once")
end)

test.it("off unless a number of seconds is set",function()
  rig{seconds=0} test.falsy(test.ipc("arm")) test.eq(test.ipc("take"),false)
end)

for _,reason in ipairs {"manual","lockdown","","suspend"} do
  test.it("never for a lock of reason '"..reason.."'",function()
    rig{reason=reason} test.falsy(test.ipc("arm")) test.eq(test.ipc("take"),false)
  end)
end

test.it("never on a phone",function()
  rig{phone=true} test.falsy(test.ipc("arm")) test.eq(test.ipc("take"),false)
end)

test.it("never where sleep cannot be heard or counted",function()
  rig{no_guard=true} test.falsy(test.ipc("arm"))
  rig() test.ipc("set","reachable","false") test.falsy(test.ipc("arm"))
  rig() test.ipc("set","count","false") test.falsy(test.ipc("arm"))
  rig() test.ipc("set","clock","false") test.falsy(test.ipc("arm"))
end)

test.it("not while the machine goes to sleep or the lid is shut",function()
  rig() test.ipc("set","preparing","true") test.falsy(test.ipc("arm"))
  rig() test.ipc("set","lid","true") test.falsy(test.ipc("arm"))
end)

test.it("ends when the time runs out",function()
  rig{seconds=2} test.truthy(test.ipc("arm"))
  step(1) step(1)
  test.eq(test.ipc("take"),false)
  test.eq(test.ipc("why"),"expired")
end)

test.it("logind saying sleep ends it for good, awake or not",function()
  rig() test.truthy(test.ipc("arm"))
  test.ipc("fire","sleep")
  test.eq(test.ipc("take"),false)
  test.eq(test.ipc("arm"),false,"a later arm finds nothing to open")
end)

test.it("another lock request ends it",function()
  rig() test.truthy(test.ipc("arm"))
  test.ipc("fire","lock")
  test.eq(test.ipc("take"),false)
end)

test.it("a gap in the clock is a sleep nobody announced",function()
  rig{seconds=60} test.truthy(test.ipc("arm"))
  step(3)
  test.eq(test.ipc("take"),false)
  test.eq(test.ipc("why"),"slept")
end)

test.it("the kernel's count of suspends moving ends it",function()
  rig{seconds=60} test.truthy(test.ipc("arm"))
  step(1) test.ipc("slept")
  test.eq(test.ipc("take"),false)
  test.eq(test.ipc("why"),"slept")
end)

test.it("the sensors going away ends it",function()
  rig() test.truthy(test.ipc("arm")) test.ipc("set","count","false")
  test.eq(test.ipc("take"),false)
  rig() test.truthy(test.ipc("arm")) test.ipc("set","clock","false")
  test.eq(test.ipc("take"),false)
end)

test.it("the lid shutting or sleep starting after it armed ends it",function()
  rig() test.truthy(test.ipc("arm")) test.ipc("set","lid","true")
  test.eq(test.ipc("take"),false) test.eq(test.ipc("why"),"lid")
  rig() test.truthy(test.ipc("arm")) test.ipc("set","preparing","true")
  test.eq(test.ipc("take"),false) test.eq(test.ipc("why"),"sleeping")
end)

test.it("a wrong password ends it",function()
  rig() test.truthy(test.ipc("arm"))
  test.ipc("revoke","wrong password")
  test.eq(test.ipc("take"),false)
end)
