-- The Touch gestures page on the real shell, in both themes: it says what the
-- reader is doing, what each gesture does; a gesture is chosen, reset and tried
-- with the fingers on show. The launcher finds it.
local test=morf.test
local SOURCE=[[
  require("init")
  morf.ipc.detail=function() return require("utilities").detail:get() end
  morf.ipc.value=function(key) return require("config").get(key) end
  morf.ipc.bound=function(key) return require("touch_bindings").action(key) end
  morf.ipc.command_of=function(key) return require("touch_bindings").command(key) end
  morf.ipc.gesture_keys=function()
    local out={}
    for i,gesture in ipairs(require("touch_bindings").GESTURES) do out[i]=gesture.key end
    return out
  end
  morf.ipc.search=function(word)
    local out={}
    for i,entry in ipairs(require("settings_registry").search(word)) do out[i]=entry.key end
    return out
  end
]]
local loads=0
local function load(style,fake,w,h)
  loads=loads+1
  test.stub_run("task",{code=0,stdout="[]"})
  test.load("../shell/init.lua",{source=SOURCE,size={w or 1280,h or 800},env={EVA_STYLE=style,EVA_DRY_RUN="1",
    EVA_WALLPAPER="",EVA_FAKE_TOUCH=fake or "1",EVA_FAKE_LOGIND="{}",
    EVA_SETTINGS=morf.fs.join(morf.env("XDG_CACHE_HOME"),"touch-page-"..loads..".json")}})
  test.advance(200)
  test.ipc("settings","touch") test.advance(1500)
end
-- Scrolls page `scroll` until the node `id` stands inside it, and presses it.
local function press(id,scroll)
  local page=test.get(scroll or "touch-scroll")
  for _=1,60 do
    local node=test.get(id)
    if node.y>=page.y and node.y+node.height<=page.y+page.height then break end
    test.wheel(0,node.y>page.y and 120 or -120,{x=page.x+40,y=page.y+60}) test.advance(200)
  end
  test.click(id)
end
local function line(kind,id,x,y)
  local at=(" event99  %-23s      +%.3fs\t"):format(kind,0.1)
  if id==nil then return at end
  if not x then return at..("%d (%d)"):format(id,id) end
  return at..("%d (%d) %.2f/%.2f (1.00/1.00mm)"):format(id,id,x/12.8,y/8)
end

test.it("is on the launcher's search, by what people call it",function()
  load("material")
  for _,word in ipairs {"gesture","swipe","touch","multitouch"} do
    local found=test.ipc("search",word)
    local hit=false
    for _,key in ipairs(found) do hit=hit or key=="touch" end
    test.truthy(hit,word)
  end
end)

test.it("has a real field for every gesture on every form",function()
  load("material")
  for _,form in ipairs {"desk","phone"} do
    press("touch-form-"..form) test.advance(200)
    for _,key in ipairs(test.ipc("gesture_keys")) do
      test.truthy(test.get("touch-gesture-"..key),key)
      test.truthy(test.get("touch-gesture-"..key.."-subtitle").text~="",key.." says what it does")
    end
  end
  test.get("touch-enabled-switch")
  test.eq(#test.logs("error"),0)
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." lists each gesture with what it does",function()
    load(style)
    test.eq(test.ipc("detail"),"touch")
    test.eq(test.get("touch-status-title").text,"Reading the touchscreen")
    test.get("touch-gesture-two_up_bottom")
    test.eq(test.get("touch-gesture-three_up-subtitle").text,"Overview")
    test.eq(test.get("touch-gesture-five_pinch_in-subtitle").text,"Launcher")
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." chooses what a gesture does, and resets it",function()
    load(style)
    press("touch-gesture-three_down") test.advance(1500)
    test.eq(test.ipc("detail"),"touch/gesture")
    press("touch-action-lock","touch-gesture-scroll") test.advance(200)
    test.eq(test.ipc("bound","three_down"),"lock")
    test.eq(test.get("touch-gesture-name-subtitle").text,"Changed")
    press("touch-gesture-reset","touch-gesture-scroll") test.advance(200)
    test.eq(test.ipc("bound","three_down"),"show_desktop")
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." takes a command for a gesture",function()
    load(style)
    press("touch-gesture-four_down") test.advance(1500)
    test.falsy(test.find("touch-command") and test.find("touch-command").visible)
    press("touch-action-command","touch-gesture-scroll") test.advance(300)
    test.eq(test.ipc("bound","four_down"),"command")
    test.truthy(test.get("touch-command").visible)
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." turns the whole thing off, and says so",function()
    load(style)
    test.click("touch-enabled-switch") test.advance(300)
    test.eq(test.ipc("value","gestures.enabled"),false)
    test.eq(test.get("touch-status-title").text,"Off")
    test.eq(test.ipc("touch").reading,false)
  end)
  test.it(style.." puts every gesture back as it came",function()
    load(style)
    test.ipc("touch","set","three_up","lock")
    test.advance(100)
    test.eq(test.get("touch-gesture-three_up-subtitle").text,"Lock")
    press("touch-reset-button") test.advance(200)
    test.eq(test.ipc("bound","three_up"),"overview")
  end)
  test.it(style.." shows the fingers while trying, and runs nothing",function()
    load(style)
    test.click("touch-try-button") test.advance(300)
    test.ipc("touch","feed",line("TOUCH_DOWN",1,900,300))
    test.ipc("touch","feed",line("TOUCH_DOWN",2,980,320))
    test.ipc("touch","feed",line("TOUCH_DOWN",3,1060,300))
    test.ipc("touch","feed",line("TOUCH_FRAME"))
    test.advance(100)
    test.truthy(test.get("touch-finger-1").visible)
    test.truthy(test.get("touch-finger-3").visible)
    test.falsy(test.get("touch-finger-4").visible)
    for n=1,6 do
      for id,x in ipairs {900,980,1060} do test.ipc("touch","feed",line("TOUCH_MOTION",id,x,300+n*30)) end
      test.ipc("touch","feed",line("TOUCH_FRAME"))
    end
    for id=1,3 do test.ipc("touch","feed",line("TOUCH_UP",id)) end
    test.ipc("touch","feed",line("TOUCH_FRAME"))
    test.advance(300)
    test.eq(test.get("touch-try-row-title").text,"Three fingers down")
    test.eq(test.get("touch-try-row-subtitle").text,"Show desktop")
    test.falsy(test.get("touch-finger-1").visible)
    test.click("touch-try-button") test.advance(100)
    test.falsy(test.ipc("touch","state").trying)
  end)
end

for _,case in ipairs {
  {"none","No touchscreen"},{"missing","libinput is not installed"},{"denied","Not allowed to read the touchscreen"},
} do
  test.it("says plainly when it cannot run: "..case[1],function()
    load("material",case[1])
    test.advance(100)
    test.eq(test.get("touch-status-title").text,case[2])
    test.falsy(test.get("touch-try").visible)
    test.eq(#test.logs("error"),0)
  end)
end

test.it("fits a phone",function()
  load("material","1",390,844)
  local status=test.get("touch-status")
  test.truthy(status.width<=390)
  test.eq(#test.logs("error"),0)
end)
