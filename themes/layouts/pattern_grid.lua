-- The 3x3 grid a pattern is drawn on: dots in rings and a line through the
-- joined ones to the finger. Drags go to `spec.trace` (models/pattern_trace),
-- a release hands its digits to `spec.on_done`.
local base_ui = require("morf.ui")
local trace_model = require("models.pattern_trace")

local M = {}

--- `look`: `ring`, `dot`, `lit`, `line`, `error` (colour fns) and `round(r)`.
function M.build(spec)
  local ui, look, trace, size = spec.ui or base_ui, spec.look, spec.trace, spec.size
  local _, _, pitch = trace_model.centre(1, size)
  local reach, ring, dot = pitch * .36, math.floor(pitch * .3), math.max(4, math.floor(pitch * .075))
  local width = math.max(3, math.floor(pitch * .055))
  local function bad() return spec.bad and spec.bad() and trace.count() > 0 end
  local function ink() return bad() and look.error() or look.line() end
  local nodes = { id = spec.id, width = size, height = size,
    translate_x = function() return spec.shake and spec.shake() == 1 and math.floor(pitch * .12) or 0 end,
    behavior = { translate_x = base_ui.spring { stiffness = 900, damping = 9 } } }
  nodes[1] = base_ui.Path { id = spec.id .. "-line", x = 0, y = 0, width = size, height = size,
    view_box = { 0, 0, size, size }, stroke_width = width, stroke_join = "round", stroke_cap = "round",
    stroke_color = ink, fill_color = function() return ink():alpha(0) end,
    d = function()
      local dots, parts = trace.dots(), {}
      if #dots == 0 then return "M0 0" end
      for i, n in ipairs(dots) do
        local x, y = trace_model.centre(n, size)
        parts[#parts + 1] = ("%s%.1f %.1f"):format(i == 1 and "M" or "L", x, y)
      end
      local finger = trace.finger:get()
      if finger then parts[#parts + 1] = ("L%.1f %.1f"):format(finger[1] * size, finger[2] * size) end
      return table.concat(parts, " ")
    end }
  for n = 1, 9 do
    local x, y = trace_model.centre(n, size)
    local function on() return trace.lit(n) end
    nodes[#nodes + 1] = ui.Rect { id = spec.id .. "-ring-" .. n, x = x - ring, y = y - ring,
      width = 2 * ring, height = 2 * ring, radius = look.round(ring), border_width = 2,
      color = function() return on() and (bad() and look.error() or look.lit()):alpha(.16) or look.ring():alpha(0) end,
      border_color = function() return on() and (bad() and look.error() or look.lit()) or look.ring() end,
      behavior = { color = { duration = 140 }, border_color = { duration = 140 } } }
    nodes[#nodes + 1] = ui.Rect { id = spec.id .. "-dot-" .. n, x = x - dot, y = y - dot,
      width = 2 * dot, height = 2 * dot, radius = look.round(dot),
      scale = function() return on() and 1.6 or 1 end,
      behavior = { scale = { duration = 160, easing = "out_back" }, color = { duration = 140 } },
      color = function() return on() and (bad() and look.error() or look.lit()) or look.dot() end }
  end
  local from, held
  local function follow(x, y)
    for _, n in ipairs(trace_model.passed(from or { x, y }, { x, y }, size, reach)) do trace.join(n) end
    from = { x, y }
    if trace.count() > 0 then trace.finger:set({ x / size, y / size }) end
  end
  nodes[#nodes + 1] = base_ui.MouseArea { id = spec.id .. "-area", x = 0, y = 0, width = size, height = size,
    cursor = "pointer",
    on_pressed = function(_, _, x, y)
      if spec.enabled and not spec.enabled() then held = false return end
      held, from = true, nil
      trace.clear()
      if spec.on_start then spec.on_start() end
      follow(x or 0, y or 0)
    end,
    on_dragged = function(_, _, _, _, x, y) if held then follow(x or 0, y or 0) end end,
    on_released = function()
      if not held then return end
      held, from = false, nil
      trace.finger:set(false)
      if trace.count() > 0 then spec.on_done(trace.digits()) end
    end }
  return ui.Item(nodes)
end

return M
