-- Power readings and profile actions shared by visual packages.
local morf=require("morf")
local services=require("services")
local M={}
M.PROFILES={
  {id="power-saver",icon="energy_savings_leaf",name="Power saver",short="Saver",hint="Longest battery"},
  {id="balanced",icon="balance",name="Balanced",hint="The default"},
  {id="performance",icon="rocket_launch",name="Performance",short="Fast",hint="Fastest, hottest"},
}
function M.new(active,open_battery)
  local model=require("battery_model").new {opened=active}
  model.key,model.PROFILES="power",M.PROFILES
  model.message=morf.signal("eva.power.message","")
  local cached={available=false,active="",degraded="",supported={}}
  local function profiles()
    if not active() then return cached end
    local u=services.upower
    local p=u and u.state and u.state.profiles
    local supported={}
    if p and p.list then
      for i=1,p.list:len() do supported[p.list:get(i).name]=true end
    end
    cached={available=p and p.available==true or false,active=p and p.active or "",
      degraded=p and p.degraded or "",supported=supported}
    return cached
  end
  function model.profile() return profiles().active end
  function model.profile_available() return profiles().available end
  function model.supports(id) local p=profiles() return p.available and p.supported[id]==true end
  function model.profile_note()
    local p=profiles()
    if not p.available then return "Power profile service is unavailable." end
    if p.degraded~="" then return "Performance limited: "..p.degraded end
    return "Choose how the system balances energy and speed."
  end
  model.charge=require("charge_limit_model")
  model.charge.probe()
  --- Whether the Charging section has anything to say.
  function model.charging_shown()
    return model.present() and (model.state().ac==true or model.charging() or model.feed().kind~=nil
      or model.charge.route()~="")
  end
  function model.charger_icon()
    local f=model.feed()
    if f.wireless then return "contactless" end
    if model.charging() then return f.fast and "bolt" or "battery_charging_full" end
    return "power"
  end
  function model.select(id)
    if not active() then return false end
    local known=false
    for _,p in ipairs(M.PROFILES) do if id==p.id then known=true break end end
    if not known or not model.supports(id) then return false end
    local dry=morf.env("EVA_DRY_RUN")
    if dry and dry~="" and dry~="0" then return false end
    if model.profile()==id then return true end
    local ok,result,err=pcall(services.upower.set_profile,id)
    model.message:set(ok and result and "" or tostring(ok and (err or "Could not change power mode.") or result))
    return ok and not not result
  end
  function model.open_battery() if active() then open_battery() end end
  function model.summary()
    local s,b=model.state(),model.battery()
    local seconds=b.status=="Discharging" and s.time_left or model.to_target()
    local words=b.status or "No battery"
    if seconds and seconds>0 then
      local left=model.duration(seconds)
      local target=model.target()
      words=words..(b.status=="Discharging" and (", "..left.." left")
        or ((target<100 and (", %d%% in "):format(target) or ", full in ")..left))
    end
    if b.power and b.power>.05 and not model.charging() then words=words..("  ·  %.1f W"):format(b.power) end
    return words
  end
  model.FACTS={
    {key="health",name="Health",value=function() local b=model.battery() return b.health and ("%d%%"):format(math.floor(b.health+.5)) or "--" end},
    {key="limit",name="Charge limit",value=function()
      local b=model.battery()
      if not b.charge_limit then return "--" end
      return b.charge_start and ("%d–%d%%"):format(b.charge_start,b.charge_limit) or ("%d%%"):format(b.charge_limit)
    end},
    {key="mode",name="Charge mode",value=function() return model.battery().charge_mode or "--" end},
    {key="cycles",name="Cycles",value=function() local n=model.battery().cycles return n and tostring(n) or "--" end},
    {key="temperature",name="Temperature",value=function() local n=model.battery().temperature return n and ("%.1f °C"):format(n) or "--" end},
  }
  morf.effect("eva.power.visibility",function() if not active() then model.message:set("") end end)
  -- The charge limit, the module eva-battery runs too.
  local charge=require("lib.services.charge_limit").new()
  morf.effect("eva.power.charge",function() if active() then charge.refresh() end end)
  function model.limit_supported() return charge.state:get().supported==true end
  function model.limit_on() return charge.state:get().enabled==true end
  function model.limit_note()
    local message=charge.message:get()
    if message~="" then return message end
    local s=charge.state:get()
    if not s.stop then return "Stops charging early to spare the battery" end
    return s.start and ("Holds the charge between %d and %d%%"):format(s.start,s.stop)
      or ("Stops charging at %d%%"):format(s.stop)
  end
  function model.set_limit(on) charge.set(on) end
  return model
end
return M
