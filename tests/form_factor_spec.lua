-- The size classes and forms: every kind of output eva runs on lands as what
-- it is, from its logical size, its input devices and its connector.
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=10,height=10}
  local output=morf.env("TEST_OUTPUT")
  if output then
    local name=morf.screens[1].name
    morf.screens=setmetatable({{name=output,width=morf.screens[1].width,height=morf.screens[1].height,
      transform=morf.env("TEST_TRANSFORM") or "normal"}},{__index=morf.screens})
  end
  local R=require("responsive")
  morf.ipc.form=function()
    return {form=R.form(),width=R.width_class(),height=R.height_class(),touch=R.touch(),sheets=R.sheets(),
      phone=R.phone(),target=R.target(),layout=R.layout()}
  end
  morf.ipc.lanes=function() return R.lanes(40) end
  morf.ipc.cutout=function() return R.cutout() end
  morf.ipc.corner=function() return R.corner() end
  morf.ipc.panel=function() return {width=R.panel_width(),height=R.panel_height(1000),anchors=R.panel_anchors()} end
]]
local DEVICES=morf.env("EVA_INPUT_DEVICES")
local function load(w,h,touch,env)
  env=env or {}
  env.EVA_INPUT_DEVICES=touch and DEVICES.."-touch" or DEVICES
  test.load("../shell/init.lua",{source=HOST,size={w,h},env=env})
  return test.ipc("form")
end
local CASES={
  {"a phone upright at its shell scale",868,1932,true,"phone","compact","expanded"},
  {"a phone on its side at its shell scale",1932,868,true,"phone","expanded","compact"},
  {"a phone upright at two times",412,915,true,"phone","compact","expanded"},
  {"a phone on its side at two times",915,412,true,"phone","expanded","compact"},
  {"a phone at its panel's pixels",1116,2484,true,"phone","compact","expanded"},
  {"a phone-shaped output without a touchscreen",868,1932,false,"phone","compact","expanded"},
  {"a wide touchscreen with no keyboard",1280,800,true,"desk","expanded","medium"},
  {"an upright touchscreen too narrow for a desk's sides",800,1280,true,"phone","medium","expanded"},
  {"a small upright touchscreen",600,960,true,"phone","medium","expanded"},
  {"a narrow upright window",500,720,false,"phone","compact","medium"},
  {"a narrow upright screen without a touchscreen",800,1280,false,"phone","medium","expanded"},
  {"a laptop",1280,800,false,"desk","expanded","medium"},
  {"a desk",1920,1080,false,"desk","expanded","expanded"},
  {"an ultrawide",3440,1440,false,"desk","expanded","expanded"},
  {"a monitor stood upright",1080,1920,false,"desk","expanded","expanded"},
  {"a short landscape window",800,480,false,"desk","medium","medium"},
}
for _,case in ipairs(CASES) do
  test.it(case[1].." lands as a "..case[5],function()
    local f=load(case[2],case[3],case[4])
    test.eq({f.form,f.width,f.height},{case[5],case[6],case[7]})
    test.eq(f.sheets,case[5]~="desk")
    test.eq(f.target,case[5]~="desk" and 48 or 40)
  end)
end
test.it("classes change at the sizes the shell promises",function()
  test.eq(load(599,700,false).width,"compact")
  test.eq(load(600,500,false).width,"medium")
  test.eq(load(839,500,false).width,"medium")
  test.eq(load(840,500,false).width,"expanded")
  test.eq(load(700,479,false).height,"compact")
  test.eq(load(700,480,false).height,"medium")
  test.eq(load(700,899,false).height,"medium")
  test.eq(load(700,900,false).height,"expanded")
end)
test.it("a touchscreen is the main input only without a real keyboard",function()
  test.truthy(load(1280,800,true).touch)
  test.falsy(load(1280,800,false).touch)
end)
test.it("a keyboard coming or going changes what the layout is built for, not the form",function()
  local alone,keyed=load(1280,800,true),load(1280,800,false)
  test.eq(alone.form,keyed.form)
  test.truthy(alone.layout~=keyed.layout)
end)
test.it("a docked phone is a desk on its monitor and a phone on its panel",function()
  local monitor=load(1920,1080,true,{TEST_OUTPUT="DP-1"})
  test.eq(monitor.form,"desk") test.falsy(monitor.touch) test.falsy(monitor.sheets)
  local hdmi=load(2560,1440,true,{TEST_OUTPUT="HDMI-A-1"})
  test.eq(hdmi.form,"desk") test.falsy(hdmi.touch)
  local panel=load(868,1932,true,{TEST_OUTPUT="DSI-1"})
  test.eq(panel.form,"phone") test.truthy(panel.touch)
end)
test.it("a rotation changes what the layout is built for",function()
  test.truthy(load(868,1932,true).layout~=load(1932,868,true).layout)
  test.truthy(load(800,1280,true).layout~=load(1280,800,true).layout)
end)
test.it("the sheet is the desk on a phone upright and a panel elsewhere",function()
  load(868,1932,true)
  local phone=test.ipc("panel")
  test.truthy(phone.width>560) test.truthy(phone.anchors.horizontal_center)
  load(800,1280,true)
  local upright=test.ipc("panel")
  test.eq(upright.width,560) test.truthy(upright.anchors.right) test.falsy(upright.anchors.horizontal_center)
  load(1932,868,true)
  test.eq(test.ipc("panel").width,560)
end)
test.it("corners take a phone's share of the bar, and a desk's fixed step",function()
  load(868,1932,true) test.eq(test.ipc("corner"),39)
  load(1920,1080,false) test.eq(test.ipc("corner"),34)
end)
test.it("a cutout splits the bar, or shortens its end, and stays out of a row it misses",function()
  local env={EVA_FAKE_CUTOUT="400,68,34"}
  load(868,1932,true,env)
  local middle=test.ipc("lanes")
  test.eq({middle.gap_from,middle.gap_to},{392,476})
  test.eq({middle.left,middle.right},{39,829})
  load(868,1932,true,{EVA_FAKE_CUTOUT="60,60,34"})
  local left=test.ipc("lanes")
  test.eq(left.left,128) test.eq(left.gap_to,nil)
  load(868,1932,true,{EVA_FAKE_CUTOUT="740,60,34"})
  local right=test.ipc("lanes")
  test.eq(right.right,732) test.eq(right.gap_to,nil)
  load(868,1932,true,{EVA_FAKE_CUTOUT="400,68,44"})
  test.truthy(test.ipc("lanes").gap_to~=nil)
  load(868,1932,true,{EVA_FAKE_CUTOUT="400,68,34",TEST_OUTPUT="DSI-1",TEST_TRANSFORM="90"})
  local turned=test.ipc("cutout")
  test.eq({turned.x,turned.width},{0,34})
end)
