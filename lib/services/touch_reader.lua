-- Every contact on a touchscreen, read beside the compositor: morf has no evdev
-- API, so `libinput debug-events --device` runs per touchscreen and its lines are
-- parsed here. Apps keep their touches: nothing is grabbed.
--
--   local reader = require("lib.services.touch_reader").new {
--     screen = function() return morf.screens[1] end,
--     sink = { down = function(id, x, y, ms) end, move = ..., up = function(id, ms) end,
--       cancel = function() end, frame = function(ms) end },
--   }
--   reader.start()   -- follows plug and unplug through `refresh`
--   reader.stop()    -- ends the process: a stopped reader reads nothing
--
-- `state()` is "off", "none" (no touchscreen), "missing" (no libinput), "denied"
-- (no right to the device), "starting" or "running". Positions come in the
-- logical pixels of `screen()`, through its rotation.
local morf = require("morf")

local M = { LIBINPUT = "libinput", RETRY = 2000, LONGEST = 60000 }

local KINDS = {
  TOUCH_DOWN = "down", TOUCH_MOTION = "move", TOUCH_UP = "up", TOUCH_CANCEL = "cancel",
  TOUCH_FRAME = "frame", DEVICE_ADDED = "added", DEVICE_REMOVED = "removed",
}

--- One line of `libinput debug-events`: `{ kind, node, ms, slot, seat, x, y }`,
--- `x` and `y` in percent of the device, or nil for a line that says nothing here.
--- `-event2   TOUCH_DOWN              +1.234s<TAB>0 (0) 50.00/90.00 (160.00/180.00mm)`
function M.parse(line)
  local node, name, rest = line:match("^[%-%s]?%s*(event%d+)%s+([%u_]+)%s*(.*)$")
  local kind = KINDS[name or ""]
  if not kind then return nil end
  local event = { kind = kind, node = node }
  local seconds = rest:match("^%s*%d*%s*([%+%-]%d+%.%d+)s")
  event.ms = seconds and tonumber(seconds) * 1000 or nil
  local slot, seat = rest:match("s%s+(%-?%d+) %((%-?%d+)%)")
  event.slot, event.seat = tonumber(slot), tonumber(seat)
  local x, y = rest:match("%)%s+(%-?[%d%.]+)/%s*(%-?[%d%.]+)")
  event.x, event.y = tonumber(x), tonumber(y)
  return event
end

-- Each output transform, as libinput's calibration matrix: x = au + bv + c,
-- y = du + ev + f, with u and v the device's own axes from 0 to 1.
M.MATRICES = {
  normal = { 1, 0, 0, 0, 1, 0 },
  ["90"] = { 0, -1, 1, 1, 0, 0 },
  ["180"] = { -1, 0, 1, 0, -1, 1 },
  ["270"] = { 0, 1, 0, -1, 0, 1 },
  flipped = { -1, 0, 1, 0, 1, 0 },
  flipped_90 = { 0, 1, 0, 1, 0, 0 },
  flipped_180 = { 1, 0, 0, 0, -1, 1 },
  flipped_270 = { 0, -1, 1, -1, 0, 1 },
}

--- Where `x` and `y` percent of the device fall on `screen`, in its logical pixels.
function M.place(screen, x, y)
  local m = M.MATRICES[screen.transform or "normal"] or M.MATRICES.normal
  local u, v = x / 100, y / 100
  return (m[1] * u + m[2] * v + m[3]) * (screen.width or 0), (m[4] * u + m[5] * v + m[6]) * (screen.height or 0)
end

--- The screen the touchscreen sits on: the one named `chosen`, the first for which
--- `built_in(name)` holds, or the only one there is. nil when it cannot be told.
function M.panel(screens, chosen, built_in)
  for _, screen in ipairs(screens or {}) do
    if chosen and chosen ~= "" and screen.name == chosen then return screen end
  end
  if chosen and chosen ~= "" then return nil end
  for _, screen in ipairs(screens or {}) do
    if built_in and built_in(screen.name or "") then return screen end
  end
  return screens and #screens == 1 and screens[1] or nil
end

--- Whether `libinput` can be run.
function M.installed()
  local program = M.LIBINPUT
  if program:find("/", 1, true) then return morf.fs.exists(program) end
  for dir in ((morf.env and morf.env("PATH") or "") .. ":/usr/bin:/usr/local/bin"):gmatch("[^:]+") do
    if morf.fs.exists(dir .. "/" .. program) then return true end
  end
  return false
end

--- A reader. `options`, each a seam: `screen()`, `sink`, `find()` (the
--- touchscreens, as models.touchscreens lists them), `installed()`,
--- `spawn(spec)` (morf.process.spawn), `changed(state)`.
function M.new(options)
  options = options or {}
  local find = options.find or function() return require("models.touchscreens").list() end
  local installed = options.installed or M.installed
  local spawn = options.spawn or morf.process.spawn
  local sink = options.sink or {}
  local r = {}
  local wanted, state = false, "off"
  local open, retry = {}, nil
  local wait, serial = M.RETRY, 0

  local function say(value)
    if value == state then return end
    state = value
    if options.changed then options.changed(value) end
  end

  local function close(entry)
    entry.closing = true
    if entry.child then
      pcall(entry.child.kill, entry.child, "TERM")
      pcall(entry.child.close, entry.child)
    end
    open[entry.node] = nil
  end

  -- A line from `entry`'s process, passed on in the screen's pixels.
  local function heard(entry, line)
    local event = M.parse(line)
    if not event or entry.closing then return end
    if event.kind == "added" then
      entry.live = true
      say("running")
      return
    end
    local screen = options.screen and options.screen()
    if not screen then return end
    local kind, id = event.kind, entry.index .. ":" .. tostring(event.seat)
    if kind == "down" or kind == "move" then
      if event.x and sink[kind] then
        local x, y = M.place(screen, event.x, event.y)
        sink[kind](id, x, y, event.ms)
      end
    elseif kind == "up" then
      if sink.up then sink.up(id, event.ms) end
    elseif kind == "cancel" then
      if sink.cancel then sink.cancel() end
    elseif kind == "frame" then
      if sink.frame then sink.frame(event.ms) end
    end
  end

  local function back_off()
    if retry or not wanted then return end
    retry = morf.time.timer(wait, function()
      retry = nil
      if wanted then r.refresh() end
    end, false)
    wait = math.min(wait * 2, M.LONGEST)
  end

  local function launch(device)
    serial = serial + 1
    local entry = { node = device.node, index = serial }
    open[device.node] = entry
    local ok, child = pcall(spawn, {
      command = { M.LIBINPUT, "debug-events", "--device", device.node },
      on_stdout = function(line) heard(entry, line) end,
      on_stderr = function() end,
      on_exit = function()
        if entry.closing then return end
        open[entry.node] = nil
        if sink.cancel then sink.cancel() end
        if wanted then
          say(entry.live and "starting" or "denied")
          back_off()
        end
      end,
    })
    if not ok or not child then
      open[device.node] = nil
      say("missing")
      return false
    end
    entry.child = child
    return true
  end

  --- Looks at the touchscreens again: one that went is let go, one that came is read.
  function r.refresh()
    if not wanted then return end
    local devices, present = find(), {}
    for _, device in ipairs(devices) do present[device.node] = true end
    for node, entry in pairs(open) do
      if not present[node] then close(entry) end
    end
    if #devices == 0 then
      if sink.cancel then sink.cancel() end
      say("none")
      return
    end
    if not installed() then say("missing") return end
    if state ~= "running" then say("starting") end
    for _, device in ipairs(devices) do
      if not open[device.node] then launch(device) end
    end
  end

  --- Starts reading; on a machine with no touchscreen or no libinput it spawns nothing.
  function r.start()
    if wanted then return end
    wanted = true
    wait = M.RETRY
    r.refresh()
  end

  --- Stops: each process ended, and nothing more is heard.
  function r.stop()
    wanted = false
    if retry then retry:cancel() retry = nil end
    for _, entry in pairs(open) do close(entry) end
    if sink.cancel then sink.cancel() end
    say("off")
  end

  --- Takes `line` as the first open process would have printed it: a stand-in's way in.
  function r.feed(line)
    local _, entry = next(open)
    if entry then heard(entry, line) end
  end

  --- What the reader is doing.
  function r.state() return state end

  --- Whether any process is open.
  function r.reading() return next(open) ~= nil end

  return r
end

return M
