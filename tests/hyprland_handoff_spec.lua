-- nix/nixos/scripts/hyprland-handoff.lua against a stand-in for Hyprland and a
-- stand-in for the disk: no compositor, and nothing is written.
local test=morf.test
local SOURCE=morf.fs.read("nix/nixos/scripts/hyprland-handoff.lua")

local function scenario(files,monitors)
  local rules,events,timers,renamed={},{},{},{}
  local function reader(path,mode)
    if mode=="w" then
      local written={}
      return {write=function(_,...) for _,text in ipairs {...} do written[#written+1]=text end end,
        close=function() files[path]=table.concat(written) end}
    end
    local text=files[path]
    if not text then return nil end
    return {read=function() return text:match("^[^\n]*") end,close=function() end,
      lines=function() return text:gmatch("[^\n]+") end}
  end
  local env=setmetatable({
    hl={monitor=function(rule) rules[#rules+1]=rule end,
      on=function(name,fn) events[name]=fn end,
      get_monitors=function() return monitors or {} end,
      timer=function(fn,options)
        local timer={fn=fn,options=options,enabled=true}
        function timer:is_enabled() return self.enabled end
        function timer:set_enabled(value) self.enabled=value end
        timers[#timers+1]=timer
        return timer
      end},
    io={open=reader},
    os={rename=function(from,to) files[to]=files[from] files[from]=nil renamed[#renamed+1]=to end},
  },{__index=_G})
  local handoff=assert(load(SOURCE,"hyprland-handoff","t",env))()
  return handoff,{rules=rules,events=events,timers=timers,files=files,renamed=renamed}
end

local PANEL={name="eDP-1",description="BOE 0x0BCA",width=2256,height=1504,refresh_rate=59.999,
  x=0,y=0,scale=1.5,transform=0,is_mirror=false}
local DESK={name="DP-2",description="LG 27GL850 007NTAB",width=3840,height=2160,refresh_rate=144,
  x=1504,y=-200,scale=2,transform=3,is_mirror=false}

test.describe("hyprland handoff",function()
  test.it("the background is the bridge's colour, or the fallback",function()
    local handoff=scenario {good="#1A2b3C\n",bad="not a colour\n",short="#123\n"}
    test.eq(handoff.background("good","rgb(000000)"),"rgb(1a2b3c)")
    test.eq(handoff.background("bad","rgb(000000)"),"rgb(000000)")
    test.eq(handoff.background("short","rgb(000000)"),"rgb(000000)")
    test.eq(handoff.background("missing","rgb(000000)"),"rgb(000000)")
  end)

  test.it("the session's outputs come back to the greeter as monitor rules",function()
    local files={}
    local handoff,run=scenario(files,{PANEL,DESK})
    handoff.record("outputs")
    run.events["hyprland.start"]()
    test.eq(#run.timers,1)
    run.timers[1].fn()
    test.eq(run.renamed,{"outputs"})
    local greeter,seen=scenario(files)
    greeter.adopt("outputs")
    test.eq(seen.rules,{
      {output="desc:BOE 0x0BCA",mode="2256x1504@59.999",position="0x0",scale=1.5,transform=0},
      {output="desc:LG 27GL850 007NTAB",mode="3840x2160@144.000",position="1504x-200",scale=2,transform=3},
    })
  end)

  test.it("outputs that share a description are told apart by connector",function()
    local twin={name="DP-3",description=DESK.description,width=1920,height=1080,refresh_rate=60,
      x=0,y=0,scale=1,transform=0,is_mirror=false}
    local files={}
    local handoff,run=scenario(files,{DESK,twin})
    handoff.record("outputs")
    run.events["monitor.added"]()
    run.timers[1].fn()
    test.truthy(files.outputs:match("^DP%-2\t"))
    test.truthy(files.outputs:match("\nDP%-3\t"))
  end)

  test.it("settling outputs write once, and a mirror is left out",function()
    local files={}
    local handoff,run=scenario(files,{PANEL,{name="HDMI-A-1",description="x",is_mirror=true}})
    handoff.record("outputs")
    run.events["monitor.added"]()
    run.events["monitor.layout_changed"]()
    test.eq(#run.timers,2)
    test.falsy(run.timers[1].enabled)
    test.truthy(run.timers[2].enabled)
    run.timers[2].fn()
    test.eq(select(2,files.outputs:gsub("\n","")),1)
  end)

  test.it("no outputs leave the last description alone",function()
    local files={outputs="kept"}
    local handoff,run=scenario(files,{})
    handoff.record("outputs")
    run.events["hyprland.start"]()
    run.timers[1].fn()
    test.eq(files.outputs,"kept")
  end)

  test.it("a line the session could not have written is refused",function()
    local bad={
      "desc:x\tpreferred\t0x0\t1\t0",
      "desc:x\t1920x1080@60\tauto\t1\t0",
      "desc:x\t1920x1080@60\t0x0\t100\t0",
      "desc:x\t1920x1080@60\t0x0\t1\t9",
      "desc:x\t1920x1080@60\t0x0\t1\t1.5",
      "bad key\t1920x1080@60\t0x0\t1\t0",
      "desc:x\t1920x1080@60\t0x0",
    }
    local files={outputs=table.concat(bad,"\n").."\nDP-1\t1920x1080@60\t0x0\t1\t0\n"}
    local handoff,run=scenario(files)
    handoff.adopt("outputs")
    test.eq(run.rules,{{output="DP-1",mode="1920x1080@60",position="0x0",scale=1,transform=0}})
    local fresh,none=scenario {}
    fresh.adopt("missing")
    test.eq(none.rules,{})
  end)
end)
