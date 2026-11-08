-- eva-text's transforms on a command line, `eva-text base64 < file`: a job that
-- answers and ends. The scratchpad is a page of the Tools window (page.lua).
local morf = require("morf")
local job = require("lib.util.job")
local model = require("apps.text.model")

job.quiet()
model.job(morf.args, job.input(), job.finish)
