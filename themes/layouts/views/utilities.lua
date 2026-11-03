-- Material Settings composition, supplied only with model callbacks.
local morf=require("morf")
local ui=require("morf.ui")
local theme=require("theme")
local kit=require("kit")
local P=require("themes.layouts.page")
local C=theme.color
local V={WIDTH=430,RADIUS=15}
--- The Theme page: dark or light, and Lule one page in.
function V.theme_page(model,w,h)
  local mode=require("themes.color_mode")
  local function dark() return require("appearance_model").mode()~="light" end
  local inner=P.inner(w)
  return P.page {id="settings-theme-scroll",width=w,height=h,
    P.section {id="settings-theme",width=w,title="Appearance",
      P.row {id="settings-theme-mode",width=inner,icon=function() return dark() and "dark_mode" or "light_mode" end,
        title="Dark mode",
        subtitle=function() return dark() and "The shell in dark colours" or "The shell in light colours" end,
        trailing=P.switch {id="utilities-toggle-theme-mode",name="Dark mode",on=dark,
          on_toggled=function(on) mode.set(on and "dark" or "light") end}},
      P.row {id="settings-theme-lule",width=inner,icon="palette",title="Lule",
        subtitle="Wallpaper, colours, the shell's theme and font",trailing=P.chevron(),
        on_clicked=function() model.request("theme/lule") end},
    },
  }
end

--- A row to one of the registry's pages under Eva.
function V.eva_link(key,inner,model)
  local page=model.registry.BY_KEY[key]
  return P.row {id="settings-eva-"..key,width=inner,icon=page.icon,title=page.name,subtitle=page.summary,
    trailing=P.chevron(),on_clicked=function() model.request(key) end}
end

--- The Eva page: the shell's own parts -- the bar, one page in -- and how
--- its panels open.
function V.eva_page(model,w,h)
  local inner=P.inner(w)
  local bar=model.CONTROLS.bar
  local hover=model.edge_hover
  local reduced=model.reduce_motion
  local styles={width=inner}
  local function steps(id,key,list)
    local row={id=id,width=inner}
    for _,entry in ipairs(list) do
      row[#row+1]={id=id.."-"..tostring(entry[1]),label=entry[2],group=id,
        enabled=function() return not reduced() end,
        selected=function() return require("config").get(key)==entry[1] end,
        on_clicked=function() require("config").set(key,entry[1]) end}
    end
    return row
  end
  for _,style in ipairs(model.MOTIONS) do
    styles[#styles+1]={id="settings-motion-"..style[1],icon=style[2],label=style[3],group="settings-motion",
      enabled=function() return not reduced() end,
      selected=function() return model.motion_style()==style[1] end,
      on_clicked=function() model.set_motion_style(style[1]) end}
  end
  return P.page {id="settings-eva-scroll",width=w,height=h,
    P.section {id="settings-eva",width=w,title="Shell",
      P.row {id="settings-eva-bar",width=inner,icon="toolbar",title="Bar",
        subtitle=function() local s=bar.status() return s=="Off" and "Off" or "On the "..s:lower().." edge" end,
        trailing=P.chevron(),on_clicked=function() model.request("bar") end},
      P.row {id="settings-eva-osd",width=inner,icon="picture_in_picture",title="On-screen displays",
        subtitle="Where each one appears, and for how long",
        trailing=P.chevron(),on_clicked=function() model.request("osd") end},
      P.row {id="settings-eva-island",width=inner,icon="music_note",title="Island",
        subtitle="A pill out of the top of the frame, for music and the time",
        on=function() return require("island").enabled() end,
        trailing=P.switch {id="utilities-toggle-island",name="Island",on=function() return require("island").enabled() end,
          on_toggled=function(on) require("config").set("island.enabled",on==true) end}},
      P.row {id="settings-eva-standby",width=inner,icon="bedtime",title="StandBy",
        subtitle="A phone on charge, turned sideways, becomes a clock",
        on=function() return require("config").get("desktop.standby") end,
        trailing=P.switch {id="utilities-toggle-standby",name="StandBy",on=function() return require("config").get("desktop.standby") end,
          on_toggled=function(on) require("config").set("desktop.standby",on==true) end}},
      P.row {id="settings-eva-notifications",width=inner,icon="notifications",title="Notifications",
        subtitle="Sounds, popups, history and each app's rules",
        trailing=P.chevron(),on_clicked=function() model.request("notifications") end},
      P.row {id="settings-eva-keyboard",width=inner,icon="keyboard",title="On-screen keyboard",
        subtitle="When it comes up",
        trailing=P.chevron(),on_clicked=function() model.request("keyboard") end},
      P.row {id="settings-eva-windows",width=inner,icon="select_window",title="Windows",
        subtitle="Hot corners, the switcher and snapping",
        trailing=P.chevron(),on_clicked=function() model.request("windows") end},
    },
    P.section {id="settings-eva-panels",width=w,title="Panels",
      P.row {id="settings-eva-arrange",width=inner,icon="dashboard_customize",title="Arrange panels",
        subtitle="Which panel holds which page",
        trailing=P.chevron(),on_clicked=function() model.request("panels") end},
      P.row {id="settings-eva-hover",width=inner,icon="near_me",title="Open on hover",on=hover,
        subtitle=function() return hover() and "Reaching an edge opens its panel" or "A press at an edge opens its panel" end,
        trailing=P.switch {id="utilities-toggle-edge-hover",name="Open panels on hover",on=hover,
          on_toggled=model.set_edge_hover}},
    },
    P.section {id="settings-eva-motion",width=w,title="Motion",
      P.buttons(styles),
      P.buttons(steps("settings-speed","appearance.speed",{{.75,"Unhurried"},{1,"Usual"},{1.5,"Quick"}})),
      P.buttons(steps("settings-deform","appearance.deform",{{0,"Rigid"},{1,"Fluid"},{2,"Liquid"}})),
      P.row {id="settings-eva-reduce",width=inner,icon="animation",title="Reduce motion",on=reduced,
        subtitle=function() return reduced() and "Everything lands at once" or "Things travel on springs" end,
        trailing=P.switch {id="utilities-toggle-reduce-motion",name="Reduce motion",on=reduced,
          on_toggled=model.set_reduce_motion}},
    },
    P.section {id="settings-eva-more",width=w,title="More",
      V.eva_link("launcher",inner,model),V.eva_link("rail",inner,model),
      V.eva_link("capture",inner,model),V.eva_link("weather",inner,model),
      V.eva_link("commands",inner,model),
      P.row {id="settings-eva-welcome",width=inner,icon="waving_hand",title="Welcome",
        subtitle="The short tour again",
        trailing=P.chevron(),on_clicked=function() model.request("welcome") end},
    },
    P.section {id="settings-eva-services",width=w,title="Services",
      P.row {id="settings-eva-assistant",width=inner,icon="auto_awesome",title="Assistant",
        subtitle=function() return require("assistant_model").summary() end,
        trailing=P.chevron(),on_clicked=function() model.request("assistant") end},
      P.row {id="settings-eva-calendars",width=inner,icon="calendar_month",title="Calendars",
        subtitle=function() return require("calendar_sources").summary() end,
        trailing=P.chevron(),on_clicked=function() model.request("calendars") end},
    },
    P.section {id="settings-eva-lock-section",width=w,title="Lock and sleep",
      P.row {id="settings-eva-lock",width=inner,icon="lock",title="Lock screen",
        subtitle="What it shows, and how it opens",
        trailing=P.chevron(),on_clicked=function() model.request("lock") end},
      P.row {id="settings-eva-idle",width=inner,icon="bedtime",title="Idle and sleep",
        subtitle="When the screen locks, dims and sleeps",
        trailing=P.chevron(),on_clicked=function() model.request("idle") end},
    },
  }
end

function V.build(model,w,h)
local M={TOGGLES=model.TOGGLES,DETAILS=model.DETAILS,detail=model.detail,RADIUS=V.RADIUS}
-- A side panel's cards are 408 wide; a sheet's (a phone's quick settings)
-- take its width.
local CARD_W,GAP=w,P.GAP
local overview_viewport, overview_viewport_node, overview_viewport_t, overview_viewport_ctl
local tiles = require("themes").view("quick_tiles").build(model, CARD_W,
  { viewport = function() return overview_viewport end })

-- ----------------------------------------------------------------- sliders --

-- The output's volume and the screen's brightness, as Material 3
-- expressive sliders: a tall rounded track, the active part in the primary
-- colour up to a slim handle with a gap either side, the icon inside the
-- track's start and the value at its end. The handle follows the hand
-- directly while held. They read and set what the OSD does.
-- The shell's scale: -1 (half) to 1 (twice) along the slider, 0 -- the
-- compositor's own -- in its middle, in steps of 0.05.
local function scale_now()
  local v = tonumber(require("config").get("appearance.zoom")) or 0
  return (math.max(-1, math.min(1, v)) + 1) / 2
end
local function scale_set(position)
  local v = math.max(0, math.min(1, position)) * 2 - 1
  if not require("themes.ui_scale").compositor then v = math.floor(v / 0.05 + 0.5) * 0.05 end
  if math.abs(v) < 1e-6 then v = 0 end
  require("config").set("appearance.zoom", v)
end
local function scale_reading(position)
  local scale = require("themes.ui_scale")
  if scale.compositor then return ("%.2f×"):format(scale.display_scale(position * 2 - 1)) end
  local v = math.floor((position * 2 - 1) * 100 + 0.5)
  return v == 0 and "0" or ("%+d%%"):format(v)
end

local function slider(id, value, set, icon, name, reading)
  return kit.slider { id = id, accessible_name = name, width = CARD_W - 2 * P.PAD, value = value, set = set, icon = icon,
    reading = reading, live = id ~= "utilities-scale" or not require("themes.ui_scale").compositor }
end

local function sliders()
  local osd = model.levels
  local brightness = slider("utilities-brightness", function() return (osd.brightness()) end, osd.set_brightness,
    osd.brightness_icon, "Brightness")
  brightness.visible = osd.brightness_known
  local column=ui.Column {
    x = P.PAD, y = P.PAD, gap = 4,
    slider("utilities-volume", function() return (osd.volume()) end, osd.set_volume, osd.volume_icon, "Volume"),
    brightness,
    slider("utilities-scale", scale_now, scale_set, "zoom_in",
      require("themes.ui_scale").compositor and "Display scale" or "Scale", scale_reading),
  }
  return kit.card {
    id = "utilities-sliders",
    width = CARD_W, height = function() return (column.layout_height or 0)+2*P.PAD end,
    radius = kit.round(P.RADIUS), column,
  }
end

-- ------------------------------------------------------------------- power --

-- -------------------------------------------------------------------- page --

local capture_button = kit.pill {
  id = "utilities-capture", width = CARD_W, height = 40,
  icon = "screenshot_monitor", label = "Screenshot / Record",
  on_clicked = function()
    model.capture()
  end,
}
local all_settings = kit.pill {
  id = "utilities-all-settings", width = CARD_W, height = 40, icon = "settings", label = "All settings",
  on_clicked = function() model.open_home() end,
}
local session_card = require("themes").view("quick_session").build(model, CARD_W)
local slider_card = sliders()
local cards = { session_card, slider_card, capture_button, all_settings, tiles.node }

-- While the tiles are edited the cards above them step aside: they fade where
-- they stand and the tiles rise to the top of the page.
local function editing() return model.tiles.editing:get() end
local function card_height(card) return card.layout_height or 0 end
local function stacked(index)
  local y = 0
  for i = 1, index - 1 do y = y + card_height(cards[i]) + GAP end
  return y
end
local function above(card, index)
  local slot = ui.Item { width = CARD_W, y = function() return stacked(index) end,
    height = function() return card_height(card) end, behavior = { y = theme.spring.spatial }, card }
  local claims = ui.claims(slot, {
    kept = { when = function() return not editing() end, motion = theme.spring.effects, set = { opacity = 1 } },
    aside = { set = { opacity = 0 } },
  })
  slot.visible = function() return not editing() or claims.kept.presence:get() > 0.01 end
  return slot
end
local tiles_slot = ui.Item { width = CARD_W,
  y = function() return editing() and 0 or stacked(#cards) end,
  height = tiles.height, behavior = { y = theme.spring.spatial }, tiles.node }
--- The page's height: the cards and their gaps.
function M.height() return (editing() and 0 or stacked(#cards)) + tiles.height() end
--- Whether its cards have been measured.
function M.laid_out() return card_height(session_card) > 0 and card_height(slider_card) > 0 end
local stack = ui.Item { width = CARD_W, height = M.height,
  above(session_card, 1), above(slider_card, 2), above(capture_button, 3), above(all_settings, 4), tiles_slot }


--- The Settings page of the right panel: the cards, top down, and the
--- detail pages (Network, Bluetooth, Sound) beside them, which slide in
--- over them as a tile's ">" opens one. The panel's frame draws the head:
--- "Settings", or a detail's name with the way back (`M.head`).
local SWITCH = { duration = theme.duration.normal, easing = theme.ease.emphasized_decel }
-- How far in from a detail's left edge a swipe back may start.
local BACK_EDGE = theme.space.xxl + theme.space.s
function M.page(w, h)
  overview_viewport_node, overview_viewport, overview_viewport_t, overview_viewport_ctl = kit.scroll({id="settings-overview-scroll",width=w,height=h,clip=true,
    stack})
  -- Out of Tab's way while a detail is on show.
  local main = ui.Item {
    id = "utilities", width = w, height = h, clip = true,
    enabled = function() return M.detail:get() == "" end,
    overview_viewport_node,
  }
  local stack = {}
  local names = {}
  -- How to read each detail's height, once it is built.
  local measured = morf.signal("eva.settings.measured", 0)
  local readers = {}
  function M.detail_height(key)
    measured:get()
    local read = readers[key]
    local whole = read and read() or 0
    return whole > 0 and whole or nil
  end
  -- Going back under a finger: how far the page has been pulled, the page it
  -- goes back to, and whether that is another detail or the overview.
  local pull_x = model.peek
  local function pull() return pull_x:get() end
  local function peek() return math.min(1, pull() / math.max(1, w)) end
  local function parent_of(key)
    for _, d in ipairs(M.DETAILS) do if d.key == key then return d.parent or "" end end
    return ""
  end
  local function peek_key()
    if pull() <= 0 then return nil end
    local parent = parent_of(M.detail:get())
    return parent ~= "" and parent or nil
  end
  local function nested() return parent_of(M.detail:get()) ~= "" end
  for _, d in ipairs(M.DETAILS) do
    names[d.key] = d.name
    -- Each detail is built the first time it opens, and kept.
    local wanted = morf.signal("eva.settings.built." .. d.key, M.detail:get() == d.key)
    morf.effect("eva.settings.build." .. d.key, function()
      if M.detail:get() == d.key and not wanted:get() then wanted:set(true) end
    end)
    -- Pulled back from a page, the page above it shows beneath, a touch small.
    local function peeked() return peek_key()==d.key end
    stack[#stack + 1] = ui.Item {
      id = "settings-detail-" .. d.key,
      width = w, height = h,
      visible = function() return M.detail:get() == d.key or peeked() end,
      opacity=function() return M.detail:get()==d.key and 1 or peeked() and .4+.6*peek() or 0 end,
      scale=function()
        if M.detail:get()==d.key then return 1-.06*peek() end
        return peeked() and .94+.06*peek() or 1
      end,
      z=function() return M.detail:get()==d.key and 1 or 0 end,
      behavior={opacity={duration=theme.duration.small}},
      ui.Loader {
        anchors = { fill = true }, keep = true,
        active = function() return wanted:get() end,
        source = function()
          local node, _, read = P.measure(function() return model.page_content(d.key, w, h) end)
          readers[d.key] = read
          measured:set(measured:get() + 1)
          return node
        end,
      },
    }
    -- A page pulled back from its parent is the finger's; else it eases in.
    ui.claims(stack[#stack], { motion = SWITCH,
      a_hand = { when = function() return pull() > 0 and M.detail:get() == d.key and nested() end,
        motion = { duration = 0 }, set = { translate_x = pull } },
      b_rest = { set = { translate_x = function()
        return (M.detail:get() == d.key or peeked()) and 0 or 20
      end } } })
  end
  -- The pencil: edits the tiles, and says done while they are.
  local pencil = kit.action { id = "utilities-edit", width = 40, height = 40, cursor = "pointer",
    accessible_name = function() return editing() and "Done" or "Edit quick settings" end,
    visible = function() return M.detail:get() == "" end,
    on_clicked = function()
      model.tiles.editing:set(not editing())
      if overview_viewport then overview_viewport.content_y = 0 end
    end,
    kit.icon(function() return editing() and "check" or "edit" end, 22, kit.ink("hi"), { anchors = { center_in = true } }) }
  kit.hover(pencil, function(hovered) return hovered and C.onSurface:alpha(0.08) or C.onSurface:alpha(0) end, 20)
  M.head = {
    title = function()
      if M.detail:get() == "" and editing() then return "Edit tiles" end
      return names[M.detail:get()] or "Settings"
    end,
    subtitle = function()
      if M.detail:get() ~= "" then return model.breadcrumb() end
      return editing() and "Drag to arrange" or ""
    end,
    back = model.back, back_id = "settings-back",
    can_back = function() return M.detail:get() ~= "" end,
    keep = function() return true end,
    actions = { pencil },
    -- Read in afresh as the overview or a detail comes on show.
    active = function()
      local key = M.detail:get()
      return require("presentation").active(key == "" and "settings.overview" or "settings." .. key)()
    end,
  }
  local detail = ui.Item {
    id = "settings-detail", width = w, height = h,
    table.unpack(stack),
  }
  -- The last detail shown stays drawn while it slides away. The pages are
  -- a Navigation stack: with focus inside, Alt+Left and the back button pop.
  -- The panels board keeps Alt with the arrows for its tiles.
  local shortcuts = model.navigation.shortcuts()
  local pop = shortcuts["alt+Left"]
  shortcuts["alt+Left"] = function()
    if M.detail:get() == "panels" then return false end
    return pop()
  end
  local row = ui.Row { gap = 24, main, detail }
  -- Under a finger the row is the finger's; on its own it eases there.
  ui.claims(row, { motion = SWITCH,
    a_hand = { when = function() return pull() > 0 and not nested() end, motion = { duration = 0 },
      set = { translate_x = function() return -(w + 24) + pull() end } },
    b_rest = { set = { translate_x = function() return M.detail:get() == "" and 0 or -(w + 24) end } } })
  local holder = ui.Item {
    width = w, height = h, clip = true,
    shortcuts = shortcuts,
    row,
  }
  -- A pull in from the page's left edge goes back, what it goes back to
  -- showing under the finger; let go early, it stays. Further in, a sideways
  -- drag is the panel's, for its tabs.
  local gesture = require("gesture_motion")
  local COMMIT = .35
  local pulling
  holder.on_panned = function(phase, dx, dy, vx, _, start_x)
    if phase == "begin" then
      pulling = false
      if M.detail:get() == "" or dx <= 0 or math.abs(dx) <= math.abs(dy) * 1.2 then return false end
      if not start_x or start_x - (holder.layout_x or 0) > BACK_EDGE then return false end
      pulling = true
      return true
    end
    if not pulling then return end
    if phase == "update" then pull_x:set(math.max(0, dx))
    else
      local done = phase == "end" and (dx >= w * COMMIT or gesture.fling(dx, vx) and (vx or 0) > 0)
      pulling = false
      pull_x:set(0)
      if done then
        require("haptics").fire("commit")
        model.back()
      end
    end
  end
  return holder
end


local node=M.page(w,h)
morf.effect("material.settings.present",function() model.present(model.detail:get()) end)
local running={}
morf.effect("material.settings.shown",function()
  for _, handle in ipairs(running) do handle:stop() end
  running=kit.bud(cards,model.opened:get())
end,{owner=node})
return {node=node,height=M.height,head=M.head,laid_out=M.laid_out,detail_height=M.detail_height}
end
return V
