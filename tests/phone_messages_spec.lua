-- Text threads and public warnings, through the shell and the stand-in modem.
local test=morf.test
local run=0
local dir
local function load(w,h)
  run=run+1
  dir=morf.env("XDG_CACHE_HOME").."/phone-messages-"..run
  test.load("../shell/init.lua",{size={w or 868,h or 1932},env={EVA_WALLPAPER="",EVA_DRY_RUN="1",EVA_FAKE_MODEM="1",
    EVA_FAKE_HAPTICS="1",EVA_CONTACTS="tests/fixtures/contacts",EVA_SETTINGS=dir..".json",XDG_STATE_HOME=dir}})
  test.advance(20)
end
local function fake(...) return test.ipc("phone","fake",...) end
local function state() return test.ipc("phone","state") end
local function journal(name)
  local ok,text=pcall(morf.fs.read,dir.."/eva/phone/"..name..".jsonl")
  local out={}
  for line in (ok and text or ""):gmatch("[^\n]+") do out[#out+1]=morf.json.decode(line) end
  return out
end

test.it("a text lands in its thread, unread, named, and off the modem",function()
  load()
  fake("text","+31612345678","hello there")
  test.advance(60)
  local s=state()
  test.eq(s.unread,1)
  test.eq(s.threads[1].label,"Ann Veldman")
  test.eq(s.threads[1].last,"hello there")
  test.eq(s.threads[1].unread,1)
  test.eq(s.on_modem,0)
  test.contains(test.ipc("drawers"),"notifications")
end)

test.it("a text from a blocked number is kept out of sight and rings nothing",function()
  load()
  test.ipc("phone","block","+31612345678")
  fake("text","0612345678","buy now")
  test.advance(60)
  local s=state()
  test.eq(#s.threads,0)
  test.eq(s.unread,0)
  test.eq(s.on_modem,0)
  test.eq(test.ipc("drawers"):find("notifications",1,true),nil)
  test.truthy(journal("messages")[1].blocked)
end)

test.it("a reply goes out, marks the thread read and joins it",function()
  load()
  fake("text","+31612345678","hello")
  test.advance(60)
  test.truthy(test.ipc("phone","reply","+31612345678","hi back"))
  test.advance(120)
  local s=state()
  test.eq(s.unread,0)
  test.eq(s.threads[1].count,2)
  test.eq(s.threads[1].last,"hi back")
  local rows=journal("messages")
  test.eq(rows[#rows].state,"sent")
end)

test.it("the notification keeps the number an inline reply goes to",function()
  test.load("../shell/init.lua",{source=[[
    local notifs=require("notifs")
    morf.ipc.push=function() notifs.push{summary="Ann",body="hi",reply="+3161234"} return notifs.list:get()[1].reply end
  ]],size={868,1932},env={EVA_DRY_RUN="1"}})
  test.eq(test.ipc("push"),"+3161234")
end)

test.it("several senders are several threads, newest first",function()
  load()
  fake("text","+31612345678","one")
  test.advance(40)
  fake("text","+3161111111","two")
  test.advance(40)
  test.eq(#state().threads,2)
end)

test.it("an empty reply is refused and nothing is logged",function()
  load()
  test.eq(test.ipc("phone","reply","+3161",""),false)
  test.eq(#journal("messages"),0)
end)

test.it("an alert covers the screen, is logged, and repeats are one",function()
  load()
  fake("alert",4371,"Flood warning for your area")
  test.advance(60)
  test.eq(state().alert,"Flood warning for your area")
  test.eq(test.get("alert-title").text,"Extreme threats")
  test.eq(#journal("alerts"),1)
  test.click("alert-ok")
  test.advance(60)
  test.eq(state().alert,"")
end)

test.it("alerts that come together wait their turn",function()
  load()
  fake("alert",4371,"first")
  fake("alert",4373,"second")
  test.advance(60)
  test.eq(state().alert,"first")
  test.ipc("phone","ok")
  test.advance(20)
  test.eq(state().alert,"second")
end)

test.it("a test alert stays out by default, a national one cannot be turned off",function()
  load()
  fake("alert",4380,"This is a test")
  test.advance(60)
  test.eq(state().alert,"")
  fake("alert",4370,"National alert")
  test.advance(60)
  test.eq(state().alert,"National alert")
end)

test.it("a channel that is no warning is not one",function()
  load()
  fake("alert",50,"Cell info")
  test.advance(60)
  test.eq(state().alert,"")
  test.eq(#journal("alerts"),0)
end)

local PURE=[[
  local m=require("models.phone_messages")
  local a=require("models.phone_alerts")
  morf.ipc.segments=function(text) return {m.segments(text)} end
  morf.ipc.seconds=function(s) return m.seconds(s) or false end
  morf.ipc.kind=function(c) local k=a.kind(c) return k and k.id or "" end
  morf.ipc.ranges=function() return a.ranges(function(id) return id=="severe" end) end
]]
test.it("a text counts its parts as the network will",function()
  test.load("pure.lua",{source=PURE,size={20,20}})
  test.eq(test.ipc("segments","hi"),{1,158})
  test.eq(test.ipc("segments",string.rep("a",160)),{1,0})
  test.eq(test.ipc("segments",string.rep("a",161)),{2,145})
  test.eq(test.ipc("segments",string.rep("€",80)),{1,0})
  test.eq(test.ipc("segments","привет"),{1,64})
  test.eq(test.ipc("segments",string.rep("я",71)),{2,63})
end)

test.it("a stamp reads as seconds, whatever its zone",function()
  test.load("pure.lua",{source=PURE,size={20,20}})
  test.eq(test.ipc("seconds","1970-01-01T00:00:00+00:00"),0)
  test.eq(test.ipc("seconds","2026-11-01T12:00:00+01:00"),1793530800)
  test.eq(test.ipc("seconds","2024-02-29T23:59:59-05:00"),1709269199)
  test.eq(test.ipc("seconds","nonsense"),false)
end)

test.it("the alert channels follow 3GPP TS 23.041",function()
  test.load("pure.lua",{source=PURE,size={20,20}})
  test.eq(test.ipc("kind",4370),"presidential")
  test.eq(test.ipc("kind",4383),"presidential")
  test.eq(test.ipc("kind",4372),"extreme")
  test.eq(test.ipc("kind",4385),"extreme")
  test.eq(test.ipc("kind",4378),"severe")
  test.eq(test.ipc("kind",4391),"severe")
  test.eq(test.ipc("kind",4379),"amber")
  test.eq(test.ipc("kind",4394),"test")
  test.eq(test.ipc("kind",50),"")
  test.eq(test.ipc("ranges"),{{4370,4370},{4383,4383},{4373,4378},{4386,4391}})
end)
