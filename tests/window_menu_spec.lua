local test=morf.test
local SOURCE=[[
  local hypr=require("lib.integrations.hyprland")
  local evals={}
  hypr.eval=function(chunk,cb) evals[#evals+1]=chunk if cb then cb("ok") end return true end
  package.loaded["lib.integrations.hyprland_config"]={flavour=function(cb) cb("lua") end}
  hypr.state.clients={{address="0xabc",class="kitty",title="~/code",workspace=2,workspace_name="2",monitor=0,
    x=400,y=200,width=800,height=500,floating=false,pinned=false,fullscreen=0,pid=4242,xwayland=false}}
  hypr.state.active_window.address="0xabc" hypr.state.active_window.class="kitty"
  require("init")
  morf.ipc.menu_state=function()
    local m=require("window_menu")
    return {open=m.opened:get(),slot=m.slot:get(),branch=m.branch:get(),sub=m.sub:get(),column=m.column:get(),
      action=m.action:get(),evals=evals,actions=#m.actions()}
  end
  morf.ipc.no_window=function() hypr.state.active_window.address="" end
]]
local function load(style)
  test.load("../shell/init.lua",{source=SOURCE,size={1600,1000},env={EVA_STYLE=style}})
  test.advance(200)
end
local function state() return test.ipc("menu_state") end
local function shot(name) if morf.env("MORF_THEME_SNAPSHOTS")=="1" then test.snapshot(name..".png") end end
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." the window menu opens over the focused window and runs its actions",function()
    load(style)
    test.eq(test.ipc("window_menu","open"),true) test.advance(700)
    test.truthy(state().open)
    local box,card=test.get("window-menu"),test.get("window-menu-card-center")
    test.near(box.x+box.width/2,800,2,"not over the window")
    test.truthy(card.visible)
    shot(style.."-window-menu")
    test.key("Up") test.advance(100) test.eq(state().slot,"top") test.falsy(state().branch)
    test.key("Up") test.advance(900) test.truthy(state().branch)
    shot(style.."-window-menu-layout")
    test.eq(state().actions,4)
    test.key("Right") test.key("Down") test.key("Return") test.advance(100)
    local evals=state().evals
    test.truthy(evals[#evals]:find('hl.dsp.window.fullscreen({ mode = "fullscreen", window = "address:0xabc" })',1,true),evals[#evals])
    test.truthy(state().open,"a toggle shuts the menu")
    test.key("Escape") test.eq(state().column,"subs")
    test.key("Escape") test.advance(600) test.falsy(state().branch)
    test.key("Down") test.key("Left") test.advance(100) test.eq(state().slot,"left")
    test.key("Return") test.advance(900)
    test.key("Right") test.key("Down") test.key("Down") test.key("Return") test.advance(100)
    evals=state().evals
    test.truthy(evals[#evals]:find('hl.dsp.window.move({ follow = true, window = "address:0xabc", workspace = "3" })',1,true),evals[#evals])
    test.falsy(state().open)
    test.eq(#test.logs("error"),0) test.eq(#test.logs("warn"),0)
  end)
end
test.it("a press off the cards shuts it, and without a window it does not open",function()
  load("material")
  test.ipc("window_menu","open") test.advance(700)
  test.click(40,960) test.advance(100)
  test.falsy(state().open)
  test.ipc("no_window") test.advance(16)
  test.eq(test.ipc("window_menu","open"),false)
  test.falsy(state().open)
end)
