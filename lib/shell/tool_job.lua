-- A tool's own job, run beside any window of it by `apps/launch TOOL ARGS`: what
-- it was handed on stdin, and the answer for its command line. The answer has
-- apps/common/job's form: EVA_JOB_OUT holds the exit status on the first line,
-- the words after it.
--
--     local job = require("lib.shell.tool_job")
--     job.finish("done")            -- ends the tool, status 0
--     job.finish(nil, "no such")    -- ends the tool, status 1
--     job.finish(bytes, nil, true)  -- no newline added
local morf = require("morf")

local M = {}

--- What the command line piped in, or nil. The file is gone once it is read.
function M.input()
  local path = morf.env("EVA_JOB_IN")
  if not path or path == "" then return nil end
  local ok, text = pcall(morf.fs.read, path)
  pcall(morf.fs.remove, path)
  return ok and text or nil
end

--- Answers the command line and ends the tool: `text`, or nil and `why`.
--- `raw` keeps `text` to the byte.
function M.finish(text, why, raw)
  local out = morf.env("EVA_JOB_OUT")
  if out and out ~= "" then
    local status = text and 0 or 1
    local words = tostring(text or why or "")
    morf.fs.write(out, status .. "\n" .. words .. (raw and "" or "\n"), { mode = 384 })
  end
  morf.quit()
end

return M
