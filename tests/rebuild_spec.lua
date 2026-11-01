-- A change of layout rebuilds the output in place: a keyboard docked on a
-- tablet here, as a turn of the screen does, and what was open stays open.
local test=morf.test
local DEVICES=morf.env("EVA_INPUT_DEVICES")
local DOCK=[[
  local docked=false
  local changed
  package.loaded["models.keyboards"]={attached=function() return docked end}
  morf.udev={subscribe=function(_,fn) changed=fn end}
  local reloads=0
  morf.reload=function() reloads=reloads+1 end
  require("init")
  morf.ipc.open=function()
    require("sidebar").select(2) require("dashboard").tab:set(2) require("sidebar").drawer.set(true)
  end
  morf.ipc.dock=function() docked=true changed() end
  morf.ipc.state=function()
    return {open=require("sidebar").drawer.open:get(),tab=require("sidebar").tab:get(),
      dashboard=require("dashboard").tab:get(),reloads=reloads}
  end
]]
test.it("a tab kept past the end of a panel with fewer falls back to the first",function()
  test.load("../shell/init.lua",{size={400,300},source=[[
    local ui=require("morf.ui")
    ui.Item {width=10,height=10}
    require("themes.session").keep("eva.narrow.tab",1):set(6)
    local model=require("side_panel_model").new {id="narrow",edge="right",tabs={{key="a"},{key="b"}}}
    morf.ipc.tab=function() return model.tab:get() end
  ]]})
  test.eq(test.ipc("tab"),1)
end)
test.it("a keyboard docked rebuilds the output, and what was open stays open",function()
  test.stub_run("task",{code=0,stdout="[]"})
  test.load("../shell/init.lua",{size={1280,800},env={EVA_DRY_RUN="1",EVA_WALLPAPER="",EVA_INPUT_DEVICES=DEVICES.."-touch",
    HOME=morf.env("XDG_CACHE_HOME")},source=DOCK})
  test.settle(2000)
  test.ipc("open") test.settle(2000)
  test.ipc("dock") test.settle(500)
  test.eq(test.ipc("state").reloads,1)
  test.truthy(test.reload {source=DOCK}) test.settle(2000)
  local s=test.ipc("state")
  test.truthy(s.open) test.eq(s.tab,2) test.eq(s.dashboard,2)
end)
