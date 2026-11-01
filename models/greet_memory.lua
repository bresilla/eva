-- What the greeter keeps between logins: who came last, the session each person
-- chose, and the accessibility choices. A small file in the greeter's own state,
-- written only after a right password, and read with suspicion: a name no longer
-- on the machine is ignored. No password or anything of the session goes here.
--
-- EVA_GREETER_MEMORY names another file; EVA_GREETER_REMEMBER=0 turns it off.
local morf = require("morf")
local M = {}

local function path()
  local named = morf.env("EVA_GREETER_MEMORY")
  if named and named ~= "" then return named end
  local state = morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")
  return state .. "/eva/greeter.json"
end

local function enabled() return morf.env("EVA_GREETER_REMEMBER") ~= "0" end

function M.read()
  local ok, text = pcall(morf.fs.read, path())
  if not ok or type(text) ~= "string" then return {} end
  local fine, value = pcall(morf.json.decode, text)
  return fine and type(value) == "table" and value or {}
end

local function save(value)
  pcall(morf.fs.write, path(), morf.json.encode(value), { atomic = true, parents = true, mode = 384 })
end

--- `user` logged in, into the session with id `session`.
function M.remember(user, session)
  if not enabled() or not user or user == "" then return end
  local value = M.read()
  value.user = user
  value.sessions = type(value.sessions) == "table" and value.sessions or {}
  value.sessions[user] = session
  save(value)
end

--- The accessibility choices, a table of booleans.
function M.access()
  local kept = M.read().access
  return type(kept) == "table" and kept or {}
end
function M.set_access(values)
  local value = M.read()
  value.access = values
  save(value)
end

--- Where `people` (each with `name`) has the one who came last, or nil.
function M.who(people)
  if not enabled() then return nil end
  local user = M.read().user
  for index, person in ipairs(people) do
    if person.name == user then return index end
  end
  return nil
end

--- Where `list` (each with `id`) has the session `user` chose last, or nil.
function M.which(list, user)
  if not enabled() then return nil end
  local sessions = M.read().sessions
  local id = type(sessions) == "table" and sessions[user] or nil
  for index, session in ipairs(list) do
    if session.id == id then return index end
  end
  return nil
end

return M
