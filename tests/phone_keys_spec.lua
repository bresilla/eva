-- The side keys, as the compositor's binds deliver them.
local test=morf.test
local run=0
local function load(settings)
  run=run+1
  local dir=morf.env("XDG_CACHE_HOME").."/phone-keys-"..run
  if settings then morf.fs.write(dir..".json",morf.json.encode(settings),{parents=true}) end
  test.load("../shell/init.lua",{size={868,1932},env={EVA_WALLPAPER="",EVA_DRY_RUN="1",EVA_FAKE_MODEM="1",
    EVA_CONTACTS="tests/fixtures/contacts",EVA_SETTINGS=dir..".json",XDG_STATE_HOME=dir}})
  test.advance(20)
end
local function key(name) return test.ipc("phone","key",name) end
local function state() return test.ipc("phone","state") end
local function ring() test.ipc("phone","fake","ring","+31612345678") test.advance(40) end

test.it("a volume key silences a ringing call and leaves it ringing on the screen",function()
  load()
  ring()
  test.eq(state().rung,"phone-incoming-call")
  test.eq(key("volume-down"),"silenced")
  test.eq(state().rung,"")
  test.eq(state().stage,"incoming")
end)

test.it("power silences too, and does nothing to a call unless asked",function()
  load()
  ring()
  test.eq(key("power"),"silenced")
  test.ipc("phone","answer")
  test.advance(40)
  test.eq(key("power"),"")
  test.eq(state().stage,"talking")
end)

test.it("power ends a call when the setting says so",function()
  load{phone={power_ends_call=true}}
  ring()
  test.ipc("phone","answer")
  test.advance(40)
  test.eq(key("power"),"ended")
  test.advance(40)
  test.eq(state().stage,"ended")
end)

test.it("volume keys with nothing ringing do nothing here",function()
  load()
  test.eq(key("volume-up"),"")
  test.eq(state().stage,"idle")
end)

test.it("five presses count down and call, if the setting is on, and can be called off",function()
  load{phone={sos=true}}
  for _=1,4 do test.eq(key("power"),"") test.advance(100) end
  test.eq(key("power"),"sos")
  test.advance(2000)
  test.eq(state().stage,"idle")
  test.eq(test.get("sos-left").text,"3")
  test.click("sos-cancel")
  test.advance(6000)
  test.eq(state().stage,"idle")
  test.eq(test.find("sos-cancel"),nil)
  for _=1,5 do key("power") test.advance(100) end
  test.advance(5400)
  test.eq(state().stage,"talking")
  test.eq(state().calls[1].number,"112")
end)

test.it("five presses are nothing while the setting is off",function()
  load()
  for _=1,5 do test.eq(key("power"),"") test.advance(100) end
  test.advance(6000)
  test.eq(state().stage,"idle")
end)

test.it("presses too far apart are not a run",function()
  load{phone={sos=true}}
  for _=1,5 do test.eq(key("power"),"") test.advance(700) end
end)
