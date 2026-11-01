-- A panel with tabs, as the dashboard has them: the theme's tab row
-- (`kit.tabs`) along the top; under it the pages side by side, sliding
-- across as the tab changes (or wiped, when the theme's motion has a
-- `page_wipe`), the incoming page growing in evenly as it fades in.
--
-- The side panels are built on it, so a tab is one more entry in a list:
--
--     local panel = tabbed.new {
--       id = "sidebar", width = 430, height = function() return h end,
--       tabs = {
--         { key = "settings", name = "Settings", icon = "tune",
--           build = function(w, h) return node end },   -- h is a function
--         ...
--       },
--     }
--     panel.content  -- the drawer's content
--     panel.tab      -- a signal: the chosen tab's index
--     panel.select("settings")

local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")

local M = {}

M.TABS_H = 64
M.PAD = 11
local SWITCH = { duration = theme.duration.normal, easing = theme.ease.emphasized_decel }
-- How long a width that eases rests before its pages are laid out at it.
local REST_MS = 420

function M.new(spec)
  local phone=require("responsive").sheets()
  local page_wipe=theme.motion.page_wipe and not phone
  local PAD, TABS_H = spec.pad or M.PAD, M.TABS_H
  -- A `width` given as a function eases: the row and the strip follow the
  -- panel as it goes, and a page, built for one width, is built again once
  -- the panel rests at another.
  local fluid = type(spec.width) == "function"
  local root
  local function W()
    if not fluid then return spec.width end
    local live = root and root.layout_width
    return live and live > 0 and live or spec.width()
  end
  local function page_w() return W() - 2 * PAD end
  local built = fluid and morf.signal("eva." .. spec.id .. ".built", spec.width() - 2 * PAD) or nil
  local again = fluid and morf.signal("eva." .. spec.id .. ".again", false) or nil
  local tabs = spec.tabs
  local tab = spec.tab or require("themes.session").keep("eva." .. spec.id .. ".tab", 1)
  local display = morf.signal("eva." .. spec.id .. ".displayed", tab:get())
  local presented = morf.signal("eva." .. spec.id .. ".presented", false)
  morf.effect(spec.id .. ".presentation", function()
    for i, t in ipairs(tabs) do
      if spec.publish ~= false then
        require("presentation").set(spec.id .. "." .. t.key, presented:get() and display:get() == i)
      end
    end
  end)
  local function page_h() return spec.height() - TABS_H - 2 * PAD end
  local panel = { tab = tab, tabs = tabs, displayed = display }

  function panel.index(key)
    for i, t in ipairs(tabs) do if t.key == key then return i end end
    return nil
  end
  function panel.select(key)
    local i = type(key) == "number" and key or panel.index(key)
    if i and tabs[i] then tab:set(i) end
    return i
  end
  function panel.showing(key)
    local t = tabs[tab:get()]
    return t ~= nil and t.key == key
  end

  -- --------------------------------------------------------------- pages --

  -- The chosen tab's page is built ahead of time while the shell is idle;
  -- the others when the panel first shows them. Each stays once built.
  local opened = morf.signal("eva." .. spec.id .. ".opened", false)
  local seen = {}
  for i in ipairs(tabs) do seen[i] = morf.signal("eva." .. spec.id .. ".seen." .. i, false) end
  -- A finger drags the neighbours in by hand: they are seen as it does.
  local reach = (phone or require("models.touchscreens").attached()) and 1 or 0
  morf.effect("eva." .. spec.id .. ".seen", function()
    if not opened:get() then return end
    local now = tab:get()
    for i = now - reach, now + reach do
      if seen[i] and not seen[i]:get() then seen[i]:set(true) end
    end
  end)
  -- Whether a finger has the track, its neighbours on show beside the page.
  local peeking = morf.signal("eva." .. spec.id .. ".peeking", false)
  local pages = {}
  for i, t in ipairs(tabs) do
    pages[i] = ui.Item {
      id = spec.id .. "-page-" .. t.key,
      width = page_w, height = page_h,
      x=page_wipe and function() return (i-1)*(page_w()+2*PAD) end or nil,
      visible=function() return not page_wipe or display:get()==i or peeking:get() end,
      -- A page beside the one on show is out of Tab's way.
      enabled=function() return tab:get()==i end,
      ui.Loader {
        anchors = { fill = true }, keep = not fluid,
        preload = not fluid and function() return tab:get() == i end or nil,
        active = function() return seen[i]:get() and not (again and again:get()) end,
        source = function() return t.build(fluid and built:get() or page_w(), page_h) end,
      },
    }
  end
  local track = (page_wipe and ui.Item or ui.Row) {
    id=spec.id.."-page-track",
    width=page_wipe and function() return #tabs*(page_w()+2*PAD) end or nil,height=page_h,
    gap = not page_wipe and 2 * PAD or nil,
    table.unpack(pages),
  }
  local running
  local pager=require("pager_drag").new {
    id=spec.id,track=track,tab=tab,shown=display,count=#tabs,
    offset=function(i) return (i-1)*(page_w()+2*PAD) end,
    spring=phone and theme.spring.spatial or SWITCH,
    -- A wipe swaps the pages under its cover, the track jumping there.
    instant=page_wipe and function() return not peeking:get() end or nil,
    peeking=function(on) peeking:set(on) end,
    prepare=function()
      if running then for _,h in ipairs(running) do h:stop() end running=nil end
      for _,page in ipairs(pages) do page.opacity,page.scale=1,1 end
      local now=tab:get()
      for i=now-1,now+1 do if seen[i] and not seen[i]:get() then seen[i]:set(true) end end
    end,
  }
  -- `tabs_at = "bottom"`: the row under the pages (a drawer from the bottom
  -- edge has it by the edge, under the thumb).
  local below = spec.tabs_at == "bottom"
  local strip = ui.Item {
    id = spec.id .. "-pages",
    x = PAD, y = below and PAD or TABS_H + PAD, width = page_w, height = page_h,
    clip = true,
    track,
  }

  local wipe = page_wipe and theme.motion.page_wipe(strip, page_w, spec.id)
  if fluid then
    local resting
    morf.effect("eva." .. spec.id .. ".width", function()
      local wanted = spec.width() - 2 * PAD
      if resting then resting:cancel() resting = nil end
      if wanted == built:get() then return end
      resting = morf.time.timer(REST_MS, function()
        resting = nil
        built:set(wanted)
        again:set(true)
        morf.time.timer(1, function() again:set(false) end, false)
      end, false)
    end)
  end
  local function present(index)
    display:set(index)
    if spec.on_present then spec.on_present(index) end
  end

  -- The incoming page grows in evenly as it fades in; a page a finger brought
  -- in is already there.
  local was = tab:get()
  morf.effect("eva." .. spec.id .. ".page", function()
    local now = tab:get()
    if now == was then return end
    was = now
    if running then for _, h in ipairs(running) do h:stop() end end
    local slid = pager.slid()
    local function enter()
      present(now)
      if not phone and not slid then running = kit.bud({ pages[now] }, true, { from = 0.97, delay = 60 }) end
    end
    if wipe and not slid then wipe(enter, not presented:get(), {
      index=now,name=tabs[now].name,key=tabs[now].key,
    }) else enter() end
    if spec.on_tab then spec.on_tab(tabs[now].key) end
  end)

  --- Called as the panel opens (`true`) or shuts: the chosen page buds in.
  local shown, budding
  function panel.shown(open)
    -- This is called from an effect. Reading tab below also subscribes that
    -- effect to selection: an unchanged open state must not cancel its wipe.
    if shown == open then return end
    shown = open
    if open then opened:set(true) end
    presented:set(open)
    if wipe then wipe(function() present(tab:get()) end, true) else present(tab:get()) end
    if running then for _, h in ipairs(running) do h:stop() end end
    if budding then budding:cancel() budding = nil end
    if wipe or phone then
      for _,page in ipairs(pages) do page.opacity,page.translate_x,page.translate_y=1,0,0 end
    else
      -- The bud runs outside the calling effect.
      local page = pages[tab:get()]
      budding = morf.time.timer(1, function()
        budding = nil
        running = kit.bud({ page }, open, { from = 0.97 })
      end, false)
    end
  end

  root = ui.Item {
    anchors = { fill = true },
    on_panned = require("phone_gestures").pan {drawer=spec.id,dismiss=spec.dismiss,pager=pager,
      grip=function(_,y)
        local top=root.layout_y or 0
        if below then return y>=top+spec.height()-TABS_H end
        return y<top+TABS_H
      end},
    on_swiped = require("phone_gestures").panel {
      tab = tab, count = #tabs, close = spec.close, dismiss = spec.dismiss,
    },
    -- Behind everything, so the whole panel takes the pointer.
    ui.MouseArea { anchors = { fill = true }, z = -1 },
    -- The tab row is the theme's (every kit has `tabs`, the kit contract).
    ui.Item { width = fluid and W or spec.width, height = TABS_H, y = below and function() return spec.height() - TABS_H end or 0,
      kit.tabs {id=spec.id,accessible_name=spec.title or ({sidebar="Sidebar",leftbar="Planner",bottom="Tools"})[spec.id] or spec.id,
        tabs=tabs,tab=tab,width=fluid and W or spec.width,pad=PAD,height=TABS_H,icons_only=spec.icons_only} },
    strip,
  }
  panel.content = root
  panel.pages = pages
  return panel
end

return M
