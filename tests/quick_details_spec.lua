-- The quick controls' own pages, in the real shell, dry: a tile's chevron opens
-- its page inside the panel, More settings and a page's deeper rows open the
-- Settings window, the panel and the window each build their own copy of a
-- page, and what leads to a quick control's page reaches the panel.
--
--     morf test --no-dbus tests/quick_details_spec.lua
local test=morf.test
local SOURCE=[[
  require("init")
  local utilities=require("utilities")
  morf.ipc.q_state=function()
    return {panel=require("pages").on_show("settings"),quick=utilities.in_panel.detail:get(),
      window=utilities.opened:get(),page=utilities.detail:get(),keys=morf.surface.keyboard_focus}
  end
  morf.ipc.q_module=function(id)
    for _,module in ipairs(require("bar_modules").list(require("bar").model)) do
      if module.id==id then module.press() return true end
    end
    return false
  end
  morf.ipc.q_reach=function(key) return utilities.reach(key) end
  morf.ipc.q_search=function(id) return require("lib.shell.launcher.search_index").get(id).run() end
  morf.ipc.q_keys=function() return require("quick_details").KEYS end
]]
local serial=0
local function load(options)
  options=options or {}
  serial=serial+1
  local settings=morf.env("XDG_CACHE_HOME").."/quick-details-"..serial..".json"
  morf.fs.remove(settings)
  test.stub_run("task",{code=0,stdout="[]"})
  test.load("../shell/init.lua",{source=SOURCE,size=options.size or {1600,2000},env={EVA_DRY_RUN="1",
    EVA_SETTINGS=settings,EVA_STYLE=options.style or "material",EVA_WALLPAPER="",EVA_FONT_FILE="",
    LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME"),EVA_FAKE_HARDWARE="1"}})
  test.settle(1500)
  test.ipc("settings") test.settle(2500)
end
local function state() return test.ipc("q_state") end

-- Whether `node` stands inside the node whose id is `id`.
local function inside(node,id)
  local by={}
  for _,n in ipairs(test.nodes()) do by[n.handle]=n end
  local at=node
  while at do
    if at.id==id then return true end
    at=at.parent and by[at.parent] or nil
  end
  return false
end

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." every quick control's page opens inside the panel, with More settings",function()
    load({style=style})
    for _,key in ipairs(test.ipc("q_keys")) do
      local said=test.ipc("quick",key) test.settle(900)
      test.eq(said.page,key)
      test.truthy(state().panel,key.." shut the panel")
      test.falsy(state().window,key.." opened the Settings window")
      test.truthy(test.find{id="quick-detail-"..key,visible=true},key.." is not on show")
      test.truthy(test.find{id="quick-more",visible=true},key.." has no More settings")
      test.truthy(test.find{id="quick-back",visible=true},key.." has no way back")
    end
    test.ipc("quick","home") test.settle(900)
    test.falsy(test.find{id="quick-more",visible=true},"More settings over the tiles")
    test.eq(#test.logs("error"),0)
  end)
end

test.it("a tile's chevron opens its page in the panel, and the arrow comes back",function()
  load()
  for _,tile in ipairs {{"wifi","network"},{"bluetooth","bluetooth"},{"sound","sound"},{"mic","microphone"},
    {"mesh","mesh"},{"tunnel","tunnel"},{"hotspot","hotspot"},{"nightlight","nightlight"},{"powersaver","power"},
    {"focus","focus"}} do
    test.click("utilities-more-"..tile[1]) test.settle(900)
    test.eq(state().quick,tile[2],tile[1].."'s chevron")
    test.falsy(state().window,tile[1].."'s chevron opened the Settings window")
    test.click("quick-back") test.settle(900)
    test.eq(state().quick,"",tile[1].."'s page did not go back")
    test.truthy(state().panel)
  end
  -- Focus, and a tile that only opens its page, the same way.
  test.click("utilities-toggle-focus") test.settle(900)
  test.eq(state().quick,"focus")
  test.falsy(state().window)
  test.eq(#test.logs("error"),0)
end)

test.it("More settings opens the same page in the window, and the panel steps aside",function()
  load()
  test.ipc("quick","sound") test.settle(900)
  test.click("quick-more") test.settle(1500)
  local now=state()
  test.truthy(now.window,"the Settings window did not open")
  test.eq(now.page,"sound","the window is not on the same page")
  test.falsy(now.panel,"the panel stayed under the window")
  test.eq(now.quick,"","the panel kept its page")
  test.truthy(test.find{id="settings-detail-sound",visible=true})
  -- A page one in from another opens on itself, its parent behind it.
  test.ipc("quick","focus/mode") test.settle(900)
  test.falsy(state().window,"the panel opening left the window up")
  test.ipc("quick","more") test.settle(1500)
  test.eq(state().quick,"")
  test.eq(state().page,"focus/mode")
  test.truthy(test.find{id="settings-back",visible=true},"the window's page has no way to its parent")
  test.eq(#test.logs("error"),0)
end)

test.it("a deeper row of a panel's page opens the window on it",function()
  load()
  for _,row in ipairs {{"sound-equalizer","sound/equalizer"},{"sound-more","sound/more"}} do
    test.ipc("quick","sound") test.settle(900)
    test.click(row[1]) test.settle(1500)
    test.truthy(state().window,row[1].." did not open the Settings window")
    test.eq(state().page,row[2])
    test.falsy(state().panel,"the panel stayed under the window")
    test.ipc("settings","close") test.settle(900)
  end
  -- A Focus mode is the panel's own.
  test.ipc("quick","focus") test.settle(900)
  test.click("settings-focus-dnd") test.settle(900)
  test.eq(state().quick,"focus/mode")
  test.falsy(state().window,"a mode opened the Settings window")
  test.click("quick-back") test.settle(900)
  test.eq(state().quick,"focus")
  test.eq(#test.logs("error"),0)
end)

test.it("the panel and the window never build the same page node",function()
  load()
  test.ipc("quick","sound") test.settle(900)
  local pages=test.find_all{id="sound-page"}
  test.eq(#pages,1)
  test.truthy(inside(pages[1],"quick-detail-sound"),"the panel's page is not the panel's")
  test.click("quick-more") test.settle(1500)
  pages=test.find_all{id="sound-page"}
  test.eq(#pages,2,"the window took the panel's page")
  test.ne(pages[1].handle,pages[2].handle)
  local window,panel=0,0
  for _,page in ipairs(pages) do
    if inside(page,"settings-window") then window=window+1 end
    if inside(page,"quick-detail-sound") then panel=panel+1 end
  end
  test.eq(window,1,"the window has no page of its own")
  test.eq(panel,1,"the panel lost its page")
  local shown=test.find{id="sound-page",visible=true}
  test.truthy(shown and inside(shown,"settings-window"),"the window shows another host's page")
  -- Back in the panel, its own copy is the one on show.
  test.ipc("quick","sound") test.settle(1500)
  shown=test.find{id="sound-page",visible=true}
  test.truthy(shown and inside(shown,"quick-detail-sound"),"the panel shows the window's page")
  test.eq(#test.find_all{id="sound-page"},2,"a page was built again")
  test.eq(#test.logs("error"),0)
end)

test.it("the shell's own settings and All settings stay in the window",function()
  load()
  test.click("utilities-more-eva") test.settle(1500)
  test.truthy(state().window) test.eq(state().page,"eva")
  test.falsy(state().panel)
  test.ipc("settings","close") test.ipc("settings") test.settle(1500)
  test.click("utilities-all-settings") test.settle(1500)
  test.truthy(state().window) test.eq(state().page,"home")
  for _,key in ipairs {"bar","displays","eva"} do
    test.ipc("settings","close") test.settle(600)
    test.truthy(test.ipc("q_reach",key))
    test.settle(900)
    test.truthy(state().window,key.." did not open the window") test.eq(state().page,key)
  end
  test.eq(#test.logs("error"),0)
end)

test.it("routes to a quick control's page reach the panel, the rest the window",function()
  load()
  test.ipc("quick","close") test.settle(900)
  test.truthy(test.ipc("q_module","vpn")) test.settle(1200)
  test.truthy(state().panel,"the VPN module did not open the panel") test.eq(state().quick,"tunnel")
  test.truthy(test.ipc("q_module","displays")) test.settle(1200)
  test.truthy(state().window,"Displays did not open the window") test.eq(state().page,"displays")
  test.eq(test.ipc("q_search","setting:bluetooth"),"close") test.settle(1200)
  test.truthy(state().panel,"the launcher did not open the panel") test.eq(state().quick,"bluetooth")
  test.falsy(state().window)
  test.eq(test.ipc("q_search","setting:theme"),"close") test.settle(1200)
  test.truthy(state().window) test.eq(state().page,"theme")
  -- `settings PAGE` is the window's, whatever the page.
  test.eq(test.ipc("settings","network"),"network") test.settle(1200)
  test.truthy(state().window) test.falsy(state().panel)
  local said=test.ipc("quick","network") test.settle(1200)
  test.eq(said.page,"network") test.truthy(state().panel) test.falsy(state().window)
  test.eq(test.ipc("quick","state").page,"network")
  test.eq(test.ipc("quick","back").page,"")
  test.falsy(pcall(test.ipc,"quick","theme"),"the panel took a page that is not its own")
  test.eq(#test.logs("error"),0)
end)

test.it("a quick page takes the keys on a click, the tiles alone do not",function()
  load()
  test.eq(state().keys,"none")
  test.ipc("quick","network") test.settle(900)
  test.eq(state().keys,"on_demand")
  test.ipc("quick","home") test.settle(900)
  test.eq(state().keys,"none")
  test.eq(#test.logs("error"),0)
end)

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." a phone's sheet holds the same pages, and More settings fills the screen",function()
    load({style=style,size={868,1932}})
    test.click("utilities-more-wifi") test.settle(1500)
    test.eq(state().quick,"network")
    test.truthy(state().panel) test.falsy(state().window)
    local sheet,page=test.get("drawer-sidebar"),test.get("quick-detail-network")
    test.truthy(page.y>=sheet.y and page.x>=sheet.x,"the page is not in the sheet")
    test.click("quick-more") test.settle(1500)
    test.truthy(state().window) test.eq(state().page,"network")
    test.falsy(state().panel)
    local window=test.get("settings-window")
    test.near(window.width,868,1)
    test.eq(#test.logs("error"),0)
  end)
end

test.it("Sound's Microphone opens where Sound is: in the panel from the panel",function()
  load()
  test.click("utilities-more-sound") test.settle(900)
  test.eq(state().quick,"sound")
  test.click("sound-input") test.settle(900)
  test.eq(state().quick,"microphone","Microphone did not open in the panel")
  test.falsy(state().window,"Microphone opened the Settings window")
  test.click("quick-back") test.settle(900)
  test.eq(state().quick,"sound","Back from Microphone did not return to Sound")
  test.eq(#test.logs("error"),0)
end)
