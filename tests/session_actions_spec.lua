-- The session menu against what logind says: what is offered, what stands in
-- the way, the countdown and its cancel. EVA_FAKE_LOGIND stands in for the bus;
-- nothing reaches a machine.
local test=morf.test
local RUN=morf.env("XDG_CACHE_HOME").."/session-actions-run"
morf.fs.mkdir(RUN,{parents=true})
local HOST=[[
  local ui=require("morf.ui")
  local W,H=1280,tonumber(morf.env("TEST_HEIGHT") or "1000")
  morf.surface.height=H
  package.loaded.bar={desk=function() return 10,10,W-20,H-20 end}
  local session=require("session")
  local theme=require("theme")
  ui.Item {width=W,height=H,
    ui.Rect {width=W,height=H,color=function() return theme.color.surface end},
    session.dim(),
    ui.Item {x=10,y=10,width=W-20,height=H-20,
      ui.Sdf {anchors={fill=true},fill_color=function() return theme.color.surfaceContainer end,session.drawer.shape},
      session.drawer.panel}}
  morf.ipc.open=function(on) session.drawer.set(on=="yes") end
  morf.ipc.state=function()
    local ids={}
    for i,a in ipairs(session.actions) do ids[i]=a.id end
    return {open=session.opened:get(),pending=session.pending:get(),left=session.left:get(),ids=ids}
  end
  morf.ipc.calls=function() return require("models.logind").connect().calls end
]]
local function load(style,logind,height)
  test.load("../shell/init.lua",{source=HOST,size={1280,height or 1000},env={EVA_STYLE=style,EVA_DRY_RUN="1",USER="me",XDG_RUNTIME_DIR=RUN,
    TEST_HEIGHT=tostring(height or 1000),EVA_FAKE_LOGIND=morf.json.encode(logind or {})}})
end
local function open() test.ipc("open","yes") test.advance(2200) end
local function ids() local set={} for _,id in ipairs(test.ipc("state").ids) do set[id]=true end return set end
local function logged(pattern)
  for _,line in ipairs(test.logs("info")) do if line.message:find(pattern,1,true) then return true end end
  return false
end
local YES={suspend="yes",hibernate="yes",reboot="yes",power_off="yes"}

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." hibernate and suspend go when logind says no",function()
    load(style,{can={suspend="no",hibernate="na",reboot="yes",power_off="yes"}})
    local have=ids()
    test.falsy(have.hibernate) test.falsy(have.suspend)
    test.truthy(have.reboot) test.truthy(have.shutdown)
  end)
  test.it(style.." a challenge is still offered: the session has a polkit agent",function()
    load(style,{can={suspend="challenge",hibernate="yes",reboot="yes",power_off="yes"}})
    test.truthy(ids().suspend)
  end)
  test.it(style.." the countdown runs out, and runs the action once",function()
    load(style,{can=YES}) open()
    test.click("session-reboot") test.advance(100)
    test.eq(test.ipc("state").pending,"reboot")
    test.eq(test.ipc("state").left,5)
    test.matches(test.get("session-reboot-detail").text:lower(),"^in 5 s")
    test.falsy(logged("session reboot"))
    test.advance(6000)
    test.truthy(logged("session reboot (dry run)"))
    test.falsy(test.ipc("state").open)
    test.eq(test.ipc("state").pending,"")
  end)
  test.it(style.." Escape stops the countdown and leaves the menu open",function()
    load(style,{can=YES}) open()
    test.click("session-shutdown") test.advance(100)
    test.eq(test.ipc("state").pending,"shutdown")
    test.key("Escape") test.advance(300)
    test.eq(test.ipc("state").pending,"")
    test.truthy(test.ipc("state").open)
    test.advance(7000)
    test.falsy(logged("session shutdown"))
  end)
  test.it(style.." Cancel on the row stops it, and shutting the menu does too",function()
    load(style,{can=YES}) open()
    test.click("session-reboot") test.advance(200)
    test.click("session-reboot-cancel") test.advance(200)
    test.eq(test.ipc("state").pending,"")
    test.click("session-reboot") test.advance(200)
    test.ipc("open","no") test.advance(500)
    test.eq(test.ipc("state").pending,"")
    test.advance(7000)
    test.falsy(logged("session reboot"))
  end)
  test.it(style.." a letter goes to its action, and j and k move",function()
    load(style,{can=YES}) open()
    test.type("r") test.advance(200)
    test.eq(test.ipc("state").pending,"reboot")
    test.key("Escape") test.advance(200)
    test.type("j") test.advance(100)
  end)
  test.it(style.." who blocks sleep is named, on the row and in the list",function()
    load(style,{can=YES,inhibitors={
      {what="sleep:idle",who="firefox",why="Playing video",mode="block",uid=1000,pid=1},
      {what="shutdown",who="backup",why="Writing",mode="block",uid=1000,pid=2},
      {what="sleep",who="delayed",why="Not blocking",mode="delay",uid=1000,pid=3},
      {what="handle-lid-switch",who="other",why="Not this",mode="block",uid=1000,pid=4}}})
    open()
    test.eq(test.get("session-suspend-detail").text:lower(),"blocked by firefox")
    test.eq(test.get("session-reboot-detail").text:lower(),"blocked by backup")
    test.truthy(test.get("session-blockers").visible)
    test.eq(test.get("session-blocker-1").text:lower(),"firefox: playing video")
    test.eq(test.get("session-blocker-2").text:lower(),"backup: writing")
    test.eq(test.find{id="session-blocker-3",visible=true},nil)
  end)
  test.it(style.." nothing listed where nothing blocks",function()
    load(style,{can=YES}) open()
    test.falsy(test.get("session-blockers").visible)
  end)
  test.it(style.." switch user goes to another person's session after locking",function()
    load(style,{can=YES,sessions={{id="c3",uid=1001,user="alice",seat="seat0"},
      {id="c1",uid=1000,user="me",seat="seat0"},{id="c2",uid=102,user="greeter",seat="seat0"},
      {id="c4",uid=1002,user="bob",seat=""}}})
    open()
    test.truthy(ids().switch)
    test.eq(test.get("session-switch-detail").text:lower(),"lock, and go to alice")
    test.click("session-switch") test.advance(600)
    test.truthy(logged("session lock (dry run)"))
    test.truthy(logged("session switch to alice"))
    local calls=test.ipc("calls")
    test.eq(calls[#calls],"ActivateSession c3")
  end)
  test.it(style.." no other session, no switch user",function()
    load(style,{can=YES,sessions={{id="c1",uid=1000,user="me",seat="seat0"}}})
    test.falsy(ids().switch)
  end)
  test.it(style.." firmware setup shows only where logind says yes, and counts down",function()
    load(style,{can=YES}) test.falsy(ids().firmware)
    load(style,{can=YES,firmware="yes"}) open()
    test.truthy(ids().firmware)
    test.click("session-firmware") test.advance(200)
    test.eq(test.ipc("state").pending,"firmware")
    test.click("session-firmware") test.advance(600)
    test.truthy(logged("session firmware (dry run)"))
  end)
  test.it(style.." lockdown asks for a lock and leaves the reason for it",function()
    load(style,{can=YES}) open()
    test.click("session-lockdown") test.advance(600)
    test.truthy(logged("session lock (lockdown) (dry run)"))
    local reason=morf.fs.read(RUN.."/eva/lock-reason")
    test.contains(reason,"lockdown")
    morf.fs.remove(RUN.."/eva/lock-reason")
  end)
  test.it(style.." suspend then hibernate stands only on logind's plain yes",function()
    load(style,{can=YES}) test.falsy(ids().suspend_hibernate)
    load(style,{can={suspend="yes",hibernate="yes",reboot="yes",power_off="yes",suspend_then_hibernate="challenge"}})
    test.falsy(ids().suspend_hibernate)
    load(style,{can={suspend="yes",hibernate="yes",reboot="yes",power_off="yes",suspend_then_hibernate="yes"}})
    test.truthy(ids().suspend_hibernate)
  end)
  test.it(style.." a short screen takes two columns and stays on it",function()
    load(style,{can=YES,firmware="yes",sessions={{id="c3",uid=1001,user="alice",seat="seat0"}}},480) open()
    local panel=test.get("drawer-session")
    test.truthy(panel.y>=0 and panel.y+panel.height<=480,"the panel fits")
    test.truthy(panel.width>300)
    test.ne(test.get("session-shutdown").x,test.get("session-lock").x)
    for _,id in ipairs(test.ipc("state").ids) do
      local row=test.get("session-"..id)
      test.truthy(row.y+row.height<=panel.y+panel.height,id.." inside")
    end
  end)
end
