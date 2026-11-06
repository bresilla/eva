-- A finite boot pass over a host box: its outline traces in from the
-- top-left corner both ways, four corner brackets snap onto its corners, a
-- bright scan line with a glowing trail sweeps it top to bottom and a short
-- register of static words prints and fades. With `content`, the chrome laid
-- out under the host (marks.lua) boots as the scan reaches it: each card's
-- outline draws itself in, its brackets fly in from the host's corners and
-- snap on, section captions light, readings decode and meters fill. The
-- nodes are made on the first pass and hidden again when a pass ends or
-- stops, so a host at rest holds nothing that moves.
local morf = require("morf")
local ui = require("morf.ui")
local registry = require("themes.tsugumori.marks")

local OUTWARD = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
local SCAN, TRAIL = 300, 64

--- A keyframe track behind a pause of its `delay`.
local function timed(t)
  local d = t.delay
  if not t.keyframes or not d or d <= 0 then return t end
  t.delay = nil
  return { sequence = { { pause = d }, t } }
end

return function(theme)
  local C = theme.color
  local B = { SCAN = SCAN }
  local function rest_outline() return registry.OUTLINE end

  --- The chrome of `entry` (a card's) at rest.
  local function card_rest(entry)
    if entry.outline then
      entry.outline.trim_start, entry.outline.trim_end, entry.outline.opacity = 0, 1, rest_outline()
      entry.edges.opacity = 1
    end
    for _, mark in ipairs(entry.marks) do mark.translate_x, mark.translate_y, mark.opacity = 0, 0, 1 end
  end
  local function caption_rest(entry)
    entry.plate.opacity, entry.rule.scale_x = 1, 1
    if entry.hazard then entry.hazard.opacity = 1 end
  end
  B.card_rest = card_rest

  --- Each mark's flight onto its corner from the host's matching corner
  --- (or `reach` px out, whichever is further), with a hard overshoot.
  local function flight(entry, box, host, delay, reach)
    local corners, far
    if box and host then
      corners = { { box.x, box.y }, { box.x + box.w, box.y }, { box.x, box.y + box.h },
        { box.x + box.w, box.y + box.h } }
      far = { { host.x, host.y }, { host.x + host.w, host.y }, { host.x, host.y + host.h },
        { host.x + host.w, host.y + host.h } }
    end
    local tracks = {}
    for i, mark in ipairs(entry.marks) do
      for axis, property in ipairs { "translate_x", "translate_y" } do
        local out = OUTWARD[i][axis]
        local d = far and (far[i][axis] - corners[i][axis]) or 0
        if d * out < reach then d = out * reach end
        local over = -out * 4
        mark[property] = d
        tracks[#tracks + 1] = timed { node = mark, property = property, delay = delay, duration = 300, keyframes = {
          { at = 0, value = d }, { at = .66, value = over, easing = "out_cubic" },
          { at = .82, value = -over * .35, easing = "in_out_sine" }, { at = 1, value = 0, easing = "out_cubic" } } }
      end
      mark.opacity = 0
      tracks[#tracks + 1] = timed { node = mark, property = "opacity", delay = delay, duration = 300, keyframes = {
        { at = 0, value = 0 }, { at = .06, value = 1 }, { at = .68, value = 1 }, { at = .74, value = .25 },
        { at = .8, value = 1 }, { at = 1, value = 1 } } }
    end
    return tracks
  end
  B.flight = flight

  --- The marks of card `entry` flying onto `box` (a layout box) from
  --- `reach` px out after `delay` ms: its own handle, stopping the last.
  --- Lands `entry`'s flight on its rest pose.
  local function land(entry)
    if entry.flight then local flown = entry.flight entry.flight = nil pcall(flown.finish, flown) end
  end
  B.land = land
  function B.snap(entry, box, delay, reach, host)
    land(entry)
    local handle
    handle = morf.animation.play { { parallel = flight(entry, box, host, delay or 0, reach or 7) },
      on_finished = function() if entry.flight == handle then entry.flight = nil end end }
    entry.flight = handle
    return handle
  end

  --- The content pass over `host`: `play(delay)` and `stop()`.
  function B.content(host)
    local C2, touched, stops, waiting, runs = {}, nil, nil, nil, {}
    local function restore()
      -- Rest poses, passing over nodes destroyed since the pass began.
      for entry, kind in pairs(touched or {}) do
        if kind == "card" then
          land(entry)
          pcall(card_rest, entry)
        else pcall(caption_rest, entry) end
      end
      for _, stop in ipairs(stops or {}) do stop() end
      touched, stops = nil, nil
    end
    function C2.stop()
      if waiting then waiting:cancel() waiting = nil end
      for _, run in ipairs(runs) do pcall(run.finish, run) end
      runs = {}
      restore()
    end
    local function play(tracks)
      if #tracks > 0 then runs[#runs + 1] = morf.animation.play { { parallel = tracks } } end
    end
    local LIMIT = 32
    --- The cards under the host: outlines draw in, brackets fly in.
    local function cards(delay)
      local tracks = {}
      local found, area = registry.within(registry.cards, host)
      for k = 1, math.min(#found, LIMIT) do
        local item = found[k]
        local entry, at = item.entry, delay + item.at * SCAN
        touched[entry] = "card"
        local o, e = entry.outline, entry.edges
        if o then
          o.trim_start, o.trim_end, o.opacity, e.opacity = .5, .5, 1, 0
          tracks[#tracks + 1] = { node = o, property = "trim_start", from = .5, to = 0, delay = at, duration = 260,
            easing = "out_cubic" }
          tracks[#tracks + 1] = { node = o, property = "trim_end", from = .5, to = 1, delay = at, duration = 260,
            easing = "out_cubic" }
          tracks[#tracks + 1] = timed { node = o, property = "opacity", delay = at, duration = 440, keyframes = {
            { at = 0, value = 1 }, { at = .62, value = 1 }, { at = 1, value = rest_outline() } } }
          tracks[#tracks + 1] = timed { node = e, property = "opacity", delay = at, duration = 300, keyframes = {
            { at = 0, value = 0 }, { at = .06, value = 1 }, { at = .16, value = .2 }, { at = .26, value = 1 },
            { at = .8, value = 0 }, { at = .86, value = 1 }, { at = 1, value = 1 } } }
        end
        land(entry)
        for _, track in ipairs(flight(entry, item, area, at, 24)) do tracks[#tracks + 1] = track end
      end
      play(tracks)
    end
    --- The section captions under the host: plates and rules light.
    local function captions(delay)
      local tracks = {}
      local found = registry.within(registry.captions, host)
      for k = 1, math.min(#found, LIMIT) do
        local item = found[k]
        local entry, at = item.entry, delay + item.at * SCAN
        touched[entry] = "caption"
        entry.plate.opacity, entry.rule.scale_x = 0, 0
        tracks[#tracks + 1] = timed { node = entry.plate, property = "opacity", delay = at, duration = 260, keyframes = {
          { at = 0, value = 0 }, { at = .12, value = 1 }, { at = .24, value = .2 }, { at = .36, value = 1 },
          { at = 1, value = 1 } } }
        tracks[#tracks + 1] = { node = entry.rule, property = "scale_x", from = 0, to = 1, delay = at, duration = 300,
          easing = "out_cubic" }
        if entry.hazard then
          entry.hazard.opacity = 0
          tracks[#tracks + 1] = timed { node = entry.hazard, property = "opacity", delay = at, duration = 340, keyframes = {
            { at = 0, value = 0 }, { at = .5, value = 0 }, { at = .58, value = 1 }, { at = .7, value = .2 },
            { at = .8, value = 1 }, { at = 1, value = 1 } } }
        end
      end
      play(tracks)
    end
    --- The readings and meters under the host: each replays.
    local function values(delay)
      local found = registry.within(registry.values, host)
      for k = 1, math.min(#found, LIMIT) do
        local item = found[k]
        local stop = item.entry(delay + item.at * SCAN)
        if stop then stops[#stops + 1] = stop end
      end
    end
    --- One pass, `delay` ms on, in three turns of its own (cards, captions,
    --- readings); `deferred`, over what the next frame lays out, or
    --- `"late"`, over what is laid out when the pass begins.
    function C2.play(delay, deferred)
      C2.stop()
      if require("themes.session").restoring then return end
      delay = delay or 0
      touched, stops = {}, {}
      local stages, k = { cards, captions, values }, 0
      local wait = deferred == "late" and math.max(16, delay) or (deferred and 16 or 0)
      local function next_stage()
        waiting = nil
        k = k + 1
        stages[k](math.max(0, delay - wait - (k - 1) * 16))
        if stages[k + 1] then waiting = morf.time.timer(16, next_stage, false) end
      end
      if wait > 0 then waiting = morf.time.timer(wait, next_stage, false) else next_stage() end
    end
    return C2
  end

  --- `host` (a node), `id` (names the pieces `<id>-boot-*`), `opts`:
  --- `trace`, `brackets`, `scan`, `register` (booleans, all on by
  --- default), `content` (off by default; `"late"` finds the content as the
  --- pass begins, for a host still growing), `words` (the register's text),
  --- `place` (the register's anchors), `z` (104), `length` (the brackets',
  --- 10), `weight` (1.5), `reach` (how far out they start, 10). Returns
  --- `play(delay)` and `stop()`.
  function B.new(host, id, opts)
    opts = opts or {}
    local z = opts.z or 104
    local L, reach, weight = opts.length or 10, opts.reach or 10, opts.weight or 1.5
    local nodes, running
    local content = opts.content and B.content(host) or nil
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
            return ("M%g %g H1 V1 H%g V%g"):format(w - 1, h - 1, w - 1, h - 1)
          end,
          fill_color = "transparent", stroke_width = 2, stroke_cap = "butt", stroke_join = "miter",
          stroke_color = function() return C.primary end,
          trim_start = .5, trim_end = .5, opacity = 0, visible = false }
        ui.reparent(nodes.trace, host)
      end
      if want("brackets") then
        nodes.brackets, nodes.signs = {}, {}
        local h = weight / 2
        for i, corner in ipairs {
          { { left = true, top = true }, ("M%g %g V%g H%g"):format(h, L, h, L), -1, -1 },
          { { right = true, top = true }, ("M0 %g H%g V%g"):format(h, L - h, L), 1, -1 },
          { { left = true, bottom = true }, ("M%g 0 V%g H%g"):format(h, L - h, L), -1, 1 },
          { { right = true, bottom = true }, ("M0 %g H%g V0"):format(L - h, L - h), 1, 1 },
        } do
          local mark = ui.Path { id = id .. "-boot-bracket-" .. i, z = z + 1, anchors = corner[1],
            width = L, height = L, view_box = { 0, 0, L, L }, d = corner[2],
            fill_color = "transparent", stroke_width = weight, stroke_cap = "square",
            stroke_color = function() return C.primary end, opacity = 0, visible = false }
          nodes.brackets[i] = mark
          nodes.signs[i] = { corner[3], corner[4] }
          ui.reparent(mark, host)
        end
      end
      if want("scan") then
        local trail = ui.Rect { anchors = { left = true, right = true }, y = 0, height = TRAIL,
          gradient = function() return { angle = 180, stops = { C.primary:alpha(0), C.primary:alpha(.3) } } end }
        local line = ui.Rect { anchors = { left = true, right = true }, y = TRAIL, height = 2,
          color = function() return C.primary end }
        local glow = ui.Rect { anchors = { left = true, right = true }, y = TRAIL + 2, height = 6,
          gradient = function() return { angle = 180, stops = { C.primary:alpha(.4), C.primary:alpha(0) } } end }
        nodes.mover = ui.Item { anchors = { left = true, right = true }, height = TRAIL + 8, trail, line, glow }
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
      if content then content.stop() end
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
        -- Tried again once, a frame on, when a host made this turn has its size.
        if not retried then
          waiting = morf.time.timer(16, function() waiting = nil P.play(math.max(0, delay - 16), true) end, false)
        end
        return
      end
      local tracks = {}
      local function add(t) t.delay = (t.delay or 0) + delay tracks[#tracks + 1] = timed(t) end
      if nodes.trace then
        nodes.trace.trim_start, nodes.trace.trim_end = .5, .5
        add { node = nodes.trace, property = "trim_start", from = .5, to = 0, duration = 320, easing = "out_quart" }
        add { node = nodes.trace, property = "trim_end", from = .5, to = 1, duration = 320, easing = "out_quart" }
        add { node = nodes.trace, property = "opacity", duration = 520, keyframes = {
          { at = 0, value = 0 }, { at = .06, value = 1 }, { at = .62, value = .85 }, { at = 1, value = 0 } } }
      end
      for i, mark in ipairs(nodes.brackets or {}) do
        -- Held out, a hard step in, then an expo settle onto the corner.
        local sign_x, sign_y = nodes.signs[i][1], nodes.signs[i][2]
        for property, sign in pairs { translate_x = sign_x, translate_y = sign_y } do
          add { node = mark, property = property, duration = 300, keyframes = {
            { at = 0, value = sign * reach }, { at = .22, value = sign * reach },
            { at = .23, value = sign * reach * .4 }, { at = .78, value = -sign * 2, easing = "out_expo" },
            { at = 1, value = 0, easing = "out_cubic" } } }
        end
        add { node = mark, property = "opacity", duration = 480, keyframes = {
          { at = 0, value = 0 }, { at = .08, value = 1 }, { at = .2, value = .35 }, { at = .3, value = 1 },
          { at = .72, value = .9 }, { at = 1, value = 0 } } }
      end
      if nodes.scan then
        add { node = nodes.mover, property = "translate_y", from = -TRAIL, to = h - TRAIL, duration = SCAN,
          easing = "linear" }
        add { node = nodes.scan, property = "opacity", duration = SCAN + 120, keyframes = {
          { at = 0, value = 0 }, { at = .04, value = 1 }, { at = .74, value = 1 }, { at = 1, value = 0 } } }
      end
      if nodes.register then
        local W = nodes.W
        nodes.typed.width, nodes.cursor.translate_x = .001, 0
        add { node = nodes.typed, property = "width", from = .001, to = W, delay = 120, duration = 200, easing = "linear" }
        add { node = nodes.cursor, property = "translate_x", from = 0, to = W + 1, delay = 120, duration = 200,
          easing = "linear" }
        add { node = nodes.register, property = "opacity", delay = 120, duration = 420, keyframes = {
          { at = 0, value = 0 }, { at = .04, value = 1 }, { at = .7, value = 1 }, { at = 1, value = 0 } } }
        add { node = nodes.cursor, property = "opacity", delay = 120, duration = 420, keyframes = {
          { at = 0, value = 1 }, { at = .55, value = 1 }, { at = .56, value = 0 }, { at = .66, value = 0 },
          { at = .67, value = 1 }, { at = 1, value = 1 } } }
      end
      for _, node in ipairs(pieces()) do node.visible, node.opacity = true, 0 end
      if content then content.play(delay, opts.content == "late" and "late" or true) end
      running = morf.animation.play { { parallel = tracks }, on_finished = function(reason)
        if reason == "completed" then running = nil hide() end
      end }
    end
    function P.active() return running ~= nil end
    return P
  end
  return B
end
