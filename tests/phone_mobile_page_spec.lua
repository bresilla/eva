-- The Mobile page on top of the phone: threads, levels, alerts and call settings.
local test=morf.test
local run=0
local dir
local function load()
  run=run+1
  dir=morf.env("XDG_CACHE_HOME").."/phone-page-"..run
  test.load("../shell/init.lua",{size={868,1932},env={EVA_WALLPAPER="",EVA_DRY_RUN="1",EVA_FAKE_MODEM="1",
    EVA_CONTACTS="tests/fixtures/contacts",EVA_SETTINGS=dir..".json",XDG_STATE_HOME=dir}})
  test.advance(20)
  test.ipc("settings","mobile")
  test.settle(1200)
end
local function fake(...) return test.ipc("phone","fake",...) end
local function shown(id)
  local node=test.find(id)
  return node~=nil and node.visible==true
end

test.it("the radio's levels show, and stop being asked for when the page shuts",function()
  load()
  test.truthy(shown("mobile-levels"))
  test.contains(test.get("mobile-levels-title").text,"RSRP -92 dBm")
  test.contains(test.get("mobile-levels-subtitle").text,"+31600000001")
end)

test.it("conversations are the phone's, by name",function()
  load()
  fake("text","+31612345678","see you")
  test.advance(60)
  test.settle(400)
  test.eq(test.get("mobile-sms-row-1-title").text,"Ann Veldman")
  test.eq(test.get("mobile-sms-row-1-subtitle").text,"see you")
  test.eq(test.find("mobile-sms-load"),nil)
end)

test.it("an alert kind turned off stays out, and the history lists the rest",function()
  load()
  test.truthy(shown("mobile-alert-switch-severe"))
  fake("alert",4373,"Storm warning")
  test.advance(60)
  test.ipc("phone","ok")
  test.advance(40)
  test.settle(400)
  test.eq(test.get("mobile-alert-row-1-subtitle").text,"Storm warning")
  for _=1,8 do test.wheel(0,600,{x=434,y=900}) test.advance(40) end
  test.settle(600)
  test.click("mobile-alert-switch-severe")
  test.advance(40)
  fake("alert",4374,"Another storm")
  test.advance(60)
  test.eq(test.ipc("phone","state").alert,"")
end)
