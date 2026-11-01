-- Colour filters over the whole screen: Hyprland's `decoration:screen_shader`,
-- one fragment shader written from the filters that are on, the quick filters'
-- and the Accessibility page's alike. They stack, in the order of `M.ORDER`, and
-- the file's name changes with them, so the compositor reads it afresh.
--
--   local filter = require("lib.services.screen_filter")
--   filter.source { grayscale = true, dim = 0.4 }    -- GLSL, or nil for none
local M = { ORDER = { "correction", "reading", "grayscale", "invert", "extradim" } }

local HEAD = [[#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);
]]

-- A colour as a cone cell sees it, and back, for the corrections.
local CORRECT = [[
vec3 correct(vec3 c) {
  float l = 17.8824 * c.r + 43.5161 * c.g + 4.11935 * c.b;
  float m = 3.45565 * c.r + 27.1554 * c.g + 3.86714 * c.b;
  float s = 0.0299566 * c.r + 0.184309 * c.g + 1.46709 * c.b;
  %s
  vec3 seen = vec3(0.0809444479 * l - 0.130504409 * m + 0.116721066 * s,
    -0.0102485335 * l + 0.0540193266 * m - 0.113614708 * s,
    -0.000365296938 * l - 0.00412161469 * m + 0.693511405 * s);
  vec3 lost = c - seen;
  return clamp(c + vec3(0.0, 0.7 * lost.r + lost.g, 0.7 * lost.r + lost.b), 0.0, 1.0);
}
]]
-- What each kind of colour blindness does to the cones.
local CONES = {
  protanopia = "l = 2.02344 * m - 2.52581 * s;",
  deuteranopia = "m = 0.494207 * l + 1.24827 * s;",
  tritanopia = "s = -0.395913 * l + 0.801109 * m;",
}
M.CORRECTIONS = { "protanopia", "deuteranopia", "tritanopia" }

--- `set` with the Accessibility page's `choice` on: "none", a filter's id, or a
--- correction by its kind, which wins over the quick filters' kind.
function M.with(set, choice)
  if CONES[choice] then
    set.correction, set.correction_kind = true, choice
  elseif choice == "grayscale" or choice == "invert" then
    set[choice] = true
  end
  return set
end

local STEPS = {
  correction = function() return "  c = correct(c);" end,
  reading = function() return "  c = mix(c, vec3(dot(c, LUMA)), 0.7) * vec3(1.0, 0.95, 0.82);" end,
  grayscale = function() return "  c = vec3(dot(c, LUMA));" end,
  invert = function() return "  c = 1.0 - c;" end,
  extradim = function(set) return ("  c *= %.2f;"):format(set.dim or 0.4) end,
}

--- The fragment shader for `set` (filters by id, true when on; `dim`, a
--- fraction; `correction_kind`), or nil with none on.
function M.source(set)
  local body = {}
  for _, id in ipairs(M.ORDER) do
    if set[id] then body[#body + 1] = STEPS[id](set) end
  end
  if #body == 0 then return nil end
  local parts = { HEAD }
  if set.correction then
    parts[#parts + 1] = CORRECT:format(CONES[set.correction_kind] or CONES.deuteranopia)
  end
  parts[#parts + 1] = "void main() {\n  vec4 color = texture(tex, v_texcoord);\n  vec3 c = color.rgb;\n"
  parts[#parts + 1] = table.concat(body, "\n")
  parts[#parts + 1] = "\n  fragColor = vec4(c, color.a);\n}\n"
  return table.concat(parts)
end

--- A name for `set`: the same filters, the same name.
function M.key(set)
  local words = {}
  for _, id in ipairs(M.ORDER) do
    if set[id] then words[#words + 1] = id end
  end
  if set.correction then words[#words + 1] = set.correction_kind or "deuteranopia" end
  if set.extradim then words[#words + 1] = ("%d"):format(math.floor((set.dim or 0.4) * 100 + 0.5)) end
  return table.concat(words, "-")
end

--- Filters on an output through `options.hyprland` (lib.compositor.hyprland's
--- `eval` and `keyword`), files written by `options.write(path, text)`, under
--- `options.dir`.
function M.new(options)
  local filter = {}
  local shown = ""

  local function tell(path)
    local hyprland = options.hyprland
    hyprland.eval(("hl.config({decoration={screen_shader=%q}})"):format(path), function(reply)
      if not (type(reply) == "string" and reply:match("^%s*ok%s*$")) then
        hyprland.keyword("decoration:screen_shader", path)
      end
    end)
  end

  --- Shows `set`, if it is not on show already.
  function filter.apply(set)
    local key = M.key(set)
    if key == shown then return end
    shown = key
    if key == "" then return tell("") end
    local path = options.dir .. "/screen-" .. key .. ".frag"
    options.write(path, M.source(set))
    tell(path)
  end

  --- Tells the compositor again, after its configuration was read anew.
  function filter.again(set)
    shown = ""
    filter.apply(set)
  end

  return filter
end

return M
