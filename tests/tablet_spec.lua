-- Phones on their sides and tablets either way, in the real shell: each panel
-- lands whole on the screen, from the edge its form gives it, and every tab of
-- the dashboard fits.
local test=morf.test
local DEVICES=morf.env("EVA_INPUT_DEVICES")
local SOURCE=[[
  require("init")
  morf.ipc.drawers=function()
    local out={}
    for _,d in ipairs(require("drawer").all) do out[d.name]=d.edge end
    return out
  end
  morf.ipc.open=function(name) require(name).drawer.set(true) end
  morf.ipc.shut=function() require("drawer").close_all() end
  morf.ipc.tab=function(i) require("dashboard").tab:set(tonumber(i)) end
  morf.ipc.form=function() return require("responsive").form() end
  morf.ipc.bar=function() return {on=require("bar").on(),rail=require("rail").geometry().bottom} end
]]
local function load(style,w,h)
  test.stub_run("task",{code=0,stdout="[]"})
  test.load("../shell/init.lua",{source=SOURCE,size={w,h},env={EVA_STYLE=style,EVA_DRY_RUN="1",EVA_WALLPAPER="",
    EVA_INPUT_DEVICES=DEVICES.."-touch",HOME=morf.env("XDG_CACHE_HOME")}})
  test.settle(2000)
end
local function whole(id,W,H)
  local node=test.get(id)
  test.truthy(node.x>=-0.5 and node.y>=-0.5 and node.x+node.width<=W+0.5 and node.y+node.height<=H+0.5,
    ("%s falls off: %s,%s %sx%s"):format(id,node.x,node.y,node.width,node.height))
  return node
end
local CASES={
  {"a tablet held upright",800,1280,"tablet"},
  {"a tablet held wide",1280,800,"tablet"},
  {"a phone on its side",1932,868,"phone"},
}
for _,style in ipairs {"material","tsugumori"} do
  for _,case in ipairs(CASES) do
    local name,W,H,form=case[1],case[2],case[3],case[4]
    test.it(style.." "..name.." has its bar, a sheet from the top and the dashboard from the bottom",function()
      load(style,W,H)
      test.eq(test.ipc("form"),form)
      test.truthy(test.ipc("bar").on)
      local edges=test.ipc("drawers")
      test.eq(edges.sidebar,"top") test.eq(edges.dashboard,"bottom")
      test.eq(#test.logs("error"),0)
    end)
    test.it(style.." "..name.." keeps the sheet whole, at a panel's size in the corner",function()
      load(style,W,H)
      test.ipc("open","sidebar") test.settle(2000)
      local sheet=whole("drawer-sidebar",W,H)
      test.truthy(sheet.width<=560)
      test.near(sheet.x+sheet.width,W,20)
      test.truthy(sheet.y<=60,"it hangs from under the status")
      test.eq(#test.logs("error"),0)
    end)
    test.it(style.." "..name.." keeps every dashboard tab whole",function()
      load(style,W,H)
      test.ipc("open","dashboard") test.settle(2000)
      for i=1,6 do
        test.ipc("tab",i) test.settle(2000)
        whole("drawer-dashboard",W,H)
      end
      test.eq(#test.logs("error"),0)
    end)
  end
end
