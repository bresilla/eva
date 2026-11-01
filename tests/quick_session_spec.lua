-- The session row and the hardware tiles' pages, in the real shell, dry: Lock
-- runs at once, the rest must be held, and a password stays out of everything
-- but the bus call.
--
--     morf test --no-dbus tests/quick_session_spec.lua
local test=morf.test
local SOURCE=[[
  require("init")
  local utilities=require("utilities")
  morf.ipc.q_sidebar=function() return require("sidebar").drawer.open:get() end
  morf.ipc.q_session=function() return require("session").drawer.open:get() end
  morf.ipc.q_command=function(id) return require("session").command(id) end
  morf.ipc.q_hotspot=function()
    local h=require("quick_hardware").hotspot()
    return {on=h.on(),saved=h.saved(),ssid=h.ssid(),status=h.status()}
  end
  morf.ipc.q_night=function()
    local n=require("quick_hardware").nightlight()
    return {on=n.on(),temperature=n.temperature(),status=n.status()}
  end
  morf.ipc.q_set_temperature=function(k) require("quick_hardware").nightlight().set_temperature(k) end
  morf.ipc.q_light=function(id)
    for _,t in ipairs(utilities.TOGGLES) do if t.id==id then return t.on()==true end end
  end
  morf.ipc.q_set=function(id,on) utilities.CONTROLS[id].set(on) end
  morf.ipc.q_rotation=function() return require("quick_hardware").rotation().on() end
  morf.ipc.q_detail=function() return utilities.detail:get() end
  morf.ipc.q_tile_status=function(id)
    for _,t in ipairs(utilities.TOGGLES) do if t.id==id then return t.status and t.status() end end
  end
  morf.ipc.q_power=function() return require("config").get("rotation.lock") end
]]
local serial=0
local settings
local function load(options)
  options=options or {}
  serial=serial+1
  settings=morf.env("XDG_CACHE_HOME").."/quick-session-"..serial..".json"
  morf.fs.remove(settings)
  test.stub_run("task",{code=0,stdout="[]"})
  test.load("../shell/init.lua",{source=SOURCE,size=options.size or {1600,1000},env={EVA_DRY_RUN="1",
    EVA_SETTINGS=settings,EVA_STYLE=options.style or "material",EVA_WALLPAPER="",EVA_FONT_FILE="",
    LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME"),EVA_FAKE_HARDWARE=options.real and "0" or "1"}})
  test.settle(1500)
  test.ipc("settings") test.settle(2500)
end
local function said(pattern)
  for _,line in ipairs(test.logs("info")) do
    if line.message:find(pattern,1,true) then return true end
  end
  return false
end
local function centre(id)
  local n=test.get(id)
  return n.x+n.width/2,n.y+n.height/2
end

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." the row shows who is signed in with all five actions",function()
    load({style=style})
    test.truthy(test.find{id="utilities-session",visible=true})
    test.truthy(test.find{id="utilities-session-picture",visible=true})
    test.truthy(test.find{id="utilities-session-name",visible=true})
    for _,id in ipairs {"lock","logout","suspend","reboot","shutdown"} do
      test.truthy(test.find{id="utilities-session-"..id,visible=true},id.." missing")
    end
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." Lock runs at once, in a dry run",function()
    load({style=style})
    test.clear_logs()
    test.click("utilities-session-lock") test.settle(600)
    test.truthy(said("session lock (dry run)"),"Lock did not run")
    test.falsy(test.ipc("q_sidebar"),"the panel stayed over the lock")
    test.eq(#test.runs()>0 and test.runs()[#test.runs()][1]=="morf",false,"a real command ran")
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." a destructive action needs the hold, and letting go cancels it",function()
    load({style=style})
    test.clear_logs()
    local x,y=centre("utilities-session-shutdown")
    test.click(x,y) test.advance(200)
    test.falsy(said("session shutdown"),"a click powered off")
    test.truthy(test.find{text="Hold to confirm",visible=true},"a short press says nothing")
    test.move(x,y) test.press(x,y) test.advance(400)
    test.truthy(test.find{text="Power off…",visible=true})
    test.release(x,y) test.advance(600)
    test.falsy(said("session shutdown"),"letting go did not cancel it")
    test.truthy(test.ipc("q_sidebar"))
    test.press(x,y) test.advance(900)
    test.truthy(said("session shutdown (dry run): systemctl poweroff"),"a full hold did not count")
    test.release(x,y) test.advance(100)
    test.eq(#test.logs("error"),0)
  end)
end

test.it("every destructive action takes the session's own command",function()
  load()
  test.eq(test.ipc("q_command","lock"),{"morf","lock"})
  test.eq(test.ipc("q_command","suspend"),{"systemctl","suspend"})
  local x,y=centre("utilities-session-suspend")
  test.clear_logs()
  test.move(x,y) test.press(x,y) test.advance(900) test.release(x,y) test.advance(100)
  test.truthy(said("session suspend (dry run): systemctl suspend"))
  test.ipc("settings") test.settle(2500)
  x,y=centre("utilities-session-reboot")
  test.move(x,y) test.press(x,y) test.advance(900) test.release(x,y) test.advance(100)
  test.truthy(said("session reboot (dry run)"))
  test.ipc("settings") test.settle(2500)
  x,y=centre("utilities-session-logout")
  test.move(x,y) test.press(x,y) test.advance(900) test.release(x,y) test.advance(100)
  test.truthy(said("session logout (dry run)"))
  test.eq(#test.logs("error"),0)
end)

test.it("the full session drawer remains, with its own actions",function()
  load()
  test.ipc("session","open") test.settle(1200)
  test.truthy(test.ipc("q_session"))
  for _,id in ipairs {"logout","shutdown","hibernate","reboot"} do
    test.truthy(test.find{id="session-"..id,visible=true},id.." left the drawer")
  end
  test.falsy(test.find{id="session-lock"},"the row's Lock leaked into the drawer")
  test.eq(#test.logs("error"),0)
end)

test.it("a phone's row stacks and stays within its card",function()
  load({size={432,960}})
  local card=test.get("utilities-session")
  local last=test.get("utilities-session-shutdown")
  test.truthy(last.x+last.width<=card.x+card.width-15,"a button runs off the card")
  test.truthy(last.y>test.get("utilities-session-picture").y,"the row did not stack")
  test.eq(#test.logs("error"),0)
end)

-- ---------------------------------------------------------------- hotspot --

test.it("a first press of Hotspot asks for its network, then it starts and stops",function()
  load()
  test.click("utilities-toggle-hotspot") test.settle(1500)
  test.eq(test.ipc("q_detail"),"hotspot","the tile did not ask for a password")
  test.falsy(test.ipc("q_hotspot").on)
  test.truthy(test.find{text_contains="turning Wi-Fi off stops it",visible=true})
  test.click("settings-hotspot-password") test.type("short") test.advance(50)
  test.click("settings-hotspot-save") test.settle(300)
  test.truthy(test.find{text="A password is at least 8 characters",visible=true})
  test.falsy(test.ipc("q_hotspot").saved)
  test.click("settings-hotspot-password") test.type("-but-longer") test.advance(50)
  test.click("settings-hotspot-save") test.settle(300)
  test.truthy(test.ipc("q_hotspot").saved)
  test.click("settings-back") test.settle(1500)
  test.clear_logs()
  test.click("utilities-toggle-hotspot") test.settle(600)
  test.truthy(test.ipc("q_hotspot").on)
  test.truthy(said("hotspot on (dry run)"))
  test.click("utilities-toggle-hotspot") test.settle(600)
  test.falsy(test.ipc("q_hotspot").on)
  test.eq(#test.logs("error"),0)
end)

test.it("a hotspot password reaches no log and no settings file",function()
  load()
  local secret="correct-horse-battery"
  test.ipc("settings","hotspot") test.settle(1500)
  test.click("settings-hotspot-password") test.type(secret) test.advance(50)
  test.click("settings-hotspot-save") test.settle(800)
  test.truthy(test.ipc("q_hotspot").saved)
  for _,level in ipairs {"debug"} do
    for _,line in ipairs(test.logs(level)) do
      test.falsy(line.message:find(secret,1,true),"the password was logged")
    end
  end
  local ok,text=pcall(morf.fs.read,settings)
  test.falsy(ok and type(text)=="string" and text:find(secret,1,true),"the password was saved")
  for _,run in ipairs(test.runs()) do
    test.falsy(table.concat(run," "):find(secret,1,true),"the password was on a command line")
  end
  test.eq(#test.logs("error"),0)
end)

-- ------------------------------------------------------------------ others --

test.it("night light keeps its temperature and says it",function()
  load()
  test.ipc("settings","nightlight") test.settle(1500)
  test.falsy(test.ipc("q_night").on)
  test.click("settings-nightlight-switch") test.settle(400)
  test.truthy(test.ipc("q_night").on)
  test.ipc("q_set_temperature",3333) test.settle(400)
  test.eq(test.ipc("q_night").temperature,3300)
  test.truthy(said("hyprctl hyprsunset temperature 3300 (dry run)"),"it did not speak to hyprsunset")
  test.eq(test.ipc("q_night").status,"3300 K")
  test.click("settings-back") test.settle(1500)
  test.click("utilities-toggle-nightlight") test.settle(400)
  test.falsy(test.ipc("q_night").on)
  test.truthy(said("hyprctl hyprsunset identity (dry run)"))
  test.eq(#test.logs("error"),0)
end)

test.it("the machine is left alone in a dry run",function()
  load()
  test.clear_logs()
  for _,id in ipairs {"flashlight","powersaver","rotation","nightlight"} do
    test.ipc("q_set",id,true)
  end
  test.settle(500)
  test.truthy(said("flashlight on (dry run)"))
  test.truthy(said("power saver on (dry run)"))
  for _,run in ipairs(test.runs()) do
    test.eq(run[1]=="hyprctl",false,"a command ran: "..table.concat(run," "))
  end
  test.eq(#test.logs("error"),0)
end)

test.it("a rotation lock is a setting: the tile reads it, on a desk locked by default",function()
  load()
  test.truthy(test.ipc("q_rotation"))
  test.ipc("q_set","rotation",false) test.settle(200)
  test.falsy(test.ipc("q_rotation"))
  test.eq(test.ipc("q_power"),"off")
  test.eq(#test.logs("error"),0)
end)

test.it("Screenshot and Screen record ask the capture tool from their tiles",function()
  load()
  test.clear_logs()
  test.ipc("q_set","screenshot") test.settle(1500)
  test.falsy(test.ipc("q_sidebar"),"the panel stayed over the capture")
  test.truthy(said("capture screenshot region (dry run)"))
  test.ipc("settings") test.settle(2500)
  test.ipc("q_set","record") test.settle(1500)
  test.truthy(said("capture record region (dry run)"),"it did not ask for a recording")
  test.eq(#test.logs("error"),0)
end)

test.it("lights the record tile from what the capture tool publishes",function()
  load()
  local path=morf.env("XDG_RUNTIME_DIR").."/eva/capture.json"
  local function publish(recording)
    morf.fs.write(path,morf.json.encode {pid=morf.process_id,recording=recording,phase=recording and "recording" or "ready",
      started=morf.time.now_ms()-65000},{atomic=true,parents=true})
  end
  test.falsy(test.ipc("q_light","record"))
  publish(true)
  test.wait(function() return test.ipc("q_light","record") end,2000,"the tile did not light")
  publish(false)
  test.wait(function() return not test.ipc("q_light","record") end,2000,"the tile stayed lit")
  morf.fs.remove(path)
  test.eq(#test.logs("error"),0)
end)

test.it("the on-screen keyboard tile opens the keyboard and is lit while it is up",function()
  load()
  test.ipc("q_set","keyboard",true) test.settle(800)
  test.ipc("settings") test.settle(2500)
  test.truthy(test.ipc("q_light","keyboard"))
  test.ipc("q_set","keyboard",false) test.settle(800)
  test.ipc("settings") test.settle(2500)
  test.falsy(test.ipc("q_light","keyboard"))
  test.eq(#test.logs("error"),0)
end)

test.it("game mode runs its commands, dry",function()
  load()
  test.clear_logs()
  test.ipc("q_set","gamemode",true) test.settle(200)
  test.truthy(said("utilities gamemode_on (dry run)"))
  test.truthy(test.ipc("q_light","gamemode"),"game mode is not lit")
  test.ipc("q_set","gamemode",false) test.settle(200)
  test.truthy(said("utilities gamemode_off (dry run)"))
  test.falsy(test.ipc("q_light","gamemode"))
  test.eq(#test.logs("error"),0)
end)
