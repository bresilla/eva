-- eva-phone and eva-messages, each against its own stand-in modem.
local test=morf.test
local run=0
local dir
local function load(app,args,seed)
  run=run+1
  dir=morf.env("XDG_CACHE_HOME").."/phone-apps-"..run
  if seed then
    morf.fs.write(dir.."/eva/phone/"..seed..".jsonl",morf.fs.read("tests/fixtures/phone/"..seed..".jsonl"),{parents=true})
  end
  test.load("../apps/"..app.."/app.lua",{size={480,860},args=args,env={EVA_DRY_RUN="1",EVA_FAKE_MODEM="1",
    EVA_CONTACTS="tests/fixtures/contacts",EVA_SETTINGS=dir..".json",XDG_STATE_HOME=dir}})
  test.advance(40)
end

test.it("the pad types, T9 finds people, and a number opens the tool typed",function()
  load("phone")
  test.click("phone-key-2") test.click("phone-key-6") test.click("phone-key-6")
  test.advance(20)
  local s=test.ipc("state")
  test.eq(s.number,"266")
  test.eq(s.matches,2)
  test.eq(test.get("phone-match-1-title").text,"Ann Veldman")
  test.click("phone-back")
  test.eq(test.ipc("state").number,"26")
  load("phone",{"tel:+3112345"})
  test.eq(test.ipc("state").number,"+3112345")
end)

test.it("the call button dials what is typed, and a USSD code is sent elsewhere",function()
  load("phone")
  test.truthy(test.ipc("state").can_call)
  test.eq(test.ipc("call","*100#"),false)
  test.contains(test.ipc("state").message,"USSD")
  test.ipc("press","112")
  test.click("phone-call")
  test.advance(200)
  test.eq(test.ipc("state").number,"")
end)

test.it("recent calls come from the shell's history, by name, newest first",function()
  load("phone",nil,"calls")
  test.ipc("tab",2)
  test.advance(20)
  test.eq(test.ipc("state").recents,4)
  test.eq(test.get("phone-recent-1-title").text,"Ben de Vries")
  test.eq(test.get("phone-recent-2-title").text,"Drita Berisha")
  test.contains(test.get("phone-recent-2-subtitle").text,"missed")
  test.eq(test.get("phone-recent-3-title").text,"+4915112345678")
end)

test.it("contacts are searched and starred",function()
  load("phone")
  test.ipc("tab",3)
  test.advance(20)
  test.eq(test.ipc("state").people,4)
  test.eq(test.get("phone-person-1-title").text,"Ann Veldman")
  test.click("phone-star-2")
  test.advance(20)
  test.truthy(morf.fs.read(dir.."/eva/phone/contacts.json"):find("ben-2",1,true))
end)

test.it("a recent caller can be blocked from the list, and an emergency contact chosen",function()
  load("phone",nil,"calls")
  test.ipc("tab",2)
  test.advance(20)
  test.click("phone-block-3")
  test.advance(20)
  test.truthy(morf.fs.read(dir.."/eva/phone/contacts.json"):find("+4915112345678",1,true))
  test.ipc("tab",3)
  test.advance(20)
  test.click("phone-ice-1")
  test.advance(20)
  test.contains(morf.fs.read(dir.."/eva/phone/contacts.json"),'"emergency":"ann-1"')
end)

test.it("vCards are imported from a file and exported to one",function()
  run=run+1
  dir=morf.env("XDG_CACHE_HOME").."/phone-apps-"..run
  local out=dir.."/out.vcf"
  test.load("../apps/phone/app.lua",{size={480,860},args={"export",out},env={EVA_DRY_RUN="1",
    EVA_CONTACTS="tests/fixtures/contacts",EVA_SETTINGS=dir..".json",XDG_STATE_HOME=dir}})
  test.advance(20)
  test.contains(morf.fs.read(out),"FN:Ann Veldman")
end)

test.it("threads list by who, newest first, with what is unread",function()
  load("messages",nil,"messages")
  local s=test.ipc("state")
  test.eq(#s.threads,3)
  test.eq(s.threads[1].label,"Drita Berisha")
  test.eq(s.threads[1].unread,1)
  test.eq(s.threads[2].label,"Ann Veldman")
  test.eq(s.threads[2].count,3)
end)

test.it("opening a thread reads it, and a reply goes out into it",function()
  load("messages",{"sms:+38344123456"},"messages")
  test.eq(test.ipc("state").threads[1].unread,0)
  test.eq(test.get("messages-person").text,"Drita Berisha")
  test.ipc("write","Po, tani")
  test.truthy(test.ipc("send"))
  test.advance(120)
  local s=test.ipc("state")
  test.eq(#s.thread,2)
  local sent
  for _,row in ipairs(s.thread) do if row.direction=="out" then sent=row end end
  test.eq(sent.text,"Po, tani")
  test.eq(sent.state,"sent")
  test.eq(s.draft,"")
end)

test.it("a new message starts a thread with that number",function()
  load("messages")
  test.ipc("compose","+3161234")
  test.ipc("write","Hello")
  test.truthy(test.ipc("send"))
  test.advance(120)
  local s=test.ipc("state")
  test.eq(s.open,"+3161234")
  test.eq(s.composing,false)
  test.eq(#s.threads,1)
end)

test.it("a bubble is as wide as its words, up to its limit",function()
  load("messages",nil,"messages")
  test.eq(test.ipc("fit","hi",15,325),120)
  test.eq(test.ipc("fit",string.rep("a",30),15,325),279)
  test.eq(test.ipc("fit",string.rep("a",60),15,325),325)
  test.eq(test.ipc("fit","ab\n"..string.rep("a",30),15,325),279)
  test.eq(test.ipc("fit",string.rep("ë",30),15,325),279)
  test.ipc("show","+31612345678")
  test.advance(200)
  test.truthy(test.get("messages-text-1").width>100,"a bubble never collapses to its padding")
end)

test.it("a long message wraps inside its bubble instead of running out of it",function()
  load("messages",nil,"messages")
  test.ipc("show","+31612345678")
  test.settle(400)
  test.ipc("write",string.rep("word ",40))
  test.truthy(test.ipc("send"))
  test.advance(120)
  local rows=test.ipc("state").thread
  local index
  for i,row in ipairs(rows) do if row.direction=="out" and #row.text>100 then index=i end end
  local bubble=test.get("messages-bubble-"..index)
  test.truthy(bubble.height>test.get("messages-bubble-1").height*1.5)
  test.truthy(test.get("messages-text-"..index).width<=480*0.78)
end)
