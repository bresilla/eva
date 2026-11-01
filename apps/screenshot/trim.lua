-- A recording in the editor: a stretch of it chosen on a timeline, saved as a
-- shorter recording or a GIF beside the original, which stays. ffmpeg does the
-- work, and the frames shown are scratch. Loaded the first time one is opened.
local morf = require("morf")
local config = require("config")
local backend = require("lib.shell.capture")
local read = require("lib.shell.capture.read")

local M = {
  path = morf.signal("eva.capture.trim.path", ""),
  duration = morf.signal("eva.capture.trim.duration", 0),
  from = morf.signal("eva.capture.trim.from", 0),
  to = morf.signal("eva.capture.trim.to", 0),
  frame = morf.signal("eva.capture.trim.frame", ""),
  note = morf.signal("eva.capture.trim.note", ""),
  busy = morf.signal("eva.capture.trim.busy", false),
}

M.MISSING = "ffmpeg is not installed, so a recording cannot be trimmed or made a GIF"
-- The shortest stretch that can be kept, and the frames' width.
M.LEAST = 0.2
M.FRAME_W = 960

local capture, session, serial, wanted, working = nil, nil, 0, nil, false

local function dry()
  local value = morf.env("EVA_DRY_RUN")
  return value and value ~= "" and value ~= "0"
end

--- Whether ffmpeg and ffprobe are on PATH.
function M.available()
  return read.on_path("ffmpeg") and read.on_path("ffprobe")
end

local function seconds(value) return ("%.3f"):format(value) end

--- "m:ss.d" for `value` seconds.
function M.clock(value)
  local whole = math.floor(value)
  return ("%d:%02d.%d"):format(whole // 60, whole % 60, math.floor((value - whole) * 10))
end

local function fetch(at)
  if working then wanted = at return end
  working = true
  serial = serial + 1
  local mine = serial
  local out = session.path("frame-" .. mine .. ".png")
  morf.process.run({ "ffmpeg", "-y", "-loglevel", "error", "-ss", seconds(at), "-i", M.path:get(), "-frames:v", "1",
    "-vf", "scale=" .. M.FRAME_W .. ":-2", out }, {}, function(result)
    if mine ~= serial then return end
    working = false
    if result and result.ok then
      local old = M.frame:get()
      M.frame:set(out)
      if old ~= "" then session.remove(old) end
    end
    if wanted then
      local next_at = wanted
      wanted = nil
      fetch(next_at)
    end
  end)
end

--- The edge `which`, "from" or "to", moved to `at` seconds, a stretch of LEAST
--- always left between them. Answers where it stands.
function M.move(which, at)
  local length = M.duration:get()
  if which == "from" then
    at = math.max(0, math.min(at, M.to:get() - M.LEAST))
    M.from:set(at)
  else
    at = math.min(length, math.max(at, M.from:get() + M.LEAST))
    M.to:set(at)
  end
  fetch(at)
  return at
end

--- Ends it, the original as it was.
function M.close()
  serial = serial + 1
  wanted, working = nil, false
  if session then session.close() session = nil end
  M.frame:set("") M.note:set("") M.busy:set(false) M.path:set("")
  if capture and capture.trim_open:get() then
    capture.trim_open:set(false)
    capture.phase:set("ready")
  end
end

--- Writes the chosen stretch, by the `trim` or `gif` command, as a new file.
function M.save(kind)
  if M.busy:get() or M.duration:get() <= 0 then return false end
  M.busy:set(true)
  M.note:set(kind == "gif" and "Making the GIF…" or "Trimming…")
  local ok = capture.run_command(kind, { SOURCE = M.path:get(), START = seconds(M.from:get()), END = seconds(M.to:get()),
    RATE = tostring(config.get("capture.gif_fps")), WIDTH = tostring(config.get("capture.gif_width")) }, function(result)
    M.busy:set(false)
    if result and result.ok then
      local file = capture.file:get()
      capture.recorded(file)
      capture.message:set((kind == "gif" and "GIF saved: " or "Trim saved: ") .. (file:match("[^/]+$") or ""))
      M.close()
    else
      M.note:set(tostring(result and (result.error or result.stderr) or "It did not finish"))
    end
  end)
  if not ok or dry() then M.busy:set(false) end
  return ok
end

--- Opens the recording at `path`. Answers whether it opened, and why not.
function M.open(module, path)
  capture = module
  if not M.available() then return false, M.MISSING end
  local phase = capture.phase:get()
  if phase ~= "ready" and phase ~= "error" then return false, "Busy with a capture" end
  session = backend.session {}
  M.path:set(path) M.duration:set(0) M.from:set(0) M.to:set(0) M.note:set("Reading the recording…")
  capture.phase:set("editing")
  capture.trim_open:set(true)
  morf.process.run({ "ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", path }, {}, function(result)
    if M.path:get() ~= path then return end
    local length = result and result.ok and tonumber((result.stdout or ""):match("[%d%.]+"))
    if not length or length <= 0 then
      M.note:set("Could not read this recording")
      return
    end
    M.duration:set(length) M.to:set(length) M.note:set("")
    fetch(0)
  end)
  return true
end

return M
