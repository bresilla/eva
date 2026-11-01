-- Material drawer choreography, separate from drawer state and placement.
local morf = require("morf")
local ui = require("morf.ui")
return function(theme)
  local M = {}

  -- What a presence lights: whole by the middle of the way out, and whole
  -- still until the middle of the way back.
  local function lit(gone)
    return function() return math.max(0, math.min(1, (1 - gone:get()) * 2)) end
  end

  -- A panel on an edge slides out of it: the axis on the drawer spring, its
  -- contents, background and seam following who owns the axis.
  local function slide(ctx)
    local panel, content, d = ctx.panel, ctx.spec.content, ctx.drawer
    local axis
    axis = require("themes.drawer_axis").new {
      node = panel, property = ctx.axis, name = "eva.drawer." .. d.name,
      spring = theme.spring.drawer, away = ctx.tucked,
      out = function() return d.open:get() end,
      landed = function() panel.visible = d.open:get() end,
    }
    local shown = lit(axis.away)
    content.opacity, d.shape.opacity = shown, shown
    d.shape.blend = function() return theme.SEAM * shown() end
    panel.stretch = theme.stretch.drawer
    return {
      move = function(opening) if opening then panel.visible = true end end,
      stop = axis.stop,
      grab = function(from)
        panel.visible = true
        return axis.grab(from)
      end,
      drag = axis.drag, release = axis.release,
    }
  end

  -- A floating panel joins no edge: it grows about its centre as it and its
  -- background fade in, and shrinks a touch as they fade out.
  local function pop(ctx)
    local panel, d = ctx.panel, ctx.drawer
    local function open() return d.open:get() end
    local claims = ui.claims(panel, {
      grown = { when = open, motion = theme.spring.spatial, set = { scale = 1 } },
      small = { motion = theme.spring.fast, set = { scale = 0.92 } },
      shown = { when = open, motion = theme.spring.effects, set = { opacity = 1 } },
      gone = { motion = theme.spring.effects, set = { opacity = 0 } },
    })
    d.shape.opacity = lit(claims.gone.presence)
    morf.effect("eva.drawer." .. d.name .. ".landed", function()
      if claims.gone.presence:get() >= 1 and not open() then panel.visible = false end
    end, { owner = panel })
    local function idle() end
    return { move = function(opening) if opening then panel.visible = true end end,
      stop = idle, grab = idle, drag = idle, release = idle }
  end

  function M.drawer(ctx)
    return (ctx.floating and pop or slide)(ctx)
  end

  -- The frame's working panels share one seam group: where two meet they melt
  -- into one surface. A shut one has no layer, so nothing needs switching.
  local NEIGHBOURS = { dashboard = true, sidebar = true, leftbar = true, bottom = true,
    session = true, capture = true, notifications = true }
  function M.seam_group(name, own) return NEIGHBOURS[name] and 900 or own end

  function M.entries(entries, coming, opts)
    if require("themes.session").restoring then
      for _, entry in ipairs(entries) do
        entry.node.opacity = coming and 1 or 0
        entry.node.scale, entry.node.translate_x, entry.node.translate_y = 1, 0, 0
        if entry.shape then entry.shape.opacity = coming and 1 or 0 end
      end
      return {}, 0
    end
    opts = opts or {}
    local handles = {}
    for k, entry in ipairs(entries) do
      local n = entry.node
      local fresh = not (n.opacity > 0 and n.opacity < 1)
      local steps
      if coming then
        local delay = (opts.delay or 40) + (k - 1) * (opts.stagger or 26)
        steps = {
          { node = n, property = "scale", from = fresh and (opts.from or 0.92) or nil, to = 1,
            duration = theme.bounce.spatial.duration, easing = theme.bounce.spatial.easing, delay = delay },
          { node = n, property = "opacity", from = fresh and 0 or nil, to = 1, duration = 220, delay = delay },
        }
      else
        steps = {
          { node = n, property = "scale", to = 0.96, duration = 160, easing = theme.ease.emphasized_accel, delay = (k - 1) * (opts.leave_stagger or 0) },
          { node = n, property = "opacity", to = 0, duration = 120, delay = (k - 1) * (opts.leave_stagger or 0) },
        }
      end
      if entry.shape then
        steps[#steps + 1] = { node = entry.shape, property = "opacity", from = coming and fresh and 0 or nil,
          to = coming and 1 or 0, duration = coming and 220 or 120,
          delay = coming and ((opts.delay or 40) + (k - 1) * (opts.stagger or 26)) or 0 }
      end
      handles[#handles + 1] = morf.animation.play { { parallel = steps } }
    end
    return handles, coming and (420 + #entries * (opts.stagger or 26)) or 200
  end

  return M
end
