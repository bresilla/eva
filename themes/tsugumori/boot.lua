-- A finite boot pass over a host box: its outline traces in from the
-- top-left corner both ways, four corner brackets snap onto its corners, a
-- scan line crosses it and a short register of static words prints and
-- fades. The nodes are made on the first pass and hidden again when a pass
-- ends or stops, so a host at rest holds nothing that moves.
local morf = require("morf")
local ui = require("morf.ui")

return function(theme)
  local C = theme.color
  local B = {}

  --- `host` (a node), `id` (names the pieces `<id>-boot-*`), `opts`:
  --- `trace`, `brackets`, `scan`, `register` (booleans, all on by
  --- default), `words` (the register's text), `place` (the register's
  --- anchors), `z` (104), `length` (the brackets', 10), `reach` (how far out
  --- they start, 10). Returns `play(delay)` and `stop()`.
  function B.new(host, id, opts)
    opts = opts or {}
    local z = opts.z or 104
    local L, reach = opts.length or 10, opts.reach or 10
    local nodes, running
    local function want(name) return opts[name] ~= false end
    local function size() return host.layout_width or host.width or 0, host.layout_height or host.height or 0 end

    local function build()
      nodes = {}
      if want("trace") then
        -- One loop from the bottom-right corner, so the top-left sits at its
        -- middle: trimming outwards from 0.5 draws both ways at once.
        nodes.trace = ui.Path { id = id .. "-boot-trace", z = z, anchors = { fill = true },
          d = function()
            local w, h = size()
            if w < 2 or h < 2 then return "M0 0" end
            return ("M%g %g H.5 V.5 H%g V%g"):format(w - .5, h - .5, w - .5, h - .5)
          end,
          fill_color = "transparent", stroke_width = 1, stroke_cap = "butt", stroke_join = "miter",
          stroke_color = function() return C.primary:alpha(.85) end,
          trim_start = .5, trim_end = .5, opacity = 0, visible = false }
        ui.reparent(nodes.trace, host)
      end
      if want("brackets") then
        nodes.brackets, nodes.signs = {}, {}
        local h = .5
        for i, corner in ipairs {
          { { left = true, top = true }, ("M%g %g V%g H%g"):format(h, L, h, L), -1, -1 },
          { { right = true, top = true }, ("M0 %g H%g V%g"):format(h, L - h, L), 1, -1 },
          { { left = true, bottom = true }, ("M%g 0 V%g H%g"):format(h, L - h, L), -1, 1 },
          { { right = true, bottom = true }, ("M0 %g H%g V0"):format(L - h, L - h), 1, 1 },
        } do
          local mark = ui.Path { id = id .. "-boot-bracket-" .. i, z = z + 1, anchors = corner[1],
            width = L, height = L, view_box = { 0, 0, L, L }, d = corner[2],
            fill_color = "transparent", stroke_width = 1.5, stroke_cap = "square",
            stroke_color = function() return C.primary end, opacity = 0, visible = false }
          nodes.brackets[i] = mark
          nodes.signs[i] = { corner[3], corner[4] }
          ui.reparent(mark, host)
        end
      end
      if want("scan") then
        local trail = ui.Rect { anchors = { left = true, right = true }, y = 0, height = 18,
          gradient = function() return { angle = 180, stops = { C.secondary:alpha(0), C.secondary:alpha(.22) } } end }
        local line = ui.Rect { anchors = { left = true, right = true }, y = 18, height = 1,
          color = function() return C.onSurface:alpha(.7) end }
        nodes.mover = ui.Item { anchors = { left = true, right = true }, height = 19, trail, line }
        nodes.scan = ui.Item { id = id .. "-boot-scan", z = z, anchors = { fill = true }, clip = true,
          opacity = 0, visible = false, nodes.mover }
        ui.reparent(nodes.scan, host)
      end
      if want("register") then
        local words = opts.words or "SYS // LINK"
        local W = math.ceil(utf8.len(words) * 6.6) + 2
        -- A clip of no width takes its child's, so an empty run keeps a sliver.
        nodes.typed = ui.Item { width = .001, height = 12, clip = true,
          ui.Text { width = W, height = 12, text = words, font_family = theme.font, font_size = 9,
            letter_spacing = 1.2, vertical_alignment = "center", color = function() return C.primary end } }
        nodes.cursor = ui.Rect { y = 2, width = 5, height = 8, color = function() return C.primary end }
        local place = opts.place or { right = true, bottom = true, right_margin = 14, bottom_margin = 2 }
        nodes.W = W
        nodes.register = ui.Item { id = id .. "-boot-register", z = z + 2, anchors = place, width = W + 6,
          height = 12, opacity = 0, visible = false, nodes.typed, nodes.cursor }
        ui.reparent(nodes.register, host)
      end
    end

    local function pieces()
      local out = {}
      for _, key in ipairs { "trace", "scan", "register" } do if nodes[key] then out[#out + 1] = nodes[key] end end
      for _, mark in ipairs(nodes.brackets or {}) do out[#out + 1] = mark end
      return out
    end
    local function hide()
      if not nodes then return end
      for _, node in ipairs(pieces()) do node.visible, node.opacity = false, 0 end
    end

    local P, waiting = {}, nil
    --- Ends a pass: at once, or `soft`ly, its pieces fading out first.
    function P.stop(soft)
      if waiting then waiting:cancel() waiting = nil end
      if running then running:stop() running = nil end
      if not (soft and nodes) then hide() return end
      local fades = {}
      for _, node in ipairs(pieces()) do
        if node.visible and node.opacity > 0 then
          fades[#fades + 1] = { node = node, property = "opacity", to = 0, duration = 90, easing = "out_cubic" }
        end
      end
      if #fades == 0 then hide() return end
      running = morf.animation.play { { parallel = fades }, on_finished = function(reason)
        if reason == "completed" then running = nil hide() end
      end }
    end
    --- One pass, `delay` ms from now.
    function P.play(delay, retried)
      if not nodes then build() end
      if waiting then waiting:cancel() waiting = nil end
      if running then running:stop() running = nil end
      delay = delay or 0
      local w, h = size()
      if w < 4 or h < 4 then
        hide()
        -- A host made this turn is laid out by the next frame.
        if not retried then
          waiting = morf.time.timer(16, function() waiting = nil P.play(math.max(0, delay - 16), true) end, false)
        end
        return
      end
      local tracks = {}
      local function add(t) t.delay = (t.delay or 0) + delay tracks[#tracks + 1] = t end
      if nodes.trace then
        nodes.trace.trim_start, nodes.trace.trim_end = .5, .5
        add { node = nodes.trace, property = "trim_start", from = .5, to = 0, duration = 300, easing = "out_quart" }
        add { node = nodes.trace, property = "trim_end", from = .5, to = 1, duration = 300, easing = "out_quart" }
        add { node = nodes.trace, property = "opacity", duration = 460, keyframes = {
          { at = 0, value = 0 }, { at = .06, value = .9 }, { at = .62, value = .7 }, { at = 1, value = 0 } } }
      end
      for i, mark in ipairs(nodes.brackets or {}) do
        -- Held out, a hard step in, then an expo settle onto the corner.
        local sign_x, sign_y = nodes.signs[i][1], nodes.signs[i][2]
        for property, sign in pairs { translate_x = sign_x, translate_y = sign_y } do
          add { node = mark, property = property, duration = 300, keyframes = {
            { at = 0, value = sign * reach }, { at = .22, value = sign * reach },
            { at = .23, value = sign * reach * .4 }, { at = 1, value = 0, easing = "out_expo" } } }
        end
        add { node = mark, property = "opacity", duration = 480, keyframes = {
          { at = 0, value = 0 }, { at = .08, value = 1 }, { at = .2, value = .35 }, { at = .3, value = 1 },
          { at = .72, value = .9 }, { at = 1, value = 0 } } }
      end
      if nodes.scan then
        add { node = nodes.mover, property = "translate_y", from = -19, to = h, delay = 60, duration = 320,
          easing = "out_cubic" }
        add { node = nodes.scan, property = "opacity", delay = 60, duration = 320, keyframes = {
          { at = 0, value = 0 }, { at = .1, value = 1 }, { at = .8, value = .7 }, { at = 1, value = 0 } } }
      end
      if nodes.register then
        local W = nodes.W
        nodes.typed.width, nodes.cursor.translate_x = .001, 0
        add { node = nodes.typed, property = "width", from = .001, to = W, delay = 120, duration = 200, easing = "linear" }
        add { node = nodes.cursor, property = "translate_x", from = 0, to = W + 1, delay = 120, duration = 200,
          easing = "linear" }
        add { node = nodes.register, property = "opacity", delay = 120, duration = 360, keyframes = {
          { at = 0, value = 0 }, { at = .04, value = 1 }, { at = .7, value = 1 }, { at = 1, value = 0 } } }
        add { node = nodes.cursor, property = "opacity", delay = 120, duration = 360, keyframes = {
          { at = 0, value = 1 }, { at = .55, value = 1 }, { at = .56, value = 0 }, { at = .66, value = 0 },
          { at = .67, value = 1 }, { at = 1, value = 1 } } }
      end
      for _, node in ipairs(pieces()) do node.visible, node.opacity = true, 0 end
      running = morf.animation.play { { parallel = tracks }, on_finished = function(reason)
        if reason == "completed" then running = nil hide() end
      end }
    end
    function P.active() return running ~= nil end
    return P
  end
  return B
end
