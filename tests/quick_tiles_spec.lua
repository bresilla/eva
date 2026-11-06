-- The quick settings' tile board, in the real shell: what is offered, honest
-- state, the editor by mouse and by touch, how tiles feel, and the phone sheet.
--
--     morf test --no-dbus tests/quick_tiles_spec.lua
local test=morf.test
local SOURCE=[[
  local surfaces={}
  local kit=require("kit")
  local tile_surface=kit.tile_surface
  kit.tile_surface=function(spec)
    local node=tile_surface(spec)
    surfaces[spec.id]=node
    return node
  end
  require("init")
  local config=require("config")
  local utilities=require("utilities")
  local board=utilities.tiles
  morf.ipc.q_shown=function()
    local out={}
    for i,item in ipairs(board.shown()) do out[i]=item.id end
    return out
  end
  morf.ipc.q_spare=function()
    local out={}
    for i,item in ipairs(board.spare()) do out[i]=item.id end
    return out
  end
  morf.ipc.q_saved=function(form) return config.get("quick.tiles."..form) end
  morf.ipc.q_small=function(id) return board.small(id) end
  morf.ipc.q_editing=function() return board.editing:get() end
  morf.ipc.q_detail=function() return utilities.detail:get() end
  morf.ipc.q_radius=function(id) return surfaces["utilities-toggle-"..id.."-shape"].radius end
  morf.ipc.q_light=function(id)
    for _,t in ipairs(utilities.TOGGLES) do if t.id==id then return t.on()==true end end
  end
  morf.ipc.q_status=function(id)
    for _,t in ipairs(utilities.TOGGLES) do if t.id==id then return t.status and t.status() end end
  end
  morf.ipc.q_form=function() return require("responsive").form_factor() end
  morf.ipc.q_tile_set=function(id,on) utilities.CONTROLS[id].set(on) end
  morf.ipc.q_panel=function()
    local d=require("sidebar").drawer
    return {open=d.open:get(),y=d.panel.translate_y,height=d.panel.height,target=d.panel.height_target}
  end
  -- Four fifths of the desk: what a sheet may reach.
  morf.ipc.q_most=function()
    local _,_,_,h=require("bar").desk()
    return math.floor((h-2*require("theme").BORDER)*.8)
  end
]]
local serial=0
local settings
local function load(options)
  options=options or {}
  if not options.keep then
    serial=serial+1
    settings=morf.env("XDG_CACHE_HOME").."/quick-tiles-"..serial..".json"
    morf.fs.remove(settings)
  end
  test.stub_run("task",{code=0,stdout="[]"})
  local env={EVA_DRY_RUN="1",EVA_SETTINGS=settings,EVA_STYLE=options.style or "material",EVA_WALLPAPER="",
    EVA_FONT_FILE="",LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME"),
    EVA_FAKE_HARDWARE=options.fake and "1" or "0"}
  for k,v in pairs(options.env or {}) do env[k]=v end
  test.load("../shell/init.lua",{source=SOURCE,size=options.size or {1600,1000},env=env})
  test.settle(1500)
end
local function open() test.ipc("settings") test.settle(2500) end
local function has(list,id)
  for _,v in ipairs(list) do if v==id then return true end end
  return false
end
local function index_of(list,id)
  for i,v in ipairs(list) do if v==id then return i end end
end
local function edit() open() test.click("utilities-edit") test.settle(1500) end
local function centre(node) return node.x+node.width/2,node.y+node.height/2 end

-- ------------------------------------------------------------- catalogue --

test.it("each kind of machine has its own defaults, and a tile without hardware is not offered",function()
  load()
  test.eq(test.ipc("q_form"),"desk")
  open()
  local shown,spare=test.ipc("q_shown"),test.ipc("q_spare")
  for _,id in ipairs {"hotspot","rotation","nightlight","powersaver","flashlight","mobile","wired","gamemode"} do
    test.falsy(has(shown,id),id.." shown without hardware")
    test.falsy(has(spare,id),id.." offered without hardware")
  end
  test.truthy(has(shown,"wifi")) test.truthy(has(shown,"focus"))
  for _,id in ipairs {"awake","dnd","screenshot","record","keyboard"} do
    test.truthy(has(spare,id),id.." should wait in Available")
  end
  load({size={432,960}})
  test.eq(test.ipc("q_form"),"phone")
  test.truthy(index_of(test.ipc("q_saved","phone"),"flashlight"))
  test.eq(#test.logs("error"),0)
end)

test.it("a wide touchscreen with no keyboard is a desk, with a desk's tiles",function()
  local devices=morf.env("XDG_CACHE_HOME").."/quick-touch-devices"
  morf.fs.write(devices,"N: Name=\"Goodix Capacitive TouchScreen\"\nH: Handlers=event5\nB: PROP=2\nB: EV=b\n")
  load({size={1280,800},fake=true,env={EVA_INPUT_DEVICES=devices}})
  test.eq(test.ipc("q_form"),"desk")
  open()
  local shown=test.ipc("q_shown")
  test.falsy(has(shown,"rotation"),"rotation is no tile of a desk's")
  test.falsy(has(shown,"keyboard"),"the keyboard is no tile of a desk's")
  test.truthy(has(shown,"wifi"))
  test.eq(#test.logs("error"),0)
end)

test.it("with the hardware there every new tile is offered",function()
  load({fake=true})
  open()
  local all={}
  for _,id in ipairs(test.ipc("q_shown")) do all[id]=true end
  for _,id in ipairs(test.ipc("q_spare")) do all[id]=true end
  for _,id in ipairs {"hotspot","rotation","nightlight","powersaver","flashlight","screenshot","record","keyboard",
    "dnd","awake","ringer"} do
    test.truthy(all[id],id.." is not offered")
  end
  test.truthy(test.find{id="utilities-toggle-hotspot",visible=true})
  test.truthy(test.find{id="utilities-more-hotspot",visible=true})
  test.falsy(test.find{id="utilities-toggle-flashlight"},"a tile not shown was built")
  test.eq(#test.logs("error"),0)
end)

-- ---------------------------------------------------------------- honesty --

test.it("lit means active: Eva never lights",function()
  load()
  open()
  test.falsy(test.ipc("q_light","eva"))
  test.eq(#test.logs("error"),0)
end)

test.it("a tile acts on click and its chevron opens the detail",function()
  load({fake=true})
  open()
  test.falsy(test.ipc("q_light","nightlight"))
  test.click("utilities-toggle-nightlight") test.settle(600)
  test.truthy(test.ipc("q_light","nightlight"),"the click did not act")
  test.eq(test.ipc("q_detail"),"")
  test.click("utilities-more-nightlight") test.settle(1500)
  test.eq(test.ipc("q_detail"),"nightlight")
  test.truthy(test.find{id="settings-nightlight-temperature",visible=true})
  test.eq(#test.logs("error"),0)
end)

-- ----------------------------------------------------------------- editing --

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." edit mode hides, adds back, resizes and resets",function()
    load({style=style,size={1600,2400}})
    edit()
    test.truthy(test.ipc("q_editing"))
    test.truthy(test.find{id="utilities-available",visible=true})
    test.truthy(test.find{id="utilities-edit-reset",visible=true})
    test.falsy(test.find{id="utilities-sliders",visible=true},"the sliders stayed under the editor")
    local defaults=test.ipc("q_shown")
    test.click("utilities-hide-bluetooth") test.settle(1200)
    test.falsy(has(test.ipc("q_shown"),"bluetooth"))
    test.truthy(has(test.ipc("q_spare"),"bluetooth"))
    test.truthy(test.find{id="utilities-add-bluetooth",visible=true},"a hidden tile has no way back")
    test.click("utilities-toggle-bluetooth") test.settle(1200)
    local shown=test.ipc("q_shown")
    test.eq(shown[#shown],"bluetooth","added back at the end")
    test.click("utilities-size-wifi") test.settle(1200)
    test.truthy(test.ipc("q_small","wifi"))
    test.click("utilities-size-mic") test.settle(1200)
    local a,b=test.get("utilities-toggle-wifi"),test.get("utilities-toggle-mic")
    test.truthy(a.width<100,"a small tile is half a slot")
    test.click("utilities-edit-reset") test.settle(1500)
    test.eq(test.ipc("q_shown"),defaults)
    test.falsy(test.ipc("q_small","wifi"))
    test.truthy(b.width<100)
    test.click("utilities-edit") test.settle(1500)
    test.falsy(test.ipc("q_editing"))
    test.truthy(test.find{id="utilities-sliders",visible=true})
    test.falsy(test.find{id="utilities-available",visible=true})
    test.falsy(test.find{id="utilities-hide-wifi",visible=true})
    test.eq(#test.logs("error"),0)
  end)
end

test.it("two small tiles share a slot, and neither has a chevron",function()
  load()
  edit()
  test.click("utilities-size-wifi") test.settle(800)
  test.click("utilities-size-bluetooth") test.settle(1500)
  local a,b=test.get("utilities-toggle-wifi"),test.get("utilities-toggle-bluetooth")
  test.near(a.y,b.y,.5,"not on one row")
  test.near(b.x-a.x,a.width+8,.5,"not side by side")
  test.click("utilities-edit") test.settle(1500)
  test.falsy(test.find{id="utilities-more-wifi",visible=true},"a small tile kept its chevron")
  test.click("utilities-toggle-wifi") test.settle(400)
  test.eq(#test.logs("error"),0)
end)

test.it("a long press on a small tile opens what its chevron would",function()
  load({fake=true})
  edit()
  test.click("utilities-size-nightlight") test.settle(800)
  test.click("utilities-edit") test.settle(1200)
  test.falsy(test.find{id="utilities-more-nightlight",visible=true})
  local x,y=centre(test.get("utilities-toggle-nightlight"))
  test.move(x,y) test.press(x,y) test.advance(700) test.release(x,y) test.settle(1500)
  test.eq(test.ipc("q_detail"),"nightlight","a long press did not open the page")
  test.falsy(test.ipc("q_light","nightlight"),"a long press also toggled it")
  test.eq(#test.logs("error"),0)
end)

test.it("a mouse drag rearranges, on a spring, without building anything",function()
  load()
  edit()
  local before=test.ipc("q_shown")
  local handle=test.get("utilities-toggle-bluetooth").handle
  local wifi=test.get("utilities-toggle-wifi")
  local mic=test.get("utilities-toggle-mic")
  local x,y=centre(wifi)
  local tx,ty=centre(mic)
  test.press(x,y)
  for i=1,12 do test.move(x+(tx-x)*i/12,y+(ty-y)*i/12) test.advance(16) end
  local during=test.ipc("q_shown")
  test.eq(during[index_of(before,"mic")],"wifi","the carried tile did not take its place")
  test.release(tx,ty)
  test.settle(1500)
  test.eq(test.ipc("q_shown"),during)
  test.eq(test.ipc("q_saved","desk")[1]~="wifi",true)
  test.eq(test.get("utilities-toggle-bluetooth").handle,handle,"the tile was built again")
  test.eq(#test.logs("error"),0)
end)

test.it("rearranging travels: a tile sets out from where it stood",function()
  load()
  edit()
  local bluetooth=test.get("utilities-toggle-bluetooth")
  test.click("utilities-hide-wifi")
  test.advance(32)
  local moving=test.get("utilities-toggle-bluetooth")
  test.truthy(moving.x<bluetooth.x and moving.x>bluetooth.x-180,"it jumped: "..moving.x)
  test.settle(1500)
  test.truthy(test.get("utilities-toggle-bluetooth").x<moving.x)
  test.eq(#test.logs("error"),0)
end)

test.it("a finger drag rearranges too, and a finger on a tile at rest scrolls",function()
  load({size={620,1000},fake=true})
  test.eq(test.ipc("q_form"),"phone")
  edit()
  local before=test.ipc("q_shown")
  local first=test.get("utilities-toggle-"..before[1])
  local third=test.get("utilities-toggle-"..before[3])
  local x,y=centre(first)
  local tx,ty=centre(third)
  test.touch("down",0,x,y) test.advance(16)
  for i=1,16 do test.touch("move",0,x+(tx-x)*i/16,y+(ty-y)*i/16) test.advance(16) end
  test.touch("up",0,tx,ty) test.settle(1500)
  local after=test.ipc("q_shown")
  test.truthy(after[1]~=before[1],"the finger did not carry the tile")
  test.falsy(test.ipc("q_detail")~="","the press opened something")
  test.click("utilities-edit") test.settle(1500)
  test.eq(#test.logs("error"),0)
end)

test.it("a finger drag on a tile outside edit mode does not move it",function()
  load({size={620,1000},fake=true})
  open()
  local before=test.ipc("q_shown")
  local tile=test.get("utilities-toggle-"..before[1])
  local x,y=centre(tile)
  test.touch("down",0,x,y) test.advance(16)
  for i=1,14 do test.touch("move",0,x+i*8,y) test.advance(16) end
  test.touch("up",0,x+112,y) test.settle(1000)
  test.eq(test.ipc("q_shown"),before)
  test.eq(#test.logs("error"),0)
end)

test.it("Alt with the arrows walks a tile by keyboard",function()
  load()
  edit()
  local before=test.ipc("q_shown")
  local focused
  for _=1,24 do
    test.key("Tab") test.advance(16)
    focused=test.find(function(n) return n.focused and (n.id or ""):match("^utilities%-tile%-") end)
    if focused then break end
  end
  test.truthy(focused,"Tab never reached a tile")
  local id=focused.id:match("^utilities%-tile%-(.+)$")
  local from=index_of(before,id)
  test.key("Right","alt") test.settle(300)
  test.eq(index_of(test.ipc("q_shown"),id),from+1,"the tile did not step on")
  test.key("Left","alt") test.settle(300)
  test.eq(test.ipc("q_shown"),before)
  test.eq(#test.logs("error"),0)
end)

test.it("shutting the panel leaves edit mode",function()
  load()
  edit()
  test.ipc("sidebar","close") test.settle(1000)
  test.falsy(test.ipc("q_editing"))
  test.eq(#test.logs("error"),0)
end)

test.it("an edit is saved, and the next start shows it",function()
  load()
  edit()
  test.click("utilities-hide-tunnel") test.settle(800)
  test.click("utilities-size-mic") test.settle(800)
  test.falsy(has(test.ipc("q_saved","desk"),"tunnel"))
  test.click("utilities-edit") test.settle(800)
  test.falsy(test.find{id="utilities-toggle-tunnel",visible=true})
  load({keep=true})
  open()
  test.falsy(has(test.ipc("q_shown"),"tunnel"),"the hidden tile came back")
  test.truthy(test.ipc("q_small","mic"),"the size was forgotten")
  test.truthy(test.get("utilities-toggle-mic").width<100)
  test.eq(#test.logs("error"),0)
end)

-- -------------------------------------------------------------------- feel --

test.it("a Material tile is a pill off and rounded on, its press on a quicker spring than its state",function()
  load()
  open()
  test.near(test.ipc("q_radius","wifi"),30,.5,"off is a pill")
  local tile=test.get("utilities-toggle-airplane")
  local x,y=centre(tile)
  test.move(x,y)
  test.press(x,y)
  test.advance(48)
  local pressed_early=test.ipc("q_radius","airplane")
  test.truthy(pressed_early<30,"a press did not reach the shape")
  test.advance(300)
  test.truthy(test.ipc("q_radius","airplane")<20,"a press did not settle tight")
  test.release(x,y)
  test.advance(16)
  test.settle(1200)
  test.near(test.ipc("q_radius","airplane"),16,1,"on is a rounded rectangle")
  test.click("utilities-toggle-airplane") test.advance(32)
  local changing=test.ipc("q_radius","airplane")
  test.truthy(changing<28,"state change jumped: "..changing)
  test.settle(1200)
  test.near(test.ipc("q_radius","airplane"),30,.5,"off again is a pill")
  test.eq(#test.logs("error"),0)
end)

test.it("Tsugumori tiles keep their corners and react with a wash that runs out",function()
  load({style="tsugumori"})
  open()
  local tile=test.get("utilities-toggle-airplane")
  local wash=function() return test.find("utilities-toggle-airplane-shape-wash").width end
  test.near(wash(),0,.5,"an off tile has no wash")
  test.click("utilities-toggle-airplane") test.advance(32)
  local running=wash()
  test.truthy(running>0 and running<tile.width,"the wash did not run: "..running)
  test.settle(800)
  test.near(wash(),tile.width,1,"the wash stopped short")
  test.truthy(test.ipc("q_light","airplane"))
  test.click("utilities-toggle-airplane") test.settle(800)
  test.near(wash(),0,.5,"the wash did not run back")
  test.eq(#test.logs("error"),0)
end)

-- ------------------------------------------------------------------- sheet --

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." the phone sheet fits its content, its pages opening in the window",function()
    load({style=style,size={620,1380}})
    test.ipc("sidebar","open","settings") test.settle(2500)
    local sheet=test.get("drawer-sidebar")
    local full=test.ipc("q_most")
    test.truthy(sheet.height<full,"the sheet kept its dead area: "..sheet.height)
    local card=test.get("utilities-toggles")
    test.truthy(card.y+card.height<=sheet.y+sheet.height,"the sheet cuts its tiles")
    test.truthy(sheet.y+sheet.height-(card.y+card.height)<=40,"dead area under the tiles: "
      ..(sheet.y+sheet.height-card.y-card.height))
    test.ipc("settings","theme") test.settle(2500)
    local detail=test.get("settings-detail")
    local last=test.get("settings-theme-lule")
    test.truthy(last.y+last.height<=detail.y+detail.height,"the window cuts the page")
    test.ipc("settings","close") test.ipc("sidebar","open","settings") test.settle(2500)
    test.near(test.get("drawer-sidebar").height,sheet.height,1)
    test.eq(#test.logs("error"),0)
  end)
end

test.it("a first pull shrinks the sheet to its page on a spring, and it stays open",function()
  load({size={1116,2484}})
  test.touch("down",0,558,4) test.advance(400)
  test.touch("move",0,558,1500)
  local lowest=math.huge
  for _=1,30 do
    test.advance(16)
    lowest=math.min(lowest,test.ipc("q_panel").height)
  end
  test.touch("up",0,558,1500) test.advance(800)
  local panel=test.ipc("q_panel")
  test.truthy(panel.open,"a slow pull past the sheet's height shut it")
  test.near(panel.y,0,1)
  test.truthy(lowest>panel.target*.7,"the sheet folded on its way: "..lowest)
  test.eq(#test.logs("error"),0)
end)

test.it("a phone's sheet with more than fits stops at four fifths and scrolls",function()
  load({size={500,700},fake=true})
  test.ipc("sidebar","open","settings") test.settle(2500)
  test.near(test.get("drawer-sidebar").height,test.ipc("q_most"),1)
  test.eq(#test.logs("error"),0)
end)

-- Every shown node's box and opacity, as one string, less a title's finite
-- light pulses (`*-light`).
local function at_rest()
  local parts={}
  for _,n in ipairs(test.nodes()) do
    if n.visible and not (n.id or ""):match("%-light$") then
      parts[#parts+1]=("%s:%.2f,%.2f,%.2f,%.2f,%.3f"):format(n.handle,n.x,n.y,n.width,n.height,n.opacity or 1)
    end
  end
  return table.concat(parts,";")
end
for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." nothing moves at rest, open or being edited",function()
    load({style=style,fake=true})
    open()
    test.settle(2000)
    local still=at_rest()
    test.advance(1000)
    test.truthy(at_rest()==still,"the open page moves at rest")
    test.click("utilities-edit") test.settle(3000)
    still=at_rest()
    test.advance(1000)
    test.truthy(at_rest()==still,"the editor moves at rest")
    test.eq(#test.logs("error"),0)
  end)
end

test.it("a desk keeps its panel width",function()
  load()
  open()
  test.eq(test.get("drawer-sidebar").width,450)
  test.eq(#test.logs("error"),0)
end)
