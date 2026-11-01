-- eva-screenshot: the capture tool, a process of its own on every screen as the
-- shell is, so what opens opens on the focused one. It takes the verbs below
-- from `morf -i DISPLAY-screenshot ipc call`, and its first order as operands:
--
--     morf -i wayland-1-screenshot app.lua -- capture open      does it, then ends
--     morf -i wayland-1-screenshot app.lua -- standby           stays, out of sight
--
-- The shell keeps it on standby, so a key opens the panel at once. Its state is
-- published for the shell in $XDG_RUNTIME_DIR/eva/capture-DISPLAY.json.
local morf = require("morf")

local first = { table.unpack(morf.operands or {}) }
local stays = first[1] == "standby"
if stays then table.remove(first, 1) end
local kept = morf.reloadable("eva.capture.ordered", false)

morf.surface.blend = "srgb"
morf.surface.namespace = "eva-capture"
morf.surface.keyboard_focus = "none"

local host = require("host")
local ui_scale = require("themes.ui_scale")
local frame = require("common.frame")
local focused = require("focused")
local capture = require("capture")
local config = require("config")
local themes = require("themes")
local responsive = require("responsive")
local ui = require("morf.ui")

local editor = capture.editor
local screen_name = focused.output
local me = screen_name()

-- Out of sight on standby; a first order has it whole.
host.posture(stays and #first == 0 and "hidden" or "full")
ui_scale.apply()
frame.follow_scheme()
frame.follow_appearance(function() return not capture.recording:get() end)
morf.effect("eva.capture.scale", function() ui_scale.get() ui_scale.apply() end)
host.framed:set(host.shell_up())

local built_layout = responsive.layout()
morf.effect("eva.capture.rotation", function()
  morf.window.screens_revision()
  local layout = responsive.layout()
  if layout ~= built_layout then
    built_layout = layout
    morf.reload { output = true }
  end
end)

morf.effect("eva.capture.keyboard", function()
  morf.surface.keyboard_focus = editor.active:get() and "exclusive" or "none"
end)

-- ------------------------------------------------------------- notifications --

local function dry()
  local value = morf.env("EVA_DRY_RUN")
  return value and value ~= "" and value ~= "0"
end

local function notify(summary, body)
  if dry() then return end
  body = body or ""
  if host.shell_up() then
    morf.process.detach { morf.executable, "ipc", "call", "notify", summary, body, "normal", "Morf" }
  else
    morf.process.detach { "notify-send", "-a", "Morf", summary, body }
  end
end

editor.on_export = function(action, result)
  if action == "ocr" or action == "qr" then notify("Copied", tostring(result or ""))
  elseif action == "save" then
    if not dry() then morf.process.detach { "sh", morf.paths.shell("cli"), "--saved-picture", tostring(result or "") } end
  else
    notify(action == "copy" and "Capture copied" or "Capture uploaded",
      action == "upload" and tostring(result or "Link copied to clipboard") or "")
  end
end

-- ----------------------------------------------------------------- the owner --

-- The screen that last acted; it publishes, and it ends the tool.
local owner = morf.shared("eva.capture.owner", "")
local function claim() owner:set(me) end
local function mine() return owner:get() == "" or owner:get() == me end

local state_path = require("capture_state").path

-- A dry run tells the shell nothing.
local silent = dry()
local written
morf.effect("eva.capture.publish", function()
  local recording, phase = capture.recording:get(), capture.phase:get()
  local line = morf.json.encode {
    pid = morf.process_id, panel = capture.drawer.open:get(), editing = editor.running(),
    phase = recording and phase ~= "stopping" and "recording" or phase, recording = recording,
    started = capture.started:get(), target = capture.target:get(), output = me,
  }
  if silent or not mine() or line == written then return end
  written = line
  morf.fs.write(state_path(), line, { atomic = true, parents = true })
end)

-- -------------------------------------------------------------------- at rest --

local function working()
  local phase = capture.phase:get()
  return capture.drawer.open:get() or capture.drawer.panel.visible or editor.running()
    or phase == "countdown" or phase == "saving" or phase == "editing" or phase == "stopping"
end

local function pill_wanted() return capture.recording:get() and not host.framed:get() end

-- Whole while it works; out of sight, or gone, when there is nothing to do.
local orphaned = false
local function rest()
  if capture.recording:get() then
    host.posture(pill_wanted() and "strip" or "hidden")
  elseif stays then
    host.posture("hidden")
  elseif #first > 0 or orphaned then
    config.flush()
    morf.fs.remove(state_path())
    morf.quit()
  end
end

-- The panel lands a moment after it shuts, so its end is watched for.
local resting
local function watch_rest()
  if resting then return end
  resting = morf.time.timer(120, function()
    if working() then return end
    resting:cancel() resting = nil
    if mine() then rest() end
  end, true)
end

morf.effect("eva.capture.rest", function()
  capture.phase:get() capture.recording:get() capture.drawer.open:get()
  editor.active:get() editor.pending:get()
  if owner:get() == me then watch_rest() end
end)

-- Kept ready for the shell, and no longer than the shell.
if stays then
  morf.time.timer(5000, function()
    if not stays or host.shell_up() then return end
    host.framed:set(false)
    stays, orphaned = false, true
    claim()
    watch_rest()
  end, true)
end

--- `fn` once the surface is whole: at once when it is, a moment later when it
--- has to grow.
local function wake(fn)
  claim()
  host.framed:set(host.shell_up())
  if host.now == "full" then fn() return end
  host.posture("full")
  morf.time.timer(40, fn, false)
end

-- ---------------------------------------------------------------------- verbs --

local here = focused.here

-- Kept here as well as given to `morf.ipc`, which only takes them.
local ipc = setmetatable({}, { __newindex = function(t, k, v) rawset(t, k, v) morf.ipc[k] = v end })

-- `key=value` words after a verb's first: what the command line asked for.
local function options(...)
  local out = {}
  for _, word in ipairs { ... } do
    local key, value = tostring(word):match("^(%w+)=(.*)$")
    if key then out[key] = value else out[#out + 1] = word end
  end
  return out
end

local function verb(how)
  how = how or "toggle"
  local d = capture.drawer
  if how == "close" then
    d.set(false)
    if here() then return d.is_open() end
    return
  end
  if how ~= "open" and how ~= "toggle" and how ~= "state" then
    error("`" .. tostring(how) .. "`: open, close, toggle or state")
  end
  if not here() then
    -- Opened elsewhere now: shut here, so one screen has it at a time.
    if how ~= "state" then d.set(false) end
    return
  end
  if how == "state" then return d.is_open() end
  local opening = how == "open" or not d.is_open()
  wake(function() d.set(opening) end)
  return opening
end

ipc.capture = function(how)
  how = how or "toggle"
  if how == "menu" then how = "open" end
  if how == "close" or ((how == "open" or how == "toggle") and editor.running()) then capture.cancel() end
  return verb(how)
end

ipc["capture-claim"] = function(name)
  local own = (morf.screens or {})[1]
  if own and own.name ~= name then capture.cancel() capture.drawer.set(false) end
end

ipc["capture-stop"] = function() return capture.stop() end

ipc["capture-editor"] = function(action, ...)
  if action == "cancel" then capture.cancel() return true end
  if not here() then return end
  if action == "tool" then editor.choose(...) return true end
  if action == "copy" or action == "save" or action == "upload" then editor.export(action) return true end
  if action == "ocr" or action == "qr" then editor.export(action) return true end
  if action == "last" then return editor.restore_last() end
  if action == "file" then
    local path, order = (...), options(select(2, ...))
    wake(function() capture.open_file(path, order.result) end)
    return true
  end
  return { open = editor.active:get(), pending = editor.pending:get(), busy = editor.busy:get(), phase = editor.phase:get() }
end

-- `screenshot WHAT [quick] [how=copy] [delay=N] [last=1] [result=FILE]`.
ipc.screenshot = function(what, ...)
  if not here() then return nil end
  local order = options(...)
  local shot = { quick = order[1] == "quick", how = order.how, last = order.last == "1",
    delay = tonumber(order.delay), result = order.result }
  if shot.how == "edit" then shot.how = nil end
  wake(function() capture.shoot(what, shot) end)
  return what
end

-- `record [WHAT] [audio=KIND] [fps=N] [start=1]`, `record stop`, `record state`.
-- The screen that holds the recorder answers a stop, wherever the focus is.
ipc.record = function(what, ...)
  if what == "state" then
    if here() then return capture.recording:get() and capture.file:get() or "idle" end
    return
  end
  if what == "stop" then
    if not capture.recording:get() then
      if here() then return "idle" end
      return
    end
    local answered = capture.file:get()
    if capture.stop() then return answered end
    return
  end
  if capture.recording:get() and not here() then return capture.stop() end
  if not here() then return nil end
  local order = options(...)
  local asked = { audio = order.audio, fps = tonumber(order.fps), start = order.start == "1" }
  if capture.recording:get() then return capture.record(what, asked) end
  wake(function() capture.record(what, asked) end)
  return what
end

ipc.standby = function()
  stays = true
  return true
end
ipc.reload = function() morf.reload() return true end
ipc.quit = function()
  config.flush()
  morf.quit()
  return true
end
ipc.state = function()
  return { output = me, panel = capture.drawer.open:get(), phase = capture.phase:get(), recording = capture.recording:get(),
    editing = editor.running(), stage = editor.phase:get(), posture = host.now, framed = host.framed:get() }
end

-- ------------------------------------------------------------------- the root --

ui.Item { anchors = { fill = true }, host.build(capture, pill_wanted) }

-- --------------------------------------------------------------- the first order --

-- Told once it has drawn, so the drawer has somewhere to come from.
if not kept:get() and #first > 0 then
  kept:set(true)
  local tries = 0
  local hypr = require("lib.compositor.hyprland")
  local function go()
    -- Hyprland says which monitor has the focus a moment after the start.
    if hypr.available() and (hypr.state.focused_monitor or "") == "" and tries < 30 then
      tries = tries + 1
      morf.time.timer(16, go, false)
      return
    end
    ipc[first[1]](table.unpack(first, 2))
  end
  morf.time.timer(32, go, false)
end
