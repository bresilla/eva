-- eva-pomodoro with a word: a job on the session that ends. The session itself
-- is a file and a timer in eva-clock's store, so it goes on with no window; the
-- dial is a page of the Tools window (page.lua).
local morf = require("morf")
local job = require("lib.util.job")
local model = require("apps.pomodoro.model")

job.quiet()
model.start_up(false, false)
model.job(morf.args[1], job.finish)
