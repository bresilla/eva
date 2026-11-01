-- Compact capture popup, opened explicitly by a key, button or IPC.
-- Captures close the drawer before a cancellable delay. Recording state
-- follows the child process; only that recording is stopped.
local morf = require("morf")
local theme = require("theme")
local config = require("config")
local drawer = require("drawer")
local backend = require("lib.shell.capture")
local M = {}
M.editor=require("capture_editor")
local screen = morf.screens and morf.screens[1] or { width = 1920, height = 1080 }
M.WIDTH = math.min(480, screen.width - theme.LEFT - theme.BORDER - 20)
M.target = morf.signal("eva.capture.target", "region")
M.delay = morf.signal("eva.capture.delay", 0)
-- One recording across the screens: a panel on any of them stops it.
M.recording = morf.shared("eva.capture.recording", false)
M.elapsed = morf.shared("eva.capture.elapsed", 0)
M.started = morf.shared("eva.capture.started", 0)
M.file = morf.shared("eva.capture.file", "")
M.paused = morf.shared("eva.capture.paused", false)
M.pausable = morf.shared("eva.capture.pausable", false)
-- The seconds a replay buffer keeps; 0 for a plain recording.
M.replay = morf.shared("eva.capture.replay", 0)
M.phase = morf.signal("eva.capture.phase", "ready")
M.message = morf.signal("eva.capture.message", "")
M.countdown = morf.signal("eva.capture.countdown", 0)
-- What keeps a tool with nothing else to do alive: thumbnails and pins.
M.held = morf.signal("eva.capture.held", 0)
M.pins_kept = morf.reloadable("eva.capture.pins.kept", "")
local pending, ticker, process, d, pause_began
local sequence, generation = 0, 0
local function dry_run()
  local v = morf.env("EVA_DRY_RUN")
  return v and v ~= "" and v ~= "0"
end
local function expand(word)
  local home = morf.fs.home()
  return (tostring(word):gsub("^~/", function() return home .. "/" end):gsub("%$HOME", function() return home end))
end
function M.folder() return expand(config.get("capture.folder") or "~/Pictures/Captures") end
local function fail(message)
  M.message:set(message)
  M.phase:set("error")
  M.recording:set(false)
  M.paused:set(false) M.replay:set(0)
  if d then d.set(true) end
end
--- Runs the configured command `name`. `$FILE` is the file it writes; `values`
--- fills the other capital words it names.
local function run(name, extra, done, values)
  local words = config.get("capture.commands." .. name)
  if type(words) ~= "table" or #words == 0 then
    fail("No command configured for " .. name .. ".")
    return false
  end
  sequence = sequence + 1
  local file = M.folder() .. "/capture_" .. morf.time.format("%Y%m%d_%H-%M-%S") .. ("_%03d"):format(sequence)
  local argv = {}
  for i, word in ipairs(words) do
    argv[i] = expand(word):gsub("%$(%u+)", function(key)
      if key == "FILE" then return file end
      return values and values[key] or nil
    end)
  end
  for _, word in ipairs(extra or {}) do argv[#argv + 1] = word end
  for _, word in ipairs(argv) do if word:sub(1, #file) == file then M.file:set(word) end end
  if dry_run() then
    morf.log("info", "eva: capture " .. name .. " (dry run): " .. table.concat(argv, " "))
    return true
  end
  if name ~= "open" then
    local ok, made, why = pcall(morf.fs.mkdir, M.folder())
    if not ok or not made then fail("Cannot create capture folder: " .. tostring(why or made)) return false end
  end
  local ok, child = pcall(morf.process.run, argv, {}, function(result)
    if done then done(result or { ok = false })
    elseif result and not result.ok then M.message:set(result.error or result.stderr or "Could not open capture.") end
  end)
  if not ok then fail(tostring(child)) return false end
  return true, child
end
function M.open(path) return run("open", { path or M.folder() }) end
local function stop_ticker()
  if ticker then ticker:cancel() ticker = nil end
end
function M.cancel()
  if M.editor.running() then M.editor.cancel() return true end
  if not pending then return false end
  generation = generation + 1
  pending:cancel() pending = nil
  stop_ticker()
  M.recording:set(false)
  M.replay:set(0)
  M.phase:set("ready")
  M.countdown:set(0)
  return true
end
local function after_shutting(fn, wait)
  if d then d.set(false) end
  local delay = wait or M.delay:get() or 0
  M.phase:set("countdown")
  M.countdown:set(delay)
  stop_ticker()
  if delay > 0 then ticker = morf.time.timer(1000, function() M.countdown:set(math.max(0, M.countdown:get() - 1)) end, true) end
  pending = morf.time.timer(theme.duration.drawer_close + 50 + delay * 1000, function()
    pending = nil
    stop_ticker()
    fn()
  end, false)
end
local function checked(what)
  what = what or M.target:get()
  if what ~= "region" and what ~= "window" and what ~= "screen" then error("Choose region, window or screen") end
  return what
end
local function busy()
  local phase = M.phase:get()
  return phase ~= "ready" and phase ~= "error"
end
local function claim()
  if morf.broadcast then morf.broadcast("capture-claim",screen.name) end
  -- A thumbnail goes before the next picture.
  local thumb = package.loaded.thumb
  if thumb then thumb.dismiss() end
end
-- What the tool's own command line waits on: "ok" or "no", then a line.
local function report(path, ok, value)
  if path then morf.fs.write(path, (ok and "ok\n" or "no\n") .. tostring(value or ""), { atomic = true }) end
end
--- A screenshot of `what` through the selection. `how` is true for a quick
--- one, or a table: `how` (copy, save, ocr or qr: done on the selection, the
--- editor left out), `delay`, `last` and `result` (a file told how it went).
function M.shoot(what,how)
  what = checked(what)
  if busy() then return "busy" end
  local order = type(how) == "table" and how or { quick = how }
  M.message:set("")
  claim()
  after_shutting(function()
    local after = order.how
    if not after and (order.quick or not config.get("capture.editor")) then after = "save" end
    if dry_run() then
      morf.log("info", "eva: capture screenshot_" .. what .. " (dry run)")
      M.phase:set("ready") M.message:set("Screenshot saved.")
      report(order.result, true, "dry run")
      return
    end
    M.phase:set("editing")
    M.editor.start(what,function(ok,message,value)
      -- A cancelled selection answers with neither, and that is not a result.
      report(order.result, ok and value ~= nil, value or message or "cancelled")
      if ok then M.phase:set("ready") M.message:set(message or "Capture closed.")
      elseif after then M.phase:set("ready") M.message:set(message or "Capture failed.")
      else fail(message or "Capture failed.") end
    end,{after=after,last=order.last})
  end, order.delay)
  return what
end
--- The editor on the picture at `path`. `closed`, if any, runs when it ends.
function M.open_file(path, result, closed)
  if busy() then return false end
  claim()
  M.phase:set("editing")
  local ok, why = M.editor.open_file(path, function(good, message, value)
    report(result, good, value or message or "cancelled")
    M.phase:set("ready")
    if closed then closed() end
  end)
  if not ok then M.phase:set("ready") end
  return ok, why
end
local function spell(r) return ("%dx%d+%d+%d"):format(r.w, r.h, r.x, r.y) end
-- Where a recording looks, for `ready(values)`: the selection for a region, the
-- focused window by its geometry, this output for a screen.
local function aim(what, ready, cancelled)
  if what == "screen" then ready { OUTPUT = screen.name or "screen" } return end
  if dry_run() then ready { REGION = "0x0+0+0" } return end
  if what == "window" then
    backend.focused_window(function(r) ready(r and { REGION = spell(r) } or nil) end)
    return
  end
  local chosen
  M.phase:set("editing")
  M.editor.start("region", function(ok, message)
    if chosen then ready { REGION = chosen }
    else cancelled(ok, message) end
  end, { after = function(editor)
    chosen = spell(editor.region())
    editor.cancel()
  end })
end
local function recorded(file)
  if dry_run() or file == "" then return end
  morf.process.detach { "sh", morf.paths.shell("cli"), "--saved-recording", file }
end
M.recorded = recorded
--- Runs the configured command `name`, its capital words from `values`:
--- `done(result)`. What it writes is in `M.file`.
function M.run_command(name, values, done) return run(name, nil, done, values) end
local function stop_recorder()
  if M.phase:get() == "stopping" then return "stopping" end
  M.phase:set("stopping")
  if dry_run() then
    stop_ticker() M.recording:set(false) M.paused:set(false) M.replay:set(0) M.phase:set("ready")
  elseif process then
    local ok, sent = pcall(function() return process:kill("INT") end)
    if not ok or not sent then
      M.phase:set("recording")
      M.message:set("Could not stop the recorder. Try again.")
    end
  elseif morf.broadcast and morf.broadcast("capture-stop") then
    M.phase:set("ready")
  else
    fail("No recorder process is running.")
  end
  return "stopped"
end
--- This screen's recorder stopped, wherever the stop was asked.
function M.stop()
  if process or (dry_run() and M.recording:get()) then return stop_recorder() end
end
-- Whether the command `name` runs gpu-screen-recorder, which pauses on USR2.
local function takes_pause(name)
  local words = config.get("capture.commands." .. name)
  for _, word in ipairs(type(words) == "table" and words or {}) do
    if tostring(word):match("gpu%-screen%-recorder$") then return true end
  end
  return false
end
--- Starts a recording of `what`, or stops the one running. `order`: `audio`
--- (the recorder's -a), `fps`, `start`, which refuses to stop one, and `replay`,
--- the seconds a replay buffer keeps instead of a file.
function M.record(what,order)
  order = order or {}
  if M.recording:get() then
    if order.start then return "already recording" end
    if M.cancel() then return "stopped" end
    return stop_recorder()
  end
  if busy() then return "busy" end
  what = checked(what)
  M.message:set("") M.elapsed:set(0) M.recording:set(true)
  M.paused:set(false) M.replay:set(order.replay or 0)
  generation = generation + 1
  local current = generation
  claim()
  after_shutting(function()
    local function begin(values)
      if current ~= generation then return end
      values = values or {}
      values.FPS = tostring(order.fps or 60)
      M.phase:set("recording")
      M.started:set(morf.time.now_ms())
      local name = (what == "window" and not values.REGION) and "record_portal" or "record_" .. what
      if order.replay then
        name, values.SECONDS, values.FOLDER = "record_replay", tostring(order.replay), M.folder()
        M.file:set("")
      end
      M.pausable:set(not order.replay and takes_pause(name))
      local extra = order.audio and { "-a", order.audio } or nil
      local ok, child = run(name, extra, function(result)
        if current ~= generation then return end
        local stopped = M.phase:get() == "stopping"
        local plain = M.replay:get() == 0
        process = nil
        stop_ticker()
        M.recording:set(false)
        M.paused:set(false) M.replay:set(0)
        if result.ok or (stopped and result.signal == 2) then
          M.phase:set("ready") M.message:set(plain and "Recording saved." or "Replay stopped.")
          if plain then recorded(M.file:get()) end
        else fail(result.error or result.stderr or "Recording cancelled or failed.") end
      end, values)
      if not ok then return end
      if M.phase:get() ~= "recording" then return end
      process = child
      ticker = morf.time.timer(1000, function()
        if not M.paused:get() then M.elapsed:set(M.elapsed:get() + 1) end
      end, true)
    end
    aim(what, begin, function(ok, message)
      M.recording:set(false)
      M.replay:set(0)
      if ok then M.phase:set("ready") M.message:set("")
      else fail(message or "Recording cancelled or failed.") end
    end)
  end, order.replay and 0 or nil)
  return what
end
--- Whether the recorder running can be paused.
function M.can_pause() return M.pausable:get() end
--- Pauses the recording, or takes it up again; `on` says which, a toggle without
--- it. Answers "paused", "recording", or false when nothing changed.
function M.pause(on)
  if on == nil then on = not M.paused:get() end
  if not M.recording:get() or M.phase:get() ~= "recording" or not M.can_pause() then return false end
  if on == M.paused:get() then return false end
  if process then
    local ok, sent = pcall(function() return process:kill("USR2") end)
    if not ok or not sent then M.message:set("Could not reach the recorder.") return false end
  elseif not dry_run() then
    if morf.broadcast then morf.broadcast("capture-pause", on and "on" or "off") end
    return on and "paused" or "recording"
  end
  local now = morf.time.now_ms()
  if on then pause_began = now
  elseif pause_began then M.started:set(M.started:get() + now - pause_began) end
  M.paused:set(on)
  return on and "paused" or "recording"
end
--- Keeps the last `order.seconds` of the screen, or the configured seconds, until
--- asked to save them or stop. `order.audio` and `order.fps` as for a recording.
function M.replay_start(order)
  order = order or {}
  local seconds = tonumber(order.seconds) or tonumber(config.get("capture.replay_seconds")) or 30
  return M.record("screen", { replay = math.max(2, math.floor(seconds)), audio = order.audio, fps = order.fps, start = true })
end
--- The replay buffer on, or off when it is on.
function M.replay_toggle()
  if M.replay:get() > 0 then return M.record() end
  return M.replay_start()
end
-- Finds the file the recorder writes for a save: it names it itself, so the
-- folder is watched until a new one stops growing.
local function await_replay(before)
  local tries, seen, size = 0, nil, -1
  local timer
  timer = morf.time.timer(250, function()
    tries = tries + 1
    local found
    for _, entry in ipairs(morf.fs.list(M.folder()) or {}) do
      if not before[entry.name] and entry.name:lower():match("%.mp4$") then found = entry end
    end
    if found and found.path == seen and found.size == size and size > 0 then
      timer:cancel()
      M.file:set(found.path)
      M.message:set("Replay saved.")
      recorded(found.path)
    elseif tries >= 40 then
      timer:cancel()
      M.message:set("The recorder did not save a replay.")
    elseif found then
      seen, size = found.path, found.size
    end
  end, true)
end
--- Saves what the replay buffer holds; it runs on. Answers whether it was asked.
function M.replay_save()
  if M.replay:get() == 0 then return false end
  if dry_run() then return true end
  if not process then
    if morf.broadcast then return morf.broadcast("capture-replay-save") == true end
    return false
  end
  local before = {}
  for _, entry in ipairs(morf.fs.list(M.folder()) or {}) do before[entry.name] = true end
  local ok, sent = pcall(function() return process:kill("USR1") end)
  if not ok or not sent then M.message:set("Could not reach the recorder.") return false end
  M.message:set("Saving the replay…")
  await_replay(before)
  return true
end
--- A long picture of `what` as it scrolls: the selection for a region, the
--- focused window by its place, or this screen.
function M.scroll(what)
  if busy() then return "busy" end
  what = checked(what)
  M.message:set("")
  claim()
  after_shutting(function()
    local function ready(values)
      local area
      if values and values.OUTPUT then
        area = { x = screen.x or 0, y = screen.y or 0, w = screen.width, h = screen.height }
      elseif values and values.REGION then
        local w, h, x, y = values.REGION:match("^(%d+)x(%d+)%+(-?%d+)%+(-?%d+)$")
        area = { x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) }
      end
      if not area then fail("The compositor does not say where the window is.") return end
      M.phase:set("scrolling")
      local ok, why = require("scroll").start(M, area)
      if not ok then fail(why) end
    end
    aim(what, ready, function(ok, message)
      if ok then M.phase:set("ready") M.message:set("")
      else fail(message or "Selection cancelled.") end
    end)
  end)
  return what
end
-- A recording's trim, over the desk while it is open.
M.trim_open = morf.signal("eva.capture.trim", false)
--- Whether the file at `path` is a recording: the editor takes those by trimming.
function M.is_recording(path)
  local extension = tostring(path):lower():match("%.(%w+)$")
  return extension == "mp4" or extension == "mkv" or extension == "webm" or extension == "mov" or extension == "gif"
end
-- The panel's history in the place of its controls, and the height it needs.
M.history_open = morf.signal("eva.capture.history", false)
function M.height()
  if not M.history_open:get() then return 264 end
  return math.max(264, math.min(520, math.floor((screen.height or 800) * 0.62)))
end
M.drawer = drawer.new {
  name = "capture", edge = "bottom", width = M.WIDTH, height = M.height,
  content = require("capture_view").build(M, M.WIDTH, M.height), close_policy = "outside",
}
d = M.drawer
morf.effect("eva.capture.history.shut", function()
  if not d.open:get() and M.history_open:get() then M.history_open:set(false) end
end)
return M
