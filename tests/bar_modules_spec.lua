-- The bar's modules in the real shell: each one drawn, with its tooltip, its press
-- and its right press, and the readings against a fake machine.
--
--     morf test --no-dbus tests/bar_modules_spec.lua
local test=morf.test
local ROOT=morf.env("XDG_CACHE_HOME").."/bar-machine"
local function write(path,text)
  morf.fs.mkdir((ROOT..path):match("^(.*)/[^/]+$"),{parents=true})
  morf.fs.write(ROOT..path,text)
end
write("/proc/stat","cpu  100 0 100 800 0 0 0 0 0 0\ncpu0 50 0 50 400 0 0 0 0 0 0\ncpu1 50 0 50 400 0 0 0 0 0 0\n")
write("/proc/meminfo","MemTotal: 16000000 kB\nMemFree: 2000000 kB\nMemAvailable: 8000000 kB\nBuffers: 0 kB\nCached: 4000000 kB\nSwapTotal: 8000000 kB\nSwapFree: 6000000 kB\n")
write("/proc/loadavg","1.50 1.25 1.00 2/300 999\n")
write("/proc/uptime","93784.00 0.00\n")
write("/sys/class/hwmon/hwmon0/name","coretemp\n")
write("/sys/class/hwmon/hwmon0/temp1_input","77000\n")
write("/sys/class/hwmon/hwmon0/temp1_label","Package id 0\n")

local SOURCE=[[
  require("lib.services.sysinfo").configure {root=morf.env("TEST_MACHINE"),blocking=true}
  require("init")
  local bar=require("bar")
  local function module(id)
    for _,m in ipairs(bar.model.modules) do if m.id==id then return m end end
  end
  morf.ipc.q_ids=function()
    local out={}
    for _,m in ipairs(bar.model.modules) do out[#out+1]=m.id end
    return out
  end
  morf.ipc.q_module=function(id)
    local m=module(id)
    local function read(field)
      local value=m[field]
      if type(value)~="function" then return value end
      local ok,got=pcall(value)
      if ok then return got end
      return "error: "..tostring(got)
    end
    return {name=m.name,text=read("text"),tooltip=read("tooltip"),icon=read("icon"),tone=read("tone"),gauge=read("gauge"),
      tier=m.tier,press=m.press~=nil,kind=m.kind,active=read("active")}
  end
  morf.ipc.q_press=function(id) module(id).press() return true end
  morf.ipc.q_run=function(code) return load(code)() end
]]
local serial=0
local function load_shell(options)
  options=options or {}
  serial=serial+1
  local settings=morf.env("XDG_CACHE_HOME").."/bar-modules-"..serial..".json"
  morf.fs.remove(settings)
  test.stub_run("task",{code=0,stdout="[]"})
  local env={EVA_DRY_RUN="1",EVA_SETTINGS=settings,EVA_STYLE=options.style or "material",EVA_WALLPAPER="",
    EVA_FONT_FILE="",LULE_A="/nonexistent/lule",HOME=morf.env("XDG_CACHE_HOME"),TEST_MACHINE=ROOT,
    EVA_FAKE_HARDWARE="1",EVA_FAKE_BATTERY="57,charging",EVA_FAKE_MEDIA="So What|Miles Davis",
    EVA_FAKE_DEVICES="Pixel Buds:82:headphones,MX Master:12:mouse",EVA_FAKE_WEATHER="18:2",
    EVA_FAKE_PRIVACY="mic:Firefox,camera:Zoom"}
  for k,v in pairs(options.env or {}) do env[k]=v end
  test.load("../shell/init.lua",{source=SOURCE,size=options.size or {1920,1000},env=env})
  test.settle(1500)
  test.ipc("bar","show","on") test.settle(1200)
end
local function up(id)
  local node=test.find {id=id,visible=true}
  return node~=nil and node.width>0.5 and node.height>0.5
end
local function add(id,zone) test.ipc("bar","add",id,zone or "start") test.settle(700) end
local function module(id) return test.ipc("q_module",id) end
local function sample(ms) test.advance(ms or 2200) end

-- The modules with no press of their own: their press is the menu.
local LAYOUT={spacer=true,spacer_2=true,divider=true,divider_2=true}
local OWN={logo="bar-logo",clock="bar-clock",status="bar-status",windows="bar-windows",tray="bar-tray",
  live="bar-live",workspaces="bar-module-workspaces"}

for _,style in ipairs {"material","tsugumori"} do
  test.it(style.." draws every module the machine has, with no errors",function()
    load_shell {style=style}
    local ids=test.ipc("q_ids")
    test.truthy(#ids>=60,"a long catalogue: "..#ids)
    local spare=test.ipc("bar","modules").spare
    local count=0
    for _,id in ipairs(spare) do
      add(id)
      local m=module(id)
      if m.active~=false and not LAYOUT[id] then
        test.truthy(up(OWN[id] or ("bar-module-"..id)),id.." is not drawn")
        count=count+1
      end
      test.ipc("bar","remove",id) test.advance(200)
    end
    test.truthy(count>=30,"drew "..count)
    test.eq(test.logs("error"),{})
  end)
end

test.it("gives every module a name, a tooltip and a way to press and right-press it",function()
  load_shell {}
  for _,id in ipairs(test.ipc("q_ids")) do
    local m=module(id)
    test.truthy(type(m.name)=="string" and m.name~="",id.." has no name")
    test.truthy(type(m.tier)=="number",id.." has no tier")
    if not LAYOUT[id] and id~="windows" and id~="tray" then
      test.truthy(type(m.tooltip)=="string",id.." has no tooltip")
      test.falsy(tostring(m.tooltip):match("^error:"),id..": "..tostring(m.tooltip))
    end
  end
end)

test.describe("a right press",function()
  test.it("opens the module's menu, with the bar's own items",function()
    load_shell {}
    add("volume")
    test.click("bar-module-volume",{button="right"}) test.advance(300)
    test.truthy(test.find {text="Sound settings",visible=true}~=nil)
    test.truthy(test.find {text="Arrange the bar",visible=true}~=nil)
    test.truthy(test.find {text="Remove from the bar",visible=true}~=nil)
  end)
  test.it("removes a module from the bar",function()
    load_shell {}
    add("load")
    test.click("bar-module-load",{button="right"}) test.advance(300)
    test.click(test.get {text="Remove from the bar",visible=true}) test.settle(900)
    test.falsy(up("bar-module-load"))
  end)
  test.it("goes to the Bar page",function()
    load_shell {}
    add("load")
    test.click("bar-module-load",{button="right"}) test.advance(300)
    test.click(test.get {text="Arrange the bar",visible=true}) test.settle(1500)
    test.truthy(test.ipc("q_run","return require('sidebar').drawer.open:get()"))
    test.eq(test.ipc("q_run","return require('utilities').displayed:get()"),"bar")
  end)
  test.it("opens again and again at once, whatever the last one was doing",function()
    load_shell {}
    add("load")
    for _=1,4 do
      test.click("bar-module-load",{button="right"}) test.advance(30)
      test.key("Escape") test.advance(10)
    end
    test.click("bar-module-load",{button="right"}) test.advance(400)
    test.truthy(test.find {text="Arrange the bar",visible=true}~=nil)
    test.advance(1500)
    test.eq(test.logs("error"),{})
    test.eq(test.logs("warn"),{})
  end)
  test.it("reaches the clock, the status and the logo too",function()
    load_shell {}
    for _,id in ipairs {"bar-clock","bar-status","bar-logo"} do
      test.click(id,{button="right"}) test.advance(300)
      test.truthy(test.find {text="Arrange the bar",visible=true}~=nil,id)
      test.key("Escape") test.advance(300)
    end
  end)
end)

test.it("shows a tooltip on hover, and takes it away",function()
  load_shell {}
  add("load")
  local node=test.get("bar-module-load")
  test.move(node.x+node.width/2,node.y+node.height/2) test.advance(800)
  test.truthy(test.find {text="1, 5 and 15 minutes: 1.50 1.25 1.00",visible=true}~=nil)
  test.move(900,700) test.advance(600)
  test.eq(test.find {text="1, 5 and 15 minutes: 1.50 1.25 1.00",visible=true},nil)
end)

test.describe("the readings",function()
  test.it("reads the machine's memory, swap, load and uptime",function()
    load_shell {}
    add("memory") add("swap") add("load") add("uptime") sample()
    test.eq(module("memory").text,"50%") test.near(module("memory").gauge,0.5,0.01)
    test.eq(module("swap").text,"25%")
    test.eq(module("load").text,"1.50")
    test.eq(module("uptime").text,"1d 2h")
  end)
  test.it("reads the CPU's load and temperature, and tints a hot one",function()
    load_shell {}
    add("cpu") add("temperature") sample(5500)
    write("/proc/stat","cpu  200 0 200 800 0 0 0 0 0 0\ncpu0 100 0 100 400 0 0 0 0 0 0\ncpu1 100 0 100 400 0 0 0 0 0 0\n")
    sample(2200)
    test.eq(module("cpu").text,"100%") test.eq(module("cpu").tone,"alert")
    test.eq(module("temperature").text,"77°C") test.eq(module("temperature").tone,"warn")
  end)
  test.it("reads the disk at the mount the setting names",function()
    load_shell {}
    test.ipc("q_run",[[require('config').set('bar.disk.mount','/nowhere') return true]])
    add("disk") sample()
    test.truthy(module("disk").tooltip:find("/nowhere",1,true)~=nil)
  end)
  test.it("lists each Bluetooth device's battery",function()
    load_shell {}
    add("bt_batteries") sample(300)
    test.truthy(test.find {text="82%",visible=true}~=nil)
    test.truthy(test.find {text="12%",visible=true}~=nil)
    test.truthy(module("bt_batteries").tooltip:find("MX Master 12%",1,true)~=nil)
  end)
  test.it("reads the weather",function()
    load_shell {}
    add("weather")
    test.eq(module("weather").text,"18°") test.truthy(module("weather").tooltip:find("Wageningen",1,true)~=nil)
  end)
  test.it("counts the notifications from their history, and from a signal where there is one",function()
    load_shell {}
    test.eq(module("notifications").text,"")
    test.ipc("q_run",[[require('notifs').push{summary='Hi',body='',app='Test'} return true]]) test.advance(100)
    test.eq(module("notifications").text,"1")
    test.ipc("q_run",[[require('notifs').unread=require('morf').signal('test.unread',7) return true]]) test.advance(100)
    test.eq(test.ipc("q_run",[[return require('bar').model.notifications.count()]]),7)
  end)
  test.it("counts down to a date, and offers no countdown without one",function()
    load_shell {}
    local spare=test.ipc("bar","modules").spare
    local has=false
    for _,id in ipairs(spare) do has=has or id=="countdown" end
    test.falsy(has)
    test.ipc("q_run",[[require('config').set('bar.countdown.date','2099-01-01') return true]]) test.advance(100)
    spare=test.ipc("bar","modules").spare
    for _,id in ipairs(spare) do has=has or id=="countdown" end
    test.truthy(has)
  end)
  test.it("shows a second zone's time",function()
    load_shell {}
    test.ipc("q_run",[[require('config').set('bar.clock.zone','Asia/Tokyo') require('config').set('bar.clock.twelve_hour',false) return true]])
    add("world_clock")
    local here=test.ipc("q_run",[[return morf.time.format('%H:%M',morf.time.now(),{tz='Asia/Tokyo'})]])
    test.eq(module("world_clock").text,here)
  end)
end)

test.describe("a press",function()
  test.it("goes to the workspace it names, and shows which is active",function()
    load_shell {env={EVA_DRY_RUN="0"}}
    test.click("bar-workspace-3") test.settle(900)
    test.eq(test.ipc("q_run",[[return require('services').workspace.active()]]),3)
    local active=test.get("bar-workspace-active")
    local button=test.get("bar-workspace-3")
    test.near(active.x,button.x,1)
  end)
  test.it("toggles keep awake and focus",function()
    load_shell {}
    add("idle") add("focus")
    test.click("bar-module-idle") test.advance(100)
    test.truthy(test.ipc("q_run",[[return require('settings_model').awake:get()]]))
    test.eq(module("idle").tone,"accent")
    test.click("bar-module-focus") test.advance(100)
    test.truthy(test.ipc("q_run",[[return require('notifs').dnd:get()]]))
  end)
  test.it("opens the page a reading belongs to",function()
    load_shell {}
    add("cpu")
    test.click("bar-module-cpu") test.settle(1500)
    test.truthy(test.ipc("q_run",[[return require('dashboard').drawer.open:get()]]))
    test.eq(test.ipc("q_run",[[return require('dashboard_model').tabs[require('dashboard').tab:get()].key]]),"performance")
  end)
  test.it("runs a media module's transport, and the wheel skips",function()
    load_shell {}
    add("media")
    test.truthy(test.find {text="So What",visible=true}~=nil)
    test.truthy(test.get("bar-media-progress").width>0,"the progress fills it")
    test.click("bar-module-media") test.advance(100)
    test.falsy(test.ipc("q_run",[[return require('media_state').playing()]]))
    local node=test.get("bar-module-media")
    test.wheel(0,120,{x=node.x+20,y=node.y+10}) test.advance(100)
    test.eq(test.ipc("q_run",[[return require('media_state').active().position]]),0)
  end)
  test.it("shows the recording's timer, and stops it",function()
    load_shell {}
    add("recording")
    test.falsy(up("bar-module-recording"))
    test.ipc("q_run",[[local c=require('capture') c.recording:set(true) c.phase:set('recording') c.elapsed:set(75) return true]])
    test.settle(900)
    test.truthy(up("bar-module-recording"))
    test.eq(module("recording").text,"1:15")
    test.click("bar-module-recording") test.settle(900)
    test.falsy(test.ipc("q_run",[[return require('capture').recording:get()]]))
  end)
end)

test.describe("privacy",function()
  test.it("names the app on a press",function()
    load_shell {}
    test.truthy(up("bar-module-privacy"))
    test.click("bar-module-privacy") test.advance(300)
    test.truthy(test.find {text="Microphone: Firefox",visible=true}~=nil)
    test.truthy(test.find {text="Camera: Zoom",visible=true}~=nil)
  end)
  test.it("marks screen sharing, in its own module too",function()
    load_shell {}
    add("screen_share")
    test.falsy(up("bar-module-screen_share"))
    test.ipc("fake-privacy","screen:OBS") test.settle(900)
    test.truthy(up("bar-privacy-screen")) test.truthy(up("bar-module-screen_share"))
    test.eq(module("screen_share").tooltip,"Screen sharing: OBS")
  end)
  test.it("leaves the status's own marks to the module, and takes them back without it",function()
    load_shell {}
    test.falsy(up("bar-mic"))
    test.ipc("bar","remove","privacy") test.settle(900)
    test.truthy(up("bar-mic")) test.truthy(up("bar-camera"))
  end)
  test.it("takes no room while nothing is in use",function()
    load_shell {env={EVA_FAKE_PRIVACY="none:none"}}
    test.falsy(up("bar-module-privacy"))
  end)
end)

test.describe("folding",function()
  test.it("folds the rare modules into a mark that lists them",function()
    load_shell {size={1000,800}}
    for _,id in ipairs {"cpu","memory","load","uptime","host","swap","disk"} do test.ipc("bar","add",id,"end") end
    test.settle(900)
    test.truthy(up("bar-more-end"),"nothing folded")
    test.truthy(up("bar-status"))
    local clock,status=test.get("bar-clock"),test.get("bar-status")
    test.truthy(clock.x+clock.width<=status.x,"the end runs into the clock")
    test.click("bar-more-end") test.advance(300)
    test.truthy(test.find {id="bar-menu-more"}~=nil)
  end)
  test.it("keeps a phone's clock, battery and status with every tier in use",function()
    load_shell {size={412,915},env={EVA_INPUT_DEVICES=morf.env("EVA_INPUT_DEVICES").."-touch"}}
    for _,id in ipairs {"cpu","memory","weather","load"} do test.ipc("bar","add",id,"end") end
    test.settle(900)
    test.truthy(up("bar-clock")) test.truthy(up("bar-status")) test.truthy(up("bar-battery"))
    local clock,status=test.get("bar-clock"),test.get("bar-status")
    test.truthy(clock.x+clock.width<=status.x+1)
    test.truthy(status.x+status.width<=412)
  end)
end)
