-- The launcher's modes, by name: what a prefix or a word turns the search box
-- into. A plugin registers one just as the shell's own do.
--
--   registry.mode {
--     id = "ip", name = "Address", material = "public", words = { "ip" },
--     hint = "ip  ·  this machine's addresses",
--     search = function(term) return { { name = "127.0.0.1", run = ... } } end,
--   }
--
-- `id` (required), `name` and `material` (what the field's badge shows), `shape`
-- (the badge's shape), `prefix` (one character that opens it), `words` (what it
-- answers to after `>` or as the first word of a plain search), `hint`, `search`
-- (required: `search(term, query)` gives rows, and a view mode if not "apps").
-- A mode with `bare = false` answers only after `>`; `hidden = true` keeps it out
-- of the list of modes. Registering an `id` again replaces the mode.

local morf = require("morf")

local M = {}

M.MODES = {}
M.ORDER = {}
M.PREFIXES = {}
local words = {}

--- Moves whenever a mode comes or goes.
M.revision = morf.signal("eva.launcher.modes", 0)

--- Adds `mode`, or replaces the one with its `id`.
function M.mode(mode)
  assert(type(mode) == "table" and mode.id, "a launcher mode needs an id")
  assert(type(mode.search) == "function", "launcher mode " .. tostring(mode.id) .. " needs a search")
  local old = M.MODES[mode.id]
  if old then
    if old.prefix then M.PREFIXES[old.prefix] = nil end
    for _, word in ipairs(old.words or {}) do words[word] = nil end
  else
    M.ORDER[#M.ORDER + 1] = mode.id
  end
  mode.name = mode.name or mode.id
  mode.material = mode.material or "extension"
  M.MODES[mode.id] = mode
  if mode.prefix then M.PREFIXES[mode.prefix] = mode.id end
  for _, word in ipairs(mode.words or {}) do words[word:lower()] = mode end
  M.revision:set(M.revision:get() + 1)
end

--- The mode answering to `word`, or nil.
function M.by_word(word) return words[tostring(word):lower()] end

--- The modes in the order they came.
function M.list()
  local out = {}
  for _, id in ipairs(M.ORDER) do out[#out + 1] = M.MODES[id] end
  return out
end

local function action_prefix()
  local ok, value = pcall(function() return require("config").get("launcher.action_prefix") end)
  return ok and value or ">"
end
M.action_prefix = action_prefix

--- The mode `query` is in and the text meant for it, or nil for a plain
--- search: a prefix character, or the action prefix and a mode's word.
function M.route(query)
  local id = M.PREFIXES[query:sub(1, 1)]
  if id then return M.MODES[id], (query:sub(2):gsub("^%s+", "")) end
  local prefix = action_prefix()
  if query:sub(1, #prefix) ~= prefix then return nil end
  local rest = query:sub(#prefix + 1):gsub("^%s+", "")
  local word, after = rest:match("^(%S+)%s(.*)$")
  local mode = word and M.by_word(word)
  if mode then return mode, (after:gsub("^%s+", "")) end
  return nil
end

--- What to put in the field to enter `mode`.
function M.entry(mode)
  if mode.prefix then return mode.prefix end
  return action_prefix() .. " " .. tostring((mode.words or {})[1] or mode.id) .. " "
end

--- The mode a typed word is the start of: one word, no prefix, at least two
--- letters. Where several modes have a word beginning so, the one whose name
--- begins so; nil when that does not settle it.
function M.completing(text)
  local typed = text:lower():match("^(%a[%w-]+)$")
  if not typed then return nil end
  local found, named, several
  for _, id in ipairs(M.ORDER) do
    local mode = M.MODES[id]
    if not mode.hidden then
      for _, word in ipairs(mode.words or {}) do
        if word:sub(1, #typed) == typed then
          if found and found ~= mode then several = true end
          found = found or mode
          if mode.name:lower():sub(1, #typed) == typed then named = named or mode end
        end
      end
    end
  end
  if several then return named end
  return found
end

return M
