-- The greeter: who came last, the status row, layouts, the accessibility menu,
-- and its power buttons. In preview: it never reaches greetd.
local test=morf.test
local dir=morf.env("XDG_CACHE_HOME").."/greet-features"
morf.fs.mkdir(dir,{parents=true})
local MEMORY=dir.."/greeter.json"
local SOURCE=[[
  package.loaded["lib.services.accounts"]={list=function() return {
    {name="alice",label="Alice",initial="A"},{name="bob",label="Bob",initial="B"},{name="carol",label="Carol",initial="C"}} end}
  package.loaded["lib.services.sessions"]={
    list=function() return {
      {id="hyprland",name="Hyprland",command={"h"},environment={}},
      {id="sway",name="Sway",command={"s"},environment={}}} end,
    default_index=function() return 1 end}
  local ctx
  local theme=require("themes").current.greet local build=require(theme)
  package.loaded[theme]=function(context) ctx=context return build(context) end
  require("init")
  morf.ipc.audit=function()
    return {who=ctx.person().name,session=ctx.session().id,stage=ctx.stage:get()}
  end
  morf.ipc.choose=function(index) ctx.choose(tonumber(index)) end
  morf.ipc.verified=function()
    local memory=require("models.greet_memory")
    memory.remember(ctx.person().name,ctx.session().id)
  end
  morf.ipc.step=function() ctx.step_session(1) end
  morf.ipc.message=function() return ctx.message:get() end
  morf.ipc.unsay=function() ctx.say("") end
  morf.ipc.power=function(method) return {require("lib.shell.auth").power(method)} end
]]
local function load(options)
  options=options or {}
  local env={EVA_STYLE=options.style or "material",EVA_SCALE_MODE="compositor",EVA_DRY_RUN="1",
    EVA_GREETER_MEMORY=MEMORY,EVA_FAKE_LOGIND=morf.json.encode(options.logind or {can={suspend="yes",reboot="yes",power_off="yes"}})}
  for k,v in pairs(options.env or {}) do env[k]=v end
  test.load("../greet/init.lua",{source=SOURCE,size=options.size or {1920,1080},args={"preview"},env=env})
  test.settle(1500)
end
local function shown(id) return test.find{id=id,visible=true} end
local function click(id) test.click{id=id} test.settle(400) end
test.before_each(function() morf.fs.remove(MEMORY) end)

test.it("with nothing kept it opens on the first person and the default session",function()
  load()
  local audit=test.ipc("audit")
  test.eq(audit.who,"alice") test.eq(audit.session,"hyprland")
end)

test.it("the last person and the session they chose come back",function()
  load()
  test.ipc("choose","2") test.ipc("step") test.ipc("verified")
  load()
  local audit=test.ipc("audit")
  test.eq(audit.who,"bob") test.eq(audit.session,"sway")
  test.ipc("choose","1")
  test.eq(test.ipc("audit").session,"hyprland","each person has their own")
  test.ipc("choose","2")
  test.eq(test.ipc("audit").session,"sway")
end)

test.it("what is kept holds nothing but names",function()
  load()
  test.ipc("choose","3") test.ipc("verified")
  local kept=morf.json.decode(morf.fs.read(MEMORY))
  test.eq(kept.user,"carol")
  for key in pairs(kept) do test.truthy(key=="user" or key=="sessions" or key=="access",key) end
end)

test.it("a person who left, a session gone or a broken file is ignored",function()
  morf.fs.write(MEMORY,morf.json.encode{user="mallory",sessions={mallory="gone"}})
  load()
  test.eq(test.ipc("audit").who,"alice")
  morf.fs.write(MEMORY,morf.json.encode{user="bob",sessions={bob="removed"}})
  load()
  test.eq(test.ipc("audit").who,"bob")
  test.eq(test.ipc("audit").session,"hyprland")
  morf.fs.write(MEMORY,"{ not json")
  load()
  test.eq(test.ipc("audit").who,"alice")
end)

test.it("it can be told to forget",function()
  morf.fs.write(MEMORY,morf.json.encode{user="bob"})
  load{env={EVA_GREETER_REMEMBER="0"}}
  test.eq(test.ipc("audit").who,"alice")
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." status, layouts and Caps Lock",function()
    local leds=dir.."/leds"
    morf.fs.mkdir(leds.."/input3::capslock",{parents=true})
    morf.fs.write(leds.."/input3::capslock/brightness","1\n")
    load{style=style,env={EVA_FAKE_BATTERY="64,charging",EVA_FAKE_STATUS="wifi",EVA_FAKE_LAYOUTS="us,de",EVA_LEDS=leds}}
    test.eq(test.get("greet-status-charge").text,"64% · 40m")
    test.eq(test.get("greet-status-network").text,"network_wifi_3_bar")
    test.key("Return") test.settle(500)
    test.truthy(shown("greet-layout"))
    test.eq(test.get("greet-layout-label").text,"US")
    click("greet-layout")
    test.eq(test.get("greet-layout-label").text,"DE")
    test.key("F3") test.settle(200)
    test.eq(test.get("greet-layout-label").text,"US")
    test.ipc("unsay") test.settle(200)
    test.eq(test.get("greet-message").text,"Caps Lock is on")
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." the accessibility menu changes the screen, and is kept",function()
    load{style=style}
    test.falsy(shown("greet-access-panel"))
    click("greet-access")
    test.truthy(shown("greet-access-panel"))
    local before=test.get("greet-clock").font_size or test.get("greet-glance").width
    click("greet-access-large") test.settle(400)
    test.truthy(shown("greet-access-panel"),"the menu stays open through the rebuild")
    click("greet-access-contrast")
    click("greet-access-motion")
    click("greet-access-keyboard")
    local kept=morf.json.decode(morf.fs.read(MEMORY)).access
    test.eq(kept,{large=true,contrast=true,motion=true,keyboard=true})
    load{style=style}
    test.ipc("audit")
    test.key("Return") test.settle(500)
    test.truthy(shown("greet-keyboard"),"the keyboard came back with the choice")
    test.eq(#test.logs("error"),0)
  end)
end

test.it("power buttons follow logind and the firmware one needs a yes and a hold",function()
  load{logind={can={suspend="no",reboot="yes",power_off="na"},firmware="yes"}}
  test.falsy(shown("greet-suspend"))
  test.truthy(shown("greet-reboot"))
  test.falsy(shown("greet-poweroff"))
  test.truthy(shown("greet-firmware"))
  load{logind={can={suspend="yes",reboot="yes",power_off="yes"}}}
  test.falsy(shown("greet-firmware"))
end)

test.it("a preview's buttons reach nothing",function()
  load()
  click("greet-reboot")
  local said=false
  for _,line in ipairs(test.logs("info")) do if line.message:find("reboot (preview)",1,true) then said=true end end
  test.truthy(said)
end)

test.it("asking logind with no bus answers why, and throws nothing",function()
  load()
  local answer=test.ipc("power","Suspend")
  test.eq(answer[1],nil)
  test.truthy(type(answer[2])=="string","a reason")
end)

test.it("a password goes to no file",function()
  load()
  test.key("Return") test.settle(400)
  test.type("hunter2") test.settle(200)
  test.ipc("verified")
  test.eq(tostring(morf.fs.read(MEMORY)):find("hunter2",1,true),nil)
end)
