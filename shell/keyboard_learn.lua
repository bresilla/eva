-- Words the person typed, kept on disk to predict them later. Asleep unless
-- `keyboard.learn` is on, and never written while the keyboard is private: the
-- README says why it is off by default.
local morf = require("morf")
local config = require("config")
local model = require("keyboard_model")
local unicase = require("lib.util.unicase")

local M = {}

local LIMIT = 2000
local SAVE_AFTER = 2000

local function path() return morf.paths.state("eva-keyboard-words.json") end

local counts, saving

local function book()
  if counts then return counts end
  counts = {}
  local ok, list = pcall(function() return morf.json.decode(morf.fs.read(path())) end)
  if ok and type(list) == "table" then counts = list end
  return counts
end

local function save()
  saving = nil
  if config.get("keyboard.learn") ~= true then return end
  morf.fs.write(path(), morf.json.encode(book()), { atomic = true, parents = true, mode = 384 })
end

--- Counts `word` as typed, when learning is on and nothing is private.
function M.note(word)
  if config.get("keyboard.learn") ~= true or model.is_private() then return end
  if word == "" or utf8.len(word) < 2 or word:find("%d") then return end
  local list = book()
  if not list[word] then
    local size = 0
    for _ in pairs(list) do size = size + 1 end
    if size >= LIMIT then return end
  end
  list[word] = (list[word] or 0) + 1
  if not saving then saving = morf.time.timer(SAVE_AFTER, save, false) end
end

--- The learned words `typed` begins, the most typed first.
function M.complete(typed, limit)
  if config.get("keyboard.learn") ~= true or typed == "" then return {} end
  local want, found = unicase.fold(typed), {}
  for word, count in pairs(book()) do
    local folded = unicase.fold(word)
    if folded ~= want and folded:sub(1, #want) == want then found[#found + 1] = { word, count } end
  end
  table.sort(found, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[1] < b[1]
  end)
  local out = {}
  for i = 1, math.min(limit, #found) do out[i] = found[i][1] end
  return out
end

--- Whether `word` has been learned.
function M.known(word)
  return config.get("keyboard.learn") == true and book()[word] ~= nil
end

--- Forgets every word, on disk too.
function M.forget()
  if saving then saving:cancel() saving = nil end
  counts = {}
  if morf.fs.exists(path()) then pcall(morf.fs.remove, path()) end
end

return M
