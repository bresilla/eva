local morf=require("morf")
local ical=require("lib.integrations.ical")
local M={}

-- Tasks and events of one day, all-day ones first, then by the time they start.
function M.merge(tasks,instances,when)
  local rows={}
  for _,task in ipairs(tasks) do
    local row={}
    for key,value in pairs(task) do row[key]=value end
    row.order=task.time~="" and task.time or "99"
    rows[#rows+1]=row
  end
  for i,item in ipairs(instances) do
    local event=item.event
    rows[#rows+1]={uuid="event-"..i.."-"..tostring(math.floor(item.at)),event=true,description=event.summary or "Event",
      project=event.location or "",time=when(item),kind=event.calendar_name or "Calendar",
      link=ical.meeting_link(event) or "",order=item.all_day and "00" or morf.time.format("%H:%M",item.at),
      uid=event.uid or "",at=item.at}
  end
  table.sort(rows,function(a,b) if a.order~=b.order then return a.order<b.order end return a.uuid<b.uuid end)
  return rows
end

function M.new(ctx)
  local planner=ctx.planner or require("planner")
  local sources=ctx.sources or require("calendar_sources")
  local model={key="calendar",active=ctx.active,can_plan=ctx.can_plan,days=morf.list_model({}),agenda=morf.list_model({}),
    month=morf.signal("eva.calendar.title",""),selected_day=planner.selected_day,error=planner.client.error,
    weekdays={"M","T","W","T","F","S","S"},sources=sources}
  model.events=require("calendar_event_model").new {active=ctx.active,sources=sources,day=function() return planner.selected_day:get() end}
  morf.effect("eva.calendar.month",function()
    if not model.active() then return end
    morf.time.minute_clock:get()
    local today=morf.time.date()
    local first=morf.time.time {year=today.year,month=today.month,day=1,hour=12}
    first=morf.time.add(first,{months=planner.month_offset:get()})
    local date=morf.time.date(first)
    model.month:set(morf.time.format("%B %Y",first))
    sources.want(first)
    local out={}
    for _,week in ipairs(morf.time.month(date.year,date.month,1)) do for _,day in ipairs(week) do
      local key=("%04d-%02d-%02d"):format(day.year,day.month,day.day)
      out[#out+1]={key=key,day=day.day,current=day.current,today=key==morf.time.format("%Y-%m-%d"),
        count=#planner.agenda(key)+sources.count(key)}
    end end
    model.days:replace(out,"key")
  end)
  morf.effect("eva.calendar.agenda",function()
    if not model.active() then return end
    local day=model.selected_day:get()
    model.agenda:replace(M.merge(planner.agenda(day),sources.on_day(day),sources.when),"uuid")
  end)
  function model.day_title()
    local t=morf.time.parse(model.selected_day:get())
    return t and morf.time.format("%A, %d %B",t) or model.selected_day:get()
  end
  function model.step(delta) if model.active() then planner.month_offset:set(planner.month_offset:get()+delta) end end
  function model.today()
    if not model.active() then return end
    planner.month_offset:set(0) model.selected_day:set(morf.time.format("%Y-%m-%d"))
  end
  function model.select(day)
    if model.active() and type(day)=="string" and day:match("^%d%d%d%d%-%d%d%-%d%d$") and morf.time.parse(day) then model.selected_day:set(day) end
  end
  function model.plan() if model.active() then ctx.edit(nil,model.selected_day:get()) end end
  function model.edit(id)
    if not model.active() then return false end
    for _,row in ipairs(planner.client.tasks:get()) do if row.uuid==id then ctx.edit(row) return true end end
    return false
  end
  --- Whether any calendar is set up or found.
  function model.connected() sources.revision:get() return sources.configured() end
  --- The next event that is not over: `{ title, when, link, at }`, or nil.
  function model.next_up()
    if not model.active() then return nil end
    morf.time.minute_clock:get()
    local now=morf.time.now()
    local item=sources.next_event(now)
    if not item then return nil end
    local minutes=math.floor((item.at-now)/60+.5)
    local today=morf.time.format("%Y-%m-%d",item.at)==morf.time.format("%Y-%m-%d",now)
    local soon=item.at<=now and "On now" or minutes<60 and ("In "..minutes.." min")
      or morf.time.format(today and "Today %H:%M" or "%a %-d %b %H:%M",item.at)
    return {title=item.event.summary or "Event",when=soon,link=ical.meeting_link(item.event) or "",at=item.at}
  end
  --- The forecast for the day on show: `{ symbol, words }`, or nil.
  local forecast=ctx.forecast or function() return require("services").weather() end
  local last
  function model.weather()
    if not model.active() then return last end
    local day,now=model.selected_day:get(),forecast()
    last=nil
    for _,d in ipairs(now and now.daily or {}) do
      if d.time and morf.time.format("%Y-%m-%d",d.time)==day then
        local unit=now.units and now.units.temperature or "°"
        last={symbol=require("services").weather_symbol(d.code,true),
          words=("%d%s / %d%s"):format(math.floor((d.high or 0)+.5),unit,math.floor((d.low or 0)+.5),unit),
          condition=d.condition or ""}
        break
      end
    end
    return last
  end
  --- Opens a meeting.
  function model.join(link)
    if link=="" then return false end
    local dry=morf.env and morf.env("EVA_DRY_RUN")
    if dry and dry~="" and dry~="0" then morf.log("info","eva: join (dry run)") return true end
    morf.process.detach {"xdg-open",link}
    return true
  end
  function model.settings() require("pages").settings("calendars") end
  return model
end
return M
