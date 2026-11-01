-- A voice note at a press: `pw-record` into a file, stopped with SIGINT so it
-- closes the file cleanly.
--
--   local recorder = require("lib.services.voice_recorder").new { folder = "/home/me/Recordings" }
--   recorder.set(true)
--   recorder.set(false)     -- `saved(path)` hears the file
local morf = require("morf")

local M = {}

--- `options`: `folder`, `spawn(argv, ended)` (a child with `:kill(signal)`),
--- `saved(path)`, `name()` (the file's stem).
function M.new(options)
  options = options or {}
  local stamp = tostring(options)
  local recorder = { running = morf.signal("eva.voice.running." .. stamp, false),
    seconds = morf.signal("eva.voice.seconds." .. stamp, 0) }
  local child, ticker, path

  local spawn = options.spawn or function(argv, ended)
    local ok, made = pcall(morf.process.spawn, { command = argv, on_stderr = function() end,
      on_exit = function() ended() end })
    if ok and made then return made end
    ended()
  end
  local function name() return options.name and options.name() or morf.time.format("note-%Y%m%d_%H-%M-%S") end

  local function finished()
    if ticker then ticker:cancel() ticker = nil end
    child = nil
    recorder.running:set(false)
    local file = path
    path = nil
    if file and options.saved then options.saved(file) end
  end

  --- Starts or stops recording.
  function recorder.set(on)
    if on == recorder.running:get() then return end
    if not on then
      if child then child:kill("INT") end
      return
    end
    morf.fs.mkdir(options.folder)
    path = options.folder .. "/" .. name() .. ".ogg"
    recorder.seconds:set(0)
    recorder.running:set(true)
    ticker = morf.time.timer(1000, function() recorder.seconds:set(recorder.seconds:get() + 1) end, true)
    child = spawn({ "pw-record", "--media-role", "Communication", path }, finished)
  end

  return recorder
end

return M
