-- What a verb of the shell answered, as the verb returned it: `morf ipc call`
-- wraps it in a list, a table in it as a JSON string.
--
--     sys.shell({ "awake", "state" }, { read = true }, function(answer)
--       local state = require("lib.util.reply")(answer)
--     end)
local morf = require("morf")

return function(answer)
  if type(answer) ~= "table" then return answer end
  local value = answer[1]
  if type(value) ~= "string" then return value end
  local ok, decoded = pcall(morf.json.decode, value)
  if ok then return decoded end
  return value
end
