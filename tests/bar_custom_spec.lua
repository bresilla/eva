-- A person's own modules: from a command in the settings, and from Lua files
-- found on the search path.
local test=morf.test
local ROOT=morf.env("XDG_CACHE_HOME").."/bar-root"
morf.fs.mkdir(ROOT.."/plugin",{parents=true})
morf.fs.write(ROOT.."/plugin/10-ups.lua",[[
local bar = require("eva.bar")
bar.modules["ups"] = { name = "UPS", icon = "battery_saver", text = function() return "98%" end,
  tooltip = function() return "On mains" end }
]])
morf.fs.write(ROOT.."/plugin/20-broken.lua","this is not lua")
morf.fs.write(ROOT.."/plugin/30-raises.lua",'error("no")')
morf.fs.write(ROOT.."/plugin/40-ups-again.lua",[[
require("eva.bar").modules["ups"] = { name = "UPS two", icon = "bolt", text = function() return "99%" end }
]])
morf.fs.write(ROOT.."/plugin/notes.txt","not a module")

local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=100,height=100}
  morf.ipc.run=function(code) return load(code)() end
]]
local function load_it(env)
  env=env or {}
  env.EVA_BAR_ROOT=ROOT
  env.EVA_SETTINGS=morf.env("XDG_CACHE_HOME").."/bar-custom.json"
  test.load("../shell/init.lua",{source=HOST,size={200,200},env=env})
end
test.before_each(function() load_it() end)

test.describe("what a command prints",function()
  local function parse(text) return test.ipc("run",("return require('bar_custom').parse(%q)"):format(text)) end
  test.it("is its first line, trimmed",function()
    test.eq(parse("  42 mails\nsecond\n").text,"42 mails")
  end)
  test.it("may be JSON",function()
    local out=parse('{"text":"up","tooltip":"All fine","tone":"ok","percentage":30,"icon":"cloud"}')
    test.eq(out.text,"up") test.eq(out.tooltip,"All fine") test.eq(out.tone,"ok") test.eq(out.percentage,30) test.eq(out.icon,"cloud")
  end)
end)

test.describe("Lua files",function()
  test.it("register modules by name, a later file replacing an earlier one",function()
    local names=test.ipc("run",[[
      local out={}
      for _,spec in ipairs(require('bar_custom').from_files()) do out[#out+1]=spec.id..'='..spec.name..'='..spec.text() end
      return out
    ]])
    test.eq(names,{"lua_ups=UPS two=99%"})
  end)
  test.it("are reported when they fail, and the rest still load",function()
    local failures=test.ipc("run",[[
      require('bar_custom').from_files()
      return require('bar_custom').failures
    ]])
    test.eq(#failures,2)
    test.truthy(failures[1].path:find("20-broken.lua",1,true)~=nil)
    test.truthy(failures[2].why:find("no",1,true)~=nil)
  end)
  test.it("run as text, never bytecode",function()
    morf.fs.write(ROOT.."/plugin/50-bytecode.lua",string.dump(function() end))
    local failures=test.ipc("run",[[
      require('bar_custom').from_files()
      return require('bar_custom').failures
    ]])
    test.eq(#failures,3)
    morf.fs.remove(ROOT.."/plugin/50-bytecode.lua")
  end)
end)

test.it("a module from a command reads what it prints, and presses run what it says",function()
  test.stub_run("mail-count",{code=0,stdout='{"text":"7","tooltip":"Seven unread"}'})
  test.load("../shell/init.lua",{source=[[
    local ui=require("morf.ui")
    ui.Item {width=100,height=100}
    local config=require("config")
    config.set("bar.custom",{{id="mail",name="Mail",icon="mail",command={"mail-count"},interval=1000,press={"true"},right={"false"}}})
    local list=require("bar_custom").modules(function(argv) morf.log("info","ran "..table.concat(argv," ")) return true end)
    local mod=list[1]
    morf.ipc.read=function() return {id=mod.id,text=mod.text(),tooltip=mod.tooltip(),icon=mod.icon()} end
    morf.ipc.press=function() mod.press() return true end
    morf.ipc.menu=function() local m=mod.menu() m[1].on_clicked() return m[1].label end
    morf.effect("custom.read",function() mod.text() end)
  ]],size={200,200},env={EVA_BAR_ROOT="/nonexistent"}})
  test.advance(50)
  test.advance(1100)
  local out=test.ipc("read")
  test.eq(out.id,"custom_mail") test.eq(out.text,"7") test.eq(out.tooltip,"Seven unread") test.eq(out.icon,"mail")
  test.ipc("press") test.ipc("menu")
  local said=""
  for _,line in ipairs(test.logs("info")) do said=said..line.message.." " end
  test.truthy(said:find("ran true",1,true)~=nil) test.truthy(said:find("ran false",1,true)~=nil)
end)
