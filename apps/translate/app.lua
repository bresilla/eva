-- eva-translate with words: a job that translates them, answers and ends. The
-- translator itself is a page of the Tools window (page.lua), which sends
-- nothing until pressed.
local morf = require("morf")
local job = require("lib.util.job")
local model = require("apps.translate.model")

job.quiet()
model.load()
model.job(morf.args, job.input(), job.finish)
