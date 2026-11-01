-- A windowless job: no surface anyone sees, and an answer to whoever started it.
-- EVA_JOB_OUT names the file the answer goes to, the exit status on the first
-- line and the words after it, which is what `eva_relay` of apps/common/cli.sh
-- prints.
--
--     local job = require("lib.util.job")
--     job.quiet()
--     require("model").job(morf.args, job.finish)
local morf = require("morf")
local ui = require("morf.ui")

local M = {}

--- The configuration's own surface out of the way.
function M.quiet()
  ui.Item { width = 1, height = 1 }
  morf.surface.layer = "background"
  morf.surface.width, morf.surface.height = 1, 1
  morf.surface.exclusive_zone = 0
  morf.surface.keyboard_focus = "none"
end

--- Ends the job with `text`, or failed with `why`.
function M.finish(text, why)
  local out = morf.env("EVA_JOB_OUT")
  if out then
    morf.fs.write(out, ("%d\n%s\n"):format(text and 0 or 1, tostring(text or why or "")), { mode = 384 })
  end
  morf.quit()
end

return M
