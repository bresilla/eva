-- The live pill: one surface for what is going on, morphing into its panel on a
-- press, a second activity budding off it, and wrapping a cutout on a phone.
--
--     morf test --no-dbus tests/bar_live_spec.lua
local test=morf.test
local SOURCE=[[
  local ui=require("morf.ui")
  local shape,shapes=ui.SdfShape,{}
  ui.SdfShape=function(props)
    local node=shape(props)
    if props.id then shapes[props.id]={props=props,node=node} end
    return node
  end
  morf.ipc.q_shape=function(id)
    local s=shapes[id]
    return {operation=s.props.operation,radius=s.node.radius,opacity=s.node.opacity,tracks=s.props.track~=nil}
  end
  require("init")
  morf.ipc.q_run=function(code) return load(code)() end
  morf.ipc.q_list=function()
    local out={}
    for i,item in ipairs(require("bar").model.live.list()) do out[i]=item.key end
    return out
  end
  morf.ipc.q_expanded=function() return require("bar").model.live.expanded:get() end
]]
local serial=0
local function load_shell(options)
  options=options or {}
  serial=serial+1
  local settings=morf.env("XDG_CACHE_HOME").."/bar-live-"..serial..".json"
  morf.fs.remove(settings)
  test.stub_run("task",{code=0,stdout="[]"})
  local env={EVA_DRY_RUN="1",EVA_SETTINGS=settings,EVA_STYLE=options.style or "material",EVA_WALLPAPER="",
    EVA_FONT_FILE="",LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME")}
  for k,v in pairs(options.env or {}) do env[k]=v end
  test.load("../shell/init.lua",{source=SOURCE,size=options.size or {1600,1000},env=env})
  test.settle(1500)
  test.ipc("bar","show","on") test.settle(1200)
end
local function up(id)
  local node=test.find {id=id,visible=true}
  return node~=nil and node.width>0.5 and node.height>0.5
end
local TOUCH={EVA_INPUT_DEVICES=morf.env("EVA_INPUT_DEVICES").."-touch"}
local function with(extra)
  local out={}
  for k,v in pairs(TOUCH) do out[k]=v end
  for k,v in pairs(extra) do out[k]=v end
  return out
end

test.it("a timer from the launcher is the pill and the indicator, and the pill stops it",function()
  load_shell {}
  test.ipc("q_run",[[require('timers_model').timer(600,'pasta') return true]]) test.settle(300)
  test.eq(test.ipc("q_list"),{"timer"})
  test.eq(test.ipc("q_run",[[return require('services').alarm.timer().label]]),"pasta")
  test.truthy(test.ipc("q_run",[[return require('services').alarm.armed()]]),"the bar's indicator stays dark")
  test.eq(test.ipc("q_run",[[return #require('timers_model').list()]]),1)
  test.ipc("q_run",[[require('services').alarm.cancel_timer() return true]]) test.settle(300)
  test.eq(test.ipc("q_list"),{})
  test.eq(test.ipc("q_run",[[return #require('timers_model').list()]]),0)
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." takes no room while nothing is going on",function()
    load_shell {style=style}
    test.eq(test.ipc("q_list"),{})
    test.falsy(up("bar-live"))
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." morphs the pill into its panel on a press, and back",function()
    load_shell {style=style,env={EVA_FAKE_MEDIA="So What|Miles Davis"}}
    test.eq(test.ipc("q_list"),{"media"})
    local rest=test.get("bar-live")
    test.truthy(rest.width>40) test.truthy(rest.height<=40)
    local width,height=rest.width,rest.height
    test.click("bar-live-press") test.settle(1500)
    test.truthy(test.ipc("q_expanded"))
    local open=test.get("bar-live")
    test.eq(open.width,420) test.truthy(open.height>height+24)
    test.truthy(test.find {id="bar-live-title",text="So What",visible=true}~=nil)
    test.truthy(test.find {id="bar-live-subtitle",text="Miles Davis",visible=true}~=nil)
    test.truthy(up("bar-live-control-2"))
    test.key("Escape") test.settle(1500)
    test.falsy(test.ipc("q_expanded"))
    test.near(test.get("bar-live").width,width,1) test.near(test.get("bar-live").height,height,1)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." shuts on a press outside",function()
    load_shell {style=style,env={EVA_FAKE_MEDIA="So What|Miles Davis"}}
    test.click("bar-live-press") test.settle(1200)
    test.click(800,700) test.settle(1200)
    test.falsy(test.ipc("q_expanded"))
  end)
end

test.it("is a distance field: one shape tracking the pill, and the bubble joined by a smooth seam",function()
  load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis",EVA_FAKE_TIMER="Tea:300"}}
  test.truthy(test.find {id="bar-live-ground"}~=nil)
  test.truthy(test.ipc("q_shape","bar-live-shape").tracks)
  local bubble=test.ipc("q_shape","bar-live-bubble-shape")
  test.eq(bubble.operation,"smooth_union") test.truthy(bubble.tracks)
  test.near(bubble.opacity,1,.01)
  test.truthy(up("bar-live-bubble"))
  test.ipc("bar","live","toggle") test.settle(1200)
  test.near(test.ipc("q_shape","bar-live-bubble-shape").opacity,0,.01)
end)

test.it("rounds off less as it opens: a capsule morphing into a panel",function()
  load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis"}}
  local function roundness() return test.ipc("q_shape","bar-live-shape").radius/test.get("bar-live").height end
  test.near(roundness(),.5,.01)
  test.ipc("bar","live","toggle") test.settle(1200)
  test.truthy(roundness()<.3)
end)

test.it("shows no tooltip over its open panel",function()
  load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis"}}
  test.click("bar-live-press") test.settle(1500)
  test.falsy(test.find {text="So What",visible=true,id=""}~=nil)
  local node=test.get("bar-live")
  test.move(node.x+10,node.y+node.height-8) test.advance(900)
  test.key("Escape") test.settle(1200)
  test.falsy(test.ipc("q_expanded"),"a tooltip in the way would take the Escape")
end)

test.it("fills with the progress, cut from the pill's outline",function()
  load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis"}}
  test.settle(600)
  local fill,pill=test.get("bar-live-fill"),test.get("bar-live")
  test.truthy(fill.width>0 and fill.width<pill.width)
end)

test.describe("what it follows",function()
  test.it("puts the most pressing first, and the next in the bubble",function()
    load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis",EVA_FAKE_TIMER="Tea:300",EVA_FAKE_CALL="Ada"}}
    test.eq(test.ipc("q_list"),{"call","timer","media"})
    test.truthy(test.find {text="0:00",visible=true}~=nil or test.find {id="bar-live-rest",visible=true}~=nil)
  end)
  test.it("swaps on a press of the bubble, and on a right press",function()
    load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis",EVA_FAKE_TIMER="Tea:300"}}
    test.eq(test.ipc("q_list"),{"timer","media"})
    test.click("bar-live-bubble-press") test.settle(600)
    test.eq(test.ipc("q_list"),{"media","timer"})
    test.click("bar-live-press",{button="right"}) test.settle(600)
    test.eq(test.ipc("q_list"),{"timer","media"})
  end)
  test.it("shows a recording's time, and its control stops it",function()
    load_shell {}
    test.ipc("q_run",[[local c=require('capture') c.recording:set(true) c.phase:set('recording') c.elapsed:set(5) return true]])
    test.settle(900)
    test.eq(test.ipc("q_list"),{"recording"})
    test.ipc("bar","live","toggle") test.settle(1200)
    test.click("bar-live-control-1") test.settle(1200)
    test.falsy(test.ipc("q_run",[[return require('capture').recording:get()]]))
    test.falsy(up("bar-live"))
    test.falsy(test.ipc("q_expanded"),"it shuts when nothing is left")
  end)
  test.it("hangs up a call from its panel",function()
    load_shell {env={EVA_FAKE_CALL="Ada Lovelace"}}
    test.ipc("bar","live","toggle") test.settle(1200)
    test.truthy(test.find {text="Ada Lovelace",visible=true}~=nil)
    test.click("bar-live-control-2") test.settle(1200)
    test.eq(test.ipc("q_list"),{})
  end)
  test.it("counts a timer down, and cancels it",function()
    load_shell {env={EVA_FAKE_TIMER="Tea:300"}}
    test.eq(test.ipc("q_list"),{"timer"})
    test.ipc("bar","live","toggle") test.settle(1200)
    test.truthy(test.find {text="Tea",visible=true}~=nil)
    test.click("bar-live-control-1") test.settle(1200)
    test.eq(test.ipc("q_list"),{})
  end)
  test.it("follows screen sharing, and names the app",function()
    load_shell {env={EVA_FAKE_PRIVACY="screen:OBS"}}
    test.eq(test.ipc("q_list"),{"share"})
    test.ipc("bar","live","toggle") test.settle(1200)
    test.truthy(test.find {text="OBS",visible=true}~=nil)
  end)
  test.it("runs media's transport from the panel",function()
    load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis"}}
    test.ipc("bar","live","toggle") test.settle(1200)
    test.click("bar-live-control-2") test.settle(600)
    test.falsy(test.ipc("q_run",[[return require('media_state').playing()]]))
  end)
end)

test.describe("on a phone",function()
  test.it("sits in the middle of the bar, between the clock and the status",function()
    load_shell {size={868,1932},env=with {EVA_FAKE_MEDIA="So What|Miles Davis"}}
    local pill,clock,status=test.get("bar-live"),test.get("bar-clock"),test.get("bar-status")
    test.truthy(clock.x+clock.width<=pill.x) test.truthy(pill.x+pill.width<=status.x)
  end)
  test.it("wraps a cutout, the camera in its middle, the bubble past it",function()
    load_shell {size={868,1932},env=with {EVA_FAKE_CUTOUT="400,68,34",EVA_FAKE_MEDIA="So What|Miles Davis",EVA_FAKE_TIMER="Tea:300"}}
    local pill=test.get("bar-live")
    test.near(pill.x+pill.width/2,434,1)
    test.truthy(pill.x<400 and pill.x+pill.width>468,"it reaches round the camera")
    test.truthy(up("bar-live-split"))
    test.falsy(up("bar-live-rest"))
    test.truthy(test.get("bar-live-bubble").x>468)
    local status=test.get("bar-status")
    test.truthy(test.get("bar-live-bubble").x+test.get("bar-live-bubble").width<=status.x+1)
  end)
  test.it("keeps its status clear of a cutout with nothing going on",function()
    load_shell {size={868,1932},env=with {EVA_FAKE_CUTOUT="400,68,34"}}
    test.truthy(test.get("bar-status").x>=476)
  end)
  test.it("opens inside a small screen",function()
    load_shell {size={412,915},env=with {EVA_FAKE_MEDIA="So What|Miles Davis"}}
    test.ipc("bar","live","toggle") test.settle(1200)
    local open=test.get("bar-live")
    test.truthy(open.x>=0) test.truthy(open.x+open.width<=412)
    test.eq(open.width,412-32)
  end)
end)

test.describe("on any edge",function()
  test.it("grows up from a bar at the bottom",function()
    load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis"}}
    test.ipc("bar","side","bottom") test.settle(1200)
    local rest=test.get("bar-live")
    test.ipc("bar","live","toggle") test.settle(1200)
    local open=test.get("bar-live")
    test.truthy(open.y<rest.y) test.near(open.y+open.height,rest.y+rest.height,2)
  end)
  test.it("stands upright on a side bar, and opens across",function()
    load_shell {env={EVA_FAKE_MEDIA="So What|Miles Davis"}}
    test.ipc("bar","side","left") test.settle(1200)
    local rest=test.get("bar-live")
    test.eq(rest.width,rest.height)
    test.truthy(up("bar-live-upright"))
    test.ipc("bar","live","toggle") test.settle(1200)
    test.eq(test.get("bar-live").width,420)
    test.ipc("bar","live","toggle") test.settle(1200)
    test.ipc("bar","side","right") test.settle(1200)
    test.ipc("bar","live","toggle") test.settle(1200)
    local open=test.get("bar-live")
    test.truthy(open.x+open.width<=1600) test.truthy(open.x<1200)
  end)
end)
