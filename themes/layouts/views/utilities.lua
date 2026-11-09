-- Material Settings composition, supplied only with model callbacks.
local morf=require("morf")
local ui=require("morf.ui")
local theme=require("theme")
local kit=require("kit")
local P=require("themes.layouts.page")
local C=theme.color
local V={WIDTH=430,RADIUS=15}
--- The motion choices: a style, a speed and how far shapes give, each a row
--- of buttons, held still while Reduce motion is on.
local function motion_section(model,w)
  local inner=P.inner(w)
  local reduced=model.reduce_motion
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
  local styles={width=inner}
  for _,style in ipairs(model.MOTIONS) do
    styles[#styles+1]={id="settings-motion-"..style[1],icon=style[2],label=style[3],group="settings-motion",
      enabled=function() return not reduced() end,
      selected=function() return model.motion_style()==style[1] end,
      on_clicked=function() model.set_motion_style(style[1]) end}
  end
  return P.section {id="settings-eva-motion",width=w,title="Motion",
    P.buttons(styles),
    P.buttons(steps("settings-speed","appearance.speed",{{.75,"Unhurried"},{1,"Usual"},{1.5,"Quick"}})),
    P.buttons(steps("settings-deform","appearance.deform",{{0,"Rigid"},{1,"Fluid"},{2,"Liquid"}})),
    P.row {id="settings-motion-reduced",width=inner,icon="animation",title="Reduce motion is on",
      subtitle="Turned off in Accessibility",visible=reduced,trailing=P.chevron(),
      on_clicked=function() model.request("accessibility") end},
  }
end

--- The Appearance page: dark or light, Lule and Fonts one page in, and how
--- things move.
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
      P.row {id="settings-theme-fonts",width=inner,icon="font_download",title="Fonts",
        subtitle="Every family, previewed, and the shell's",trailing=P.chevron(),
        on_clicked=function() model.request("theme/fonts") end},
    },
    motion_section(model,w),
  }
end

--- A row to one of the registry's pages under Eva.
function V.eva_link(key,inner,model)
  local page=model.registry.BY_KEY[key]
  return P.row {id="settings-eva-"..key,width=inner,icon=page.icon,title=page.name,subtitle=page.summary,
    trailing=P.chevron(),on_clicked=function() model.request(key) end}
end

--- The Desktop page: the shell's own parts, each a page in, and what shows
--- over the windows.
function V.eva_page(model,w,h)
  local inner=P.inner(w)
  local bar=model.CONTROLS.bar
  local hover=model.edge_hover
  local function switch(id,key,icon,title,subtitle)
    local function on() return require("config").get(key)==true end
    return P.row {id="settings-eva-"..id,width=inner,icon=icon,title=title,subtitle=subtitle,on=on,
      trailing=P.switch {id="utilities-toggle-"..id,name=title,on=on,
        on_toggled=function(now) require("config").set(key,now==true) end}}
  end
  return P.page {id="settings-eva-scroll",width=w,height=h,
    P.section {id="settings-eva",width=w,title="Shell",
      P.row {id="settings-eva-bar",width=inner,icon="toolbar",title="Bar",
        subtitle=function() local s=bar.status() return s=="Off" and "Off" or "On the "..s:lower().." edge" end,
        trailing=P.chevron(),on_clicked=function() model.request("bar") end},
      P.row {id="settings-eva-arrange",width=inner,icon="dock_to_right",title="Panels",
        subtitle="Which panel holds which page",
        trailing=P.chevron(),on_clicked=function() model.request("panels") end},
      P.row {id="settings-eva-hover",width=inner,icon="near_me",title="Open panels on hover",on=hover,
        subtitle=function() return hover() and "Reaching an edge opens its panel" or "A press at an edge opens its panel" end,
        trailing=P.switch {id="utilities-toggle-edge-hover",name="Open panels on hover",on=hover,
          on_toggled=model.set_edge_hover}},
      V.eva_link("rail",inner,model),
      V.eva_link("launcher",inner,model),
      V.eva_link("windows",inner,model),
    },
    P.section {id="settings-eva-over",width=w,title="Over the windows",
      V.eva_link("osd",inner,model),
      V.eva_link("capture",inner,model),
      switch("island","island.enabled","music_note","Island","A pill out of the top of the frame, for music and the time"),
      switch("standby","desktop.standby","bedtime","StandBy","A phone on charge, turned sideways, becomes a clock"),
    },
  }
end

function V.build(model,w,h)
-- The panel's own pages and their navigation, apart from the Settings window's.
local Q=model.in_panel
local M={TOGGLES=model.TOGGLES,DETAILS=Q.DETAILS,detail=Q.detail,RADIUS=V.RADIUS}
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

local session_card = require("themes").view("quick_session").build(model, CARD_W)
local slider_card = sliders()
local cards = { session_card, slider_card, tiles.node }

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
  above(session_card, 1), above(slider_card, 2), tiles_slot }


--- The Settings page of the right panel: the cards, top down, and the quick
--- controls' own pages (Network, Bluetooth, Sound) beside them, which slide in
--- over them as a tile's ">" opens one. The panel's frame draws the head:
--- "Settings", or a page's name with the way back and More settings, its whole
--- page in the Settings window (`M.head`). Anything else the cards lead to
--- opens in that window.
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
  local measured = morf.signal("eva.settings.quick.measured", 0)
  local readers = {}
  function M.detail_height(key)
    measured:get()
    local read = readers[key]
    local whole = read and read() or 0
    return whole > 0 and whole or nil
  end
  -- Going back under a finger: how far the page has been pulled, the page it
  -- goes back to, and whether that is another detail or the overview.
  local pull_x = Q.peek
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
    local wanted = morf.signal("eva.settings.quick.built." .. d.key, M.detail:get() == d.key)
    morf.effect("eva.settings.quick.build." .. d.key, function()
      if M.detail:get() == d.key and not wanted:get() then wanted:set(true) end
    end)
    -- Pulled back from a page, the page above it shows beneath, a touch small.
    local function peeked() return peek_key()==d.key end
    stack[#stack + 1] = ui.Item {
      id = "quick-detail-" .. d.key,
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
          local node, _, read = P.measure(function() return Q.page_content(d.key, w, h) end)
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
  -- The head's own buttons, over the tiles: an icon each, hovered softly.
  local function head_button(id, icon, name, on_clicked, visible)
    local button = kit.action { id = id, width = 40, height = 40, cursor = "pointer", accessible_name = name,
      visible = visible, on_clicked = on_clicked,
      kit.icon(icon, 22, kit.ink("hi"), { anchors = { center_in = true } }) }
    kit.hover(button, function(hovered) return hovered and C.onSurface:alpha(0.08) or C.onSurface:alpha(0) end, 20)
    return button
  end
  local function overview() return M.detail:get() == "" and not editing() end
  local capture = head_button("utilities-capture", "screenshot_monitor", "Screenshot or record", model.capture, overview)
  local everything = head_button("utilities-all-settings", "settings", "All settings", model.open_home, overview)
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
  -- More settings: the page on show, whole, in the Settings window.
  local more = P.button { id = "quick-more", label = "More settings", icon = "open_in_new",
    visible = function() return M.detail:get() ~= "" end, on_clicked = Q.more }
  M.head = {
    title = function()
      if M.detail:get() == "" and editing() then return "Edit tiles" end
      return names[M.detail:get()] or "Settings"
    end,
    subtitle = function()
      if M.detail:get() ~= "" then return Q.breadcrumb() end
      return editing() and "Drag to arrange" or ""
    end,
    back = Q.back, back_id = "quick-back",
    can_back = function() return M.detail:get() ~= "" end,
    keep = function() return true end,
    actions = { capture, everything, pencil, more },
    -- Read in afresh as the overview or a detail comes on show.
    active = function()
      local key = M.detail:get()
      return require("presentation").active(key == "" and "settings.overview" or "quick." .. key)()
    end,
  }
  local detail = ui.Item {
    id = "quick-detail", width = w, height = h,
    table.unpack(stack),
  }
  -- The last detail shown stays drawn while it slides away. The pages are
  -- a Navigation stack: with focus inside, Alt+Left and the back button pop.
  local shortcuts = Q.navigation.shortcuts()
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
        Q.back()
      end
    end
  end
  return holder
end


local node=M.page(w,h)
morf.effect("material.settings.present",function() Q.present(Q.detail:get()) end)
local running={}
morf.effect("material.settings.shown",function()
  for _, handle in ipairs(running) do handle:stop() end
  running=kit.bud(cards,model.quick:get())
end,{owner=node})
return {node=node,height=M.height,head=M.head,laid_out=M.laid_out,detail_height=M.detail_height}
end
return V
