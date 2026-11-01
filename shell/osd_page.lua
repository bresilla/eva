-- The Settings page behind Eva's "On-screen displays": a kind chosen, and its
-- preferences. The view is the selected theme's; this is its model.
local morf=require("morf")
local M={}

local NOTIFICATIONS={id="notifications",name="Notifications",icon="notifications"}
-- How long a tried popup stays, and how long after a try the sheet returns.
local TRIED,RETURN=2400,500

function M.model(active)
  local osd=require("osd")
  local prefs=require("osd_model")
  local chosen=morf.signal("eva.osd.settings.kind","volume")
  local model={active=active,POSITIONS=prefs.POSITIONS,HOLDS=prefs.HOLDS,kinds={NOTIFICATIONS}}
  for _,kind in ipairs(prefs.KINDS) do model.kinds[#model.kinds+1]=kind end
  local function notifying() return chosen:get()==NOTIFICATIONS.id end

  function model.present(kind) return kind==NOTIFICATIONS.id or osd.present(kind) end
  function model.selected() return chosen:get() end
  function model.select(kind) chosen:set(kind) end
  function model.kind() return prefs.BY_ID[chosen:get()] or NOTIFICATIONS end
  function model.position()
    if notifying() then return prefs.notifications() end
    return prefs.position(chosen:get())
  end
  --- Whether the chosen kind may stand at `position`.
  function model.allows(position)
    return not notifying() or position:match("^center")==nil
  end
  function model.place(position)
    if not active() then return false end
    if notifying() then prefs.set_notifications(position)
    else prefs.set_position(chosen:get(),position) end
    return true
  end
  function model.notifying() return notifying() end
  function model.level() return model.kind().family=="level" end
  -- Popups have a place and none of the rest: these read a display's own.
  function model.enabled() return notifying() or prefs.enabled(chosen:get()) end
  function model.set_enabled(on) if active() and not notifying() then prefs.set_enabled(chosen:get(),on) end end
  function model.percent() return notifying() or prefs.percent(chosen:get()) end
  function model.set_percent(on) if active() and not notifying() then prefs.set_percent(chosen:get(),on) end end
  function model.hold() return notifying() and 0 or prefs.chosen_hold(chosen:get()) end
  function model.set_hold(ms) if active() and not notifying() then prefs.set_hold(chosen:get(),ms) end end
  -- Upright the page is a sheet over the screen's top: it steps aside for what
  -- it tries, and comes back unless something else was opened meanwhile.
  local function step_aside(ms)
    local sidebar=require("sidebar")
    if not (require("responsive").portrait() and sidebar.drawer.open:get()) then return end
    sidebar.drawer.set(false)
    morf.time.timer(ms+RETURN,function()
      for _,d in ipairs(require("drawer").all) do
        if d.is_open() and d.name~="notifications" then return end
      end
      require("utilities").request("osd")
      sidebar.select("settings")
      sidebar.drawer.set(true)
    end,false)
  end
  --- Flashes the chosen display, whatever its switch says.
  function model.try()
    if notifying() then
      step_aside(TRIED)
      require("notifs").push {summary="Notifications stand here",body="Swipe one away, or press it.",app="Eva",
        timeout_ms=TRIED}
      return true
    end
    local kind=chosen:get()
    if not osd.flash(kind,true) then return false end
    step_aside(prefs.hold(kind))
    return true
  end
  return model
end

function M.page(w,h)
  local model=M.model(require("presentation").active("settings.osd"))
  return require("themes").view("osd_page").build(model,w,h)
end

return M
