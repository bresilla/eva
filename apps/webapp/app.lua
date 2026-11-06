-- eva-webapp's jobs, with no window: `add NAME URL [--icon FILE]`, `list`,
-- `remove NAME`. The list and the form are a page of the Tools window
-- (page.lua). EVA_FAKE_WEBAPP=1 puts a stand-in where the web would be.
local morf = require("morf")
local job = require("lib.util.job")

if morf.env("EVA_FAKE_WEBAPP") == "1" then require("apps.webapp.fake").install() end
job.quiet()
require("apps.webapp.model").job(morf.args, job.finish)
