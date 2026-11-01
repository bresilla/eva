-- What stands on the lock, on a held lock over the headless backend. The door
-- is a fixture: nothing here reaches PAM. Each test states what must not happen
-- as well as what must.
local test=morf.test
local dir=morf.env("XDG_CACHE_HOME").."/lock-features"
morf.fs.mkdir(dir,{parents=true})
local SETTINGS=dir.."/eva.json"
local POLICY=dir.."/policy.json"
local RUN=dir.."/run"
morf.fs.mkdir(RUN,{parents=true})
local VIEW=RUN.."/eva/lock-view.json"
local REASON=RUN.."/eva/lock-reason"
local SOURCE=[[
  local submits,finished=0,0
  pcall(function()
    morf.pam=setmetatable({},{__index=function(_,name) error("the spec reached PAM: "..name) end})
  end)
  package.loaded["lib.services.accounts"]={me=function() return {name="fixture",label="Fixture Name",initial="F"} end}
  package.loaded["lib.services.keyboards"]={attached=function() return true end}
  package.loaded["lib.services.mpris"]={connect=function() return {state={active={}}} end}
  local verdict="wrong"
  local auth=require("lib.shell.auth")
  local readers=0
  local handlers
  package.loaded["lib.shell.auth"]=setmetatable({lock=function(on)
    local door={done=false}
    handlers=on
    readers=on.reader==false and 0 or 1
    function door.submit(self,password)
      submits=submits+1
      on.on_busy(true)
      morf.time.timer(50,function()
        on.on_busy(false)
        if verdict=="right" and password=="right" then self:finish() else on.on_failed("Wrong password") end
      end,false)
    end
    function door.finish(self)
      if self.done then return end
      self.done=true finished=finished+1 on.on_open()
    end
    function door.listen() end
    function door.stop() end
    return door
  end},{__index=auth})
  local ctx
  local theme=require("themes").current.lock local build=require(theme)
  package.loaded[theme]=function(context) ctx=ctx or context return build(context) end
  require("init")
  morf.ipc.audit=function(answer)
    if answer then verdict=answer end
    return {state=morf.lock.state:get(),stage=ctx.stage:get(),submits=submits,finished=finished,readers=readers}
  end
  morf.ipc.prefs=function() local p=ctx.parts.prefs return {level=p.notifications.level,lockdown=p.lockdown==true} end
  morf.ipc.fire=function(kind,...) require("models.logind").connect().fire(kind,...) end
  morf.ipc.say=function() return ctx.message:get() end
  morf.ipc.failed=function() handlers.on_failed("Wrong password") end
]]

local function write(file,value) morf.fs.write(file,morf.json.encode(value),{parents=true}) end
local function clean()
  morf.fs.remove(SETTINGS) morf.fs.remove(POLICY) morf.fs.remove(VIEW) morf.fs.remove(REASON)
end
local function uptime() return tonumber(tostring(morf.fs.read("/proc/uptime")):match("^[%d.]+")) end
local function mark(reason) write(REASON,{reason=reason,at=uptime()}) end

local function load(options)
  options=options or {}
  local env={EVA_STYLE=options.style or "material",EVA_SCALE_MODE="compositor",EVA_DRY_RUN="1",XDG_RUNTIME_DIR=RUN,
    EVA_SETTINGS=SETTINGS,EVA_LOCK_POLICY=POLICY,
    EVA_FAKE_LOGIND=morf.json.encode(options.logind or {can={suspend="yes",reboot="yes",power_off="yes"}})}
  for k,v in pairs(options.env or {}) do env[k]=v end
  test.load("../lock/init.lua",{source=SOURCE,size=options.size or {1920,1080},
    screens=options.screens,env=env})
  test.settle(1500)
end
local function shown(id) local n=test.find {id=id,visible=true} return n end
local function centre(id)
  local n=test.get(id)
  return n.x+n.width/2,n.y+n.height/2
end
local function press(id)
  local x,y=centre(id)
  test.click(x,y)
  test.settle(400)
end
local function text_of(id) return tostring(test.get(id).text) end

test.before_each(clean)

for _,style in ipairs {"material","tsugumori"} do
  test.describe(style,function()
    test.it("the lock opens by a key inside the window after an idle lock, and asks nothing",function()
      write(SETTINGS,{lock={grace_seconds=30}}) mark("idle")
      load{style=style}
      test.key("space")
      test.advance(1000) test.settle(500)
      local audit=test.ipc("audit")
      test.eq(audit.submits,0)
      test.eq(audit.state,"unlocked")
    end)

    test.it("a manual lock with the window set still wants the password",function()
      write(SETTINGS,{lock={grace_seconds=30}})
      load{style=style}
      test.key("space") test.key("a")
      test.advance(600) test.settle(300)
      test.eq(test.ipc("audit").state,"locked")
      test.eq(test.ipc("audit").stage,"sheet")
    end)
  end)
end

test.it("a sleep ends the window, and the key after it only opens the sheet",function()
  write(SETTINGS,{lock={grace_seconds=30}}) mark("idle")
  load()
  test.ipc("fire","sleep",true)
  test.key("a")
  test.advance(800) test.settle(300)
  local audit=test.ipc("audit")
  test.eq(audit.state,"locked")
  test.eq(audit.stage,"sheet")
end)

test.it("a wrong password ends the window",function()
  write(SETTINGS,{lock={grace_seconds=30}}) mark("idle")
  load()
  test.ipc("failed")
  test.key("a") test.advance(800) test.settle(300)
  test.eq(test.ipc("audit").state,"locked")
  test.eq(test.ipc("audit").stage,"sheet")
end)

test.it("a press in the window opens it too, and the hint says so while it lasts",function()
  write(SETTINGS,{lock={grace_seconds=30}}) mark("idle")
  load()
  test.matches(text_of("lock-hint"),"^Any key opens it for %d+ s$")
  test.click(960,700)
  test.advance(1000) test.settle(500)
  test.eq(test.ipc("audit").state,"unlocked")
  test.eq(test.ipc("audit").submits,0)
end)

test.it("the system's policy can shut the window whatever the person set",function()
  write(SETTINGS,{lock={grace_seconds=30}}) write(POLICY,{grace_seconds=0}) mark("idle")
  load()
  test.key("a") test.advance(800) test.settle(300)
  test.eq(test.ipc("audit").state,"locked")
end)

test.it("the lock is given up in one place, reached only through the door or the window",function()
  local source=morf.fs.read("lock/init.lua")
  local _,gives=source:gsub("session_lock%s*=%s*false","")
  test.eq(gives,1,"one place sets the session free")
  -- Everything that calls lift: the door's answer, the preview's fake door,
  -- and the window, which goes through the door when it can.
  local names={}
  for line in source:gmatch("[^\n]+") do
    if line:find("%f[%w_]lift%f[^%w_]") and not line:find("^%s*%-%-") then names[#names+1]=line:match("^%s*(.-)%s*$") end
  end
  test.eq(names,{"local function lift()","on_open = lift,",
    'if pw == "wrong" then handlers.on_failed("Wrong password") else lift() end',
    "if door.finish then door:finish() else lift() end"})
end)

test.it("nothing that takes the window but a key or a press",function()
  local source=morf.fs.read("lock/init.lua")
  local _,uses=source:gsub("take_grace%(%)","")
  test.eq(uses,2,"its definition and the key handler")
  local layout=morf.fs.read("themes/layouts/lock.lua")
  local _,presses=layout:gsub("parts%.take_grace%(%)","")
  test.eq(presses,1,"the press on the lock's own surface")
end)

test.it("a held lock has no verb that moves it",function()
  load()
  local verbs=test.ipc_verbs()
  local have={}
  for _,verb in ipairs(verbs) do have[verb]=true end
  test.falsy(have.stage,"stage")
  test.falsy(have.card,"card")
end)

test.it("a lock in a window leaves the reason for the held one",function()
  mark("idle")
  test.load("../lock/init.lua",{size={800,600},args={"window","preview"},env={EVA_STYLE="material",
    EVA_SCALE_MODE="compositor",EVA_DRY_RUN="1",XDG_RUNTIME_DIR=RUN,EVA_SETTINGS=SETTINGS,EVA_LOCK_POLICY=POLICY}})
  test.settle(500)
  test.truthy(morf.fs.exists(REASON),"the check before a lock must not use it up")
end)

test.it("a stale, unknown or missing reason leaves a plain lock",function()
  write(SETTINGS,{lock={grace_seconds=30}})
  write(REASON,{reason="idle",at=uptime()-600})
  load()
  test.key("a") test.advance(800) test.settle(300)
  test.eq(test.ipc("audit").state,"locked")
  test.falsy(morf.fs.exists(REASON),"a reason is used once")
end)

test.it("a lockdown hides everything and turns the readers off",function()
  write(SETTINGS,{lock={notifications={level="all"},grace_seconds=30,power_buttons=true,widgets={"calendar"},
    readers=true}})
  write(VIEW,{notifications={level="all",count=1,items={{app="Signal",summary="Mira",body="x",time=1}}}})
  mark("lockdown")
  load()
  test.eq(test.ipc("prefs").lockdown,true)
  test.eq(test.ipc("audit").readers,0)
  test.falsy(shown("lock-notifications"))
  test.falsy(shown("lock-power"))
  test.falsy(shown("lock-widget-calendar"))
  test.key("a") test.advance(800) test.settle(300)
  test.eq(test.ipc("audit").state,"locked")
end)

test.it("each level shows what it says and no more",function()
  local rich={level="all",count=2,items={{app="Signal",summary="Mira",body="the code",time=1},
    {app="Mail",summary="Invoice",body="ready",time=1}}}
  write(SETTINGS,{lock={notifications={level="all"}}})
  write(VIEW,{notifications=rich})
  load()
  test.eq(text_of("lock-notification-summary-1"),"Mira")
  test.eq(text_of("lock-notification-body-1"),"the code")

  write(SETTINGS,{lock={notifications={level="senders"}}})
  write(VIEW,{notifications={level="senders",count=3,items={{app="Signal",count=2,time=1},{app="Mail",count=1,time=1}}}})
  load()
  test.eq(text_of("lock-notification-app-1"),"Signal · 2")
  test.falsy(shown("lock-notification-summary-1"))

  write(SETTINGS,{lock={notifications={level="count"}}})
  write(VIEW,{notifications={level="count",count=3,items={}}})
  load()
  test.eq(text_of("lock-notification-count"),"3 notifications")
  test.falsy(shown("lock-notification-1"))

  write(SETTINGS,{lock={notifications={level="none"}}})
  write(VIEW,{notifications=rich})
  load()
  test.falsy(shown("lock-notifications"))
end)

test.it("a looser file does not raise what the lock shows",function()
  write(SETTINGS,{lock={notifications={level="count"}}})
  write(VIEW,{notifications={level="all",count=1,items={{app="Signal",summary="Mira",body="the code",time=1}}}})
  load()
  test.falsy(shown("lock-notifications"))
end)

test.it("only the screen in use shows what is private",function()
  write(SETTINGS,{lock={notifications={level="all"}}})
  write(VIEW,{notifications={level="all",count=1,items={{app="Signal",summary="Mira",body="the code",time=1}}}})
  load{screens=2}
  local cards=test.find_all {id="lock-notification-1"}
  test.eq(#cards,2)
  local visible=0
  for _,card in ipairs(cards) do if card.visible then visible=visible+1 end end
  test.eq(visible,1)
end)

test.it("Caps Lock is said on the sheet",function()
  local leds=dir.."/leds"
  morf.fs.mkdir(leds.."/input3::capslock",{parents=true})
  morf.fs.write(leds.."/input3::capslock/brightness","1\n")
  load{env={EVA_LEDS=leds}}
  test.key("Return") test.settle(400)
  test.eq(text_of("lock-message"),"Caps Lock is on")
  morf.fs.write(leds.."/input3::capslock/brightness","0\n")
  test.key("Shift_L") test.advance(200) test.settle(200)
  test.eq(text_of("lock-message"),"")
end)

test.it("the layout chip moves through the layouts, by press and by F3",function()
  load{env={EVA_FAKE_LAYOUTS="us,de,fr"}}
  test.key("Return") test.settle(400)
  test.eq(text_of("lock-layout-label"),"US")
  press("lock-layout")
  test.eq(text_of("lock-layout-label"),"DE")
  test.key("F3") test.settle(200)
  test.eq(text_of("lock-layout-label"),"FR")
  test.key("F3") test.settle(200)
  test.eq(text_of("lock-layout-label"),"US")
end)

test.it("one layout shows no chip",function()
  load{env={EVA_FAKE_LAYOUTS="us"}}
  test.key("Return") test.settle(400)
  test.falsy(shown("lock-layout"))
end)

test.it("after too many wrong passwords the field waits and asks nothing",function()
  write(SETTINGS,{lock={attempts={limit=2,wait=30}}})
  load()
  for _=1,2 do
    test.type("wrong") test.key("Return")
    test.advance(200) test.settle(200)
  end
  test.eq(test.ipc("audit").submits,2)
  test.type("again") test.key("Return")
  test.advance(200) test.settle(200)
  test.eq(test.ipc("audit").submits,2,"the third is held back")
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." power buttons are off until chosen, need a yes from logind and a hold",function()
    load{style=style}
    test.falsy(shown("lock-power"))
    write(SETTINGS,{lock={power_buttons=true}})
    load{style=style,logind={can={suspend="yes",reboot="challenge",power_off="na"}}}
    test.truthy(shown("lock-power-suspend"))
    test.falsy(shown("lock-power-reboot"),"a challenge has nobody to answer it")
    test.falsy(shown("lock-power-poweroff"))
    local function asked()
      for _,line in ipairs(test.logs("info")) do if line.message:find("Suspend",1,true) then return true end end
      return false
    end
    local x,y=centre("lock-power-suspend")
    test.click(x,y) test.settle(300)
    test.falsy(asked(),"a click is not a hold")
    test.press(x,y) test.advance(900) test.release(x,y) test.settle(200)
    test.truthy(asked(),"a hold is")
  end)
end

test.it("the policy keeps power buttons off",function()
  write(SETTINGS,{lock={power_buttons=true}}) write(POLICY,{power_buttons=false})
  load()
  test.falsy(shown("lock-power"))
end)

test.it("a safe shortcut acts; one that opens something waits for the door",function()
  write(SETTINGS,{lock={shortcuts={"flashlight","camera","command"},
    command={name="Notes",icon="edit_note",argv={"notes"},safe=false}}})
  load{env={EVA_FAKE_HARDWARE="1"}}
  test.truthy(shown("lock-shortcut-flashlight"))
  press("lock-shortcut-flashlight")
  test.eq(test.ipc("audit").stage,"rest","the flashlight needs no way in")
  press("lock-shortcut-camera")
  test.eq(test.ipc("audit").stage,"sheet")
  test.eq(test.ipc("say"),"Unlock to open Camera")
  test.eq(test.ipc("audit").state,"locked")
  test.key("Escape") test.settle(300)
  press("lock-shortcut-command")
  test.eq(test.ipc("say"),"Unlock to open Notes")
  test.eq(#test.runs(),0,"nothing has started")
end)

test.it("a command marked safe runs where it stands, dry here",function()
  write(SETTINGS,{lock={shortcuts={"command"},command={name="Mute",argv={"wpctl"},safe=true}}})
  load()
  press("lock-shortcut-command")
  test.eq(test.ipc("audit").stage,"rest")
  local said=false
  for _,line in ipairs(test.logs("info")) do if line.message:find("lock command",1,true) then said=true end end
  test.truthy(said)
end)

test.it("the emergency card shows what was set, dials only what is listed, opens nothing",function()
  write(SETTINGS,{lock={emergency={text="If found call Sam",name="Alex",blood="O+",numbers={"112"}}}})
  load{env={EVA_FAKE_DIAL="1"}}
  test.eq(text_of("lock-line"),"If found call Sam")
  press("lock-emergency")
  test.truthy(shown("lock-emergency-card"))
  test.eq(text_of("lock-emergency-value-1"),"Alex")
  local x,y=centre("lock-emergency-call-112")
  test.press(x,y) test.advance(900) test.release(x,y) test.settle(200)
  test.eq(text_of("lock-emergency-said"),"Calling 112")
  test.eq(test.ipc("audit").state,"locked")
  test.falsy(test.find{id="lock-emergency-call-5551234"})
  test.key("Escape") test.settle(300)
  test.falsy(shown("lock-emergency-card"))
  test.eq(test.ipc("audit").stage,"rest","Escape shut the card, nothing else")
end)

test.it("with nothing set and no dialler there is no emergency chip",function()
  load()
  test.falsy(shown("lock-emergency"))
end)

test.it("a widget not marked safe is not drawn, and a failing one leaves the lock standing",function()
  write(SETTINGS,{lock={widgets={"open-door","broken","calendar"}}})
  morf.fs.write(dir.."/catalogue.lua","")
  test.load("../lock/init.lua",{size={1920,1080},env={EVA_DRY_RUN="1",EVA_SCALE_MODE="compositor",EVA_STYLE="material",
    EVA_SETTINGS=SETTINGS,EVA_LOCK_POLICY=POLICY},args={"window","preview"},source=[[
    package.loaded["themes.widgets_catalogue"]={list=function() return {
      {id="open-door",name="Door",lock_safe=false,build=function(v) return require("morf.ui").Item{id="door-widget"} end},
      {id="broken",name="Broken",lock_safe=true,build=function() error("no") end},
    } end}
    require("init")
  ]]})
  test.settle(1500)
  test.falsy(test.find{id="door-widget"})
  test.truthy(shown("lock-widget-calendar"))
  test.eq(#test.logs("error"),0)
end)

test.it("the desktop's date and clock stand on the lock, what reads the shell does not",function()
  write(SETTINGS,{lock={widgets={"date","clock","weather","note"}}})
  load{}
  test.truthy(shown("lock-widget-date"))
  test.truthy(shown("lock-widget-clock"))
  test.falsy(shown("lock-widget-weather"))
  test.falsy(shown("lock-widget-note"))
  test.eq(#test.logs("error"),0)
end)

test.it("a person can hide the name, the face and the readings",function()
  write(SETTINGS,{lock={name=false,avatar=false,media=false,weather=false,status={battery=false,network=false,
    bluetooth=false,mode=false}}})
  load{env={EVA_FAKE_BATTERY="64,charging",EVA_FAKE_STATUS="wifi,bluetooth"}}
  test.falsy(shown("lock-status-charge"))
  test.falsy(shown("lock-status-network"))
  test.falsy(shown("lock-weather"))
  test.key("Return") test.settle(400)
  test.eq(test.find{id="lock-name",visible=true}.text,"Locked")
end)

test.it("two taps on the empty lock put a phone's panel to sleep, and one does not",function()
  local screen=dir.."/phone.json"
  morf.fs.write(screen,morf.json.encode{command="/bin/true",doubleTap=true})
  local function slept()
    for _,line in ipairs(test.logs("info")) do
      if line.message:find("phone screen: off",1,true) then return true end
    end
    return false
  end
  test.load("../lock/init.lua",{size={406,903},args={"window","preview"},env={EVA_STYLE="material",
    EVA_SCALE_MODE="compositor",EVA_DRY_RUN="1",EVA_PHONE_SCREEN_CONFIG=screen,EVA_SETTINGS=SETTINGS,
    EVA_LOCK_POLICY=POLICY,EVA_INPUT_DEVICES=morf.fs.home().."/none"}})
  test.advance(900)
  test.touch("down",1,200,500) test.touch("up",1,200,500) test.advance(60)
  test.falsy(slept())
  test.touch("down",1,200,500) test.touch("up",1,200,500) test.advance(60)
  test.truthy(slept())
  test.eq(test.ipc("stage"),"rest")
end)

test.it("the ambient face stands on a panel that can, black, with the time and dots",function()
  local screen=dir.."/phone.json"
  morf.fs.write(screen,morf.json.encode{command="/bin/true",doubleTap=true,alwaysOn=true})
  write(SETTINGS,{lock={always_on={enabled=true},notifications={level="senders"}}})
  write(VIEW,{notifications={level="senders",count=3,items={{app="Signal",count=2,time=1},{app="Mail",count=1,time=1}}}})
  load{env={EVA_PHONE_SCREEN_CONFIG=screen,EVA_FAKE_AMBIENT="1"},size={868,1932}}
  test.truthy(shown("lock-ambient"))
  test.truthy(shown("lock-ambient-clock"))
  test.truthy(shown("lock-ambient-dots"))
  test.eq(test.ipc("audit").state,"locked")
end)

test.it("no ambient face without the system saying the panel can",function()
  local screen=dir.."/phone.json"
  morf.fs.write(screen,morf.json.encode{command="/bin/true",doubleTap=true})
  write(SETTINGS,{lock={always_on={enabled=true}}})
  load{env={EVA_PHONE_SCREEN_CONFIG=screen,EVA_FAKE_AMBIENT="1"},size={868,1932}}
  test.falsy(test.find{id="lock-ambient"})
end)

test.it("the status row says the charge and no names",function()
  load{env={EVA_FAKE_BATTERY="64,charging",EVA_FAKE_STATUS="wifi,bluetooth"}}
  test.eq(text_of("lock-status-charge"),"64% · 40m")
  test.eq(text_of("lock-status-network"),"network_wifi_3_bar")
  test.eq(text_of("lock-status-bluetooth"),"bluetooth_connected")
end)
