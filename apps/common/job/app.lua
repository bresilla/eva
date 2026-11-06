-- A command of the shell's own code with no window and no shell running:
--
--     morf app apps/common/job/app.lua -- NAME [ARGS]
--
-- NAME is a module below with a `job(args, done, via)`, the same code the shell
-- runs for the same thing. `done(text, why)` ends it; `via` is common/sys.lua,
-- for a job that asks the running shell.
local morf = require("morf")
local job = require("lib.util.job")

job.quiet()

local JOBS = {
  nightlight = "lib.services.nightlight",
  battery = "lib.services.charge_limit",
  clock = "lib.services.alarm",
  audio = "sound_cli",
  displays = "displays_model",
  fonts = "fonts_model",
  startup = "apps_model",
  update = "system_updates",
}

-- Every word after `--`, a flag (`--check`) among them as it was given.
local words = morf.args or morf.operands
local module = JOBS[words[1]]
if not module then
  job.finish(nil, "no job " .. tostring(words[1]))
else
  local args = {}
  for index = 2, #words do args[#args + 1] = words[index] end
  require(module).job(args, job.finish, require("common.sys"))
end
