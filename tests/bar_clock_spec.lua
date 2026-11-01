-- How the bar writes the time: 12 or 24 hours, seconds, the date, a pattern of
-- one's own, and the clocks that read the same settings.
local test=morf.test
local AT=1790584200
local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=100,height=100}
  morf.ipc.run=function(code) return load(code)() end
]]
test.before_each(function() test.load("../shell/init.lua",{source=HOST,size={200,200}}) end)
local function stamp(options)
  return test.ipc("run","return require('clock_format').stamp("..options..","..AT..")")
end

test.it("writes 24 hours",function()
  local s=stamp("{twelve_hour=false,seconds=false,date='short'}")
  test.eq(s.time,"10:30") test.eq(s.meridiem,"") test.eq(s.date,"Mon 28 Sep")
end)
test.it("writes 12 hours when the setting says so",function()
  local s=stamp("{twelve_hour=true,seconds=false,date='short'}")
  test.eq(s.time,"10:30 AM") test.eq(s.meridiem,"AM") test.eq(s.hour,"10")
end)
test.it("adds the seconds",function()
  test.eq(stamp("{twelve_hour=false,seconds=true}").time,"10:30:00")
  test.eq(stamp("{twelve_hour=true,seconds=true}").time,"10:30:00 AM")
end)
test.it("gives every date its format, and none for none",function()
  test.eq(stamp("{date='none'}").date,"")
  test.eq(stamp("{date='day'}").date,"Mon 28")
  test.eq(stamp("{date='long'}").date,"Monday, 28 September")
  test.eq(stamp("{date='iso'}").date,"2026-09-28")
end)
test.it("lets a pattern of one's own stand for it all",function()
  local s=stamp("{format='%H.%M'}")
  test.eq(s.time,"10.30") test.eq(s.date,"")
end)
test.it("says the time as a person does",function()
  local function fuzzy(h,m) return test.ipc("run",("return require('clock_format').fuzzy(%d,%d)"):format(h,m)) end
  test.eq(fuzzy(10,0),"ten o'clock") test.eq(fuzzy(10,15),"quarter past ten") test.eq(fuzzy(22,30),"half past ten")
  test.eq(fuzzy(10,45),"quarter to eleven") test.eq(fuzzy(23,58),"twelve o'clock") test.eq(fuzzy(10,20),"20 past ten")
  test.eq(fuzzy(10,40),"20 to eleven") test.eq(fuzzy(0,0),"twelve o'clock")
end)
test.it("counts the days to a date",function()
  test.eq(test.ipc("run",("return require('clock_format').days_to('2026-10-08',%d)"):format(AT)),10)
  test.eq(test.ipc("run",("return require('clock_format').days_to('soon',%d)"):format(AT)),nil)
end)

-- The clock on the bar, with its settings.
local SHELL=[[
  local ui=require("morf.ui")
  morf.surface.height=800
  morf.time.now=function() return 1790584200 end
  local config=require("config")
  config.set("edgebar.enabled","on")
  package.loaded["lib.services.vpns"]={links=function() return {} end}
  package.loaded.apps={icon=function() return nil end}
  local function drawer(key)
    local open=morf.signal("clock.fixture."..key,false)
    return {open=open,set=function(on) open:set(on) end}
  end
  package.loaded.services={workspace={active=function() return 1 end},hyprland=nil}
  package.loaded.launcher={drawer=drawer("launcher")}
  package.loaded.dashboard={drawer=drawer("dashboard")}
  package.loaded.sidebar={drawer=drawer("sidebar"),select=function() end}
  package.loaded.utilities={detail=morf.signal("clock.fixture.detail","")}
  local bar=require("bar")
  ui.Item {width=1280,height=800,bar.build()}
  morf.ipc.set=function(key,value)
    if value=="true" then value=true elseif value=="false" then value=false end
    config.set(key,value)
  end
  morf.ipc.side=function(value) bar.set_side(value) end
]]
local serial=0
local function shell(style)
  serial=serial+1
  test.load("../shell/init.lua",{source=SHELL,size={1280,800},env={EVA_STYLE=style,EVA_DRY_RUN="1",
    EVA_SETTINGS=morf.env("XDG_CACHE_HOME").."/bar-clock-"..serial..".json"}})
  test.advance(900)
end
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." bar follows bar.clock.twelve_hour, and seconds and the date",function()
    shell(style)
    test.truthy(test.find {text="10:30 AM"}~=nil,"12 hours by the setting")
    test.ipc("set","bar.clock.twelve_hour","false") test.advance(100)
    test.truthy(test.find {text="10:30"}~=nil,"24 hours by the setting")
    test.ipc("set","bar.clock.seconds","true") test.advance(100)
    test.truthy(test.find {text="10:30:00"}~=nil)
    test.ipc("set","bar.clock.date","iso") test.advance(100)
    test.truthy(test.find {text="2026-09-28",visible=true}~=nil)
    test.ipc("set","bar.clock.date","none") test.advance(100)
    test.eq(test.find {text="2026-09-28",visible=true},nil)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." side bar stacks the hours and minutes, whichever clock",function()
    shell(style)
    test.ipc("side","left") test.advance(900)
    test.truthy(test.find {id="bar-clock-v",visible=true}~=nil)
    test.truthy(test.find {text="AM",visible=true}~=nil,"the 12-hour mark")
    test.ipc("set","bar.clock.twelve_hour","false") test.advance(100)
    test.eq(test.find {text="AM",visible=true},nil)
    test.eq(#test.logs("error"),0)
  end)
end
