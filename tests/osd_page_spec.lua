-- The Settings page of the on-screen displays, on the real shell, and the
-- `osd` verb.
local test=morf.test
local SOURCE=[[
  require("init")
  morf.ipc.page_state=function()
    local config=require("config")
    return {detail=require("utilities").detail:get(),sidebar=require("utilities").opened:get(),
      shown=require("levels").shown:get(),
      volume=require("osd").volume(),
      popups=#require("notifs").list:get(),
      position=config.get("osd.kinds.brightness.position"),enabled=config.get("osd.kinds.brightness.enabled"),
      percent=config.get("osd.kinds.brightness.percent"),hold=config.get("osd.kinds.brightness.hold"),
      notifications=config.get("osd.notifications")}
  end
]]
local loads=0
local function load(style,fake,w,h)
  loads=loads+1
  test.load("../shell/init.lua",{source=SOURCE,size={w or 1600,h or 1000},env={EVA_STYLE=style,EVA_DRY_RUN="1",
    EVA_FAKE_OSD=fake==false and "0" or "1",
    EVA_SETTINGS=morf.fs.join(morf.env("XDG_CACHE_HOME"),"osd-page-spec-"..loads..".json")}})
  test.advance(200)
end
local function state() return test.ipc("page_state") end
local function open()
  test.ipc("settings","eva") test.advance(2500)
  test.click("settings-eva-osd") test.advance(2500)
end
-- The Settings window's page wheeled until `id` stands in it.
local function reach(id)
  for _=1,40 do
    local node,pane=test.find {id=id,visible=true},test.get("settings-detail")
    if node and node.y>pane.y and node.y+node.height<pane.y+pane.height then return id end
    local up=node and node.y<=pane.y
    test.wheel(0,up and -120 or 120,{x=pane.x+pane.width/2,y=pane.y+pane.height/2}) test.advance(200)
  end
  return id
end
local KINDS={"volume","brightness","mic","layout","profile","dnd","awake","night","ring","bluetooth","headphones","media"}

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." sets a display's place, switches and hold, and tries it",function()
    load(style) open()
    test.eq(state().detail,"osd")
    test.click(reach("osd-kind-brightness")) test.advance(300)
    test.eq(test.get("osd-chosen-title").text,"Brightness")
    test.click(reach("osd-place-top_left")) test.advance(300)
    test.eq(state().position,"top_left")
    test.eq(test.get("osd-chosen-subtitle").text,"Top left")
    test.click(reach("osd-hold-5000")) test.advance(100)
    test.eq(state().hold,5000)
    test.click(reach("osd-percent-switch")) test.advance(100)
    test.eq(state().percent,false)
    test.click(reach("osd-enabled-switch")) test.advance(100)
    test.eq(state().enabled,false)
    -- Off, a change stays quiet, and Try still shows it.
    test.eq(test.ipc("osd","brightness"),false)
    test.eq(state().shown,"")
    test.click(reach("osd-try")) test.advance(800)
    test.eq(state().shown,"brightness")
    test.truthy(test.get("levels-bar").visible,"it is not lying along the top")
    test.eq(#test.logs("error"),0)
  end)

  test.it(style.." gives the popups the top and bottom anchors and no others",function()
    load(style) open()
    test.click("osd-kind-notifications") test.advance(300)
    test.falsy(test.find{id="osd-place-center",visible=true},"a popup has no centre")
    test.falsy(test.find{id="osd-place-center_right",visible=true},"a popup has no side")
    test.falsy(test.find{id="osd-enabled",visible=true},"popups have no switches here")
    test.click(reach("osd-place-top_left")) test.advance(300)
    test.eq(state().notifications,"top_left")
    test.click(reach("osd-try")) test.advance(600)
    test.eq(state().popups,1)
    test.eq(#test.logs("error"),0)
  end)
end

test.it("offers only the displays this machine has",function()
  load("material",false) open()
  test.truthy(test.find{id="osd-kind-notifications",visible=true})
  for _,kind in ipairs {"volume","mic","profile","bluetooth","media","night"} do
    test.falsy(test.find{id="osd-kind-"..kind,visible=true},kind.." has no service here")
  end
end)

test.it("flashes every kind over IPC, and refuses one that does not exist",function()
  load("material")
  for _,kind in ipairs(KINDS) do
    test.truthy(test.ipc("osd",kind),kind)
    test.advance(800)
    test.eq(state().shown,kind)
    test.advance(5000)
  end
  test.truthy(test.ipc("osd"))
  test.advance(800)
  test.eq(state().shown,"volume")
  test.raises(function() test.ipc("osd","nonsense") end,"no such display")
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." on a real phone a finger along the level sets it, past the edge's gestures",function()
    load(style,true,868,1932)
    test.ipc("osd","volume") test.advance(800)
    local bud=test.get("levels-bud")
    local before=state().volume
    local y=bud.y+bud.height/2
    test.swipe({bud.x+120,y},{bud.x+240,y},{duration=240,steps=8}) test.advance(100)
    test.truthy(state().volume>before+.15,"a finger along it did not raise it")
    test.falsy(state().sidebar,"the drag opened the sheet")
    test.eq(#test.logs("error"),0)
  end)

  test.it(style.." a bud that takes another face keeps its place and lands on it",function()
    load(style,true,868,1932)
    test.ipc("osd","volume") test.advance(800)
    test.truthy(test.get("levels-bar").visible)
    test.ipc("osd","mic") test.advance(800)
    test.eq(state().shown,"mic")
    test.falsy(test.get("levels-bar").visible,"the old face stayed")
    test.truthy(test.get("levels-pill-title").visible,"the new face did not land")
    test.near(test.get("levels-bud").height,64,1)
  end)
end

for _,size in ipairs {{868,1932},{1600,1000}} do
  test.it(size[1].."x"..size[2]..": the window steps aside for a try and comes back to the page",function()
    load("material",true,size[1],size[2])
    test.ipc("settings","osd") test.advance(2500)
    test.eq(state().detail,"osd")
    test.click(reach("osd-try")) test.advance(800)
    test.eq(state().shown,"volume")
    test.falsy(state().sidebar,"the window hides what it is trying")
    test.advance(3500)
    test.truthy(state().sidebar,"the window did not come back")
    test.eq(state().detail,"osd")
    test.eq(#test.logs("error"),0)
  end)
end

test.it("the window stays away if something else was opened meanwhile",function()
  load("material",true,868,1932)
  test.ipc("settings","osd") test.advance(2500)
  test.click(reach("osd-try")) test.advance(400)
  test.ipc("launcher","open") test.advance(3500)
  test.falsy(state().sidebar,"the window came back over the launcher")
end)
