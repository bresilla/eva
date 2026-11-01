-- The freedesktop trash in the data folder: how much is in it, and emptying it.
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

--- The trash's folder.
function M.root(home)
  local data = morf.env("XDG_DATA_HOME")
  if not data or data == "" then data = (home or morf.fs.home()) .. "/.local/share" end
  return data .. "/Trash"
end

--- `{ count, size }`: how many items, and the bytes `directorysizes` and the
--- files themselves account for.
function M.read(root)
  root = root or M.root()
  local ok, entries = pcall(morf.fs.list, root .. "/files")
  local list = ok and type(entries) == "table" and entries or {}
  local size = 0
  for _, entry in ipairs(list) do size = size + (tonumber(type(entry) == "table" and entry.size) or 0) end
  return { count = #list, size = size }
end

--- Empties it for good. `done(ok, why)`.
function M.empty(done, root)
  done = done or function() end
  root = root or M.root()
  if host.held("empty the trash") then return done(true) end
  if host.installed("gio") then
    return host.act({ "gio", "trash", "--empty" }, function(text, why) done(text ~= nil or nil, why) end)
  end
  for _, folder in ipairs { "/files", "/info", "/expunged" } do
    local ok, entries = pcall(morf.fs.list, root .. folder)
    for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
      pcall(morf.fs.remove, root .. folder .. "/" .. (type(entry) == "table" and entry.name or entry), { recursive = true })
    end
  end
  done(true)
end

return M
