-- Monitors: what the compositor has, in one shape for Hyprland and sway, and
-- how to change it. No nodes and no theme: the tool and the shell share this.
--
-- An output: `name`, `make`, `model`, `serial`, `description`, `enabled`, `x`,
-- `y` (layout position), `width`, `height`, `refresh` (the mode), `scale`,
-- `transform` (0..7, wl_output's), `vrr`, `mirror` ("" or the mirrored name),
-- `modes` ({ width, height, refresh }, largest and fastest first), `focused`.
--
-- Profiles live in $XDG_STATE_HOME/eva/displays/profiles.json, matched on
-- make, model and serial, never on the port. What was last kept is written
-- beside them as a file the compositor loads.
local morf = require("morf")
local capture = require("lib.shell.capture")

local M = {}

M.TRANSFORMS = { [0] = "normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270" }
local TRANSFORM_INDEX = {}
for index, name in pairs(M.TRANSFORMS) do TRANSFORM_INDEX[name] = index end

-- The rotations the tool offers, in the order the choice lists them.
M.ROTATIONS = { { 0, "Normal" }, { 1, "90°" }, { 2, "180°" }, { 3, "270°" } }
M.SCALES = { 1, 1.25, 1.5, 1.75, 2, 2.5, 3 }

function M.kind() return capture.kind() end

--- What this compositor can do: `manage` (outputs at all), `mirror`.
function M.supports(kind)
  kind = kind or M.kind()
  return { manage = kind == "hyprland" or kind == "sway", mirror = kind == "hyprland" }
end

local function dry()
  local value = morf.env("EVA_DRY_RUN")
  return value ~= nil and value ~= "" and value ~= "0"
end

local function round(value, digits)
  local factor = 10 ^ (digits or 2)
  return math.floor(value * factor + 0.5) / factor
end

local function sort_modes(modes)
  table.sort(modes, function(a, b)
    if a.width * a.height ~= b.width * b.height then return a.width * a.height > b.width * b.height end
    return a.refresh > b.refresh
  end)
  return modes
end

-- ------------------------------------------------------------- the outputs --

--- `swaymsg -t get_outputs` as outputs.
function M.from_sway(list)
  local out = {}
  for _, o in ipairs(list or {}) do
    local mode, rect = o.current_mode or {}, o.rect or {}
    local modes, seen = {}, {}
    for _, m in ipairs(o.modes or {}) do
      local refresh = round((m.refresh or 0) / 1000)
      local key = ("%dx%d@%s"):format(m.width, m.height, refresh)
      if not seen[key] then
        seen[key] = true
        modes[#modes + 1] = { width = m.width, height = m.height, refresh = refresh }
      end
    end
    local scale = tonumber(o.scale) or 1
    local function known(text) return (text == nil or text == "Unknown") and "" or text end
    local make, model, serial = known(o.make), known(o.model), known(o.serial)
    out[#out + 1] = {
      name = o.name, make = make, model = model, serial = serial,
      description = table.concat({ make, model, serial }, " "),
      enabled = o.active ~= false, x = rect.x or 0, y = rect.y or 0,
      width = mode.width or rect.width or 0, height = mode.height or rect.height or 0,
      refresh = round((mode.refresh or 0) / 1000),
      scale = scale > 0 and scale or 1,
      transform = TRANSFORM_INDEX[o.transform or "normal"] or 0,
      vrr = o.adaptive_sync_status == "enabled", mirror = "",
      modes = sort_modes(modes), focused = o.focused == true,
    }
  end
  return out
end

local function hyprland_modes(list)
  local modes, seen = {}, {}
  for _, text in ipairs(list or {}) do
    local w, h, r = tostring(text):match("^(%d+)x(%d+)@([%d.]+)")
    if w then
      local mode = { width = tonumber(w), height = tonumber(h), refresh = round(tonumber(r)) }
      local key = ("%dx%d@%s"):format(mode.width, mode.height, mode.refresh)
      if not seen[key] then seen[key] = true modes[#modes + 1] = mode end
    end
  end
  return sort_modes(modes)
end

--- `hyprctl monitors all -j` as outputs. Hyprland's stand-in FALLBACK output
--- is no screen.
function M.from_hyprland(rows)
  local names = {}
  for _, row in ipairs(rows or {}) do names[row.id or -1] = row.name end
  local out = {}
  for _, row in ipairs(rows or {}) do
    if row.name ~= "FALLBACK" then
      local mirror = row.mirrorOf
      if mirror == nil or mirror == "none" or tonumber(mirror) == -1 then mirror = ""
      else mirror = names[tonumber(mirror)] or tostring(mirror) end
      out[#out + 1] = {
        name = row.name, make = row.make or "", model = row.model or "", serial = row.serial or "",
        description = row.description or "",
        enabled = row.disabled ~= true, x = row.x or 0, y = row.y or 0,
        width = row.width or 0, height = row.height or 0, refresh = round(row.refreshRate or 0),
        scale = round(row.scale or 1, 3), transform = row.transform or 0,
        vrr = row.vrr == true, mirror = mirror,
        modes = hyprland_modes(row.availableModes), focused = row.focused == true,
      }
    end
  end
  return out
end

--- `cb(outputs, why)`: this session's outputs, or nil and why.
function M.read(cb)
  local kind = M.kind()
  if kind == "hyprland" then
    require("lib.compositor.hyprland").json("monitors all", function(rows, why)
      if rows then cb(M.from_hyprland(rows)) else cb(nil, why or "Hyprland did not answer") end
    end)
  elseif kind == "sway" then
    morf.process.run({ "swaymsg", "-t", "get_outputs", "-r" }, {}, function(result)
      if not result or not result.ok then cb(nil, result and result.stderr or "sway did not answer") return end
      local ok, list = pcall(morf.json.decode, result.stdout or "")
      if ok then cb(M.from_sway(list)) else cb(nil, "sway answered nonsense") end
    end)
  else
    cb(nil, "Monitors can be arranged on Hyprland and sway")
  end
end

-- -------------------------------------------------------------- the layout --

--- The output's size on the layout: its mode, turned and scaled.
function M.logical(o)
  local w, h = o.width or 0, o.height or 0
  if (o.transform or 0) % 2 == 1 then w, h = h, w end
  local scale = o.scale or 1
  return math.floor(w / scale + 0.5), math.floor(h / scale + 0.5)
end

local function rect(o)
  local w, h = M.logical(o)
  return { x = o.x, y = o.y, w = w, h = h }
end

-- A position for `value` nearest an edge in `edges`, within `reach`.
local function nearest(value, edges, reach)
  local best, distance = nil, reach + 1
  for _, edge in ipairs(edges) do
    local gap = math.abs(value - edge)
    if gap < distance then best, distance = edge, gap end
  end
  return best
end

--- `moving` ({ x, y, w, h }) snapped to the edges of `others`' rects within
--- `reach` units. Each axis snaps on its own; answers x, y.
function M.snap(moving, others, reach)
  local xs, ys = {}, {}
  for _, other in ipairs(others) do
    xs[#xs + 1] = other.x
    xs[#xs + 1] = other.x + other.w
    ys[#ys + 1] = other.y
    ys[#ys + 1] = other.y + other.h
  end
  local x, y = moving.x, moving.y
  local shifted = {}
  for _, edge in ipairs(xs) do shifted[#shifted + 1] = edge - moving.w end
  local left, right = nearest(x, xs, reach), nearest(x, shifted, reach)
  if left and right then
    if math.abs(left - x) <= math.abs(right - x) then x = left else x = right end
  else x = left or right or x end
  shifted = {}
  for _, edge in ipairs(ys) do shifted[#shifted + 1] = edge - moving.h end
  local top, bottom = nearest(y, ys, reach), nearest(y, shifted, reach)
  if top and bottom then
    if math.abs(top - y) <= math.abs(bottom - y) then y = top else y = bottom end
  else y = top or bottom or y end
  return x, y
end

--- The lit outputs moved together so the layout starts at 0,0.
function M.normalize(outputs)
  local left, top
  for _, o in ipairs(outputs) do
    if o.enabled and o.mirror == "" then
      left = left and math.min(left, o.x) or o.x
      top = top and math.min(top, o.y) or o.y
    end
  end
  for _, o in ipairs(outputs) do
    if o.enabled then o.x, o.y = o.x - (left or 0), o.y - (top or 0) end
  end
  return outputs
end

--- The first two lit outputs sharing layout space, or nil.
function M.overlap(outputs)
  local lit = {}
  for _, o in ipairs(outputs) do
    if o.enabled and o.mirror == "" then lit[#lit + 1] = o end
  end
  for i = 1, #lit do
    local a = rect(lit[i])
    for j = i + 1, #lit do
      local b = rect(lit[j])
      if a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h then
        return lit[i], lit[j]
      end
    end
  end
end

--- A monitor that cannot be reached from the others across a shared edge, or
--- nil: the pointer could never get to it.
function M.detached(outputs)
  local lit = {}
  for _, o in ipairs(outputs) do
    if o.enabled and o.mirror == "" then lit[#lit + 1] = rect(o) end
  end
  if #lit < 2 then return nil end
  local reached, stack = { [1] = true }, { 1 }
  local function touching(a, b)
    local across = a.y < b.y + b.h and b.y < a.y + a.h and (a.x + a.w == b.x or b.x + b.w == a.x)
    local down = a.x < b.x + b.w and b.x < a.x + a.w and (a.y + a.h == b.y or b.y + b.h == a.y)
    return across or down
  end
  while #stack > 0 do
    local at = table.remove(stack)
    for i = 1, #lit do
      if not reached[i] and touching(lit[at], lit[i]) then reached[i] = true stack[#stack + 1] = i end
    end
  end
  for i = 1, #lit do if not reached[i] then return lit[i] end end
end

-- ---------------------------------------------------------------- applying --

-- The mode, without a refresh where the output reports none.
local function mode_text(o, unit)
  local size = ("%dx%d"):format(o.width, o.height)
  if (o.refresh or 0) <= 0 then return size end
  return size .. "@" .. tostring(o.refresh) .. (unit or "")
end

-- An output as a Hyprland monitor rule, spelled by its name or its identity.
local function hyprland_rule(o, output)
  if not o.enabled then return { output = output, disabled = true } end
  local rule = {
    output = output, mode = mode_text(o), position = ("%dx%d"):format(o.x, o.y),
    scale = o.scale, transform = o.transform, vrr = o.vrr and 1 or 0,
  }
  if o.mirror ~= "" then rule.mirror = o.mirror end
  return rule
end

--- Hyprland's rules for `outputs`.
function M.hyprland_rules(outputs)
  local rules = {}
  for _, o in ipairs(outputs) do rules[#rules + 1] = hyprland_rule(o, o.name) end
  return rules
end

local function sway_line(o, output)
  if not o.enabled then return ("output %q disable"):format(output) end
  return ("output %q enable mode %s pos %d %d scale %s transform %s adaptive_sync %s"):format(
    output, mode_text(o, "Hz"), o.x, o.y, tostring(o.scale),
    M.TRANSFORMS[o.transform] or "normal", o.vrr and "on" or "off")
end

--- The sway commands for `outputs`, one to a line.
function M.sway_lines(outputs)
  local lines = {}
  for _, o in ipairs(outputs) do lines[#lines + 1] = sway_line(o, o.name) end
  return lines
end

--- `cb(ok, why)` once `outputs` are the compositor's.
function M.apply(outputs, cb)
  local kind = M.kind()
  if dry() then
    morf.log("info", "eva: displays (dry run): " .. table.concat(M.sway_lines(outputs), "; "))
    cb(true)
  elseif kind == "hyprland" then
    local config = require("lib.compositor.hyprland_config")
    config.apply(function(how) return config.monitors_plan(M.hyprland_rules(outputs), how) end, function(ok, replies)
      cb(ok == true, not ok and "Hyprland refused: " .. tostring(replies) or nil)
    end)
  elseif kind == "sway" then
    morf.process.run({ "swaymsg", table.concat(M.sway_lines(outputs), "; ") }, {}, function(result)
      cb(result ~= nil and result.ok == true, result and (result.stdout ~= "" and result.stdout or result.stderr) or "sway did not answer")
    end)
  else
    cb(false, "Monitors can be arranged on Hyprland and sway")
  end
end

-- ------------------------------------------------------------- persistence --

local function folder()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/displays"
end

M.paths = {
  profiles = function() return folder() .. "/profiles.json" end,
  hyprland = function() return folder() .. "/monitors.lua" end,
  sway = function() return folder() .. "/outputs.sway" end,
}

-- How the persisted file names an output: its identity where it has one,
-- without any port in brackets.
local function hyprland_output(o)
  local words = (o.description or ""):gsub("%s*%b()%s*$", "")
  if words ~= "" then return "desc:" .. words end
  return o.name
end

--- The text of the file Hyprland's session loads.
function M.hyprland_text(outputs)
  local config = require("lib.compositor.hyprland_config")
  local lines = {}
  for _, o in ipairs(outputs) do
    local rule, why = config.monitor_rule(hyprland_rule(o, hyprland_output(o)), "lua")
    if not rule then return nil, why end
    lines[#lines + 1] = rule
  end
  return table.concat(lines, "\n") .. "\n"
end

--- The text of the file sway includes.
function M.sway_text(outputs)
  local lines = {}
  for _, o in ipairs(outputs) do
    local known = o.make ~= "" and o.serial ~= ""
    lines[#lines + 1] = sway_line(o, known and table.concat({ o.make, o.model, o.serial }, " ") or o.name)
  end
  return table.concat(lines, "\n") .. "\n"
end

-- The scale eva's own session re-applies for one output keeps to what was kept.
local function keep_scale(outputs)
  local scale = require("themes.ui_scale")
  if not scale.compositor then return end
  local ok, saved = pcall(function() return morf.json.decode(morf.fs.read(scale.path)) end)
  if not ok or type(saved) ~= "table" then return end
  for _, o in ipairs(outputs) do
    if o.enabled and (saved.output == o.name or (saved.output or "") == "") and saved.scale ~= o.scale then
      saved.scale, saved.zoom, saved.output = o.scale, math.log(o.scale) / math.log(2), o.name
      morf.fs.write(scale.path, morf.json.encode(saved), { mode = 420, atomic = true, parents = true })
      return
    end
  end
end

--- Writes what the compositor loads at its next start or reload. Answers ok, why.
function M.persist(outputs)
  local kind, text, path = M.kind(), nil, nil
  if kind == "hyprland" then
    local why
    text, why = M.hyprland_text(outputs)
    if not text then return false, why end
    path = M.paths.hyprland()
  elseif kind == "sway" then
    text, path = M.sway_text(outputs), M.paths.sway()
  else
    return false, "Monitors can be arranged on Hyprland and sway"
  end
  local ok, why = morf.fs.write(path, text, { atomic = true, parents = true })
  if not ok then return false, why end
  keep_scale(outputs)
  return true
end

-- ---------------------------------------------------------------- profiles --

local function clean(text) return tostring(text or ""):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "") end

--- What an output is, whichever port it is on.
function M.identity(o)
  local parts = { clean(o.make), clean(o.model), clean(o.serial) }
  if parts[1] == "" and parts[2] == "" and parts[3] == "" then return "port:" .. tostring(o.name) end
  return table.concat(parts, "|")
end

-- The identities of `outputs`, sorted; two alike are told apart by a count.
local function identities(outputs)
  local seen, list = {}, {}
  for _, o in ipairs(outputs) do
    local id = M.identity(o)
    seen[id] = (seen[id] or 0) + 1
    list[#list + 1] = id .. "#" .. seen[id]
  end
  table.sort(list)
  return list
end

--- One string for a set of outputs: the same set, the same key.
function M.key(outputs) return table.concat(identities(outputs), ",") end

function M.load_profiles()
  local ok, data = pcall(function() return morf.json.decode(morf.fs.read(M.paths.profiles())) end)
  if ok and type(data) == "table" and type(data.profiles) == "table" then return data.profiles end
  return {}
end

function M.save_profiles(list)
  return morf.fs.write(M.paths.profiles(), morf.json.encode({ profiles = list }), { atomic = true, parents = true })
end

--- A profile of `outputs` as they stand, named `name`.
function M.profile(name, outputs, auto)
  local saved = {}
  for _, o in ipairs(outputs) do
    saved[#saved + 1] = {
      identity = M.identity(o), make = o.make, model = o.model, serial = o.serial,
      enabled = o.enabled, x = o.x, y = o.y, width = o.width, height = o.height, refresh = o.refresh,
      scale = o.scale, transform = o.transform, vrr = o.vrr,
      mirror = "",
    }
    for _, other in ipairs(outputs) do
      if other.name == o.mirror then saved[#saved].mirror = M.identity(other) end
    end
  end
  return { name = name, auto = auto ~= false, key = M.key(outputs), outputs = saved }
end

--- The saved profile for exactly the outputs connected, or nil. A profile that
--- applies by itself is preferred, then the one saved last.
function M.match(profiles, outputs)
  local key, found = M.key(outputs), nil
  for _, profile in ipairs(profiles) do
    if profile.key == key and (not found or profile.auto or not found.auto) then found = profile end
  end
  return found
end

--- `outputs` with `profile`'s settings on them, by identity, not by port.
function M.resolve(profile, outputs)
  local by_identity = {}
  for _, saved in ipairs(profile.outputs) do
    local list = by_identity[saved.identity] or {}
    list[#list + 1] = saved
    by_identity[saved.identity] = list
  end
  local names, result = {}, {}
  for _, o in ipairs(outputs) do names[M.identity(o)] = o.name end
  for _, o in ipairs(outputs) do
    local copy = {}
    for key, value in pairs(o) do copy[key] = value end
    local saved = table.remove(by_identity[M.identity(o)] or {}, 1)
    if saved then
      for _, field in ipairs { "enabled", "x", "y", "width", "height", "refresh", "scale", "transform", "vrr" } do
        copy[field] = saved[field]
      end
      copy.mirror = saved.mirror ~= "" and (names[saved.mirror] or "") or ""
    end
    result[#result + 1] = copy
  end
  return result
end

-- The fields a profile sets, compared.
local function same(a, b)
  if #a ~= #b then return false end
  for i, o in ipairs(a) do
    local other = b[i]
    for _, field in ipairs { "enabled", "x", "y", "width", "height", "refresh", "scale", "transform", "vrr", "mirror" } do
      if o[field] ~= other[field] then return false end
    end
  end
  return true
end

--- The matching self-applying profile put in place: `cb(name or nil, why)`.
--- A set of outputs already arranged so is left alone.
function M.auto_apply(cb)
  cb = cb or function() end
  M.read(function(outputs, why)
    if not outputs then cb(nil, why) return end
    local profile = M.match(M.load_profiles(), outputs)
    if not profile or not profile.auto then cb(nil) return end
    local wanted = M.resolve(profile, outputs)
    if same(wanted, outputs) then cb(profile.name) return end
    M.apply(wanted, function(ok, reason)
      if ok then M.persist(wanted) end
      cb(ok and profile.name or nil, reason)
    end)
  end)
end

return M
