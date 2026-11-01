-- The recogniser, fed contacts as numbers: which gestures it hears, and the ones
-- it must never hear. The screen is 1280 by 800 logical pixels.
local test=morf.test
local HOST=[[
  local ui=require("morf.ui")
  ui.Item {width=10,height=10}
  local gestures=require("touch_gestures")
  morf.ipc.drive=function(text)
    local log={}
    local regions=text:find("KEYBOARD",1,true) and {{name="keyboard",x=0,y=500,width=1280,height=300}} or {}
    local g=gestures.new {size=function() return 1280,800 end,regions=function() return regions end,
      on=function(event) log[#log+1]=event end}
    for _,step in ipairs(morf.json.decode((text:gsub("KEYBOARD","")))) do
      local kind=step[1]
      if kind=="down" then g.down(step[2],step[3],step[4],step[5])
      elseif kind=="move" then g.move(step[2],step[3],step[4])
      elseif kind=="up" then g.up(step[2],step[3])
      elseif kind=="frame" then g.frame(step[2])
      elseif kind=="tick" then g.tick(step[2])
      elseif kind=="cancel" then g.cancel() end
    end
    return log
  end
  morf.ipc.key=function(text) return gestures.key(morf.json.decode(text)) end
  morf.ipc.constants=function() return {BAND=gestures.BAND,TRAVEL=gestures.TRAVEL,HOLD=gestures.HOLD,TAP=gestures.TAP} end
]]
test.before_each(function() test.load("../shell/init.lua",{source=HOST,size={100,100}}) end)

-- The steps of fingers landing at `starts` at once, moving by dx,dy over `ms`
-- in `steps`, and lifting.
local function stroke(starts,dx,dy,ms,steps,options)
  options=options or {}
  local out,t={},options.at or 0
  for i,s in ipairs(starts) do out[#out+1]={"down",i,s[1],s[2],t} end
  out[#out+1]={"frame",t}
  for n=1,steps do
    local now=t+ms*n/steps
    for i,s in ipairs(starts) do
      local f=options.still and options.still[i] and 0 or 1
      out[#out+1]={"move",i,s[1]+f*dx*n/steps,s[2]+f*dy*n/steps}
    end
    out[#out+1]={"frame",now}
  end
  local last=t+ms
  for i in ipairs(starts) do out[#out+1]={"up",i,last+1} end
  out[#out+1]={"frame",last+1}
  return out
end
local function drive(steps,keyboard) return test.ipc("drive",(keyboard and "KEYBOARD" or "")..morf.json.encode(steps)) end
local function kinds(log)
  local out={}
  for _,e in ipairs(log) do out[#out+1]=e.phase end
  return table.concat(out," "):gsub("update ",""):gsub(" update","")
end
local function first(log) return log[1] or {} end
local function last(log) return log[#log] or {} end

test.describe("two fingers",function()
  test.it("go up from the bottom with one finger far above the old strip",function()
    local log=drive(stroke({{640,770},{720,700}},0,-300,300,24))
    test.eq(kinds(log),"begin end")
    test.eq(first(log).kind,"swipe") test.eq(first(log).fingers,2)
    test.eq(first(log).direction,"up") test.eq(first(log).edge,"bottom")
    test.eq(test.ipc("key",morf.json.encode(first(log))),"two_up_bottom")
    test.truthy(last(log).committed)
  end)
  test.it("count a finger near an edge, wherever the other is",function()
    local log=drive(stroke({{640,790},{700,300}},0,-200,200,20))
    test.eq(first(log).edge,"bottom")
  end)
  test.it("swipe in from each edge the way that leaves it",function()
    test.eq(first(drive(stroke({{640,20},{700,90}},0,200,200,20))).edge,"top")
    test.eq(first(drive(stroke({{20,400},{90,460}},200,0,200,20))).edge,"left")
    test.eq(first(drive(stroke({{1260,400},{1190,460}},-200,0,200,20))).edge,"right")
  end)
  test.it("never fire in the middle of the screen, however far or slow",function()
    for _,way in ipairs {{0,-300},{0,300},{300,0},{-300,0}} do
      test.eq(#drive(stroke({{600,300},{680,300}},way[1],way[2],4000,200)),0)
      test.eq(#drive(stroke({{600,300},{680,300}},way[1],way[2],150,10)),0)
    end
  end)
  test.it("do nothing along an edge or toward it",function()
    test.eq(#drive(stroke({{300,780},{380,780}},400,0,300,20)),0)
    test.eq(#drive(stroke({{640,740},{720,740}},0,50,300,20)),0)
  end)
  test.it("stay spent once a scroll has been read, even if it reaches an edge",function()
    test.eq(#drive(stroke({{600,400},{680,400}},0,380,500,40)),0)
    local run=stroke({{600,400},{680,400}},0,-100,300,10)
    test.eq(#drive(run),0)
  end)
  test.it("swipe down from anywhere on the keyboard",function()
    local log=drive(stroke({{500,600},{700,620}},0,150,200,20),true)
    test.eq(first(log).region,"keyboard")
    test.eq(test.ipc("key",morf.json.encode(first(log))),"two_down_keyboard")
    test.truthy(last(log).committed)
  end)
end)

test.describe("one finger",function()
  test.it("is named from an edge, and is nothing in the middle",function()
    local log=drive(stroke({{640,790}},0,-200,200,20))
    test.eq(first(log).fingers,1) test.eq(first(log).edge,"bottom")
    test.eq(#drive(stroke({{640,400}},0,-200,200,20)),0)
  end)
end)

test.describe("three or more fingers",function()
  for _,count in ipairs {3,4,5} do
    local starts={}
    for i=1,count do starts[i]={400+i*70,400+(i%2)*30} end
    for name,way in pairs {up={0,-200},down={0,200},left={-200,0},right={200,0}} do
      test.it(count.." go "..name.." anywhere",function()
        local log=drive(stroke(starts,way[1],way[2],250,20))
        test.eq(kinds(log),"begin end")
        test.eq(first(log).fingers,count) test.eq(first(log).direction,name)
        test.eq(first(log).edge,nil)
        test.truthy(last(log).committed)
      end)
    end
  end
  test.it("say which edge they started from when they did",function()
    local log=drive(stroke({{500,780},{570,770},{640,760}},0,-200,250,20))
    test.eq(first(log).edge,"bottom")
    test.eq(test.ipc("key",morf.json.encode(first(log))),"three_up")
  end)
  test.it("do not count as a swipe when one stays behind",function()
    test.eq(#drive(stroke({{500,300},{570,300},{640,300}},0,200,250,20,{still={[3]=true}})),0)
  end)
  test.it("go on when one lifts first, with no jump",function()
    local steps={{"down",1,300,300,0},{"down",2,370,300,0},{"down",3,440,300,0},{"frame",0}}
    for n=1,10 do
      for i=1,3 do steps[#steps+1]={"move",i,230+i*70+0,300+n*10} end
      steps[#steps+1]={"frame",n*10}
    end
    steps[#steps+1]={"up",3,105}
    steps[#steps+1]={"frame",105}
    for n=11,20 do
      for i=1,2 do steps[#steps+1]={"move",i,230+i*70,300+n*10} end
      steps[#steps+1]={"frame",n*10}
    end
    steps[#steps+1]={"up",1,210} steps[#steps+1]={"up",2,210} steps[#steps+1]={"frame",210}
    local log=drive(steps)
    local before
    for _,e in ipairs(log) do
      if e.phase=="update" then
        if before then test.truthy(math.abs(e.dy-before)<=11,"a jump: "..before.." to "..e.dy) end
        before=e.dy
      end
    end
    test.truthy(before>=190)
    test.eq(last(log).phase,"end")
  end)
end)

test.describe("a resting finger",function()
  local function landed()
    return {{"down","thumb",30,700,0},{"frame",0}}
  end
  test.it("stays out of what lands later, so two more are still a scroll",function()
    local steps=landed()
    for _,s in ipairs(stroke({{600,300},{680,300}},0,300,300,20,{at=900})) do steps[#steps+1]=s end
    test.eq(#drive(steps),0)
  end)
  test.it("leaves three others free to swipe",function()
    local steps=landed()
    for _,s in ipairs(stroke({{600,300},{680,300},{760,300}},-300,0,300,20,{at=900})) do steps[#steps+1]=s end
    local log=drive(steps)
    test.eq(first(log).fingers,3) test.eq(first(log).direction,"left")
  end)
end)

test.describe("a finger joining late",function()
  test.it("within the gather makes it the larger gesture",function()
    local steps={{"down",1,500,300,0},{"down",2,570,300,0},{"down",3,640,300,0},{"frame",0}}
    for n=1,6 do
      for i=1,3 do steps[#steps+1]={"move",i,430+i*70,300+n*8} end
      steps[#steps+1]={"frame",n*16}
    end
    steps[#steps+1]={"down",4,710,348,100}
    steps[#steps+1]={"frame",100}
    for n=7,30 do
      for i=1,3 do steps[#steps+1]={"move",i,430+i*70,300+n*8} end
      steps[#steps+1]={"move",4,710,300+n*8}
      steps[#steps+1]={"frame",n*16}
    end
    for i=1,4 do steps[#steps+1]={"up",i,500} end
    steps[#steps+1]={"frame",500}
    local log=drive(steps)
    test.eq(kinds(log),"begin cancel begin end")
    test.eq(first(log).fingers,3)
    test.eq(last(log).fingers,4)
  end)
end)

test.describe("a pinch",function()
  local function around(n,r)
    local out={}
    for i=1,n do
      local a=2*math.pi*i/n
      out[i]={640+r*math.cos(a),400+r*math.sin(a)}
    end
    return out
  end
  local function pinch(n,from,to,ms)
    local steps={}
    local a,b=around(n,from),around(n,to)
    for i=1,n do steps[#steps+1]={"down",i,a[i][1],a[i][2],0} end
    steps[#steps+1]={"frame",0}
    for s=1,20 do
      for i=1,n do
        steps[#steps+1]={"move",i,a[i][1]+(b[i][1]-a[i][1])*s/20,a[i][2]+(b[i][2]-a[i][2])*s/20}
      end
      steps[#steps+1]={"frame",ms*s/20}
    end
    for i=1,n do steps[#steps+1]={"up",i,ms+1} end
    steps[#steps+1]={"frame",ms+1}
    return steps
  end
  for _,n in ipairs {3,4,5} do
    test.it(n.." fingers close in",function()
      local log=drive(pinch(n,220,60,300))
      test.eq(first(log).kind,"pinch") test.eq(first(log).direction,"in") test.eq(first(log).fingers,n)
      test.truthy(last(log).committed)
    end)
    test.it(n.." fingers spread out",function()
      local log=drive(pinch(n,60,220,300))
      test.eq(first(log).direction,"out")
      test.truthy(last(log).committed)
    end)
  end
  test.it("is named for what it binds",function()
    test.eq(test.ipc("key",morf.json.encode(first(drive(pinch(5,220,60,300))))),"five_pinch_in")
  end)
  test.it("is not two fingers: that is an app's zoom",function()
    test.eq(#drive(pinch(2,220,60,300)),0)
  end)
  test.it("a small squeeze commits to nothing",function()
    local log=drive(pinch(4,220,180,300))
    test.falsy(last(log).committed)
  end)
end)

test.describe("taps and holds",function()
  for _,n in ipairs {1,2,3,4,5} do
    test.it(n.." fingers tap",function()
      local steps={}
      for i=1,n do steps[#steps+1]={"down",i,300+i*70,300,i*5} end
      steps[#steps+1]={"frame",30}
      for i=1,n do steps[#steps+1]={"up",i,120} end
      steps[#steps+1]={"frame",120}
      local log=drive(steps)
      test.eq(kinds(log),"begin end")
      test.eq(first(log).kind,"tap") test.eq(first(log).fingers,n)
    end)
    test.it(n.." fingers hold",function()
      local steps={}
      for i=1,n do steps[#steps+1]={"down",i,300+i*70,300,0} end
      steps[#steps+1]={"frame",0}
      steps[#steps+1]={"tick",300}
      steps[#steps+1]={"tick",520}
      for i=1,n do steps[#steps+1]={"up",i,900} end
      steps[#steps+1]={"frame",900}
      local log=drive(steps)
      test.eq(first(log).kind,"hold") test.eq(first(log).fingers,n)
      test.eq(last(log).phase,"end")
    end)
  end
  test.it("too long for a tap and too short for a hold is nothing",function()
    test.eq(#drive({{"down",1,300,300,0},{"down",2,370,300,0},{"down",3,440,300,0},{"frame",0},
      {"up",1,400},{"up",2,400},{"up",3,400},{"frame",400}}),0)
  end)
  test.it("a finger that moved does not tap",function()
    test.eq(#drive({{"down",1,300,300,0},{"down",2,370,300,0},{"down",3,440,300,0},{"frame",0},
      {"move",1,300,320},{"frame",50},{"up",1,100},{"up",2,100},{"up",3,100},{"frame",100}}),0)
  end)
end)

test.describe("the end of a swipe",function()
  local fingers={{500,400},{570,400},{640,400}}
  test.it("commits past its travel, at any speed",function()
    test.truthy(last(drive(stroke(fingers,-120,0,3000,60))).committed)
  end)
  test.it("does not commit short of it, slowly",function()
    test.falsy(last(drive(stroke(fingers,-60,0,3000,60))).committed)
  end)
  test.it("commits a short fast flick",function()
    local log=drive(stroke(fingers,-60,0,80,8))
    test.truthy(last(log).committed)
    test.truthy(last(log).vx<-450)
  end)
  test.it("gives velocity and progress from 0 to 1",function()
    local log=drive(stroke(fingers,-200,0,200,20))
    local seen=0
    for _,e in ipairs(log) do
      test.truthy(e.progress>=seen)
      seen=e.progress
    end
    test.eq(seen,1)
    test.near(last(log).vx,-1000,250)
  end)
  test.it("does not commit when thrown back the way it came",function()
    local steps={}
    for i,f in ipairs(fingers) do steps[#steps+1]={"down",i,f[1],f[2],0} end
    steps[#steps+1]={"frame",0}
    for n=1,20 do
      for i,f in ipairs(fingers) do steps[#steps+1]={"move",i,f[1]-n*10,f[2]} end
      steps[#steps+1]={"frame",n*16}
    end
    for n=1,8 do
      for i,f in ipairs(fingers) do steps[#steps+1]={"move",i,f[1]-200+n*22,f[2]} end
      steps[#steps+1]={"frame",320+n*16}
    end
    for i in ipairs(fingers) do steps[#steps+1]={"up",i,450} end
    steps[#steps+1]={"frame",450}
    test.falsy(last(drive(steps)).committed)
  end)
  test.it("cancels when told to",function()
    local run=stroke(fingers,-200,0,200,20)
    for _=1,4 do table.remove(run) end
    run[#run+1]={"cancel"}
    local log=drive(run)
    test.eq(last(log).phase,"cancel")
  end)
end)
