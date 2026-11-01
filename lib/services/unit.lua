-- A systemd unit as a switch: found under the user's manager or the system's,
-- started, stopped, and whether it is running. A system unit asks polkit, and
-- the shell's agent asks the person.
--
--   local unit = require("lib.services.unit").new { unit = "syncthing.service" }
--   unit.find()                  -- then unit.found:get()
--   unit.set(true)
--
-- `phase` is "off", "starting", "on", "stopping" or "failed".
local morf = require("morf")

local M = {}

--- `options`: `unit`, `run(argv, done)` (a process).
function M.new(options)
  local name = options.unit
  local run = options.run or function(argv, done)
    local ok = pcall(morf.process.run, argv, { timeout_ms = 60000 }, done)
    if not ok then done({ ok = false }) end
  end
  local stamp = tostring(options)
  local unit = { found = morf.signal("eva.unit.found." .. stamp, false),
    phase = morf.signal("eva.unit.phase." .. stamp, "off") }
  local scope

  local function systemctl(...)
    local argv = { "systemctl" }
    if scope == "user" then argv[#argv + 1] = "--user" end
    for _, word in ipairs { ... } do argv[#argv + 1] = word end
    return argv
  end

  --- Reads whether it is running, unless it is on its way somewhere.
  function unit.check()
    if not scope then return end
    run(systemctl("is-active", name), function(result)
      local phase = unit.phase:get()
      if phase == "starting" or phase == "stopping" then return end
      local word = result and tostring(result.stdout or ""):match("%S+") or ""
      unit.phase:set(word == "active" and "on" or word == "failed" and "failed" or "off")
    end)
  end

  --- Looks for the unit, the user's first.
  function unit.find()
    scope = "user"
    run(systemctl("cat", name), function(result)
      if result and result.ok then
        unit.found:set(true)
        return unit.check()
      end
      scope = "system"
      run(systemctl("cat", name), function(again)
        local there = again ~= nil and again.ok == true
        if not there then scope = nil end
        unit.found:set(there)
        if there then unit.check() end
      end)
    end)
  end

  --- Whether it is running or on its way.
  function unit.on()
    local phase = unit.phase:get()
    return phase == "on" or phase == "starting"
  end

  --- Starts or stops it.
  function unit.set(on)
    if not scope then return end
    unit.phase:set(on and "starting" or "stopping")
    run(systemctl(on and "start" or "stop", name), function(result)
      if result and result.ok then
        unit.phase:set(on and "on" or "off")
      else
        morf.log("warn", ("eva: %s of %s failed: %s"):format(on and "start" or "stop", name,
          tostring(result and result.stderr)))
        unit.phase:set(on and "failed" or "on")
      end
    end)
  end

  --- The phase in a word for a tile.
  function unit.status()
    local phase = unit.phase:get()
    return ({ starting = "Starting…", stopping = "Stopping…", failed = "Could not start", on = "On" })[phase] or "Off"
  end

  return unit
end

return M
