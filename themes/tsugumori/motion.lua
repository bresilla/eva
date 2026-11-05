-- Tsugumori motion, adapted from its MIT-licensed Menu and ControlCenterView.
-- See REFERENCE.md and LICENSE-Tsugumori. Reversals retain the current pose.
local morf = require("morf")
local ui = require("morf.ui")
local unicase = require("lib.util.unicase")
return function(theme)
  local M = { liquid_cards = false,
    value_flash=require("themes.tsugumori.value_flash")(theme),
    auth_result=require("themes.tsugumori.auth_result")(theme),
    notification_acquire=require("themes.tsugumori.notification_acquire")(theme) }
  -- Keep the cover/swap/reveal order, with a shorter, consistent cadence.
  local PAGE_COVER, REVEAL = 140, 220
  local COVER = 230
  local ENTRY_DELAY, ENTRY_MOVE, ENTRY_LEAVE, STAGGER = 180, 240, 120, 50
  -- Each card's corner brackets, by card node (components.lua fills it).
  local card_marks = require("themes.tsugumori.marks")
  local OUTWARD = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
  -- The working panels whose ground carries the dot grid.
  local GRID = { dashboard = true, sidebar = true, leftbar = true, bottom = true }
  local UNBOOTED = { keyboard = true, notifications = true }
  -- A corner mark's way in: held out, a hard step, an expo settle.
  local function snap(from)
    return { { at = 0, value = from }, { at = .24, value = from }, { at = .25, value = from * .4 },
      { at = 1, value = 0, easing = "out_expo" } }
  end
  -- The page cover in three bands, a step apart: a slice reveal.
  local SLICES, SLICE_STEP = 3, 15
  function M.page_wipe(host, width, id)
    local function band(k, name)
      local function top(i) return math.floor((host.layout_height or 0) * i / SLICES) end
      return ui.Rect { id = id .. name, z = 90, x = 0, width = 0, visible = false, clip = true,
        y = function() return top(k) end, height = function() return top(k + 1) - top(k) end,
        color = function() return theme.color.primary end,
        require("themes.kit.widgets").shield { anchors = { fill = true } },
      }
    end
    local cover = band(1, "-page-curtain")
    local bands = { band(0, "-page-slice-1"), cover, band(2, "-page-slice-3") }
    -- This stroke is a sibling of the cover: children of a clipped, animated
    -- rectangle are not reliably composited above its fill by the renderer.
    local glow = ui.Rect { id=id.."-page-glow",z=91,x=-12,width=16,
      anchors={top=true,bottom=true},color=function() return theme.color.secondary end,
      opacity=0,visible=false }
    local flash = ui.Rect { id=id.."-page-flash",z=92,x=0,width=4,
      anchors={top=true,bottom=true},color=function() return theme.color.onSurface end,
      opacity=0,visible=false }
    local register = ui.Text {id=id.."-page-register",z=93,x=22,y=18,
      width=function() return math.max(1,width()-44) end,height=22,
      font_family=theme.font,font_size=12,letter_spacing=2,
      color=function() return theme.color.onPrimary end,
      text="",opacity=0,visible=false}
    for _, slice in ipairs(bands) do ui.reparent(slice, host) end
    ui.reparent(glow, host)
    ui.reparent(flash, host)
    ui.reparent(register,host)
    local running, generation = nil, 0
    return function(swap, immediate, destination)
      generation = generation + 1
      local own = generation
      if running then running:stop() end
      flash.visible,flash.opacity,glow.visible,glow.opacity=false,0,false,0
      register.visible,register.opacity=false,0
      register.x=22
      if immediate then
        for _, slice in ipairs(bands) do slice.visible, slice.width = false, 0 end
        swap() return
      end
      if destination then
        register.text=("%02d / %s"):format(destination.index or 0,
          unicase.upper(tostring(destination.name or destination.key or id)))
      else register.text=("TS / %s"):format(unicase.upper(id)) end
      register.visible=true
      local covering = {
        { node = register, property = "opacity",from=0,to=.85,duration=PAGE_COVER,easing="out_cubic" },
      }
      local step_in = PAGE_COVER - (SLICES - 1) * SLICE_STEP
      for k, slice in ipairs(bands) do
        slice.visible = true
        local delay = (k - 1) * SLICE_STEP
        covering[#covering + 1] = { node = slice, property = "x", to = 0, delay = delay, duration = step_in,
          easing = "in_out_quint" }
        covering[#covering + 1] = { node = slice, property = "width", to = width(), delay = delay,
          duration = step_in, easing = "in_out_quint" }
      end
      running = morf.animation.play { { parallel = covering }, on_finished = function(reason)
        if reason ~= "completed" or own ~= generation then return end
        swap()
        flash.x,flash.visible,glow.x,glow.visible=0,true,-12,true
        local step_out = REVEAL - (SLICES - 1) * SLICE_STEP
        local revealing = {}
        for k, slice in ipairs(bands) do
          local delay = (k - 1) * SLICE_STEP
          revealing[#revealing + 1] = { node = slice, property = "x", to = width(), delay = delay,
            duration = step_out, easing = "out_expo" }
          revealing[#revealing + 1] = { node = slice, property = "width", to = 0, delay = delay,
            duration = step_out, easing = "out_expo" }
        end
        running = morf.animation.play { { parallel = {
          { parallel = revealing },
          { node = register, property = "opacity",to=0,duration=100,easing="out_cubic" },
          { node = register, property = "x",to=width()+22,duration=REVEAL,easing="out_expo" },
          { node = flash, property = "x", to = width(), duration = REVEAL, easing = "out_expo" },
          { node = glow, property = "x", to = width()-12, duration = REVEAL, easing = "out_expo" },
          { node = glow, property = "opacity",duration=REVEAL,keyframes={
            {at=0,value=0},{at=.12,value=.22},{at=.68,value=.17},{at=1,value=0} } },
          { node = flash, property = "opacity",duration=REVEAL,keyframes={
            {at=0,value=0},{at=.12,value=.9},{at=.68,value=.72},{at=1,value=0} } },
        } }, on_finished = function(why)
          if why == "completed" and own == generation then
            for _, slice in ipairs(bands) do slice.visible = false end
            flash.visible,glow.visible,register.visible=false,false,false
          end
        end }
      end }
    end
  end
  --- A surface coming up under a target lock: four brackets close onto
  --- `host` from outside and a scan line crosses it. `lock(delay)` plays
  --- it, `lock(nil)` stops and hides it. Nothing is built before the first.
  function M.lock_on(host, id, opts)
    local pass
    return function(delay)
      if delay == nil or delay == false then
        if pass then pass.stop(true) end
        return
      end
      if require("themes.session").restoring then return end
      pass = pass or require("themes.tsugumori.boot")(theme).new(host, id .. "-lock",
        opts or { trace = false, register = false, length = 10, reach = 14 })
      pass.play(delay)
    end
  end
  function M.entries(entries, coming, opts)
    if require("themes.session").restoring then
      for _, entry in ipairs(entries) do
        entry.node.opacity = coming and 1 or 0
        entry.node.scale, entry.node.translate_x, entry.node.translate_y = 1, 0, 0
        if entry.shape then entry.shape.opacity = coming and 1 or 0 end
        for _, mark in ipairs(card_marks[entry.node] or {}) do mark.translate_x, mark.translate_y = 0, 0 end
      end
      return {}, 0
    end
    opts = opts or {}
    local handles = {}
    for k, entry in ipairs(entries) do
      local node = entry.node
      local fresh = not (node.opacity > 0 and node.opacity < 1)
      local delay = coming and ((opts.delay or ENTRY_DELAY) + (k - 1) * (opts.stagger or STAGGER)) or 0
      local steps = {
        { node = node, property = "translate_x", from = coming and fresh and -12 or nil, to = coming and 0 or -12,
          delay = delay, duration = coming and ENTRY_MOVE or ENTRY_LEAVE, easing = "out_cubic" },
        { node = node, property = "translate_y", from = coming and fresh and -8 or nil, to = coming and 0 or -6,
          delay = delay, duration = coming and ENTRY_MOVE or ENTRY_LEAVE, easing = "out_cubic" },
        { node = node, property = "opacity", from = coming and fresh and 0 or nil, to = coming and 1 or 0,
          delay = delay, duration = coming and ENTRY_MOVE or ENTRY_LEAVE, easing = "out_cubic" },
      }
      if entry.shape then
        steps[#steps + 1] = { node = entry.shape, property = "opacity", from = coming and fresh and 0 or nil,
          to = coming and 1 or 0, delay = delay, duration = coming and ENTRY_MOVE or ENTRY_LEAVE }
      end
      -- A card's corner brackets snap onto it as it comes in.
      for m, mark in ipairs(card_marks[node] or {}) do
        for axis, property in ipairs { "translate_x", "translate_y" } do
          if coming and fresh then
            steps[#steps + 1] = { node = mark, property = property, delay = delay, duration = ENTRY_MOVE,
              keyframes = snap(OUTWARD[m][axis] * 7) }
          else
            steps[#steps + 1] = { node = mark, property = property, to = 0, delay = delay,
              duration = coming and ENTRY_MOVE or ENTRY_LEAVE, easing = "out_cubic" }
          end
        end
      end
      handles[#handles + 1] = morf.animation.play { { parallel = steps } }
    end
    return handles, coming and ((opts.delay or ENTRY_DELAY) + ENTRY_MOVE + math.max(0, #entries - 1) * (opts.stagger or STAGGER)) or ENTRY_LEAVE
  end
  -- Menu.qml's covered entrance and uncover at a quicker cadence. Close
  -- covers before withdrawal so the visible content cannot be exposed during
  -- travel. Reversals retain the current pose of each active phase.
  function M.drawer(ctx)
    local panel, content, d = ctx.panel, ctx.spec.content, ctx.drawer
    local id="drawer-" .. (d.name or "auth")
    local curtain, unit = require("themes.tsugumori.curtain")(theme, panel, id)
    -- The on-screen keyboard keeps its own look and motion, and notification
    -- cards lock on by themselves: neither boots.
    local boot = not UNBOOTED[d.name] and require("themes.tsugumori.boot")(theme).new(panel, id, {
      brackets = false, words = ("%s %s // SYS LINK"):format(unit[3], unit[2]) }) or nil
    if GRID[d.name] then require("themes.tsugumori.dots")(theme)(panel, id) end
    local glow=ui.Rect {id=id.."-reveal-glow",z=101,x=-12,width=16,
      anchors={top=true,bottom=true},color=function() return theme.color.secondary end,
      opacity=0,visible=false}
    local flash=ui.Rect {id=id.."-reveal-flash",z=102,x=0,width=4,
      anchors={top=true,bottom=true},color=function() return theme.color.onSurface end,
      opacity=0,visible=false}
    ui.reparent(glow,panel)
    ui.reparent(flash,panel)
    local corner_a=ui.Path {id=id.."-lock-corner-a",z=103,anchors={left=true,top=true},
      width=16,height=16,view_box={0,0,16,16},d="M0 0 H16 V2 H2 V16 H0 Z",
      fill_color=function() return theme.color.secondary end,opacity=0,visible=false}
    local corner_b=ui.Path {id=id.."-lock-corner-b",z=103,anchors={right=true,bottom=true},
      width=16,height=16,rotation=180,view_box={0,0,16,16},d="M0 0 H16 V2 H2 V16 H0 Z",
      fill_color=function() return theme.color.secondary end,opacity=0,visible=false}
    local pip=ui.Rect {id=id.."-lock-pip",z=103,anchors={top=true,horizontal_center=true},
      y=7,width=5,height=5,color=function() return theme.color.primary end,
      opacity=0,visible=false}
    ui.reparent(corner_a,panel)
    ui.reparent(corner_b,panel)
    ui.reparent(pip,panel)
    local function tucked()
      if ctx.floating then return (panel.width_target or panel.width) + 2 end
      return ctx.tucked()
    end
    if ctx.floating then d.shape.opacity = d.open:get() and 1 or 0 end
    -- The panel's travel, on this theme's own spring. `out` follows the
    -- choreography: closing covers, then withdraws.
    local out = morf.signal(id .. ".out", d.open:get())
    local arrive
    local axis = require("themes.drawer_axis").new {
      node = panel, property = ctx.floating and "translate_x" or ctx.axis, name = id,
      spring = theme.spring.drawer, away = tucked,
      out = function() return out:get() end,
      landed = function()
        local go = arrive
        arrive = nil
        if go then go() end
      end,
    }
    local running, lock_motion, generation = nil, nil, 0
    local function move(opening)
      generation = generation + 1
      local own = generation
      local hidden = not panel.visible
      arrive = nil
      if running then running:stop() end
      if lock_motion then lock_motion:stop() lock_motion=nil end
      if boot then boot.stop(true) end
      corner_a.visible,corner_b.visible,pip.visible=false,false,false
      corner_a.opacity,corner_b.opacity,pip.opacity=0,0,0
      if hidden then
        curtain.width, curtain.x = math.max(panel.width, panel.width_target or 0), 0
      end
      panel.visible, curtain.visible, content.opacity, d.shape.opacity = true, true, 1, 1
      flash.x,flash.visible,flash.opacity=curtain.x,true,0
      glow.x,glow.visible,glow.opacity=curtain.x-12,true,0
      local width = panel.width_target or panel.width
      local cover = math.min(1, curtain.width / math.max(1, width))
      local easing = { x1 = 0.76, y1 = 0, x2 = 0.24, y2 = 1 }
      local function finish()
        if generation ~= own then return end
        running=nil
        panel.visible=d.open:get()
        curtain.visible,flash.visible,glow.visible=false,false,false
        if not opening then return end
        corner_a.visible,corner_b.visible,pip.visible=true,true,true
        -- Snapped in, but slid in on the keyboard's drawer as it always was.
        local function corner(node,property,from)
          if not boot then return {node=node,property=property,from=from*7/9,to=0,duration=280,easing="out_cubic"} end
          return {node=node,property=property,duration=280,keyframes=snap(from)}
        end
        lock_motion=morf.animation.play {{parallel={
          corner(corner_a,"translate_x",-9), corner(corner_a,"translate_y",-9),
          corner(corner_b,"translate_x",9), corner(corner_b,"translate_y",9),
          {node=corner_a,property="opacity",duration=360,keyframes={
            {at=0,value=0},{at=.18,value=.86},{at=.55,value=.56},{at=1,value=0}}},
          {node=corner_b,property="opacity",duration=360,keyframes={
            {at=0,value=0},{at=.18,value=.86},{at=.55,value=.56},{at=1,value=0}}},
          {node=pip,property="opacity",duration=360,keyframes={
            {at=0,value=0},{at=.12,value=1},{at=.32,value=0},
            {at=.55,value=1},{at=.75,value=0},{at=1,value=0}}},
        }},on_finished=function(reason)
          if generation~=own then return end
          if reason=="completed" and generation==own then
            corner_a.visible,corner_b.visible,pip.visible=false,false,false
          end
          lock_motion=nil
        end}
      end
      local function sweep(uncover,next_phase)
        local duration=math.max(1,uncover and REVEAL*cover or COVER*(1-cover))
        running=morf.animation.play {{parallel={
          {node=curtain,property="width",to=uncover and 0 or width,duration=duration,
            easing=uncover and "out_expo" or easing},
          {node=curtain,property="x",to=uncover and width or 0,duration=duration,
            easing=uncover and "out_expo" or easing},
          {node=flash,property="x",to=uncover and width or 0,duration=duration,
            easing=uncover and "out_expo" or easing},
          {node=glow,property="x",to=(uncover and width or 0)-12,duration=duration,
            easing=uncover and "out_expo" or easing},
          {node=glow,property="opacity",duration=duration,keyframes={
            {at=0,value=0},{at=.18,value=.22},{at=.48,value=.17},{at=1,value=0}}},
          {node=flash,property="opacity",duration=duration,keyframes={
            {at=0,value=0},{at=.18,value=.82},{at=.48,value=.58},{at=1,value=0}}},
        }},on_finished=function(reason)
          if reason=="completed" and generation==own then next_phase() end
        end}
      end
      local function travel(there,next_phase)
        out:set(there)
        if axis.arrived() then next_phase() return end
        arrive=function() if generation==own then next_phase() end end
      end
      if opening then travel(true,function()
        sweep(true,finish)
        -- The boot pass overlaps the uncover's settle.
        if boot and not require("themes.session").restoring then
          boot.play(math.floor(REVEAL*cover*.35))
        end
      end)
      else sweep(false,function() travel(false,finish) end) end
    end
    return {
      move = move,
      stop = function()
        generation = generation + 1
        arrive = nil
        axis.stop()
        if running then running:stop() running=nil end
        if lock_motion then lock_motion:stop() lock_motion=nil end
        if boot then boot.stop() end
        for _, node in ipairs {curtain,glow,flash,corner_a,corner_b,pip} do node.visible=false end
      end,
      grab = function(from)
        panel.visible, content.opacity, d.shape.opacity = true, 1, 1
        out:set(true)
        return axis.grab(from)
      end,
      drag = axis.drag,
      release = function(velocity, done)
        out:set(d.open:get())
        axis.release(velocity, function()
          panel.visible = d.open:get()
          done()
        end)
      end,
    }
  end
  return M
end
