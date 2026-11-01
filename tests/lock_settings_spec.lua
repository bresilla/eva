-- What the lock reads of its settings, and the system's policy over them. No
-- lock runs here: these are the models, with their seams.
local test=morf.test
local dir=morf.env("XDG_CACHE_HOME").."/lock-settings-spec"
morf.fs.mkdir(dir,{parents=true})
local SETTINGS,POLICY=dir.."/eva.json",dir.."/policy.json"
local function env(extra)
  local out={EVA_SETTINGS=SETTINGS,EVA_LOCK_POLICY=POLICY,EVA_DRY_RUN="1"}
  for k,v in pairs(extra or {}) do out[k]=v end
  return out
end
local function read(extra)
  test.load("../lock/init.lua",{size={40,40},env=env(extra),source=[[
    morf.ipc.prefs=function()
      local p=require("models.lock_settings").load()
      p.managed=nil
      return p
    end
  ]]})
  return test.ipc("prefs")
end
local function write(file,value) morf.fs.write(file,morf.json.encode(value)) end
local function clear() morf.fs.remove(SETTINGS) morf.fs.remove(POLICY) end

test.it("with no file everything that could reveal or open stands shut",function()
  clear()
  local p=read()
  test.eq(p.notifications.level,"senders")
  test.eq(p.grace_seconds,0)
  test.eq(p.power_buttons,false)
  test.eq(p.command.safe,false)
  test.eq(#p.widgets,0)
  test.eq(p.emergency.text,"")
  test.eq(p.on_suspend,true,"a boolean default survives a missing file")
  test.eq(p.readers,true)
end)

test.it("a person's values apply, and nonsense falls back",function()
  clear()
  write(SETTINGS,{lock={notifications={level="count",silent=true},grace_seconds=15,power_buttons=true,
    on_suspend=false,widgets={"calendar"}}})
  local p=read()
  test.eq(p.notifications.level,"count")
  test.eq(p.notifications.silent,true)
  test.eq(p.grace_seconds,15)
  test.eq(p.power_buttons,true)
  test.eq(p.on_suspend,false)
  test.eq(p.widgets[1],"calendar")
  write(SETTINGS,{lock={notifications={level="everything"},grace_seconds=9999,power_buttons="yes",
    widgets="calendar",attempts={limit=-3}}})
  p=read()
  test.eq(p.notifications.level,"senders","an unknown level")
  test.eq(p.grace_seconds,60,"a window has a ceiling")
  test.eq(p.power_buttons,false,"a string is not a yes")
  test.eq(#p.widgets,0,"a string is not a list")
  test.eq(p.attempts.limit,1)
  write(SETTINGS,{lock={grace_seconds=-5}})
  test.eq(read().grace_seconds,0)
end)

test.it("a file that is not JSON leaves the defaults",function()
  clear()
  morf.fs.write(SETTINGS,"{ not json")
  local p=read()
  test.eq(p.power_buttons,false)
  test.eq(p.grace_seconds,0)
end)

test.it("the system's policy wins over the person",function()
  clear()
  write(SETTINGS,{lock={grace_seconds=30,power_buttons=true,notifications={level="all"}}})
  write(POLICY,{grace_seconds=0,power_buttons=false,notifications={level="none"}})
  local p=read()
  test.eq(p.grace_seconds,0)
  test.eq(p.power_buttons,false)
  test.eq(p.notifications.level,"none")
end)

test.it("a lockdown leaves nothing but the password",function()
  clear()
  write(SETTINGS,{lock={notifications={level="all"},grace_seconds=30,widgets={"calendar"},
    power_buttons=true,readers=true}})
  test.load("../lock/init.lua",{size={40,40},env=env(),source=[[
    morf.ipc.down=function()
      local s=require("models.lock_settings")
      local p=s.lockdown(s.load()) p.managed=nil return p
    end
  ]]})
  local p=test.ipc("down")
  test.eq(p.notifications.level,"none")
  test.eq(p.grace_seconds,0)
  test.eq(p.readers,false)
  test.eq(p.power_buttons,false)
  test.eq(#p.widgets,0)
  test.eq(p.media,false)
end)

test.it("a reason is used once, goes stale, and names only what is known",function()
  clear()
  test.load("../lock/init.lua",{size={40,40},env=env(),source=[[
    local r=require("models.lock_reason")
    local path=morf.env("XDG_RUNTIME_DIR").."/eva/lock-reason"
    morf.ipc.flow=function(kind)
      if kind=="used" then
        r.mark("idle") return {r.take(),r.take()}
      elseif kind=="stale" then
        morf.fs.write(path,morf.json.encode{reason="idle",at=r.uptime()-r.FRESH-1}) return {r.take()}
      elseif kind=="future" then
        morf.fs.write(path,morf.json.encode{reason="idle",at=r.uptime()+100}) return {r.take()}
      elseif kind=="unknown" then
        morf.fs.write(path,morf.json.encode{reason="anything",at=r.uptime()}) return {r.take()}
      elseif kind=="junk" then
        morf.fs.write(path,"idle") return {r.take()}
      end
    end
  ]]})
  local used=test.ipc("flow","used")
  test.eq(used[1],"idle") test.eq(used[2],"manual")
  for _,kind in ipairs {"stale","future","unknown","junk"} do
    test.eq(test.ipc("flow",kind)[1],"manual",kind)
  end
end)
