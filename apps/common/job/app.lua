-- A command of the shell's own code with no window and no shell running:
--
--     morf app apps/common/job/app.lua -- NAME [ARGS]
--
-- NAME is a module below with a `job(args, done)`, the same code the shell runs
-- for the same thing. `done(text, why)` ends it. EVA_JOB_OUT names the file its
-- answer goes to: the exit status on the first line, the words after it.
local morf = require("morf")
local ui = require("morf.ui")

ui.Item { width = 1, height = 1 }
morf.surface.layer = "background"
morf.surface.width, morf.surface.height = 1, 1
morf.surface.exclusive_zone = 0
morf.surface.keyboard_focus = "none"

local JOBS = {
  nightlight = "lib.services.nightlight",
  battery = "lib.services.charge_limit",
  clock = "lib.services.alarm",
}

local function finish(text, why)
  local out = morf.env("EVA_JOB_OUT")
  if out then
    morf.fs.write(out, ("%d\n%s\n"):format(text and 0 or 1, tostring(text or why or "")), { mode = 384 })
  end
  morf.quit()
end

local module = JOBS[morf.operands[1]]
if not module then
  finish(nil, "no job " .. tostring(morf.operands[1]))
else
  local args = {}
  for index = 2, #morf.operands do args[#args + 1] = morf.operands[index] end
  require(module).job(args, finish)
end
