-- The way from a login screen to the desktop. Nothing here reaches greetd or
-- PAM: the doors are fixtures.
local test=morf.test

local function shell(style,env)
  env=env or {}
  env.EVA_STYLE=style
  env.HYPRLAND_INSTANCE_SIGNATURE=env.HYPRLAND_INSTANCE_SIGNATURE or false
  if env.EVA_DRY_RUN==nil then env.EVA_DRY_RUN="1" end
  test.load("../shell/init.lua",{size={1920,1080},env=env})
end

for _,style in ipairs {"material","tsugumori"} do
  test.describe(style.." session arrival",function()
    test.it("the wallpaper stands alone first, then the frame comes in before the rail",function()
      shell(style)
      test.advance(16)
      local opening=test.get("frame-opening")
      test.truthy(opening.x<0 and opening.y<0,"the opening's corners are past the screen")
      test.truthy(opening.x+opening.width>1920 and opening.y+opening.height>1080)
      test.eq(test.get("arrival-rail").opacity,0)
      test.eq(test.get("arrival-levels").opacity,0)
      test.advance(180)
      test.truthy(test.get("frame-opening").x>opening.x,"the frame is moving")
      test.eq(test.get("arrival-rail").opacity,0)
      test.settle(1500)
      opening=test.get("frame-opening")
      test.truthy(opening.x>0)
      test.eq(opening.width,1920-opening.x-10)
      test.eq(test.get("arrival-rail").opacity,1)
      test.eq(#test.logs("error"),0)
    end)

    test.it("a reload keeps the frame where it is",function()
      shell(style)
      test.settle(1500)
      local before=test.get("frame-opening").x
      test.truthy(test.reload())
      test.advance(16)
      test.eq(test.get("frame-opening").x,before)
      test.eq(test.get("arrival-rail").opacity,1)
    end)

    test.it("a lock lifting brings the same parts in again",function()
      shell(style)
      test.settle(1500)
      local rest=test.get("frame-opening").x
      test.truthy(test.ipc("reveal"))
      test.advance(16)
      test.truthy(test.get("frame-opening").x<0)
      test.eq(test.get("arrival-rail").opacity,0)
      test.settle(1500)
      test.eq(test.get("frame-opening").x,rest)
      test.eq(test.get("arrival-rail").opacity,1)
    end)
  end)
end

test.it("only the first shell of a session arrives, across restarts of its process",function()
  local env=function() return {EVA_DRY_RUN=false,HYPRLAND_INSTANCE_SIGNATURE="reveal-spec-"..morf.time.now_ms()} end
  local once=env()
  local again={EVA_DRY_RUN=false,HYPRLAND_INSTANCE_SIGNATURE=once.HYPRLAND_INSTANCE_SIGNATURE}
  shell("material",once)
  test.advance(16)
  test.truthy(test.get("frame-opening").x<0)
  test.settle(1500)
  shell("material",again)
  test.advance(16)
  test.truthy(test.get("frame-opening").x>0,"a restarted shell does not arrive")
  test.eq(test.get("arrival-rail").opacity,1)
end)

test.it("a dry run leaves no mark behind",function()
  local signature="reveal-spec-dry-"..morf.time.now_ms()
  shell("material",{HYPRLAND_INSTANCE_SIGNATURE=signature})
  test.advance(16)
  test.truthy(test.get("frame-opening").x<0)
  local run=morf.env("XDG_RUNTIME_DIR")
  test.falsy(morf.fs.exists(run.."/eva/arrived-"..signature.."-HEADLESS-1"))
end)

test.it("the wallpaper bridge's wrapper goes in front of every session",function()
  local source=[[
    morf.apps.entries=function()
      return {applications=function()
        return {{id="hyprland",name="Hyprland",source="/share/wayland-sessions",command={"uwsm","start"},desktop_names={"Hyprland"}}}
      end}
    end
    require("morf.ui").Item {width=10,height=10}
    morf.ipc.sessions=function() return require("lib.services.sessions").list()[1].command end
  ]]
  test.load("../greet/init.lua",{source=source,args={"preview"},env={EVA_SESSION_WRAPPER="/run/eva-session"}})
  test.eq(test.ipc("sessions"),{"/run/eva-session","uwsm","start"})
  test.load("../greet/init.lua",{source=source,args={"preview"},env={EVA_SESSION_WRAPPER=false}})
  test.eq(test.ipc("sessions"),{"uwsm","start"})
end)

local GREETER=[[
  local quits,runs=0,{}
  morf.quit=function() quits=quits+1 end
  local process=morf.process.run
  morf.process.run=function(command,options,done)
    if command[1]=="/run/eva-greeter-exit" then runs[#runs+1]=quits done({ok=true}) return end
    return process(command,options,done)
  end
  package.loaded["lib.services.accounts"]={list=function() return {{name="fixture",label="Fixture",initial="F"}} end}
  package.loaded["lib.services.sessions"]={list=function() return {{name="Desktop",command={"false"}}} end,default_index=function() return 1 end}
  local handlers,started
  package.loaded["lib.shell.auth"]={greeter=function(on)
    handlers=on
    return {available=true,submit=function() on.on_busy(true) end,switch=function() end,stop=function() end}
  end}
  require("init")
  morf.ipc.door=function(what,why)
    if what=="verified" then handlers.on_verified(function() started=morf.time.now_ms() end)
    elseif what=="open" then handlers.on_open()
    elseif what=="failed" then handlers.on_failed(why or "")
    end
    return {started=started~=nil,quits=quits,runs=#runs}
  end
]]
local function greeter(style,exit)
  test.load("../greet/init.lua",{source=GREETER,size={1920,1080},
    env={EVA_STYLE=style,EVA_DRY_RUN="1",GREETD_SOCK=false,EVA_GREETER_EXIT=exit or false}})
  test.settle(1200)
  test.key("Return")
  test.settle(800)
  test.type("hunter2")
  test.settle(200)
end

for _,style in ipairs {"material","tsugumori"} do
  test.describe(style.." greeter exit",function()
    test.it("the session is asked for after the form has left the bare wallpaper",function()
      greeter(style,"/run/eva-greeter-exit")
      test.eq(test.get("greet-veil").opacity,1)
      test.falsy(test.ipc("door","verified").started)
      test.eq(test.ipc("stage"),"leaving")
      test.advance(16)
      test.falsy(test.get("greet-glance").visible,"the clock must not come back over the fade")
      test.advance(104)
      test.falsy(test.ipc("door").started,"started before the fade had ended")
      test.advance(80)
      test.truthy(test.ipc("door").started)
      test.settle(200)
      test.eq(test.get("greet-veil").opacity,0)
      test.eq(test.get("greet-scene").opacity,0)
      test.truthy(test.get("greet-wallpaper"))
    end)

    test.it("the compositor is told to end before the greeter quits",function()
      greeter(style,"/run/eva-greeter-exit")
      test.ipc("door","verified")
      test.advance(200)
      local state=test.ipc("door","open")
      test.eq(state.runs,1)
      test.eq(state.quits,1)
    end)

    test.it("a session that will not start brings the form back",function()
      greeter(style)
      test.ipc("door","verified")
      test.advance(200)
      test.ipc("door","failed","No session to start")
      test.eq(test.ipc("stage"),"sheet")
      test.settle(400)
      test.eq(test.get("greet-scene").opacity,1)
      test.eq(test.get("greet-veil").opacity,1)
    end)
  end)
end

test.it("without a compositor to end the greeter simply quits",function()
  greeter("material")
  test.ipc("door","verified")
  test.advance(200)
  local state=test.ipc("door","open")
  test.eq(state.runs,0)
  test.eq(state.quits,1)
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." lock leaves the same bare wallpaper when it lifts",function()
    test.load("../lock/init.lua",{size={1920,1080},args={"window","preview"},
      env={EVA_STYLE=style,EVA_DRY_RUN="1"}})
    test.settle(1200)
    test.eq(test.get("lock-veil").opacity,1)
    test.ipc("stage","sheet")
    test.settle(600)
    test.ipc("stage","opening")
    test.advance(16)
    test.falsy(test.get("lock-glance").visible,"the clock must not come back over the fade")
    test.settle(300)
    test.eq(test.get("lock-veil").opacity,0)
    test.eq(test.get("lock-scene").opacity,0)
    test.truthy(test.get("lock-wallpaper"))
  end)

  test.it(style.." lock lifting from rest fades the clock with everything else",function()
    test.load("../lock/init.lua",{size={1920,1080},args={"window","preview"},
      env={EVA_STYLE=style,EVA_DRY_RUN="1"}})
    test.settle(1200)
    test.ipc("stage","opening")
    test.advance(16)
    test.truthy(test.get("lock-glance").visible)
  end)
end
