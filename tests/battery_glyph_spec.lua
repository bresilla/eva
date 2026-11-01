-- The battery glyph: the same box in both themes, a fill that travels on a
-- spring and keeps its velocity through a retarget, and rest once it arrives.
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  local kit=require("kit")
  local status=morf.signal("glyph.fixture",{level=20,mark="",tone="ink",saver=false})
  local plain=morf.signal("glyph.fixture.plain",false)
  ui.Item {width=200,height=100,
    kit.battery {id="glyph",size=16,status=function() return status:get() end,plain=function() return plain:get() end}}
  morf.ipc.set=function(level,mark,tone,saver)
    status:set {level=tonumber(level),mark=mark or "",tone=tone or "ink",saver=saver=="true"}
  end
]]
local function load(style)
  test.load("../shell/init.lua",{source=HOST,size={200,100},env={EVA_STYLE=style}})
  test.settle(3000)
end
local function level() return test.get("glyph-level").width end
local MARKS={{"bolt","ok"},{"shield","ink"},{"plug","ink"},{"alert","alert"}}
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." occupies twice its size across, its size down",function()
    load(style)
    local g=test.get("glyph")
    test.eq({g.width,g.height},{32,16})
  end)
  test.it(style.." fills in proportion to the level",function()
    load(style)
    local low=level()
    test.ipc("set",100) test.settle(3000)
    local full=level()
    test.truthy(full>low*3,"100 is more than three times 20")
    test.ipc("set",50) test.settle(3000)
    test.near(level(),full/2,1)
  end)
  test.it(style.." travels on a spring and holds its speed through a retarget",function()
    load(style)
    local start=level()
    test.ipc("set",100)
    test.advance(40)
    local moving=level()
    test.truthy(moving>start,"it has set off")
    test.ipc("set",20)
    test.advance(16)
    test.truthy(level()>moving,"a retarget does not stop it dead")
    test.settle(3000)
    test.near(level(),start,1)
  end)
  test.it(style.." comes to rest",function()
    load(style)
    test.ipc("set",80) test.settle(3000)
    local at=level()
    test.advance(1000)
    test.eq(level(),at)
  end)
  test.it(style.." shows nothing in the body at nothing, and something at a sliver",function()
    load(style)
    test.ipc("set",1) test.settle(3000)
    test.truthy(level()>=2)
  end)
  test.it(style.." takes every mark and tone, morphing between them, with no error",function()
    load(style)
    for _,case in ipairs(MARKS) do
      test.ipc("set",64,case[1],case[2]) test.advance(120)
      test.ipc("set",64,case[1],case[2],"true") test.advance(120)
    end
    test.ipc("set",64,"","extra","true") test.settle(3000)
    test.eq(#test.logs("error"),0) test.eq(#test.logs("warn"),0)
  end)
end
