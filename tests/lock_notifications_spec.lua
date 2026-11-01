-- The privacy levels of the lock's notifications, at both ends of the one way
-- out of the shell. No level may carry more than it says.
local test=morf.test
local NOW=1000
local RUN=morf.env("XDG_CACHE_HOME").."/lock-notifications-run"
morf.fs.mkdir(RUN,{parents=true})
local ENTRIES={
  {app="Signal",summary="Mira",body="the code is 4471",urgency=1,time=NOW-30},
  {app="Bank",summary="Card used",body="42.00 at the shop",urgency=2,time=NOW-20},
  {app="Signal",summary="Jon",body="call me",urgency=1,time=NOW-10},
  {app="Updater",summary="Quiet",body="low",urgency=0,time=NOW-5},
}
local function rig()
  test.load("../lock/init.lua",{size={40,40},env={EVA_DRY_RUN="1",XDG_RUNTIME_DIR=RUN},source=[[
    local n=require("models.lock_notifications")
    morf.ipc.names=function()
      return {level_all=n.level_of("all","none"),level_app=n.level_of("app","none"),
        level_count=n.level_of("count","all"),level_none=n.level_of("none","all"),
        level_unknown=n.level_of("everything","all"),level_own=n.level_of(nil,"count"),
        back_senders=n.preview_of("senders"),back_all=n.preview_of("all"),
        back_count=n.preview_of("count"),back_none=n.preview_of("none")}
    end
    morf.ipc.project=function(raw)
      local v=morf.json.decode(raw)
      local rules=v.rules and function(app) return v.rules[app] end or nil
      return morf.json.encode(n.project(v.entries,v.level,rules,v.options))
    end
    morf.ipc.reader=function(raw)
      local v=morf.json.decode(raw)
      morf.fs.write(n.path(),v.file,{parents=true})
      local reader=n.reader {notifications={level=v.level}}
      return morf.json.encode {level=reader.level(),count=reader.count(),items=reader.items()}
    end
  ]]})
end
local function project(level,rules,options)
  return morf.json.decode(test.ipc("project",morf.json.encode {entries=ENTRIES,level=level,rules=rules,options=options}))
end
local function words(value) return morf.json.encode(value) end
local SECRET={"the code","4471","Mira","Jon","Card used","42.00","call me"}
local function clean(value,label)
  local text=words(value)
  for _,word in ipairs(SECRET) do
    test.falsy(text:find(word,1,true),label.." carried '"..word.."'")
  end
end

test.it("all carries the text, newest first, without silent ones",function()
  rig()
  local p=project("all")
  test.eq(p.level,"all") test.eq(p.count,3) test.eq(#p.items,3)
  test.eq(p.items[1].summary,"Jon") test.eq(p.items[3].summary,"Mira")
  test.eq(words(p):find("Quiet",1,true),nil)
end)

test.it("senders carries apps and how many, and no word of what they said",function()
  rig()
  local p=project("senders")
  test.eq(p.count,3) test.eq(#p.items,2)
  test.eq(p.items[1].app,"Signal") test.eq(p.items[1].count,2)
  test.eq(p.items[2].app,"Bank") test.eq(p.items[2].count,1)
  clean(p,"senders")
end)

test.it("count carries a number and no app",function()
  rig()
  local p=project("count")
  test.eq(p.count,3) test.eq(#p.items,0)
  clean(p,"count")
  test.eq(words(p):find("Signal",1,true),nil)
  test.eq(words(p):find("Bank",1,true),nil)
end)

test.it("none carries nothing at all",function()
  rig()
  local p=project("none")
  test.eq(p.count,0) test.eq(#p.items,0)
  test.eq(words(p):find("Signal",1,true),nil)
  for _,level in ipairs {"","everything"} do
    test.eq(project(level).level,"none","an unknown level is the strictest")
  end
end)

test.it("a per-app rule only makes an app quieter",function()
  rig()
  local p=project("all",{Bank="none"})
  test.eq(p.count,2)
  test.eq(words(p):find("Card used",1,true),nil)
  p=project("all",{Bank="senders"})
  test.eq(p.count,3)
  test.eq(words(p):find("42.00",1,true),nil)
  p=project("all",{Bank="count"})
  test.eq(p.count,3)
  test.eq(words(p):find("Bank",1,true),nil)
  p=project("senders",{Signal="all"})
  clean(p,"a rule cannot loosen the level")
  p=project("count",{Signal="all"})
  test.eq(#p.items,0,"a rule cannot loosen count")
  p=project("none",{Signal="all"})
  test.eq(p.count,0,"a rule cannot loosen none")
end)

test.it("silent ones and old ones are chosen",function()
  rig()
  test.eq(project("all",nil,{silent=true}).count,4)
  test.eq(project("all",nil,{since=NOW-15}).count,1)
end)

test.it("text is plain, short and one line",function()
  rig()
  local long=("x"):rep(500)
  local p=morf.json.decode(test.ipc("project",morf.json.encode {level="all",
    entries={{app="A",summary="<b>Hi</b> &amp; bye\n\nthere",body=long,urgency=1,time=1}}}))
  test.eq(p.items[1].summary,"Hi & bye there")
  test.truthy(utf8.len(p.items[1].body)<=161)
end)

test.it("the lock will not show what a looser level wrote",function()
  rig()
  local written=morf.json.encode {notifications={level="all",count=2,
    items={{app="Signal",summary="Mira",body="the code",time=1}}}}
  local out=morf.json.decode(test.ipc("reader",morf.json.encode {level="senders",file=written}))
  test.eq(out.level,"none") test.eq(out.count,0) test.eq(#out.items,0)
  out=morf.json.decode(test.ipc("reader",morf.json.encode {level="none",file=written}))
  test.eq(out.count,0) test.eq(#out.items,0)
  out=morf.json.decode(test.ipc("reader",morf.json.encode {level="all",file=written}))
  test.eq(out.count,2)
  out=morf.json.decode(test.ipc("reader",morf.json.encode {level="senders",file="not json"}))
  test.eq(out.count,0)
end)

test.it("an app with `hide` in its notification rule stops at its name",function()
  test.stub_run("task",{code=0,stdout="[]"})
  local settings=morf.env("XDG_CACHE_HOME").."/lock-bridge-hide.json"
  morf.fs.write(settings,morf.json.encode {lock={notifications={level="all",new_only=false}},notifications={lock_previews="all"}})
  test.load("../shell/init.lua",{size={1200,800},env={EVA_DRY_RUN="1",EVA_SETTINGS=settings,EVA_STYLE="material",XDG_RUNTIME_DIR=RUN,
    EVA_WALLPAPER="",EVA_FONT_FILE="",LULE_A="/nonexistent/lule"},source=[[
      package.loaded.notification_rules={of=function(app) return {hide=app=="Bank"} end}
      require("init")
      morf.ipc.shot=function()
        return require("lock_bridge").snapshot {
          {id=1,app="Bank",summary="Card used",body="42.00",urgency=1,time=morf.time.now()},
          {id=2,app="Signal",summary="Mira",body="hello",urgency=1,time=morf.time.now()}}
      end
    ]]})
  test.settle(800)
  local text=morf.json.encode(test.ipc("shot"))
  test.eq(text:find("Card used",1,true),nil)
  test.eq(text:find("42.00",1,true),nil)
  test.contains(text,"Bank")
  test.contains(text,"Mira")
end)

test.it("the Notifications page's names map to the levels and back",function()
  rig()
  test.eq(test.ipc("names"),{level_all="all",level_app="senders",level_count="count",level_none="none",
    level_unknown="none",level_own="count",back_senders="app",back_all="all",back_count="count",back_none="none"})
end)

test.it("the shell writes only the chosen level, and honours the rule seam",function()
  local settings=morf.env("XDG_CACHE_HOME").."/lock-bridge.json"
  morf.fs.write(settings,morf.json.encode {lock={notifications={level="count",new_only=false}},notifications={lock_previews="count"}})
  test.stub_run("task",{code=0,stdout="[]"})
  test.load("../shell/init.lua",{size={1200,800},env={EVA_DRY_RUN="1",EVA_SETTINGS=settings,EVA_STYLE="material",XDG_RUNTIME_DIR=RUN,
    EVA_WALLPAPER="",EVA_FONT_FILE="",LULE_A="/nonexistent/lule",EVA_FAKE_LOCK_RULES=morf.json.encode{Spam="none"}},
    source=[[
      require("init")
      morf.ipc.push=function()
        local n=require("notifs")
        n.history:set({
          {id=1,app="Signal",summary="Mira",body="the code",urgency=1,time=morf.time.now()},
          {id=2,app="Spam",summary="buy",body="now",urgency=1,time=morf.time.now()}})
        return true
      end
      morf.ipc.file=function()
        return require("lock_bridge").snapshot(require("notifs").history:get())
      end
    ]]})
  test.settle(1200)
  test.ipc("push") test.settle(400)
  local shot=test.ipc("file")
  test.eq(shot.notifications.level,"count")
  test.eq(shot.notifications.count,1,"the rule took Spam out")
  test.eq(#shot.notifications.items,0)
  test.eq(morf.json.encode(shot):find("Mira",1,true),nil)
  test.eq(morf.json.encode(shot):find("the code",1,true),nil)
  local path=RUN.."/eva/lock-view.json"
  local text=morf.fs.read(path)
  test.eq(text:find("Mira",1,true),nil,"nothing past the level reaches the file")
  test.eq(text:find("buy",1,true),nil)
end)
