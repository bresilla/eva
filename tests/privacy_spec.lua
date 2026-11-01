-- Who is using the camera, the microphone, the screen and the location: PipeWire's
-- graph as `pw-dump` prints it, /dev/video holders found through /proc, and the
-- press that names them.
local test=morf.test
local dump=morf.fs.read("tests/fixtures/pipewire-in-use.json")
local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=100,height=100}
  morf.ipc.run=function(code) return load(code)() end
  local privacy=require("privacy_model")
  morf.ipc.parse=function(text) return privacy.parse_pipewire(morf.json.decode(text)) end
  morf.ipc.holders=function(text) return privacy.parse_holders(text) end
  local model
  morf.ipc.make=function(pattern,proc,count)
    model=privacy.new {pattern=pattern,proc=proc~="" and proc or nil,use_count=count~="" and count or nil,
      spawn=function() return nil end,client={has_owner=function() return false end,watch_name=function() end},
      hyprland={available=function() return false end}}
    morf.ipc.model_rows=function() return model.rows() end
    morf.ipc.users=function(kind) return model.users(kind) end
    return true
  end
  local holder
  morf.ipc.hold=function(path)
    holder=morf.process.spawn {command={"sh","-c",'exec 9<"$0"; exec sleep 20',path}}
    return holder~=nil
  end
  morf.ipc.unhold=function() if holder then holder:kill("KILL") end return true end
  morf.ipc.start=function() model.start() return true end
  morf.ipc.scan=function() model.scan() return true end
  morf.ipc.refresh=function() model.refresh() return true end
  morf.ipc.summary=function() return model.summary() end
  morf.ipc.history=function() return model.history() end
]]
test.before_each(function() test.load("../shell/init.lua",{source=HOST,size={200,200}}) end)

test.describe("PipeWire's graph",function()
  test.it("tells a camera from a shared screen by the source each stream reads",function()
    local out=test.ipc("parse",dump)
    test.eq(#out.camera,1) test.eq(out.camera[1].app,"Firefox") test.eq(out.camera[1].pid,4100)
    test.eq(#out.screen,1) test.eq(out.screen[1].app,"OBS Studio")
  end)
  test.it("leaves out a stream reading nothing, and sound",function()
    local out=test.ipc("parse",dump)
    for _,kind in ipairs {"camera","screen"} do
      for _,user in ipairs(out[kind]) do
        test.truthy(user.app~="Waiting") test.truthy(user.app~="Recorder")
      end
    end
  end)
  test.it("reads an idle graph as nothing in use",function()
    local out=test.ipc("parse",'[{"id":79,"type":"PipeWire:Interface:Node","info":{"props":{"media.class":"Video/Source","media.role":"Camera"}}}]')
    test.eq(out.camera,{}) test.eq(out.screen,{})
  end)
  test.it("feeds the model from `pw-dump`",function()
    test.stub_run("pw-dump",{code=0,stdout=dump})
    test.stub_run("find",{code=0,stdout=""})
    test.ipc("make","/dev/video*","","")
    test.ipc("refresh") test.advance(50)
    test.eq(test.ipc("users","camera")[1].app,"Firefox")
    test.eq(test.ipc("users","screen")[1].via,"pipewire")
    test.eq(test.ipc("summary"),{"Camera: Firefox","Screen sharing: OBS Studio"})
  end)
end)

test.describe("/dev/video",function()
  test.it("reads each holder once from what find prints",function()
    test.eq(test.ipc("holders","/proc/12/fd/5\n/proc/12/fd/6\n/proc/900/fd/1\n"),{12,900})
  end)
  test.it("drops the brokers, whose clients PipeWire names",function()
    local root=morf.env("XDG_CACHE_HOME").."/privacy-proc"
    morf.fs.mkdir(root.."/100",{parents=true}) morf.fs.mkdir(root.."/200",{parents=true})
    morf.fs.write(root.."/100/comm","wireplumber\n") morf.fs.write(root.."/200/comm","zoom\n")
    test.stub_run("find",{code=0,stdout=root.."/100/fd/4\n"..root.."/200/fd/9\n"})
    test.stub_run("pw-dump",{code=0,stdout="[]"})
    test.ipc("make","/dev/video*",root,"")
    test.ipc("scan") test.advance(50)
    local users=test.ipc("users","camera")
    test.eq(#users,1) test.eq(users[1].app,"zoom") test.eq(users[1].via,"device")
  end)
  test.it("counts a program PipeWire already names once",function()
    local root=morf.env("XDG_CACHE_HOME").."/privacy-proc-2"
    morf.fs.mkdir(root.."/4100",{parents=true})
    morf.fs.write(root.."/4100/comm","firefox\n")
    test.stub_run("find",{code=0,stdout=root.."/4100/fd/9\n"})
    test.stub_run("pw-dump",{code=0,stdout=dump})
    test.ipc("make","/dev/video*",root,"")
    test.ipc("refresh") test.ipc("scan") test.advance(50)
    test.eq(#test.ipc("users","camera"),1)
  end)
  test.it("walks /proc only when the driver's use count moves",function()
    local count=morf.env("XDG_CACHE_HOME").."/uvc-count"
    morf.fs.write(count,"1\n")
    test.stub_run("pw-dump",{code=0,stdout="[]"})
    test.stub_run("find",{code=0,stdout=""})
    test.ipc("make","/dev/video*","",count)
    test.ipc("start")
    local function scans()
      local n=0
      for _,argv in ipairs(test.runs()) do if argv[1]=="find" then n=n+1 end end
      return n
    end
    test.advance(13000)
    test.eq(scans(),1,"a look on start, none while the count stands")
    morf.fs.write(count,"2\n")
    test.advance(4100)
    test.eq(scans(),2,"the count moved")
    test.advance(13000)
    test.eq(scans(),2)
  end)
  test.it("finds a real process through the real /proc",function()
    test.clear_stubs()
    local path=morf.env("XDG_CACHE_HOME").."/privacy-held-video0"
    morf.fs.write(path,"")
    test.ipc("make",path,"","")
    test.ipc("hold",path)
    local found=test.wait(function()
      test.ipc("scan")
      test.advance(20)
      return test.ipc("users","camera")[1]
    end,4000,"nothing found the holder")
    test.eq(found.app,"sleep") test.eq(found.via,"device") test.truthy(found.pid>1)
    test.ipc("unhold")
  end)
end)

test.describe("what stopped",function()
  test.it("writes down a user that goes",function()
    test.stub_run("pw-dump",{code=0,stdout=dump})
    test.stub_run("find",{code=0,stdout=""})
    test.ipc("make","/dev/video*","","")
    test.ipc("start") test.advance(100)
    test.eq(#test.ipc("users","camera"),1)
    test.stub_run("pw-dump",{code=0,stdout="[]"})
    test.ipc("refresh") test.advance(100)
    local past=test.ipc("history")
    test.eq(#past,2)
    test.truthy(past[1].app=="Firefox" or past[2].app=="Firefox")
  end)
end)

test.it("a stand-in moves over IPC",function()
  test.load("../shell/init.lua",{source=[[
    local ui=require("morf.ui")
    ui.Item {width=100,height=100}
    local model=require("privacy_model").new {fake="mic:Firefox"}
    model.start()
    morf.ipc.rows=function() return model.rows() end
  ]],size={200,200}})
  local rows=test.ipc("rows")
  test.eq(rows[1].kind,"mic") test.eq(rows[1].users[1].app,"Firefox")
  test.ipc("fake-privacy","camera:Zoom,screen:OBS") test.advance(10)
  rows=test.ipc("rows")
  test.eq(rows[1].kind,"camera") test.eq(rows[2].kind,"screen")
end)
