-- Data Saver: NetworkManager's metered flag on the connection in use, through
-- nmcli. Programs that read the flag hold their background traffic back;
-- nothing here stops one that does not. What it marked it keeps a list of, and
-- puts back.
--
--   local saver = require("lib.services.datasaver").new { run = morf.process.run, marked = {} }
--   saver.follow(true, row)     -- row: an active connection's `{ uuid, devices }`
local M = {}

--- `options`: `run(argv, done)` (a process), `marked` (uuids from an earlier
--- run, to put back), `remember(list)` (keeps that list).
function M.new(options)
  local saver = {}
  local marked = {}
  for _, uuid in ipairs(options.marked or {}) do marked[uuid] = true end

  local function keep()
    if not options.remember then return end
    local list = {}
    for uuid in pairs(marked) do list[#list + 1] = uuid end
    table.sort(list)
    options.remember(list)
  end

  local function flag(uuid, value, devices)
    options.run({ "nmcli", "connection", "modify", uuid, "connection.metered", value }, function()
      for _, interface in ipairs(devices or {}) do
        options.run({ "nmcli", "device", "reapply", interface }, function() end)
      end
    end)
  end

  --- Whether anything stands marked.
  function saver.marking() return next(marked) ~= nil end

  --- On, marks `row` as it comes; off, puts back all it marked.
  function saver.follow(on, row)
    if on then
      if row and row.uuid ~= "" and not marked[row.uuid] then
        marked[row.uuid] = true
        flag(row.uuid, "yes", row.devices)
        keep()
      end
      return
    end
    if next(marked) == nil then return end
    for uuid in pairs(marked) do flag(uuid, "unknown", uuid == (row and row.uuid) and row.devices or nil) end
    marked = {}
    keep()
  end

  return saver
end

return M
