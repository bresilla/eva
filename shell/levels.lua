-- OSD visibility and hold policy: which bud shows which kind, and for how
-- long. Theme builders own the buds' geometry and motion.
local morf=require("morf")
local model=require("osd_model")
local M={}
M.shown=morf.signal("eva.levels.shown","")
M.active=morf.signal("eva.levels.active",false)
local visual
local slots,serial={},0

-- The newest kind on show, and whether any is still out.
local function publish()
  local newest,active=nil,false
  for _,slot in ipairs(slots) do
    if slot.kind then
      if not newest or slot.serial>newest.serial then newest=slot end
      active=active or slot.out
    end
  end
  M.shown:set(newest and newest.kind or "")
  M.active:set(active)
end

local function release(slot)
  if slot.timer then slot.timer:cancel() slot.timer=nil end
end

local function hold(slot)
  release(slot)
  slot.generation=slot.generation+1
  local own=slot.generation
  if slot.bud.held() then return end
  slot.timer=morf.time.timer(model.hold(slot.kind),function()
    slot.timer=nil
    slot.out=false
    publish()
    slot.bud.hide(function()
      if own==slot.generation then slot.kind=nil publish() end
    end)
  end,false)
end

-- A kind keeps its bud, or takes over one in its way, a free one, or the
-- one shown longest ago.
local function pick(kind)
  for _,slot in ipairs(slots) do if slot.kind==kind then return slot end end
  for _,slot in ipairs(slots) do if slot.kind and visual.overlap(slot.kind,kind) then return slot end end
  for _,slot in ipairs(slots) do if not slot.kind then return slot end end
  local oldest=slots[1]
  for _,slot in ipairs(slots) do if slot.serial<oldest.serial then oldest=slot end end
  return oldest
end

--- Shows `kind` where its setting says, and holds it there.
function M.pop(kind)
  if not model.BY_ID[kind] then return false end
  if not visual then M.shown:set(kind) return true end
  local slot=pick(kind)
  serial=serial+1
  slot.kind,slot.serial,slot.out=kind,serial,true
  slot.bud.show(kind)
  hold(slot)
  publish()
  return true
end

function M.build()
  local osd=require("osd")
  visual=require("themes").view("levels").build {
    shown=M.shown,active=M.active,
    position=model.position,anchor=model.anchor,percent=model.percent,
    family=function(kind) return model.BY_ID[kind].family end,
    present=osd.present,read=osd.read,artwork=osd.artwork,
    value={volume=function() return math.max(0,math.min(1,(osd.volume()))) end,
      brightness=function() return math.max(0,math.min(1,(osd.brightness()))) end},
    icon={volume=osd.volume_icon,brightness=osd.brightness_icon},
    muted=function() local _,muted=osd.volume() return muted end,
    adjust=osd.adjust,toggle_mute=osd.toggle_mute,
    rail_geometry=require("rail").geometry,desk=require("bar").desk,sidebar=require("sidebar"),
    portrait=require("responsive").portrait(),
  }
  M.shape=visual.shape
  M.panels=visual.panels
  slots={}
  for i,bud in ipairs(visual.buds) do
    local slot={bud=bud,generation=0,serial=0}
    slots[i]=slot
    -- While the pointer rests on it, it waits; let go, the hold starts over.
    morf.effect("eva.levels.held."..i,function()
      local over=bud.held()
      if over==slot.over then return end
      slot.over=over
      if not slot.out then return end
      if over then release(slot) else hold(slot) end
    end)
  end
  local was=M.shown:get()
  M.shown:set("") M.active:set(false)
  if was~="" then M.pop(was) end
  -- Upright (a phone) there are no resting pills on the edge: the levels
  -- show only while one is changing.
  if require("responsive").portrait() then
    visual.node.visible=function() return M.shown:get()~="" end
  end
  osd.watch()
  return visual.node
end
function M.geometry() return visual and visual.geometry() end
function M.spot(kind) return visual and visual.spot(kind) end
return M
