-- A private log several processes keep together: one JSON object a line,
-- appended, so the shell and a tool can each write without losing the other's
-- lines. A later line with the same `id` replaces the earlier one; `gone` drops
-- it. Each process follows the file.
--
--   local log = require("lib.services.journal").open { name = "calls" }
--   log.rows:get()        -- oldest first
--   log.put { id = "1", number = "+31..." }
--   log.remove("1")
--
-- `options.dir` names the folder, `$XDG_STATE_HOME/eva/phone` by default.
local morf = require("morf")

local M = {}

local PRIVATE = 384 -- 0600
local serial = 0

local function folder()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/phone"
end

function M.open(options)
  serial = serial + 1
  local path = (options.dir or folder()) .. "/" .. options.name .. ".jsonl"
  local log = { path = path, rows = morf.signal("eva.journal." .. options.name .. "." .. serial, {}) }

  local function read()
    local ok, text = pcall(morf.fs.read, path)
    local order, rows = {}, {}
    if ok and type(text) == "string" then
      for line in text:gmatch("[^\n]+") do
        local fine, row = pcall(morf.json.decode, line)
        if fine and type(row) == "table" and row.id ~= nil then
          if row.gone then rows[row.id] = nil
          else
            if rows[row.id] == nil then order[#order + 1] = row.id end
            rows[row.id] = row
          end
        end
      end
    end
    local list = {}
    for _, id in ipairs(order) do
      if rows[id] then list[#list + 1] = rows[id] end
    end
    log.rows:set(list)
  end

  local function append(row)
    morf.fs.write(path, morf.json.encode(row) .. "\n", { append = true, parents = true, mode = PRIVATE })
    read()
  end

  --- The row with `id`, or nil.
  function log.get(id)
    for _, row in ipairs(log.rows:get()) do
      if row.id == id then return row end
    end
  end

  --- Adds `row`, or replaces the row with its `id`.
  function log.put(row) append(row) end

  --- Changes the fields of `changes` on the row with `id`.
  function log.update(id, changes)
    local row = log.get(id)
    if not row then return false end
    for key, value in pairs(changes) do row[key] = value end
    append(row)
    return true
  end

  function log.remove(id) append { id = id, gone = true } end

  --- Empties it.
  function log.clear()
    morf.fs.write(path, "", { parents = true, mode = PRIVATE })
    read()
  end

  read()
  log.watch = morf.fs.watch(path, function() read() end)
  return log
end

return M
