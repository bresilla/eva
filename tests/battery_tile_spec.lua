-- The battery in the real shell, from the stand-in the harness uses: the quick
-- settings board comes up whole, its tile draws the glyph and says the state.
local test=morf.test
local SOURCE=[[
  require("init")
  morf.ipc.open=function()
    require("sidebar").select("settings")
    require("sidebar").drawer.set(true)
  end
  morf.ipc.count=function()
    local board=require("utilities").tiles
    return #board.shown()
  end
  morf.ipc.status=function()
    for _,t in ipairs(require("utilities").TOGGLES) do
      if t.id=="battery" then return t.status() end
    end
  end
]]
local DEVICES=morf.env("EVA_INPUT_DEVICES")
local function load(style,fake)
  test.stub_run("task",{code=0,stdout="[]"})
  test.load("../shell/init.lua",{source=SOURCE,size={868,1932},env={EVA_STYLE=style,EVA_DRY_RUN="1",EVA_WALLPAPER="",
    EVA_FAKE_BATTERY=fake or false,EVA_INPUT_DEVICES=DEVICES.."-touch",HOME=morf.env("XDG_CACHE_HOME")}})
  test.settle(2000)
  test.ipc("open") test.settle(2000)
end
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." brings the whole board up with a stand-in battery",function()
    load(style)
    local without=test.ipc("count")
    test.truthy(without>0)
    load(style,"57,charging,saver")
    test.truthy(test.ipc("count")>=without,"the stand-in costs the board its tiles")
    test.eq(#test.logs("error"),0) test.eq(#test.logs("warn"),0)
  end)
  test.it(style.." draws the glyph in the battery tile and says the state",function()
    load(style,"57,charging")
    test.truthy(test.find {id="utilities-glyph-battery-level"}~=nil)
    test.eq(test.ipc("status"),"57%, charging")
    test.ipc("fake-battery","80,limited") test.settle(1000)
    test.eq(test.ipc("status"),"80%, limit reached")
  end)
  test.it(style.." keeps the plain mark on a machine with no battery",function()
    load(style)
    local glyph=test.find {id="utilities-glyph-battery-level",visible=true}
    test.eq(glyph,nil)
    test.eq(test.ipc("status"),"On mains power")
  end)
end
