-- eva-displays' state and actions: a draft of the outputs, the live arrangement
-- it replaces, the countdown after applying, and the saved profiles. No nodes.
local morf = require("morf")
local displays = require("lib.shell.displays")

local M = {
  outputs = morf.signal("displays.outputs", {}),
  selected = morf.signal("displays.selected", ""),
  message = morf.signal("displays.message", ""),
  countdown = morf.signal("displays.countdown", 0),
  profiles = morf.signal("displays.profiles", {}),
  dirty = morf.signal("displays.dirty", false),
  ready = morf.signal("displays.ready", false),
}

M.SECONDS = 15
M.REACH = 48

local live, before, ticker

local function copy(list)
  local out = {}
  for i, o in ipairs(list) do
    local c = {}
    for key, value in pairs(o) do c[key] = value end
    out[i] = c
  end
  return out
end

local FIELDS = { "enabled", "x", "y", "width", "height", "refresh", "scale", "transform", "vrr", "mirror" }

local function differs(a, b)
  if #a ~= #b then return true end
  for i, o in ipairs(a) do
    for _, field in ipairs(FIELDS) do
      if o[field] ~= b[i][field] then return true end
    end
  end
  return false
end

local function changed(list)
  M.outputs:set(list)
  M.dirty:set(live ~= nil and differs(list, live))
end

--- Reads the compositor's outputs into the draft: `done()` afterwards.
function M.refresh(done)
  displays.read(function(outputs, why)
    if not outputs then
      M.message:set(why)
      M.ready:set(true)
      if done then done() end
      return
    end
    live = copy(outputs)
    changed(outputs)
    local chosen = M.selected:get()
    local found = false
    for _, o in ipairs(outputs) do found = found or o.name == chosen end
    if not found then
      local first = outputs[1]
      for _, o in ipairs(outputs) do if o.focused then first = o end end
      M.selected:set(first and first.name or "")
    end
    M.ready:set(true)
    if done then done() end
  end)
end

function M.load_profiles() M.profiles:set(displays.load_profiles()) end

--- The output named `name` (the selected one without), from the draft.
function M.output(name)
  name = name or M.selected:get()
  for _, o in ipairs(M.outputs:get()) do
    if o.name == name then return o end
  end
end

local function edit(name, fn)
  local list = copy(M.outputs:get())
  for _, o in ipairs(list) do
    if o.name == name then fn(o, list) end
  end
  changed(list)
end

local function others(name)
  local rects = {}
  for _, o in ipairs(M.outputs:get()) do
    if o.name ~= name and o.enabled and o.mirror == "" then
      local w, h = displays.logical(o)
      rects[#rects + 1] = { x = o.x, y = o.y, w = w, h = h }
    end
  end
  return rects
end

--- Moves an output to layout position `x`, `y`, snapped to the others' edges.
function M.place(name, x, y)
  local o = M.output(name)
  if not o then return end
  local w, h = displays.logical(o)
  local nx, ny = displays.snap({ x = math.floor(x), y = math.floor(y), w = w, h = h }, others(name), M.REACH)
  edit(name, function(target) target.x, target.y = nx, ny end)
end

--- A drag ended: the layout starts at 0,0 again.
function M.settle()
  local list = copy(M.outputs:get())
  changed(displays.normalize(list))
end

function M.set(name, field, value)
  edit(name, function(o) o[field] = value end)
end

--- The refreshes offered for the selected output at its resolution, fastest first.
function M.refreshes(o)
  local list = {}
  for _, mode in ipairs(o and o.modes or {}) do
    if mode.width == o.width and mode.height == o.height then list[#list + 1] = mode.refresh end
  end
  if #list == 0 and o then list[1] = o.refresh end
  return list
end

--- The resolutions offered for an output, largest first.
function M.resolutions(o)
  local list, seen = {}, {}
  for _, mode in ipairs(o and o.modes or {}) do
    local key = mode.width .. "x" .. mode.height
    if not seen[key] then seen[key] = true list[#list + 1] = mode end
  end
  if #list == 0 and o then list[1] = { width = o.width, height = o.height } end
  return list
end

--- A resolution chosen: the output takes its fastest refresh.
function M.set_resolution(name, width, height)
  edit(name, function(o)
    o.width, o.height = width, height
    local fastest = M.refreshes(o)[1]
    if fastest then o.refresh = fastest end
  end)
end

--- What stops the draft being applied, or nil.
function M.problem()
  local list = M.outputs:get()
  local lit = 0
  for _, o in ipairs(list) do if o.enabled then lit = lit + 1 end end
  if lit == 0 then return "Keep at least one monitor on." end
  local a, b = displays.overlap(list)
  if a then return a.name .. " overlaps " .. b.name .. "." end
  if displays.detached(list) then return "Every monitor must touch another." end
end

local function stop_ticker()
  if ticker then ticker:cancel() ticker = nil end
end

--- Puts the draft in place and starts the countdown.
function M.apply()
  local problem = M.problem()
  if problem then M.message:set(problem) return false end
  local wanted = displays.normalize(copy(M.outputs:get()))
  before = copy(live)
  displays.apply(wanted, function(ok, why)
    if not ok then
      M.message:set(tostring(why or "The compositor refused."))
      return
    end
    M.outputs:set(wanted)
    M.message:set("")
    M.countdown:set(M.SECONDS)
    stop_ticker()
    ticker = morf.time.timer(1000, function()
      local left = M.countdown:get() - 1
      M.countdown:set(left)
      if left <= 0 then M.revert() end
    end, true)
  end)
  return true
end

--- Keeps what was applied, and writes it where the compositor reloads it from.
function M.keep()
  stop_ticker()
  M.countdown:set(0)
  live = copy(M.outputs:get())
  M.dirty:set(false)
  local ok, why = displays.persist(live)
  M.message:set(ok and "Saved." or tostring(why))
end

--- Goes back to what was there before applying.
function M.revert()
  stop_ticker()
  M.countdown:set(0)
  if not before then return end
  local back = before
  displays.apply(back, function(ok, why)
    M.message:set(ok and "Reverted." or tostring(why))
    if ok then
      live = copy(back)
      changed(copy(back))
    end
  end)
end

-- ---------------------------------------------------------------- profiles --

--- Saves the draft as profile `name`, replacing one of that name.
function M.save_profile(name)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  if name == "" then M.message:set("Name the profile first.") return false end
  local list, kept = {}, displays.profile(name, M.outputs:get(), true)
  for _, profile in ipairs(displays.load_profiles()) do
    if profile.name ~= name then list[#list + 1] = profile end
  end
  list[#list + 1] = kept
  local ok, why = displays.save_profiles(list)
  M.message:set(ok and ("Saved " .. name .. ".") or tostring(why))
  M.load_profiles()
  return ok
end

--- Puts profile `name` in the draft, for the Apply button.
function M.use_profile(name)
  for _, profile in ipairs(displays.load_profiles()) do
    if profile.name == name then
      changed(displays.resolve(profile, M.outputs:get()))
      return true
    end
  end
  return false
end

function M.delete_profile(name)
  local list = {}
  for _, profile in ipairs(displays.load_profiles()) do
    if profile.name ~= name then list[#list + 1] = profile end
  end
  displays.save_profiles(list)
  M.load_profiles()
end

function M.set_auto(name, on)
  local list = displays.load_profiles()
  for _, profile in ipairs(list) do
    if profile.name == name then profile.auto = on end
  end
  displays.save_profiles(list)
  M.load_profiles()
end

--- A name on every monitor: the shell draws it when it runs, else a short-lived
--- configuration of this tool does.
function M.identify()
  morf.process.run({ "sh", morf.paths.shell("identify") }, {}, function() end)
end

return M
