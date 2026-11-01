-- Battery readings and bounded source history, independent of presentation.
local sysinfo=require("lib.services.sysinfo")
local charger=require("lib.services.charger")
local M={}
function M.duration(seconds)
  if not seconds or seconds<=0 then return "--" end
  local h,m=seconds//3600,(seconds%3600)//60
  return h>0 and ("%dh %02dm"):format(h,m) or ("%dm"):format(m)
end
function M.number(value,format) return value and format:format(value) or "--" end
-- What a charger's USB protocol is called.
local PROTOCOLS={PD="USB PD",PD_PPS="USB PD",PD_DRP="USB PD",DCP="USB charger",CDP="USB port",SDP="USB port",C="USB-C"}
local NONE={present=false,fast=false,slow=false,wireless=false}
-- The stand-in for UPower, where one stands in.
local function stand_in()
  local ok,upower=pcall(function() return require("services").upower end)
  return ok and upower or nil
end
function M.new(ctx)
  local model={active=ctx.opened,samples=sysinfo.history_size,
    interval=sysinfo.sources.battery.interval,number=M.number,duration=M.duration}
  model.minutes=("%d min"):format(math.floor(model.samples*model.interval/60000+.5))
  local last={batteries={}}
  local series={}
  local feed,feed_of=NONE,nil
  function model.state()
    if model.active() then
      local upower=stand_in()
      local ok,value=pcall(upower and upower.sysinfo or sysinfo.battery)
      last=ok and type(value)=="table" and value or {batteries={}}
    end
    return last
  end
  function model.battery() return (model.state().batteries or {})[1] or {} end
  function model.charging() return model.battery().status=="Charging" end
  function model.present() return model.battery().name~=nil end
  --- What feeds the battery, read once per sample.
  function model.feed()
    local state=model.state()
    if state~=feed_of then
      feed_of=state
      local upower=stand_in()
      local ok,value=pcall(upower and upower.charger or charger.read)
      feed=ok and type(value)=="table" and value or NONE
    end
    return feed
  end
  --- The charge it is heading for: the limit where there is one.
  function model.target()
    local limit=model.battery().charge_limit
    return limit and limit<100 and limit or 100
  end
  --- Seconds until it gets there, at the present rate.
  function model.to_target()
    local state=model.state()
    if not model.charging() then return nil end
    local target=model.target()
    if target>=100 then return state.time_to_full end
    local b,f=model.battery(),model.feed()
    local left=charger.seconds_to(b.capacity,target,f.capacity or b.energy_full,f.watts or b.power)
    return left>0 and left or state.time_to_full
  end
  function model.series(field)
    if model.active() then
      local key="bat:"..(model.battery().name or "BAT0")..":"..field
      local ok,value=pcall(sysinfo.history,key)
      series[field]=ok and type(value)=="table" and value or {}
    end
    return series[field] or {}
  end
  function model.remaining()
    local state=model.state()
    return M.duration(model.charging() and model.to_target() or state.time_left)
  end
  --- What is charging it, in words: "USB PD", "Wireless", or "Unplugged".
  function model.charger_name()
    local f=model.feed()
    if f.wireless then return "Wireless" end
    if f.kind=="usb" then return PROTOCOLS[f.protocol or ""] or "USB" end
    if f.kind=="mains" then return "Mains" end
    return model.state().ac and "Plugged in" or "Unplugged"
  end
  --- What is happening to the charge, in a few words.
  function model.charge_title()
    local f,b=model.feed(),model.battery()
    if model.charging() then
      local words={}
      if f.fast then words[#words+1]="Fast" end
      if f.wireless then words[#words+1]=#words>0 and "wireless" or "Wireless" end
      words[#words+1]=#words>0 and "charging" or (f.slow and "Slow charging" or "Charging")
      return table.concat(words," ")
    end
    if b.status=="Not charging" and model.target()<100 then return ("Held at %d%%"):format(model.target()) end
    if b.status=="Full" then return "Full" end
    return model.state().ac and "Plugged in" or "Not plugged in"
  end
  --- The rate, the charger and the time left, each where it is known.
  function model.charge_detail()
    local f,b=model.feed(),model.battery()
    local parts={}
    local watts=f.watts or (model.charging() and b.power) or nil
    if watts and watts>.05 then parts[#parts+1]=("%.1f W"):format(watts) end
    if f.kind then parts[#parts+1]=model.charger_name() end
    local left=model.to_target()
    if left and left>0 then
      local target=model.target()
      parts[#parts+1]=(target<100 and ("%d%% in "):format(target) or "Full in ")..M.duration(left)
    end
    return table.concat(parts,"  ·  ")
  end
  --- What a weak charger is told, or "".
  function model.charge_hint()
    return model.charging() and model.feed().slow and "This charger is weak: a stronger one would be faster." or ""
  end
  function model.limit()
    local b=model.battery()
    if not b.charge_limit then return "--" end
    return b.charge_start and ("%d–%d %%"):format(b.charge_start,b.charge_limit) or ("%d %%"):format(b.charge_limit)
  end
  function model.voltage_bottom()
    local design=model.battery().voltage_design or 0
    local low=design>0 and design*.92 or 0
    for _,v in ipairs(model.series("voltage")) do if v>0 and v<low then low=v*.98 end end
    return low
  end
  function model.voltage_top()
    local peak=(model.battery().voltage_design or 0)*1.05
    for _,v in ipairs(model.series("voltage")) do peak=math.max(peak,v*1.02) end
    return math.max(1,peak)
  end
  return model
end
return M
