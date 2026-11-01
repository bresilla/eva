-- A windowless job: no surface anyone sees, what the command line piped in, and
-- an answer to whoever started it. EVA_JOB_OUT names the file the answer goes to,
-- the exit status on the first line and the words after it, which is what
-- `eva_relay` of apps/common/cli.sh prints. EVA_JOB_IN names the file holding
-- stdin, from `eva_tool_job_stdin`.
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

--- What the command line piped in, or nil. The file is gone once it is read.
function M.input()
  local path = morf.env("EVA_JOB_IN")
  if not path or path == "" then return nil end
  local ok, text = pcall(morf.fs.read, path)
  pcall(morf.fs.remove, path)
  return ok and text or nil
end

--- Ends the job with `text`, or failed with `why`. `raw` keeps `text` to the
--- byte, no newline added.
function M.finish(text, why, raw)
  local out = morf.env("EVA_JOB_OUT")
  if out and out ~= "" then
    local words = tostring(text or why or "")
    morf.fs.write(out, (text and 0 or 1) .. "\n" .. words .. (raw and "" or "\n"), { mode = 384 })
  end
  morf.quit()
end

return M
