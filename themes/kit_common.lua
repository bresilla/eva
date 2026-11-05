-- Non-visual helpers every theme's kit may share. Nothing here draws or
-- decides how anything looks (see THEMING.md, theme rule 2). Append only.
local M = {}

--- A spec value that may be a binding.
function M.get(v) if type(v) == "function" then return v() end return v end

function M.clamp01(v)
  v = tonumber(v) or 0
  return v < 0 and 0 or v > 1 and 1 or v
end

--- Keep a range's moving pieces together. Values received from a service
--- ease; a held control follows the hand immediately. Each target supplies
--- a node and numeric property bindings; the theme supplies its own timing.
function M.follow_range(state,owner,targets,motion)
  local running,initial=nil,true
  morf.effect("range.follow."..tostring(owner),function()
    local direct=state.down or state.dragging
    local timing=M.get(motion)
    local steps={}
    for _,target in ipairs(targets) do
      for property,binding in pairs(target.values) do
        steps[#steps+1]={node=target.node,property=property,to=binding(),
          duration=timing.duration,easing=timing.easing}
      end
    end
    if running then running:stop() running=nil end
    if initial or direct then
      for _,step in ipairs(steps) do step.node[step.property]=step.to end
    else
      running=morf.animation.play {{parallel=steps}}
    end
    initial=false
  end,{owner=owner})
end

--- A field layer's outline that walks from one drawing onto the next. `want`
--- is a binding naming a drawing, "" for none; `path` turns a name into its
--- file. Returns the layer's `source`, `source_morph_to` and `morph_progress`
--- bindings: the end not on show takes the new drawing and the progress
--- flips towards it, so a change in flight retargets.
local outline_morphs = 0
function M.outline_morph(want, path, owner)
  outline_morphs = outline_morphs + 1
  local key = "kit.outline." .. outline_morphs
  local first = M.get(want)
  local from = morf.signal(key .. ".from", first)
  local to = morf.signal(key .. ".to", first)
  local side = morf.signal(key .. ".side", 0)
  morf.effect(key, function()
    local name = M.get(want)
    if name == "" or name == (side:get() == 0 and from:get() or to:get()) then return end
    if side:get() == 0 then to:set(name) side:set(1) else from:set(name) side:set(0) end
  end, { owner = owner })
  local function file(signal)
    local name = signal:get()
    return name ~= "" and path(name) or ""
  end
  return function() return file(from) end, function() return file(to) end, function() return side:get() end
end

--- Bytes in binary units, one decimal under ten: "1.1", "MiB". `unit`
--- forces one.
function M.bytes(n, unit)
  n = tonumber(n) or 0
  local units = { "B", "KiB", "MiB", "GiB", "TiB", "PiB" }
  local i = 1
  if unit then
    for k, u in ipairs(units) do if u == unit then i = k end end
    n = n / 1024 ^ (i - 1)
  else
    while n >= 1024 and i < #units do n = n / 1024 i = i + 1 end
  end
  local text = (n < 10 and i > 1) and ("%.1f"):format(n) or ("%d"):format(math.floor(n + 0.5))
  return text, units[i]
end

local codes = {}
--- A stable pseudo-random string for `key`, `#` digits and `X` hex digits
--- filled from a hash of the key, for themes that print decorative codes.
function M.code(key, shape)
  key = tostring(key or "") .. (shape or "")
  if codes[key] then return codes[key] end
  local h = 5381
  for i = 1, #key do h = (h * 33 + key:byte(i)) % 2147483647 end
  local function n(m) h = (h * 1103515245 + 12345) % 2147483648 return h % m end
  local out = (shape or "##.###/##.##"):gsub("#", function() return tostring(n(10)) end)
    :gsub("X", function() return string.format("%X", n(16)) end)
  codes[key] = out
  return out
end

--- NOW / AVG / PEAK of a list of numbers.
function M.summary(list)
  local n, sum, peak = 0, 0, 0
  for _, v in ipairs(list or {}) do
    v = tonumber(v) or 0
    n, sum = n + 1, sum + v
    if v > peak then peak = v end
  end
  return (list and list[#list]) or 0, n > 0 and sum / n or 0, peak
end

--- A spec value that should be a number, or `d`.
function M.num(v, d)
  v = M.get(v)
  return type(v) == "number" and v or d
end

--- A number with its thousands marked, one decimal where it has any. What is
--- no number stands as it is.
function M.grouped(v)
  if type(v) ~= "number" then return tostring(v == nil and "" or v) end
  if v == math.floor(v) and math.abs(v) < 1e15 then
    local sign, digits = ("%d"):format(v):match("^(-?)(%d+)$")
    digits = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. digits
  end
  return ("%.1f"):format(v)
end

--- Bytes in decimal units: "1.5 kB". What is no number stands as it is.
function M.decimal_bytes(n)
  if type(n) ~= "number" then return n and tostring(n) or "" end
  local units, i = { "B", "kB", "MB", "GB", "TB" }, 1
  while n >= 1000 and i < #units do n, i = n / 1000, i + 1 end
  return i == 1 and ("%d %s"):format(n, units[i]) or ("%.1f %s"):format(n, units[i])
end

--- A moment as a cell shows it: "28 Sep 08:24". What is no number stands as it is.
function M.stamp(v)
  if type(v) == "number" then return os.date("%d %b %H:%M", v) end
  return v and tostring(v) or ""
end

--- A number to two places, without the zeros that end it: "1.5".
function M.trim_number(v)
  local s = ("%.2f"):format(v)
  s = s:gsub("0+$", ""):gsub("%.$", "")
  return s
end

-- Where an entering node comes to rest, for each property a pose may name.
local REST = { opacity = 1, scale = 1, scale_x = 1, scale_y = 1, translate_x = 0, translate_y = 0 }

--- Plays each of `nodes` in from the `enter` pose `pose_of(k)` gives its
--- place `k` (its properties, `duration`, `easing`, `delay`), `lead` ms
--- after now. Returns the handles.
function M.replay(nodes, pose_of, lead)
  local handles = {}
  for k, node in ipairs(nodes) do
    local pose, steps = pose_of(k), {}
    for property, from in pairs(pose) do
      if REST[property] then
        steps[#steps + 1] = { node = node, property = property, from = from, to = REST[property],
          duration = pose.duration, easing = pose.easing, delay = (lead or 0) + (pose.delay or 0) }
      end
    end
    if #steps > 0 then handles[#handles + 1] = morf.animation.play { { parallel = steps } } end
  end
  return handles
end

return M
