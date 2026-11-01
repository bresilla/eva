-- Conversations on disk: one JSON file each, and an index of their titles,
-- under the state folder (`assistant.folder` names another). Nothing here
-- touches a key: those live in the Secret Service.
local morf = require("morf")
local config = require("config")
local M = {}

function M.folder()
  local chosen = config.get("assistant.folder")
  if type(chosen) == "string" and chosen ~= "" then return (morf.fs.expand(chosen)) end
  return morf.paths.state("assistant")
end

local function path_of(id) return M.folder() .. "/" .. id .. ".json" end
local function index_path() return M.folder() .. "/index.json" end

local function read_json(path)
  if not morf.fs.exists(path) then return nil end
  local ok, text = pcall(morf.fs.read, path)
  if not ok or type(text) ~= "string" then return nil end
  local fine, value = pcall(morf.json.decode, text)
  if fine and type(value) == "table" then return value end
end

-- Readable by this account alone.
local function write_json(path, value)
  return morf.fs.write(path, morf.json.encode(value), { mode = 384 })
end

--- The conversations, newest first: `{ id, title, updated }`.
function M.list()
  local rows = read_json(index_path()) or {}
  local out = {}
  for _, row in ipairs(rows) do
    if type(row) == "table" and type(row.id) == "string" and row.id:match("^[%w%-]+$") then out[#out + 1] = row end
  end
  table.sort(out, function(a, b) return (a.updated or 0) > (b.updated or 0) end)
  return out
end

--- One conversation, or nil.
function M.load(id)
  if type(id) ~= "string" or not id:match("^[%w%-]+$") then return nil end
  return read_json(path_of(id))
end

--- Writes `conversation`, and its line in the index.
function M.save(conversation)
  conversation.updated = morf.time.now()
  local ok, why = write_json(path_of(conversation.id), conversation)
  if not ok then return false, why end
  local rows = {}
  for _, row in ipairs(M.list()) do
    if row.id ~= conversation.id then rows[#rows + 1] = row end
  end
  rows[#rows + 1] = { id = conversation.id, title = conversation.title, updated = conversation.updated }
  return write_json(index_path(), rows)
end

--- Removes a conversation and its line in the index.
function M.remove(id)
  if type(id) ~= "string" or not id:match("^[%w%-]+$") then return false end
  pcall(morf.fs.remove, path_of(id))
  local rows = {}
  for _, row in ipairs(M.list()) do
    if row.id ~= id then rows[#rows + 1] = row end
  end
  write_json(index_path(), rows)
  return true
end

return M
