-- eva-record's window and its indicator: what to record, and the recording
-- under way. No nodes; the recording itself is apps/record/cli's.
local morf = require("morf")

local M = {
  target = morf.signal("record.target", "monitor"),
  audio = morf.signal("record.audio", "none"),
  recording = morf.signal("record.recording", false),
  elapsed = morf.signal("record.elapsed", 0),
  message = morf.signal("record.message", ""),
}

M.AUDIO = {
  { "none", "No sound", "volume_off" }, { "desktop", "Desktop", "volume_up" },
  { "mic", "Microphone", "mic" }, { "both", "Both", "graphic_eq" },
}

local function folder() return (morf.env("XDG_RUNTIME_DIR") or "/tmp") .. "/eva" end

--- Whether the recorder named in the pid file is alive.
function M.check()
  local ok, text = pcall(morf.fs.read, folder() .. "/record.pid")
  local pid = ok and tostring(text or ""):match("^%d+") or nil
  local alive = pid ~= nil and morf.fs.is_dir("/proc/" .. pid)
  M.recording:set(alive)
  return alive
end

local function cli(words, done)
  local argv = { "sh", morf.paths.shell("cli") }
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  morf.process.run(argv, {}, function(result)
    if result and not result.ok then M.message:set((result.stderr or ""):gsub("^eva: ", "")) end
    if done then done(result) end
  end)
end

--- Starts what the window says, this window having gone first.
function M.start()
  morf.process.detach { "sh", morf.paths.shell("cli"), M.target:get(), "--audio", M.audio:get() }
  morf.time.timer(50, function() morf.quit() end, false)
end

function M.stop(done)
  cli({ "stop" }, function() M.check() if done then done() end end)
end

--- "m:ss" for `seconds`.
function M.clock(seconds)
  return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

return M
