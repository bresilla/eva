-- eva-phone's jobs: `import FILE` and `export FILE` carry vCards in and out of
-- the contacts, and end. The dialler is a page of the Tools window (page.lua).
local morf = require("morf")
local contacts = require("lib.services.contacts")
local config = require("config")

local how, file = morf.operands[1], morf.operands[2] or ""
local book = contacts.open {
  folder = morf.env("EVA_CONTACTS") or config.get("phone.contacts"), country = config.get("phone.country"),
}
if how == "import" or how == "export" then
  local count = book[how](file)
  morf.log("info", ("eva: %d contacts %sed"):format(count, how))
else
  morf.log("warn", "eva-phone: no job " .. tostring(how))
end
morf.time.timer(1, function() morf.quit() end, false)
require("morf.ui").Item { width = 1, height = 1 }
