-- Bytes by interface, across the reboots that zero the kernel's counters.
local test=morf.test
local run=0
local HOST=[[
  local usage=require("data_usage")
  local dir=morf.env("TEST_NET")
  local function count(name,rx,tx)
    morf.fs.write(dir.."/"..name.."/statistics/rx_bytes",tostring(rx).."\n",{parents=true})
    morf.fs.write(dir.."/"..name.."/statistics/tx_bytes",tostring(tx).."\n",{parents=true})
  end
  local notes={}
  count("lo",999,999) count("wwan0",1000,0) count("wlan0",5000,5000)
  usage.start{dir=dir,every=3600000,limit=function() return tonumber(morf.env("TEST_LIMIT")) or 0 end,
    notify=function(n) notes[#notes+1]=n end}
  morf.ipc.count=function(name,rx,tx) count(name,tonumber(rx),tonumber(tx)) usage.sample() end
  morf.ipc.read=function() return {rows=usage.rows:get(),mobile=usage.mobile(),notes=notes} end
  morf.ipc.reset=function() usage.reset() end
  morf.ipc.size=function(n) return usage.size(n) end
  morf.ipc.kind=function(n) return usage.kind(n) or "" end
]]
local function load(limit)
  run=run+1
  local dir=morf.env("XDG_CACHE_HOME").."/data-usage-"..run
  test.load("../shell/init.lua",{source=HOST,size={20,20},env={TEST_NET=dir.."/net",XDG_STATE_HOME=dir.."/state",
    TEST_LIMIT=limit and tostring(limit) or ""}})
end
local function bytes(name)
  for _,row in ipairs(test.ipc("read").rows) do if row.name==name then return row.bytes end end
end

test.it("what passed before eva looked is not counted, what passes after is",function()
  load()
  test.ipc("count","wwan0",1500,250)
  test.ipc("count","wlan0",6000,5000)
  test.eq(bytes("wwan0"),750)
  test.eq(bytes("wlan0"),1000)
  test.eq(bytes("lo"),nil)
end)

test.it("a reboot's zeroed counters add on, they do not subtract",function()
  load()
  test.ipc("count","wwan0",2000,0)
  test.eq(bytes("wwan0"),1000)
  test.ipc("count","wwan0",300,0)
  test.eq(bytes("wwan0"),1300)
end)

test.it("the busiest interface comes first, and mobile is added up",function()
  load()
  test.ipc("count","wwan0",3000,0)
  test.ipc("count","wlan0",5500,5000)
  local read=test.ipc("read")
  test.eq(read.rows[1].name,"wwan0")
  test.eq(read.rows[1].kind,"mobile")
  test.eq(read.mobile,2000)
end)

test.it("the limit warns at 80%, then at 100%, each once",function()
  load(1)
  test.ipc("count","wwan0",801000,0)
  local notes=test.ipc("read").notes
  test.eq(#notes,1)
  test.contains(notes[1].summary,"80%")
  test.ipc("count","wwan0",850000,0)
  test.eq(#test.ipc("read").notes,1)
  test.ipc("count","wwan0",1002000,0)
  notes=test.ipc("read").notes
  test.eq(#notes,2)
  test.eq(notes[2].summary,"Mobile data limit reached")
  test.eq(notes[2].urgency,2)
end)

test.it("no limit, no warning; Start over clears the month",function()
  load()
  test.ipc("count","wwan0",90000000,0)
  test.eq(#test.ipc("read").notes,0)
  test.ipc("reset")
  test.eq(test.ipc("read").mobile,0)
end)

test.it("sizes and kinds read as a person expects",function()
  load()
  test.eq(test.ipc("size",512),"512 B")
  test.eq(test.ipc("size",12000),"12 kB")
  test.eq(test.ipc("size",12300000),"12.3 MB")
  test.eq(test.ipc("size",1234000000),"1.23 GB")
  test.eq(test.ipc("kind","rmnet_data0"),"mobile")
  test.eq(test.ipc("kind","wlp2s0"),"wifi")
  test.eq(test.ipc("kind","enp0s31f6"),"wired")
  test.eq(test.ipc("kind","docker0"),"")
end)
