-- The bar's board, in the real shell: modules added, removed and ordered per zone
-- and per form, by IPC and by hand on the Bar page, and each screen's own say.
--
--     morf test --no-dbus tests/bar_board_spec.lua
local test=morf.test
local SOURCE=[[
  require("init")
  local config=require("config")
  local bar=require("bar")
  morf.ipc.q_saved=function(form,zone) return config.get("bar.modules."..form.."."..zone) end
  morf.ipc.q_set=function(key,value) config.set(key,value) return true end
  morf.ipc.q_on=function() return bar.on() end
  morf.ipc.q_store=function(call,...) return require("bar_store")[call](...) end
  morf.ipc.q_form=function() return require("responsive").form() end
  morf.ipc.q_run=function(code) return load(code)() end
]]
local serial=0
local function load(options)
  options=options or {}
  serial=serial+1
  local settings=morf.env("XDG_CACHE_HOME").."/bar-board-"..serial..".json"
  morf.fs.remove(settings)
  test.stub_run("task",{code=0,stdout="[]"})
  local env={EVA_DRY_RUN="1",EVA_SETTINGS=settings,EVA_STYLE=options.style or "material",EVA_WALLPAPER="",
    EVA_FONT_FILE="",LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME")}
  for k,v in pairs(options.env or {}) do env[k]=v end
  test.load("../shell/init.lua",{source=SOURCE,size=options.size or {1600,1000},env=env})
  test.settle(1500)
  test.ipc("bar","show","on") test.settle(1200)
end
local function modules() return test.ipc("bar","modules") end
local function has(list,id)
  for _,v in ipairs(list) do if v==id then return true end end
  return false
end
local function up(id)
  local node=test.find {id=id,visible=true}
  return node~=nil and node.width>0.5 and node.height>0.5
end

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." starts as the bar always stood",function()
    load {style=style}
    test.truthy(up("bar-logo")) test.truthy(up("bar-clock")) test.truthy(up("bar-status"))
    test.truthy(up("bar-module-workspaces"))
    test.eq(#test.logs("error"),0)
  end)
  test.it(style.." adds, moves between zones and removes a module",function()
    load {style=style}
    test.falsy(up("bar-module-cpu"))
    test.truthy(test.ipc("bar","add","cpu","start")) test.settle(900)
    test.truthy(up("bar-module-cpu"))
    test.truthy(has(modules().start,"cpu"))
    local at=test.get("bar-module-cpu").x
    test.truthy(at<800,"at the start of the row")
    test.truthy(test.ipc("bar","move","cpu",1,"end")) test.settle(900)
    test.truthy(has(modules()["end"],"cpu")) test.falsy(has(modules().start,"cpu"))
    test.truthy(test.get("bar-module-cpu").x>800,"along to the end")
    test.ipc("bar","remove","cpu") test.settle(900)
    test.falsy(up("bar-module-cpu")) test.truthy(has(modules().spare,"cpu"))
    test.eq(#test.logs("error"),0)
  end)
end

test.it("keeps a list per form",function()
  load {}
  test.ipc("bar","add","memory","centre") test.advance(300)
  test.truthy(has(test.ipc("q_saved","desk","centre"),"memory"))
  test.falsy(has(test.ipc("q_saved","phone","centre"),"memory"))
end)

test.it("draws a small module as its icon alone",function()
  load {}
  test.ipc("bar","add","load","end") test.settle(900)
  local wide=test.get("bar-slot-load").width
  test.truthy(test.ipc("bar","small","load")) test.settle(900)
  test.truthy(test.get("bar-slot-load").width<wide-8)
end)

test.it("resets a form to its own modules",function()
  load {}
  test.ipc("bar","remove","logo") test.ipc("bar","add","cpu") test.advance(300)
  test.ipc("bar","reset") test.settle(900)
  test.truthy(has(modules().start,"logo")) test.falsy(has(modules()["end"],"cpu"))
end)

test.it("skips what the machine lacks, and offers it no tile",function()
  load {}
  test.falsy(has(modules().spare,"brightness"))
  test.falsy(has(modules().spare,"gamemode"))
end)

test.describe("the Bar page",function()
  local function open(options)
    load(options)
    test.ipc("settings","bar") test.settle(2500)
  end
  -- The page wheeled until `id` stands on the screen.
  local function reach(id)
    for _=1,60 do
      local node=test.find {id=id,visible=true}
      if node and node.y>160 and node.y+node.height<960 then return node end
      test.wheel(0,120,{x=1450,y=500}) test.advance(200)
    end
    return test.get(id)
  end
  test.it("shows the zones and what is available, in the quick tiles' board",function()
    open {}
    test.truthy(test.find {id="bar-board-tile-logo"}~=nil)
    test.truthy(test.find {id="bar-board-zone-start"}~=nil) test.truthy(test.find {id="bar-board-zone-end"}~=nil)
    test.truthy(test.find {id="bar-board-available"}~=nil)
    test.truthy(test.find {id="bar-board-edit-reset"}~=nil)
    test.eq(#test.logs("error"),0)
  end)
  test.it("hides a module with its badge and adds it back",function()
    open {}
    test.click(reach("bar-board-hide-clock")) test.settle(1500)
    test.truthy(has(modules().spare,"clock"))
    test.falsy(up("bar-clock"))
    test.click(reach("bar-board-add-clock")) test.settle(1500)
    test.truthy(has(modules()["end"],"clock"))
    test.truthy(up("bar-clock"))
  end)
  local function centre(node) return node.x+node.width/2,node.y+node.height/2 end
  local function index_of(list,id)
    for i,v in ipairs(list) do if v==id then return i end end
  end
  test.it("drags a module along its zone, as the quick tiles drag",function()
    open {}
    local logo=reach("bar-board-toggle-logo")
    local windows=reach("bar-board-toggle-windows")
    logo=test.get("bar-board-toggle-logo")
    local x,y=centre(logo)
    local tx,ty=centre(windows)
    test.press(x,y)
    for i=1,12 do test.move(x+(tx-x)*i/12,y+(ty-y)*i/12) test.advance(16) end
    test.release(tx,ty) test.settle(1500)
    test.truthy(index_of(modules().start,"logo")>1,"it did not move")
    test.eq(#test.logs("error"),0)
  end)
  test.it("drags a module across into another zone, and the bar follows",function()
    open {}
    local logo=reach("bar-board-toggle-logo")
    local target=test.get("bar-board-toggle-clock")
    if target.y+target.height>960 then
      test.wheel(0,120,{x=1450,y=500}) test.advance(300)
      logo=test.get("bar-board-toggle-logo") target=test.get("bar-board-toggle-clock")
    end
    local x,y=centre(logo)
    local tx,ty=centre(target)
    test.press(x,y)
    for i=1,16 do test.move(x+(tx-x)*i/16,y+(ty-y)*i/16) test.advance(16) end
    test.release(tx,ty) test.settle(1500)
    test.truthy(index_of(modules().centre,"logo")~=nil,"it stayed in the start")
    test.eq(index_of(modules().start,"logo"),nil)
    test.truthy(test.get("bar-logo").x>200,"the bar did not follow")
    test.eq(#test.logs("error"),0)
  end)
  test.it("steps a module along, on into the next zone and back, as Alt and the arrows do",function()
    open {}
    local function step(delta)
      return test.ipc("q_run",("return require('bar').model.board.step('logo',%d)"):format(delta))
    end
    test.truthy(step(1)) test.eq(index_of(modules().start,"logo"),2)
    test.truthy(step(1)) test.eq(index_of(modules().start,"logo"),3)
    test.truthy(step(1)) test.eq(index_of(modules().centre,"logo"),1,"it did not cross into the centre")
    test.truthy(step(-1)) test.eq(index_of(modules().start,"logo"),3,"it did not cross back")
  end)
  test.it("stops at the ends of the board",function()
    open {}
    test.falsy(test.ipc("q_run","return require('bar').model.board.step('logo',-1)"))
    test.eq(index_of(modules().start,"logo"),1)
  end)
  test.it("sets the clock, the height and the percentage from its sections",function()
    open {}
    test.truthy(test.find {id="bar-clock-seconds"}~=nil)
    test.truthy(test.find {id="bar-date-iso"}~=nil)
    test.click(reach("bar-height-48")) test.settle(1200)
    test.eq(test.ipc("q_run",[[return require('bar').insets().top]]),48)
    test.click(reach("bar-height-0")) test.settle(1200)
    test.eq(test.ipc("q_run",[[return require('bar').insets().top]]),40)
    test.truthy(test.find {id="bar-percent-switch"}~=nil)
  end)
  test.it("types a module's details into the settings",function()
    open {}
    local field=test.find {id="bar-detail-bar-text"}
    test.truthy(field~=nil)
    test.ipc("q_run",[[require('config').set('bar.text','Hello') return true]]) test.advance(100)
    test.truthy(test.ipc("q_run",[[
      for _,row in ipairs(require('bar').model.board.spare()) do if row.id=='text' then return true end end
      return false
    ]]),"the Text module is offered once it has words")
  end)
end)

test.it("offers the bar's own settings on a right press of the bare bar",function()
  load {}
  test.click(700,4,{button="right"}) test.advance(300)
  test.truthy(test.find {text="Arrange the bar",visible=true}~=nil)
end)

test.it("hides the percentage by the setting, but never a low battery's",function()
  load {env={EVA_FAKE_BATTERY="57"}}
  test.truthy(up("bar-percent"))
  test.ipc("q_set","bar.percent",false) test.settle(900)
  test.falsy(up("bar-percent"))
  test.ipc("fake-battery","12") test.settle(900)
  test.truthy(up("bar-percent"))
end)

test.describe("each screen",function()
  test.it("can keep the bar down or up against the setting",function()
    load {}
    local name=test.ipc("q_store","output")
    test.truthy(test.ipc("q_on"))
    test.ipc("q_store","set_on",name,"off") test.advance(300)
    test.falsy(test.ipc("q_on")) test.eq(test.ipc("bar","show","on"),false)
    test.ipc("q_store","set_on",name,"") test.advance(300)
    test.truthy(test.ipc("q_on"))
    test.ipc("bar","show","off") test.advance(300)
    test.ipc("q_store","set_on",name,"on") test.advance(300)
    test.truthy(test.ipc("q_on"))
  end)
  test.it("keeps modules of its own, apart from the form's",function()
    load {}
    local name=test.ipc("q_store","output")
    test.ipc("q_store","set_own",name,true,"desk") test.advance(300)
    test.truthy(test.ipc("q_store","own",name))
    test.ipc("bar","add","cpu","start") test.settle(900)
    test.truthy(has(modules().start,"cpu"))
    test.falsy(has(test.ipc("q_saved","desk","start"),"cpu"),"the form's list stands")
    test.truthy(up("bar-module-cpu"))
    test.ipc("q_store","set_own",name,false,"desk") test.settle(900)
    test.falsy(has(modules().start,"cpu"))
    test.falsy(up("bar-module-cpu"))
  end)
  test.it("leaves another screen's row alone",function()
    load {}
    test.ipc("q_store","set_on","DP-9","off") test.advance(300)
    test.truthy(test.ipc("q_on"))
    test.eq(test.ipc("q_store","on","DP-9"),"off")
  end)
end)

test.it("a phone takes the same modules, on a board of its own",function()
  load {size={868,1932},env={EVA_INPUT_DEVICES=morf.env("EVA_INPUT_DEVICES").."-touch"}}
  test.eq(test.ipc("q_form"),"phone")
  test.ipc("bar","add","cpu","start") test.settle(900)
  test.truthy(up("bar-module-cpu"))
  test.truthy(has(test.ipc("q_saved","phone","start"),"cpu"))
  test.falsy(has(test.ipc("q_saved","desk","start"),"cpu"))
end)
