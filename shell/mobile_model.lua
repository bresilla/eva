-- Mobile broadband: ModemManager supplies the radio, NetworkManager owns
-- connections. Keep action state separate from the modem's observed state.
local morf=require("morf")
local services=require("services")
local cli=require("mobile_cli")
local M={}
local function each(list,fn)
  if list then for i=1,list:len() do fn(list:get(i)) end end
end
local function mobile(row) return row.type=="gsm" or row.type=="cdma" end
local function dry_run()
  local v=morf.env("EVA_DRY_RUN")
  return v~=nil and v~="" and v~="0"
end
function M.new(active)
  local snapshot=morf.signal("eva.mobile.snapshot",{available=false,rows={}})
  local model={key="mobile",active=active,
    message=morf.signal("eva.mobile.message",""),
    failed=morf.signal("eva.mobile.failed",false),
    pending=morf.signal("eva.mobile.pending",false)}
  local serial=0
  local function read()
    local modem,net=services.modem,services.net
    if not modem or not modem.state.available then return {available=false,rows={}} end
    local s=modem.state
    local value={available=true,data=s.data,locked=s.locked,sim=s.sim_present,
      registered=s.registered,connected=s.connected,roaming=s.roaming,
      operator=s.operator,technology=s.technology,signal=s.signal,rows={},
      managed=net~=nil and net.state.available==true}
    if value.managed then
      local connections={}
      each(net.state.active_connections,function(row)
        if mobile(row) then connections[row.connection]=row end
      end)
      each(net.state.known_connections,function(row)
        if not mobile(row) then return end
        local live=connections[row.path]
        value.rows[#value.rows+1]={path=row.path,name=row.id,uuid=row.uuid,
          apn=row.apn or "",auto_apn=row.auto_apn==true,user=row.apn_user or "",
          roaming=row.home_only~=true,ip_type=cli.ip_type(row),
          active=live and live.path or "",state=live and live.state or "disconnected"}
      end)
      table.sort(value.rows,function(a,b)
        if (a.active~="")~=(b.active~="") then return a.active~="" end
        if a.name~=b.name then return a.name<b.name end
        return a.path<b.path
      end)
    end
    return value
  end
  morf.effect("eva.mobile.read",function()
    if not active() then
      serial=serial+1
      model.message:set("") model.failed:set(false) model.pending:set(false)
      return
    end
    snapshot:set(read())
  end)
  function model.available() return snapshot:get().available==true end
  function model.enabled() return snapshot:get().data==true end
  function model.list() return snapshot:get().rows end
  function model.carrier()
    local s=snapshot:get()
    return s.operator and s.operator~="" and s.operator or "Mobile network"
  end
  function model.status()
    local s=snapshot:get()
    if not s.available then return "No modem" end
    if s.locked then return "SIM locked" end
    if not s.sim then return "No SIM detected" end
    if not s.data then return "Mobile data is off" end
    if s.connected then return s.roaming and "Connected · Roaming" or "Connected" end
    if s.registered then return s.roaming and "Registered · Roaming" or "Registered · Not connected" end
    return "Searching for a network"
  end
  function model.signal()
    local s=snapshot:get()
    if not s.registered then return "No network signal" end
    return (s.technology~="" and (s.technology.." · ") or "")..tostring(s.signal or 0).."% signal"
  end
  function model.can_connect()
    local s=snapshot:get()
    return s.available and s.managed and s.data and s.sim and not s.locked and not model.pending:get()
  end
  function model.can_toggle()
    local s=snapshot:get()
    return s.available and s.managed and not model.pending:get()
  end
  local function action(label,invoke)
    if not active() or dry_run() or model.pending:get() then return false end
    local s=read()
    if not s.available or not s.managed then return false end
    serial=serial+1
    local request=serial
    model.message:set(label) model.failed:set(false) model.pending:set(true)
    local function done(result,err)
      if request~=serial or not active() then return end
      model.pending:set(false)
      model.failed:set(result==nil or result==false)
      model.message:set(result~=nil and result~=false and "Request sent" or tostring(err or "Request failed"))
    end
    local ok,result,err=pcall(invoke,services.net,s,done)
    if not ok then done(nil,result) return false end
    if result==nil or result==false then done(nil,err) return false end
    return true
  end
  function model.set_enabled(on)
    return action("Changing mobile data…",function(net,_,done) return net.set_wwan(on==true,done) end)
  end
  function model.choose(target)
    return action("Changing connection…",function(net,s,done)
      for _,row in ipairs(s.rows) do
        if row.path==target.path then
          if row.active~="" then return net.deactivate(row.active,done) end
          if not s.data or not s.sim or s.locked then return nil,"Enable mobile data and unlock the SIM first" end
          return net.activate(row.path,done)
        end
      end
      return nil,"Connection no longer exists"
    end)
  end
  function model.setup()
    return action("Setting up mobile data…",function(net,s,done)
      if #s.rows>0 then return nil,"A mobile connection already exists" end
      if not s.data or not s.sim or s.locked then return nil,"Enable mobile data and unlock the SIM first" end
      return net.connect_mobile(done)
    end)
  end
  function model.note()
    local s=snapshot:get()
    if s.available and not s.managed then return "NetworkManager is not running" end
    return "Automatic APN can pick the visited network's APN abroad; set your provider's APN if roaming fails"
  end

  -- Details from the command lines: modem, SIM, recent bearers, diagnosis.
  model.details=morf.signal("eva.mobile.details",{})
  model.networks=morf.signal("eva.mobile.networks",{})
  model.scanning=morf.signal("eva.mobile.scanning",false)
  model.ussd_reply=morf.signal("eva.mobile.ussd",{text="",open=false})
  local reading=false
  function model.refresh()
    if reading or not model.available() then return end
    reading=true
    cli.run({"mmcli","-J","-m","any"},function(ok,out)
      local modem=ok and cli.modem(cli.json(out)) or nil
      if not modem then reading=false model.details:set({}) return end
      local found,bearers,waiting={modem=modem},{},0
      local function finish()
        waiting=waiting-1
        if waiting>0 then return end
        table.sort(bearers,function(a,b) return a.order<b.order end)
        found.bearers=bearers
        found.diagnosis=cli.diagnose(modem,bearers)
        reading=false
        model.details:set(found)
      end
      local jobs={}
      if modem.sim then jobs[#jobs+1]={"mmcli","-J","-i",modem.sim} end
      for i=1,math.min(4,#modem.bearers) do jobs[#jobs+1]={"mmcli","-J","-b",modem.bearers[i],order=i} end
      waiting=#jobs+1
      for _,argv in ipairs(jobs) do
        cli.run(argv,function(fine,text)
          local reply=fine and cli.json(text)
          if reply and reply.sim then found.sim=cli.sim(reply) end
          local b=reply and reply.bearer and cli.bearer(reply)
          if b then b.order=argv.order bearers[#bearers+1]=b end
          finish()
        end)
      end
      finish()
    end)
  end
  morf.effect("eva.mobile.details.open",function() if active() then model.refresh() end end)
  morf.time.timer(15000,function() if active() then model.refresh() end end,true)

  -- A command-line action: label while it runs, the outcome after, a refresh.
  local function steps(label,commands,after,finally)
    if not active() or model.pending:get() then return false end
    if dry_run() then morf.log("info","eva: mobile "..label.." (dry run)") return false end
    serial=serial+1
    local request=serial
    model.message:set(label) model.failed:set(false) model.pending:set(true)
    local i=0
    local function step(ok,out,err)
      if request~=serial then return end
      if ok==false then
        model.pending:set(false) model.failed:set(true) model.message:set(err~="" and err or "Request failed")
        if finally then finally() end
        model.refresh() return
      end
      i=i+1
      if i>#commands then
        model.pending:set(false) model.message:set("Done")
        if finally then finally() end
        if after then after(out) end
        if services.net then pcall(services.net.refresh) end
        model.refresh() return
      end
      local c=commands[i]
      if c.call then c.call(step) else cli.run(c,step,c.timeout) end
    end
    step(nil)
    return true
  end
  local function current_profile()
    local rows=model.list()
    for _,r in ipairs(rows) do if (r.active or "")~="" then return r end end
    return rows[1]
  end
  local function reconnect(uuid)
    if not model.enabled() then return {} end
    return {{"nmcli","connection","up",uuid,timeout=90000}}
  end

  --- One profile's APN ("" automatic), user, password, IP type or roaming.
  function model.save_profile(row,change)
    if not row or not row.uuid then return false end
    local commands={cli.profile_args(row.uuid,change)}
    for _,c in ipairs(reconnect(row.uuid)) do commands[#commands+1]=c end
    return steps("Saving the mobile profile…",commands)
  end
  --- Mobile radio off and on: clears a network's throttling of new attempts.
  function model.reset_radio()
    local row=current_profile()
    local commands={{"sh","-c","nmcli radio wwan off; sleep 6; nmcli radio wwan on; sleep 6",timeout=60000}}
    if row then for _,c in ipairs(reconnect(row.uuid)) do commands[#commands+1]=c end end
    return steps("Restarting the mobile radio…",commands)
  end
  --- The diagnosis' fix: IP type, radio reset, or the APN that worked before.
  function model.fix()
    local d=(model.details:get() or {}).diagnosis
    local row=current_profile()
    if not d or not d.fix then return false end
    if d.fix=="ipv4" or d.fix=="ipv6" then return model.save_profile(row,{ip_type=d.fix}) end
    if d.fix=="reset" then return model.reset_radio() end
    if d.fix=="apn" and d.apn then return model.save_profile(row,{apn=d.apn}) end
    model.failed:set(true) model.message:set(d.fix=="unlock" and "Enter the SIM PIN below" or "Enter your provider's APN below")
    return false
  end
  function model.diagnosis() return (model.details:get() or {}).diagnosis end
  function model.fix_label()
    local d=model.diagnosis() or {}
    return ({ipv4="Use IPv4 only",ipv6="Use IPv6 only",reset="Restart mobile radio",
      unlock="Unlock SIM"})[d.fix] or (d.fix=="apn" and (d.apn and ("Use "..d.apn) or "Set APN")) or ""
  end

  --- Network mode choices this modem supports, and the active one's id.
  function model.modes() local m=(model.details:get() or {}).modem return m and m.modes or {},m and m.mode end
  function model.set_mode(choice)
    local argv={"mmcli","-m","any"}
    for _,a in ipairs(cli.mode_args(choice)) do argv[#argv+1]=a end
    return steps("Switching to "..choice.name.."…",{argv})
  end
  --- Nearby operators (a scan takes minutes), then register or go automatic.
  function model.scan_networks()
    model.scanning:set(true)
    local started=steps("Scanning for networks (this takes a few minutes)…",
      {{"mmcli","-J","-m","any","--3gpp-scan","--timeout=300",timeout=330000}},
      function(out) model.networks:set(cli.networks(cli.json(out))) end)
    if not started then model.scanning:set(false) end
    return started
  end
  morf.effect("eva.mobile.scan.done",function() if not model.pending:get() then model.scanning:set(false) end end)
  function model.register(code)
    if code then return steps("Registering on "..code.."…",{{"mmcli","-m","any","--3gpp-register-in-operator="..code,timeout=120000}}) end
    return steps("Choosing the network automatically…",{{"mmcli","-m","any","--3gpp-register-home",timeout=120000}})
  end

  --- SIM PIN: unlock, change, or turn the PIN lock on or off.
  local function sim_path() local m=(model.details:get() or {}).modem return m and m.sim end
  local function sim_step(label,method,arguments)
    local path,modem=sim_path(),services.modem
    if not path or not modem.sim_call then model.failed:set(true) model.message:set("No SIM") return false end
    return steps(label,{{call=function(done)
      modem.sim_call(path,method,arguments,function(ok,why) done(ok,"",tostring(why or "")) end)
    end}})
  end
  function model.unlock(pin) return sim_step("Unlocking the SIM…","SendPin",{pin}) end
  function model.change_pin(old,new) return sim_step("Changing the PIN…","ChangePin",{old,new}) end
  function model.set_pin_lock(pin,on) return sim_step(on and "Turning the PIN on…" or "Turning the PIN off…",
    "EnablePin",{pin,on==true}) end

  --- USSD codes such as *100#; a session may ask for a reply.
  function model.ussd(code)
    return steps("Sending "..code.."…",{{"mmcli","-m","any","--3gpp-ussd-initiate="..code,timeout=60000}},
      function(out) model.ussd_reply:set({text=cli.ussd(out),open=true}) end)
  end
  function model.ussd_respond(text)
    return steps("Replying…",{{"mmcli","-m","any","--3gpp-ussd-respond="..text,timeout=60000}},
      function(out) model.ussd_reply:set({text=cli.ussd(out),open=true}) end)
  end
  function model.ussd_cancel()
    model.ussd_reply:set({text="",open=false})
    return steps("Ending the USSD session…",{{"mmcli","-m","any","--3gpp-ussd-cancel"}})
  end

  --- The phone's conversations (shell/phone.lua), newest first.
  local function phone() return require("phone") end
  function model.threads()
    local p=phone()
    return p.ready:get() and p.messages.threads() or {}
  end
  function model.has_messages() return phone().ready:get() end
  function model.delete_thread(number)
    local p=phone()
    if p.messages then p.messages.forget(number) end
  end
  function model.send_message(number,text)
    number=(number or ""):gsub("[%s%-]","")
    if not number:match("^%+?%d+$") or (text or "")=="" then
      model.failed:set(true) model.message:set("Enter a phone number and a message") return false
    end
    model.failed:set(false) model.message:set("")
    return phone().reply(number,text)
  end

  --- What the radio measures, while the page is open.
  local function levels_source() return services.modem end
  morf.effect("eva.mobile.levels",function()
    local modem=levels_source()
    if modem and modem.watch_levels then modem.watch_levels(active() and model.available() and 5 or 0) end
  end)
  function model.levels()
    local modem=levels_source()
    if not modem or not modem.levels then return "" end
    local _=modem.state.level_stamp
    local l=modem.levels()
    if not l then return "" end
    local parts={l.radio}
    for _,entry in ipairs {{"rsrp","RSRP","dBm"},{"rsrq","RSRQ","dB"},{"snr","SNR","dB"},{"rscp","RSCP","dBm"},
      {"ecio","Ec/Io","dB"},{"rssi","RSSI","dBm"}} do
      local value=l[entry[1]]
      if value and #parts<4 then parts[#parts+1]=("%s %.0f %s"):format(entry[2],value,entry[3]) end
    end
    return table.concat(parts," · ")
  end
  function model.number()
    local modem=levels_source()
    return modem and modem.levels and modem.state.number or ""
  end

  --- Bytes this month (shell/data_usage.lua), by interface.
  function model.usage() return require("data_usage").rows:get() end
  function model.usage_size(bytes) return require("data_usage").size(bytes) end
  function model.usage_reset() require("data_usage").reset() end
  function model.limit() return tonumber(require("config").get("phone.data_limit")) or 0 end
  function model.set_limit(megabytes) require("config").set("phone.data_limit",tonumber(megabytes) or 0) end

  --- Call waiting, as the network has it.
  model.call_waiting=morf.signal("eva.mobile.waiting",false)
  function model.has_voice()
    local modem=levels_source()
    return modem~=nil and modem.voice~=nil and modem.voice.present:get()
  end
  function model.set_call_waiting(on)
    model.call_waiting:set(on==true)
    return services.modem.voice.waiting(on)
  end

  --- Public warnings: which come through, and what has.
  function model.alert_kinds()
    local out={}
    for _,kind in ipairs(require("models.phone_alerts").KINDS) do
      if not kind.locked then out[#out+1]=kind end
    end
    return out
  end
  function model.alert_on(id) return (require("config").get("phone.alerts") or {})[id]~=false end
  function model.set_alert(id,on)
    require("config").set("phone.alerts."..id,on==true)
    local p=phone()
    if p.alerts then p.alerts.apply() end
  end
  function model.alert_history()
    local p=phone()
    return p.ready:get() and p.alerts.history() or {}
  end
  return model
end
return M
