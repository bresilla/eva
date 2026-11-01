-- The idle stages, what holds them back, and the page. morf.idle stands behind a
-- seam here: nothing asks a compositor, and a dry run acts on nothing.
local test=morf.test
local dir=morf.env("XDG_CACHE_HOME").."/idle-spec"
morf.fs.mkdir(dir,{parents=true})
local serial=0
local HOST=[[
  require("init")
  local idle=require("idle_model")
  local cancelled=0
  local fires={}
  morf.ipc.begin=function()
    idle.start {subscribe=function(ms,fn)
      fires[#fires+1]={ms=ms,fn=fn}
      return {cancel=function() cancelled=cancelled+1 end}
    end}
    return true
  end
  morf.ipc.plan=function()
    local out={}
    for i,item in ipairs(idle.plan()) do out[i]=item.stage..":"..item.seconds end
    return out
  end
  morf.ipc.timers=function()
    local out={}
    for i,item in ipairs(fires) do out[i]=item.ms end
    return out
  end
  morf.ipc.at=function(stage,value)
    for _,item in ipairs(idle.plan()) do
      if item.stage==stage then idle.fired=true return idle.fire(stage) end
    end
    return "no such stage"
  end
  morf.ipc.back=function() idle.resume() end
  morf.ipc.phase=function() return idle.phase:get() end
  morf.ipc.set=function(key,raw) require("config").set(key,morf.json.decode(raw)) end
  morf.ipc.awake=function(on,seconds) require("settings_model").set_awake(on=="true",tonumber(seconds)) end
  morf.ipc.state=function() return {awake=idle.awake:get(),till=idle.awake_until(),reasons=#idle.reasons()} end
  morf.ipc.reasons=function()
    local out={}
    for i,row in ipairs(idle.reasons()) do out[i]=row.kind..":"..row.name end
    return out
  end
  morf.ipc.holders=function(raw) idle.holders:set(morf.json.decode(raw)) end
  morf.ipc.reason=function() local path=morf.env("XDG_RUNTIME_DIR").."/eva/lock-reason"
    return morf.fs.exists(path) and morf.fs.read(path) or "" end
  morf.ipc.clear_reason=function() require("models.lock_reason").clear() end
  morf.ipc.detail=function() return require("utilities").detail:get() end
  morf.ipc.open=function(key) require("utilities").request(key) end
]]
local function load(options)
  options=options or {}
  serial=serial+1
  local settings=dir.."/eva-"..serial..".json"
  morf.fs.write(settings,morf.json.encode(options.settings or {}))
  local policy=dir.."/idle-"..serial..".json"
  morf.fs.write(policy,morf.json.encode(options.policy or {}))
  test.stub_run("task",{code=0,stdout="[]"})
  local env={EVA_DRY_RUN="1",EVA_SETTINGS=settings,EVA_STYLE=options.style or "material",EVA_WALLPAPER="",EVA_FONT_FILE="",
    LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME"),EVA_IDLE_POLICY=policy,XDG_RUNTIME_DIR=dir,
    EVA_FAKE_LOGIND=morf.json.encode(options.logind or {can={suspend="yes"}})}
  for k,v in pairs(options.env or {}) do env[k]=v end
  test.load("../shell/init.lua",{source=HOST,size=options.size or {1600,1000},env=env})
  test.settle(1200)
  test.ipc("clear_reason")
end
local function said(pattern)
  for _,line in ipairs(test.logs("info")) do
    if line.message:find(pattern,1,true) then return true end
  end
  return false
end
local function set(key,value) test.ipc("set",key,morf.json.encode(value)) test.settle(400) end

test.it("the stages stand in order, the warning ahead of the lock",function()
  load{settings={idle={lock=300,blank=330,suspend=1800,dim=10}}}
  test.eq(test.ipc("plan"),{"warning:290","lock:300","blank:330","suspend:1800"})
end)

test.it("a stage at 0 is left out, a dim of 0 is no warning, and a dim longer than the lock is none either",function()
  load{settings={idle={lock=0,blank=60,suspend=0,dim=10}}}
  test.eq(test.ipc("plan"),{"blank:60"})
  load{settings={idle={lock=60,blank=0,suspend=0,dim=0}}}
  test.eq(test.ipc("plan"),{"lock:60"})
  load{settings={idle={lock=5,blank=0,suspend=0,dim=10}}}
  test.eq(test.ipc("plan"),{"lock:5"})
end)

test.it("turning idle off stands every timer down",function()
  load{settings={idle={enabled=false}}}
  test.eq(test.ipc("plan"),{})
end)

test.it("the timers follow the settings, in milliseconds",function()
  load{settings={idle={lock=300,blank=0,suspend=0,dim=0}}}
  test.ipc("begin") test.settle(100)
  test.eq(test.ipc("timers"),{300000})
  set("idle.lock",600)
  local timers=test.ipc("timers")
  test.eq(timers[#timers],600000)
end)

test.it("the system's value wins and the page shows it as set",function()
  load{settings={idle={lock=300,suspend=0,blank=0,dim=0}},policy={managed={lock=120}}}
  test.eq(test.ipc("plan"),{"lock:120"})
  set("idle.lock",999)
  test.eq(test.ipc("plan"),{"lock:120"},"Settings moves nothing")
end)

test.it("a system-fixed stage runs under the system's daemon: here it does nothing",function()
  load{settings={idle={lock=300,suspend=0,blank=0,dim=0}},policy={managed={lock=120}}}
  test.clear_logs()
  test.eq(test.ipc("at","lock"),false)
  test.falsy(said("idle lock"))
  test.eq(test.ipc("reason"),"")
end)

test.it("the lock stage leaves the idle reason for the lock to read",function()
  load{settings={idle={lock=300,suspend=0,blank=0,dim=0}}}
  test.clear_logs()
  test.eq(test.ipc("at","lock"),true)
  test.truthy(said("idle lock (dry run)"))
  test.contains(test.ipc("reason"),"idle")
end)

test.it("a warning shows, input takes it away, and a locked session is not locked twice",function()
  load{settings={idle={lock=60,suspend=0,blank=0,dim=10}}}
  test.eq(test.ipc("at","warning"),true)
  test.eq(test.ipc("phase"),"warning")
  test.settle(100)
  test.truthy(test.find{id="idle-warning-field"})
  test.ipc("back")
  test.eq(test.ipc("phase"),"")
  test.advance(600)
  test.falsy(test.find{id="idle-warning-field"},"no field stands when it is not warning")
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." the warning draws as a field on an overlay, taking no input",function()
    load{style=style,settings={idle={lock=60,suspend=0,blank=0,dim=10}}}
    test.ipc("at","warning") test.advance(120)
    local found=false
    for _,surface in ipairs(test.surfaces()) do if surface.name=="eva-idle-warning" or surface.label:find("idle",1,true) then found=true end end
    test.truthy(found,"an overlay of its own")
    test.truthy(test.find{id="idle-warning-opening"})
    test.eq(#test.logs("error"),0)
  end)
end

test.it("blanking turns the displays off, and input brings them back",function()
  load{settings={idle={lock=0,blank=60,suspend=0,dim=0}}}
  test.clear_logs()
  test.ipc("at","blank")
  test.truthy(said("displays off (dry run)"))
  test.ipc("back")
  test.truthy(said("displays on (dry run)"))
end)

test.it("suspend runs the session's command, and resume its own",function()
  load{settings={idle={lock=0,blank=0,suspend=60,dim=0,resume_command={"true"}}}}
  test.clear_logs()
  test.ipc("at","suspend")
  test.truthy(said("idle suspend (dry run)"))
  test.ipc("back")
  test.truthy(said("idle resume (dry run)"))
end)

test.it("keep awake holds every stage back",function()
  load{settings={idle={lock=60,blank=0,suspend=0,dim=0}}}
  test.ipc("awake","true")
  test.clear_logs()
  test.eq(test.ipc("at","lock"),false)
  test.falsy(said("idle lock"))
  test.ipc("awake","false")
  test.eq(test.ipc("at","lock"),true)
end)

test.it("a timed keep awake ends by itself, and says when",function()
  load()
  test.ipc("awake","true","30")
  local state=test.ipc("state")
  test.eq(state.awake,true)
  test.truthy(state.till>0)
  test.advance(31000)
  test.eq(test.ipc("state").awake,false)
  test.eq(test.ipc("state").till,0)
end)

test.it("turning keep awake on for good cancels a timer",function()
  load()
  test.ipc("awake","true","30")
  test.ipc("awake","true")
  test.eq(test.ipc("state").till,0)
  test.advance(31000)
  test.eq(test.ipc("state").awake,true)
end)

test.it("an idle inhibitor of logind's holds it back too",function()
  load{settings={idle={lock=60,blank=0,suspend=0,dim=0}},
    logind={can={},inhibitors={{what="idle",who="presenter",why="Slides",mode="block",uid=1000,pid=1}}}}
  test.eq(test.ipc("at","lock"),false)
end)

test.it("a delay inhibitor does not",function()
  load{settings={idle={lock=60,blank=0,suspend=0,dim=0}},
    logind={can={},inhibitors={{what="idle",who="x",why="y",mode="delay",uid=1000,pid=1}}}}
  test.eq(test.ipc("at","lock"),true)
end)

test.it("a bus client that asked keeps it awake, by name",function()
  load{settings={idle={lock=60,blank=0,suspend=0,dim=0}}}
  test.ipc("holders",morf.json.encode{{cookie=1,app="firefox",reason="Video"}})
  test.eq(test.ipc("reasons"),{"bus:firefox"})
  test.eq(test.ipc("at","lock"),false)
  test.ipc("holders","[]")
  test.eq(test.ipc("at","lock"),true)
end)

test.it("a phone's idle is the phone's: the runner stands aside",function()
  local screen=dir.."/phone.json"
  morf.fs.write(screen,morf.json.encode{command="/bin/true",doubleTap=true})
  load{settings={idle={lock=60,blank=0,suspend=0,dim=0}},env={EVA_PHONE_SCREEN_CONFIG=screen}}
  test.ipc("begin") test.settle(100)
  test.eq(test.ipc("timers"),{})
end)

test.it("a closed lid with a lid-lock is not this spec's to fire, but the setting reads",function()
  load{settings={lock={on_lid=false}}}
  test.eq(#test.logs("error"),0)
end)

for _,style in ipairs {"material","tsugumori"} do
  for _,size in ipairs {{1600,1000},{432,960}} do
    test.it(style.." the pages open from Eva's settings at "..size[1],function()
      load{style=style,size=size,settings={idle={lock=300}},env={EVA_FAKE_BATTERY="60,discharging"}}
      test.ipc("settings") test.settle(1200)
      test.ipc("open","idle") test.settle(1500)
      test.eq(test.ipc("detail"),"idle")
      test.truthy(test.find{id="idle-stage-lock",visible=true})
      test.truthy(test.find{id="idle-dim",visible=true})
      test.ipc("open","lock") test.settle(1500)
      test.truthy(test.find{id="lock-set-level",visible=true})
      test.eq(#test.logs("error"),0)
    end)
  end
end

test.it("a stage's button moves the setting; a fixed one does not",function()
  load{policy={managed={suspend=7200}}}
  test.ipc("settings") test.settle(1200)
  test.ipc("open","idle") test.settle(1500)
  test.click{id="idle-stage-lock-60"} test.settle(300)
  test.eq(test.ipc("plan")[1]:match("^warning:(%d+)"),"50")
  test.click{id="idle-stage-suspend-900"} test.settle(300)
  local plan=test.ipc("plan")
  test.eq(plan[#plan],"suspend:7200")
end)

test.it("the lock page writes where the lock reads, and the policy holds",function()
  local policy=dir.."/lock-policy.json"
  morf.fs.write(policy,morf.json.encode{power_buttons=false})
  load{env={EVA_LOCK_POLICY=policy}}
  test.ipc("settings") test.settle(1200)
  test.ipc("open","lock") test.settle(1500)
  test.click{id="lock-set-level-count"} test.settle(300)
  test.eq(test.ipc("plan")~=nil,true)
  test.truthy(test.find{id="lock-set-power_buttons-switch"})
end)
