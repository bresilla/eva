-- The Android container: `waydroid session start` as a child of the shell,
-- `waydroid session stop`, and `waydroid status` for what it is doing.
--
--   local droid = require("lib.services.waydroid").new()
--   droid.check()
--   droid.set(true)
--
-- `phase` is "off", "starting", "on" or "stopping".
local morf = require("morf")

local M = {}

--- What `waydroid status` prints, as a phase.
function M.parse(text)
  local session = tostring(text or ""):match("Session:%s*(%S+)")
  return session == "RUNNING" and "on" or "off"
end

--- `options`: `run(argv, done)`, `spawn(argv, ended)`.
function M.new(options)
  options = options or {}
  local run = options.run or function(argv, done)
    local ok = pcall(morf.process.run, argv, { timeout_ms = 30000 }, done)
    if not ok then done({ ok = false }) end
  end
  local spawn = options.spawn or function(argv, ended)
    local ok, child = pcall(morf.process.spawn, { command = argv, detached = true,
      on_stderr = function() end, on_exit = function() ended() end })
    if not ok or not child then ended() end
  end
  local droid = { phase = morf.signal("eva.waydroid.phase." .. tostring(options), "off") }

  --- Reads what it is doing, unless it is on its way.
  function droid.check()
    if droid.phase:get() == "starting" or droid.phase:get() == "stopping" then return end
    run({ "waydroid", "status" }, function(result)
      local phase = droid.phase:get()
      if phase == "starting" or phase == "stopping" then return end
      droid.phase:set(M.parse(result and result.stdout))
    end)
  end

  --- Whether it is running or on its way.
  function droid.on()
    local phase = droid.phase:get()
    return phase == "on" or phase == "starting"
  end

  --- Starts or stops the session.
  function droid.set(on)
    if on then
      droid.phase:set("starting")
      spawn({ "waydroid", "session", "start" }, function()
        droid.phase:set("off")
        droid.check()
      end)
      -- `session start` runs as long as the session: its status says when it is up.
      morf.time.timer(M.BOOT, function()
        if droid.phase:get() ~= "starting" then return end
        run({ "waydroid", "status" }, function(result)
          if droid.phase:get() == "starting" and M.parse(result and result.stdout) == "on" then droid.phase:set("on") end
        end)
      end, false)
      return
    end
    droid.phase:set("stopping")
    run({ "waydroid", "session", "stop" }, function()
      droid.phase:set("off")
    end)
  end

  --- The phase in a word for a tile.
  function droid.status()
    return ({ starting = "Starting…", stopping = "Stopping…", on = "Running" })[droid.phase:get()] or "Off"
  end

  return droid
end

M.BOOT = 8000

return M
