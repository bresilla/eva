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
M.phase = morf.signal("eva.capture.phase", "ready")
M.message = morf.signal("eva.capture.message", "")
M.countdown = morf.signal("eva.capture.countdown", 0)
local pending, ticker, process, d
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
--- The editor on the picture at `path`.
function M.open_file(path, result)
  if busy() then return false end
  claim()
  M.phase:set("editing")
  local ok, why = M.editor.open_file(path, function(good, message, value)
    report(result, good, value or message or "cancelled")
    M.phase:set("ready")
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
local function stop_recorder()
  if M.phase:get() == "stopping" then return "stopping" end
  M.phase:set("stopping")
  if dry_run() then
    stop_ticker() M.recording:set(false) M.phase:set("ready")
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
--- Starts a recording of `what`, or stops the one running. `order`: `audio`
--- (the recorder's -a), `fps`, and `start`, which refuses to stop one.
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
      local extra = order.audio and { "-a", order.audio } or nil
      local ok, child = run(name, extra, function(result)
        if current ~= generation then return end
        local stopped = M.phase:get() == "stopping"
        process = nil
        stop_ticker()
        M.recording:set(false)
        if result.ok or (stopped and result.signal == 2) then
          M.phase:set("ready") M.message:set("Recording saved.")
          recorded(M.file:get())
        else fail(result.error or result.stderr or "Recording cancelled or failed.") end
      end, values)
      if not ok then return end
      if M.phase:get() ~= "recording" then return end
      process = child
      ticker = morf.time.timer(1000, function() M.elapsed:set(M.elapsed:get() + 1) end, true)
    end
    aim(what, begin, function(ok, message)
      M.recording:set(false)
      if ok then M.phase:set("ready") M.message:set("")
      else fail(message or "Recording cancelled or failed.") end
    end)
  end)
  return what
end
function M.height() return 264 end
M.drawer = drawer.new {
  name = "capture", edge = "bottom", width = M.WIDTH, height = M.height,
  content = require("capture_view").build(M, M.WIDTH, M.height), close_policy = "outside",
}
d = M.drawer
return M
