-- eva-qr --png FILE ...: writes a code to a picture and ends. The code on
-- screen is a page of the Tools window (page.lua).
local morf = require("morf")
local job = require("lib.util.job")
local model = require("apps.qr.model")

job.quiet()
local png = model.take(morf.args, job.input())
if png then
  model.save(png, function(ok, words)
    if ok then job.finish(png) else job.finish(nil, words) end
  end)
else
  job.finish(nil, "usage: eva-qr --png FILE TEXT")
end
