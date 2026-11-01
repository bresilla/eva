-- The driver in the real shell: lines as libinput prints them go in through the
-- stand-in reader, and the keyboard, the workspaces and the panels answer. What
-- may not read stops it; one gesture has one owner; the strips stay the strips.
local test=morf.test
local SOURCE=[[
  require("windows_stand_in").install()
  local fired={}
  local switches={}
  local workspace=require("services").workspace
  local go=workspace.go
  workspace.go=function(id) switches[#switches+1]=id go(id) end
  local shown=0
  morf.screens[2]=morf.env("TEST_PANEL")~="" and {name=morf.env("TEST_PANEL"),width=1368,height=912} or nil
  require("init")
  local keyboard=require("keyboard")
  local show=keyboard.show
  keyboard.show=function(...) shown=shown+1 return show(...) end
  local actions=require("touch_actions")
  for _,key in ipairs {"show_desktop","close_window","screenshot","lock","back","launcher"} do
    local action=actions.BY_KEY[key]
    local run=action.run
    action.run=function(...) fired[#fired+1]=key if key=="launcher" then return run(...) end end
  end
  morf.ipc.spy=function()
    local launcher=require("launcher")
    local preview=require("phone_gestures").workspace_preview
    return {fired=fired,switches=switches,shown=shown,keyboard=keyboard.active(),keyboard_manual=keyboard.drawer.manual==true,
      preview=preview.active,preview_offset=preview.offset,launcher=launcher.drawer.open:get(),menu=require("menus").source:get(),
      overview=require("overview").opened:get(),pull=require("overview").pull:get(),
      dashboard=require("dashboard").drawer.open:get(),haptic=require("haptics").last:get(),haptics=require("haptics").count:get(),
      trying=require("touch_driver").trying:get()}
  end
  morf.ipc.lock_signal=function() require("models.logind").connect().fire("lock") end
  morf.ipc.lock_hint=function(on) require("models.logind").connect().set_locked(on=="on") end
  morf.ipc.on_screen=function(on) require("models.logind").connect().set_active(on=="on") end
  morf.ipc.editor=function(on) require("capture").editor.active:set(on=="on") end
  morf.ipc.handoff=function(on) require("phone_gestures").handoff(on=="on") end
  morf.ipc.setting=function(key,value) require("config").set(key,value=="true") end
  morf.ipc.bound=function(key,form) return require("touch_bindings").action(key,form) end
  morf.ipc.reset_bindings=function(form) require("touch_bindings").reset(form) end
  morf.ipc.command=function(key,words) require("touch_bindings").set_command(key,{words}) end
  morf.ipc.osd_level=function(kind) return (require("osd")[kind]()) end
  morf.ipc.dashboard_tab=function() return require("dashboard").tab:get() end
  morf.ipc.compositor=function(locked,off)
    local hyprland=require("lib.compositor.hyprland")
    hyprland.available=function() return true end
    hyprland.json=function(command,done)
      if command=="j/locked" then done({locked=locked=="locked"})
      else done({{name=morf.screens[1].name,dpmsStatus=off~="dark"}}) end
    end
  end
]]
local loads=0
local function load(extra,size)
  loads=loads+1
  test.stub_run("task",{code=0,stdout="[]"})
  local env={EVA_DRY_RUN="1",EVA_WALLPAPER="",EVA_FAKE_TOUCH="1",EVA_FAKE_LOGIND="{}",TEST_PANEL="",
    EVA_SETTINGS=morf.fs.join(morf.env("XDG_CACHE_HOME"),"touch-driver-"..loads..".json")}
  for name,value in pairs(extra or {}) do env[name]=value end
  test.load("../shell/init.lua",{source=SOURCE,size=size or {1280,800},env=env})
  test.settle(1500)
end
local function touch() return test.ipc("touch") end
local function spy() return test.ipc("spy") end

local clock=0
local function feed(text) test.ipc("touch","feed",text) end
local function lines(kind,id,x,y)
  local at=(" event99  %-23s      +%.3fs\t"):format(kind,clock/1000)
  if id==nil then return at end
  if not x then return at..("%d (%d)"):format(id,id) end
  return at..("%d (%d) %.2f/%.2f (1.00/1.00mm)"):format(id,id,x/12.8,y/8)
end
local function frame(ms)
  feed(lines("TOUCH_FRAME"))
  clock=clock+(ms or 16)
  test.advance(ms or 16)
end
-- Fingers landing at `from`, moving by dx,dy in `steps` frames.
local function land(from)
  for id,at in ipairs(from) do feed(lines("TOUCH_DOWN",id,at[1],at[2])) end
  frame()
end
local function move(from,dx,dy,steps,done)
  for n=done or 1,steps do
    for id,at in ipairs(from) do
      feed(lines("TOUCH_MOTION",id,at[1]+dx*n/steps,at[2]+dy*n/steps))
    end
    frame()
  end
end
local function lift(from)
  for id in ipairs(from) do feed(lines("TOUCH_UP",id)) end
  frame()
end
local function stroke(from,dx,dy,steps)
  land(from) move(from,dx,dy,steps or 20) lift(from) test.settle(1200)
end
local TWO={{640,770},{720,700}}
local THREE={{900,300},{980,320},{1060,300}}

test.it("reads on a desk with a keyboard attached: gestures do not ask for a tablet",function()
  load()
  local state=touch()
  test.eq(state.state,"running") test.eq(state.form,"desk") test.eq(state.reading,true)
end)

test.describe("without the driver",function()
  test.it("fingers above the strip reach no one: what this driver is for",function()
    load({EVA_FAKE_TOUCH="none"})
    test.touch("down",10,640,770) test.touch("down",11,720,690) test.advance(16)
    for i=1,16 do
      test.touch("move",10,640,770-i*16) test.touch("move",11,720,690-i*16)
      test.advance(16)
    end
    test.touch("up",10,640,514) test.touch("up",11,720,434) test.settle(800)
    test.falsy(spy().keyboard)
  end)
end)

test.describe("the defaults",function()
  test.it("bring the keyboard up two fingers from the bottom, one above the old strip",function()
    load()
    stroke(TWO,0,-300,20)
    local s=spy()
    test.truthy(s.keyboard) test.eq(s.shown,1) test.eq(s.haptic,"commit")
  end)
  test.it("leave the keyboard down when the fingers do not get far",function()
    load()
    stroke(TWO,0,-36,30)
    test.falsy(spy().keyboard)
  end)
  test.it("raise it for a slow swipe that went far enough",function()
    load()
    stroke(TWO,0,-110,60)
    test.truthy(spy().keyboard)
  end)
  test.it("hide the keyboard with two fingers down on it",function()
    load()
    test.ipc("keyboard","full") test.settle(1200)
    test.truthy(spy().keyboard)
    stroke({{500,600},{700,620}},0,160,12)
    test.falsy(spy().keyboard)
  end)
  test.it("hide it slowly too",function()
    load()
    test.ipc("keyboard","full") test.settle(1200)
    stroke({{500,600},{700,620}},0,120,60)
    test.falsy(spy().keyboard)
  end)
  test.it("do nothing for a slow scroll in an app",function()
    load()
    stroke({{600,300},{680,300}},0,300,100)
    local s=spy()
    test.falsy(s.keyboard) test.eq(#s.fired,0) test.eq(#s.switches,0) test.eq(s.haptics,0)
  end)
  test.it("go to the next workspace three fingers left, following them",function()
    load()
    land(THREE) move(THREE,-640,0,20,1)
    local mid=spy()
    test.truthy(mid.preview) test.truthy(mid.preview_offset<-200)
    lift(THREE) test.settle(1500)
    test.eq(spy().switches[1],2)
  end)
  test.it("go back a workspace three fingers right",function()
    load()
    test.ipc("workspace","3") test.advance(100)
    stroke(THREE,640,0,20)
    local s=spy()
    test.eq(s.switches[#s.switches],2)
  end)
  test.it("open the overview three fingers up, as far as they go",function()
    load()
    land(THREE) move(THREE,0,-160,20,1)
    local mid=spy()
    test.truthy(mid.overview) test.truthy(mid.pull>.3 and mid.pull<.7,"pulled "..tostring(mid.pull))
    lift(THREE) test.settle(800)
    test.eq(spy().pull,1)
  end)
  test.it("put a short overview pull back",function()
    load()
    stroke(THREE,0,-50,60)
    test.falsy(spy().overview)
  end)
  test.it("show the desktop three fingers down",function()
    load()
    stroke(THREE,0,200,20)
    test.eq(spy().fired,{"show_desktop"})
    test.eq(spy().haptic,"commit")
  end)
  test.it("open the app grid four fingers up",function()
    load()
    stroke({{500,500},{570,500},{640,500},{710,500}},0,-200,20)
    local s=spy()
    test.truthy(s.launcher) test.eq(s.menu,"apps")
  end)
  test.it("walk the apps four fingers sideways, on the workspace preview",function()
    load({EVA_FAKE_WINDOWS=morf.fs.join(morf.env("PWD"),"tests/fixtures/windows.json")})
    local four={{500,300},{570,300},{640,300},{710,300}}
    land(four) move(four,-400,0,14,1)
    test.truthy(spy().preview)
    lift(four) test.settle(800)
  end)
  test.it("with one window or none, walk nothing and raise no error",function()
    load()
    local four={{500,300},{570,300},{640,300},{710,300}}
    stroke(four,-400,0,14)
    test.falsy(spy().preview)
    test.eq(#test.logs("error"),0)
  end)
  test.it("open the launcher with a five finger pinch",function()
    load()
    local from,to={},{}
    for i=1,5 do
      local a=2*math.pi*i/5
      from[i]={640+250*math.cos(a),400+250*math.sin(a)}
      to[i]={640+60*math.cos(a),400+60*math.sin(a)}
    end
    land(from)
    for n=1,16 do
      for id=1,5 do
        feed(lines("TOUCH_MOTION",id,from[id][1]+(to[id][1]-from[id][1])*n/16,from[id][2]+(to[id][2]-from[id][2])*n/16))
      end
      frame()
    end
    lift(from) test.settle(1000)
    test.eq(spy().fired,{"launcher"})
    test.truthy(spy().launcher)
  end)
end)

test.describe("the bindings",function()
  test.it("hold for the form they were set on",function()
    load()
    test.eq(test.ipc("bound","three_up","desk"),"overview")
    test.eq(test.ipc("bound","three_up","phone"),"recents")
    test.ipc("touch","set","three_down","lock")
    test.eq(test.ipc("bound","three_down","desk"),"lock")
    test.eq(test.ipc("bound","three_down","tablet"),"show_desktop")
    stroke(THREE,0,200,20)
    test.eq(spy().fired,{"lock"})
    test.ipc("reset_bindings","desk")
    test.eq(test.ipc("bound","three_down","desk"),"show_desktop")
  end)
  test.it("can do nothing, and leave the strips alone",function()
    load()
    test.ipc("touch","set","three_down","none")
    stroke(THREE,0,200,20)
    test.eq(#spy().fired,0) test.eq(spy().haptics,0)
  end)
  test.it("can run a person's command",function()
    load()
    test.ipc("touch","set","three_down","command")
    test.ipc("command","three_down","hello")
    stroke(THREE,0,200,20)
    local said=false
    for _,line in ipairs(test.logs("info")) do
      if tostring(line.message or line[2]):find("gesture (dry run): hello",1,true) then said=true end
    end
    test.truthy(said)
  end)
  test.it("run volume by dragging, on the level",function()
    load({EVA_FAKE_OSD="1"})
    test.ipc("touch","set","three_up","volume")
    stroke(THREE,0,-160,20)
    test.near(test.ipc("osd_level","volume"),.92,.02)
  end)
end)

test.describe("every action",function()
  local ALL={"keyboard","overview","recents","launcher","app_grid","dashboard","quick_settings","notifications",
    "workspace_next","workspace_previous","switch_app","back","close_window","show_desktop","screenshot","lock",
    "volume","brightness","none","command"}
  local DEVICES=morf.env("EVA_INPUT_DEVICES")
  for _,form in ipairs {
    {"desk",{1280,800},DEVICES},{"tablet",{1280,800},DEVICES.."-touch"},{"phone",{868,1932},DEVICES.."-touch"},
  } do
    test.it("runs on a "..form[1].." with no error, each way the fingers go",function()
      load({EVA_INPUT_DEVICES=form[3]},form[2])
      test.eq(touch().form,form[1])
      for _,action in ipairs(ALL) do
        for _,key in ipairs {"three_up","three_left"} do
          test.ipc("touch","set",key,action)
          local x,y=form[2][1]/2,form[2][2]/2
          local shape={{x-80,y},{x,y+20},{x+80,y}}
          if key=="three_up" then stroke(shape,0,-200,16) else stroke(shape,-200,0,16) end
          test.ipc("close") test.settle(600)
        end
      end
      test.eq(#test.logs("error"),0)
    end)
  end
end)

test.describe("what stops the reader",function()
  test.it("a lock: the signal first, and the process is gone before the screen is",function()
    load()
    test.eq(touch().reading,true)
    test.ipc("lock_signal") test.advance(50)
    local state=touch()
    test.eq(state.reading,false) test.eq(state.state,"off") test.eq(state.locked,true)
  end)
  test.it("the lock's hint, for as long as it stands",function()
    load()
    test.ipc("lock_hint","on") test.advance(50)
    test.eq(touch().reading,false)
    test.advance(10000)
    test.eq(touch().reading,false)
    test.ipc("lock_hint","off") test.advance(50)
    test.eq(touch().reading,true)
  end)
  test.it("a lock asked for that never came does not stop it for good",function()
    load()
    test.ipc("lock_signal") test.advance(50)
    test.eq(touch().reading,false)
    test.advance(6000)
    test.eq(touch().reading,true)
  end)
  test.it("a gesture under way is cancelled by a lock",function()
    load()
    land(THREE) move(THREE,0,-160,20,1)
    test.truthy(spy().overview)
    test.ipc("lock_signal") test.advance(50)
    test.falsy(spy().overview)
  end)
  test.it("a lock logind was never told of, at the first finger, while it stands",function()
    load()
    test.ipc("compositor","locked","lit")
    land(THREE)
    test.advance(50)
    test.eq(touch().reading,false)
    test.advance(11000)
    test.eq(touch().reading,false)
    test.ipc("compositor","open","lit")
    test.advance(6000)
    test.eq(touch().reading,true)
  end)
  test.it("another session on the screen: this one reads nothing of it",function()
    load()
    test.ipc("on_screen","off") test.advance(50)
    test.eq(touch().reading,false)
    test.ipc("on_screen","on") test.advance(50)
    test.eq(touch().reading,true)
  end)
  test.it("a password prompt",function()
    load()
    test.ipc("polkit","demo") test.advance(100)
    test.eq(touch().reading,false)
    test.ipc("polkit","cancel") test.settle(800)
    test.eq(touch().reading,true)
  end)
  test.it("the capture editor",function()
    load()
    test.ipc("editor","on") test.advance(50)
    test.eq(touch().reading,false)
    test.ipc("editor","off") test.advance(50)
    test.eq(touch().reading,true)
  end)
  test.it("a handoff to the native recognisers",function()
    load()
    test.ipc("handoff","off") test.advance(50)
    test.eq(touch().reading,false)
    test.ipc("handoff","on") test.advance(50)
    test.eq(touch().reading,true)
  end)
  test.it("the switch on the Settings page",function()
    load()
    test.ipc("setting","gestures.enabled","false") test.advance(50)
    test.eq(touch().reading,false)
    test.ipc("setting","gestures.enabled","true") test.advance(50)
    test.eq(touch().reading,true)
  end)
  test.it("lisgd, which has the gestures on a phone that chose it",function()
    load({EVA_GESTURE_DRIVER="lisgd"})
    test.eq(touch().reading,false)
  end)
end)

test.describe("a dark screen",function()
  test.it("fires nothing, and the next lit sequence does",function()
    load()
    test.ipc("compositor","open","dark")
    stroke(THREE,0,200,20)
    test.eq(#spy().fired,0)
    test.ipc("compositor","open","lit")
    stroke(THREE,0,200,20)
    test.eq(spy().fired,{"show_desktop"})
  end)
end)

test.describe("a machine that cannot",function()
  test.it("with no touchscreen spawns nothing and says so",function()
    load({EVA_FAKE_TOUCH="none"})
    test.eq(touch().state,"none") test.eq(touch().reading,false)
    test.eq(#test.logs("error"),0)
  end)
  test.it("with no libinput spawns nothing and says so",function()
    load({EVA_FAKE_TOUCH="missing"})
    test.eq(touch().state,"missing") test.eq(touch().reading,false)
    test.eq(#test.logs("error"),0)
  end)
  test.it("without the right to the device says so",function()
    load({EVA_FAKE_TOUCH="denied"})
    test.advance(100)
    test.eq(touch().state,"denied")
    test.eq(#test.logs("error"),0)
  end)
  test.it("the real thing on a machine with no touchscreen: no process",function()
    load({EVA_FAKE_TOUCH=""})
    test.eq(touch().state,"none")
    for _,argv in ipairs(test.runs()) do test.truthy(argv[1]~="libinput") end
  end)
end)

test.describe("a machine with two screens",function()
  test.it("reads only on the shell of the touchscreen's own panel",function()
    load({TEST_PANEL="eDP-1"})
    local state=touch()
    test.eq(state.output,"eDP-1")
    test.eq(state.reading,false)
  end)
end)

test.describe("one owner",function()
  test.it("the strip leaves two fingers to the driver",function()
    load()
    test.touch("down",10,640,795) test.touch("down",11,720,790) test.advance(16)
    for i=1,16 do
      test.touch("move",10,640,795-i*16) test.touch("move",11,720,790-i*16)
      test.advance(16)
    end
    test.touch("up",10,640,540) test.touch("up",11,720,535) test.settle(800)
    test.eq(spy().shown,0)
    test.falsy(spy().keyboard)
  end)
  test.it("both hearing it, the keyboard comes up once",function()
    load()
    test.touch("down",10,640,795) test.touch("down",11,720,790) land({{640,795},{720,790}})
    for i=1,16 do
      test.touch("move",10,640,795-i*16) test.touch("move",11,720,790-i*16)
      move({{640,795},{720,790}},0,-320,16,i)
    end
    test.touch("up",10,640,540) test.touch("up",11,720,535)
    lift({{640,795},{720,790}}) test.settle(1000)
    test.truthy(spy().keyboard)
    test.eq(spy().shown,1)
  end)
  test.it("the keyboard's own two fingers and the driver both hiding it leave it hidden",function()
    load()
    test.ipc("keyboard","full") test.settle(1200)
    local from={{500,600},{700,620}}
    for id,at in ipairs(from) do test.touch("down",id,at[1],at[2]) end
    land(from)
    for n=1,12 do
      for id,at in ipairs(from) do test.touch("move",id,at[1],at[2]+n*14) end
      for id,at in ipairs(from) do feed(lines("TOUCH_MOTION",id,at[1],at[2]+n*14)) end
      frame()
    end
    for id,at in ipairs(from) do test.touch("up",id,at[1],at[2]+168) end
    lift(from) test.settle(1000)
    test.falsy(spy().keyboard)
  end)
  test.it("the bottom strip does not stretch while the driver reads",function()
    load()
    test.touch("down",10,640,795) test.advance(16)
    test.eq(test.get("phone-gesture-bottom").height,20)
    test.touch("up",10,640,795) test.advance(16)
  end)
  test.it("one finger stays the strip's: the driver neither takes nor cancels it",function()
    load()
    local before=spy().dashboard
    test.touch("down",0,640,795) test.advance(16)
    land({{640,795}})
    for i=1,14 do
      test.touch("move",0,640,795-i*20) test.advance(16)
      feed(lines("TOUCH_MOTION",1,640,795-i*20)) frame()
    end
    test.touch("up",0,640,515)
    lift({{640,515}}) test.settle(1000)
    test.eq(before,false)
    test.eq(#spy().fired,0)
  end)
  test.it("a gesture that begins takes over from a strip's pull",function()
    load()
    test.touch("down",0,900,795) test.advance(16)
    for i=1,6 do test.touch("move",0,900-i*30,795) test.advance(16) end
    test.truthy(spy().preview,"the strip's drag is running")
    land(THREE) move(THREE,0,200,20,1)
    lift(THREE) test.settle(1000)
    test.eq(spy().fired,{"show_desktop"})
    test.falsy(spy().preview)
    for i=7,12 do test.touch("move",0,900-i*30,795) test.advance(16) end
    test.falsy(spy().preview,"the rest of the strip's drag stays cancelled")
    test.touch("up",0,540,795) test.settle(800)
    test.eq(#spy().switches,0)
  end)
end)

test.describe("a panel under the fingers",function()
  local DEVICES=morf.env("EVA_INPUT_DEVICES")
  -- A tablet: the dashboard hangs from the bottom edge, over the edge band.
  local function on_tablet()
    load({EVA_INPUT_DEVICES=DEVICES.."-touch"},{1280,800})
    test.eq(touch().form,"tablet")
    test.ipc("dashboard","open") test.settle(1200)
    test.truthy(spy().dashboard)
  end
  local ON_PANEL={{640,770},{720,700}}
  -- Fingers on the shell as well as read: what a real touch does, both at once.
  local function both(from,dx,dy,steps)
    for id,at in ipairs(from) do test.touch("down",id,at[1],at[2]) end
    land(from)
    for n=1,steps do
      for id,at in ipairs(from) do test.touch("move",id,at[1]+dx*n/steps,at[2]+dy*n/steps) end
      for id,at in ipairs(from) do
        feed(lines("TOUCH_MOTION",id,at[1]+dx*n/steps,at[2]+dy*n/steps))
      end
      frame()
    end
    for id,at in ipairs(from) do test.touch("up",id,at[1]+dx,at[2]+dy) end
    lift(from) test.settle(1000)
  end
  test.it("two fingers from the edge band on an open panel are the panel's",function()
    on_tablet()
    both(ON_PANEL,0,-300,8)
    local s=spy()
    test.falsy(s.keyboard,"the driver left it alone")
    test.eq(s.shown,0)
    test.eq(touch().heard.key,nil)
    test.eq(#test.logs("error"),0)
  end)
  test.it("two fingers beside an open panel are the driver's as ever",function()
    load()
    test.ipc("sidebar","open","notifications") test.settle(1200)
    stroke({{300,770},{380,700}},0,-300,12)
    test.truthy(spy().keyboard)
  end)
  test.it("two fingers on the overview are the overview's",function()
    load()
    test.ipc("overview","open") test.settle(1200)
    stroke(TWO,0,-300,12)
    test.falsy(spy().keyboard)
    test.ipc("overview","close") test.settle(800)
    stroke(TWO,0,-300,12)
    test.truthy(spy().keyboard,"and the driver's again once it has gone")
  end)
  test.it("one finger on a panel never reaches the driver's bindings",function()
    on_tablet()
    both({{640,560}},0,200,14)
    test.eq(#spy().fired,0)
    test.falsy(spy().keyboard)
  end)
  test.it("three fingers are global: the panel's own pull lets go",function()
    on_tablet()
    local before=test.ipc("dashboard_tab")
    -- The first finger on the panel drags its pages; the others land on an app.
    test.touch("down",1,700,560) test.advance(16)
    for i=1,5 do test.touch("move",1,700-i*20,560) test.advance(16) end
    local three={{700,560},{780,300},{860,300}}
    land(three)
    move(three,-500,0,16,1)
    test.truthy(spy().preview,"the workspaces follow the fingers")
    for i=6,20 do test.touch("move",1,700-i*20,560) test.advance(16) end
    test.touch("up",1,300,560) lift(three) test.settle(1200)
    test.eq(test.ipc("dashboard_tab"),before,"its page did not turn as well")
    test.eq(spy().switches[1],2)
    test.eq(#test.logs("error"),0)
  end)
end)

test.describe("trying",function()
  test.it("names a gesture and runs nothing",function()
    load()
    test.ipc("touch","try","on")
    stroke(THREE,0,200,20)
    local heard=touch().heard
    test.eq(heard.key,"three_down") test.eq(heard.action,"show_desktop")
    test.eq(#spy().fired,0)
    test.ipc("touch","try","off")
    stroke(THREE,0,200,20)
    test.eq(spy().fired,{"show_desktop"})
  end)
end)
