-- The address book, read from a folder of real vCards.
local test=morf.test
local HOST=[[
  local lib=require("lib.services.contacts")
  local dir=morf.env("XDG_CACHE_HOME").."/contacts-spec-"..morf.env("TEST_RUN")
  local book=lib.open{folder="tests/fixtures/contacts",country="+31",state=dir.."/marks.json",watch=false}
  local names=function(rows) local out={} for i,r in ipairs(rows) do out[i]=r.name end return out end
  morf.ipc.people=function() return names(book.people:get()) end
  morf.ipc.person=function(n) local r=book.person(n) return r and r.name or "" end
  morf.ipc.label=function(n) return book.label(n) end
  morf.ipc.search=function(q) return names(book.search(q)) end
  morf.ipc.t9=function(d) return names(book.t9(d)) end
  morf.ipc.favourites=function() return names(book.favourites()) end
  morf.ipc.numbers=function(name)
    for _,r in ipairs(book.people:get()) do if r.name==name then return r.numbers end end
  end
  morf.ipc.normal=function(n,c) return lib.normal(n,c) end
  morf.ipc.mark=function(id) book.set_favourite(id,true) end
  morf.ipc.emergency=function(id) book.set_emergency(id,true) local r=book.emergency() return r and r.name or "" end
  morf.ipc.block=function(n,on) book.block(n,on) end
  morf.ipc.blocked=function(n) return book.blocked(n) end
  morf.ipc.exported=function()
    local path=dir.."/out.vcf"
    local count=book.export(path)
    return {count=count,text=morf.fs.read(path)}
  end
  morf.ipc.imported=function()
    local other=lib.open{folder=dir.."/in",state=dir.."/other.json",watch=false}
    local path=dir.."/out.vcf"
    book.export(path)
    return {count=other.import(path),people=names(other.people:get())}
  end
]]
local run=0
local function load()
  run=run+1
  test.load("contacts-fixture.lua",{source=HOST,size={20,20},env={TEST_RUN=tostring(run)}})
end

test.it("every card of every file is read, whatever vCard version",function()
  load()
  test.eq(test.ipc("people"),{"Ann Veldman","Ben de Vries","Comma, Carl","Drita Berisha"})
  test.eq(test.ipc("numbers","Ann Veldman"),{{number="+31 6 1234 5678",kind="mobile"},{number="+31 20 555 0101",kind="work"}})
  test.eq(test.ipc("numbers","Ben de Vries")[1],{number="0201234567",kind="home"})
  test.eq(test.ipc("numbers","Drita Berisha")[1].kind,"mobile")
end)

test.it("a number finds its person however it is written",function()
  load()
  test.eq(test.ipc("person","+31612345678"),"Ann Veldman")
  test.eq(test.ipc("person","0031612345678"),"Ann Veldman")
  test.eq(test.ipc("person","0612345678"),"Ann Veldman")
  test.eq(test.ipc("person","+31201234567"),"Ben de Vries")
  test.eq(test.ipc("person","+49123456"),"")
  test.eq(test.ipc("label","+49123456"),"+49123456")
  test.eq(test.ipc("label",""),"Unknown")
end)

test.it("a bare number takes the country code",function()
  load()
  test.eq(test.ipc("normal","06 1234 5678","+31"),"+31612345678")
  test.eq(test.ipc("normal","0044 20","+31"),"+4420")
  test.eq(test.ipc("normal","112","+31"),"112")
  test.eq(test.ipc("normal","*100#",""),"*100#")
end)

test.it("searches by name and number, and by the dial pad's letters",function()
  load()
  test.eq(test.ipc("search","ben"),{"Ben de Vries"})
  test.eq(test.ipc("search","5678"),{"Ann Veldman"})
  test.eq(test.ipc("search","1234"),{"Ann Veldman","Ben de Vries","Drita Berisha"})
  test.eq(test.ipc("t9","266"),{"Ann Veldman","Comma, Carl"})
  test.eq(test.ipc("t9","236"),{"Ben de Vries"})
  test.eq(test.ipc("t9","8353"),{"Ann Veldman"})
  test.eq(test.ipc("t9",""),{})
end)

test.it("favourites come from the card and from eva's own marks",function()
  load()
  test.eq(test.ipc("favourites"),{"Ann Veldman"})
  test.ipc("mark","urn:uuid:ben-2")
  test.eq(test.ipc("favourites"),{"Ann Veldman","Ben de Vries"})
  test.eq(test.ipc("emergency","ann-1"),"Ann Veldman")
end)

test.it("a blocked number stays blocked however it is written",function()
  load()
  test.eq(test.ipc("blocked","0612345678"),false)
  test.ipc("block","+31612345678",true)
  test.truthy(test.ipc("blocked","0612345678"))
  test.ipc("block","0612345678",false)
  test.eq(test.ipc("blocked","+31612345678"),false)
end)

test.it("export and import carry every card",function()
  load()
  local out=test.ipc("exported")
  test.eq(out.count,4)
  test.truthy(out.text:find("FN:Ann Veldman",1,true))
  local back=test.ipc("imported")
  test.eq(back.count,4)
  test.eq(back.people,{"Ann Veldman","Ben de Vries","Comma, Carl","Drita Berisha"})
end)
