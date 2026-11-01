-- Word lists for prediction, offline: shell/assets/words/<language>.txt, one
-- word a line, the most common first, and `typed>word` lines for the slips a
-- list corrects. A list of the person's own at
-- $XDG_DATA_HOME/eva/words/<language>.txt comes before it.
--
--   local words = require("lib.shell.words")
--   words.load("en")                  -- read in pieces, off the frame
--   words.complete("en", "th", 3)     -- { "the", "this", "that" }
--   words.fix("en", "wierd", 2)       -- { "weird" }
--   words.known("en", "weird")        -- true
--
-- `words.revision` moves when a list has finished loading.

local morf = require("morf")
local unicase = require("lib.util.unicase")

local M = { revision = morf.signal("eva.words.revision", 0) }

local PIECE = 300
local books = {}

local function shipped(language) return morf.paths.shell("assets/words/" .. language .. ".txt") end
local function own(language)
  local home = morf.env("XDG_DATA_HOME")
  if not home or home == "" then home = morf.fs.home() .. "/.local/share" end
  return home .. "/eva/words/" .. language .. ".txt"
end

-- The first `n` characters of `text`.
local function head(text, n)
  local stop = utf8.offset(text, n + 1)
  return stop and text:sub(1, stop - 1) or text
end

local function bucket(book, key, n)
  local list = book.buckets[key]
  if not list then
    list = {}
    book.buckets[key] = list
  end
  list[#list + 1] = n
end

local function add(book, line)
  if line:sub(1, 1) == "#" then return end
  local typed, target = line:match("^(.-)>(.+)$")
  if typed then
    book.fixes[unicase.fold(typed)] = target
    return
  end
  local folded = unicase.fold(line)
  if book.rank[folded] then return end
  local n = #book.list + 1
  book.list[n], book.folded[n], book.rank[folded] = line, folded, n
  bucket(book, head(folded, 1), n)
  bucket(book, head(folded, 2), n)
end

local function read(path)
  if not morf.fs.exists(path) then return "" end
  local ok, text = pcall(morf.fs.read, path)
  return ok and text or ""
end

--- Starts reading `language`'s list, once; it is ready a few turns later.
function M.load(language)
  if books[language] then return end
  local book = { list = {}, folded = {}, rank = {}, buckets = {}, fixes = {}, ready = false }
  books[language] = book
  morf.time.timer(1, function()
    local lines = (read(own(language)) .. "\n" .. read(shipped(language))):gmatch("[^\n]+")
    local function step()
      for _ = 1, PIECE do
        local line = lines()
        if not line then
          book.ready = true
          M.revision:set(M.revision:get() + 1)
          return
        end
        add(book, line)
      end
      morf.time.timer(1, step, false)
    end
    step()
  end, false)
end

local function ready(language)
  local book = books[language]
  return book and book.ready and book or nil
end

--- Whether `language`'s list has loaded and holds any word.
function M.ready(language)
  local book = ready(language)
  return book ~= nil and #book.list > 0
end

--- Whether `word` is in `language`'s list.
function M.known(language, word)
  local book = ready(language)
  return book ~= nil and book.rank[unicase.fold(word)] ~= nil
end

--- The most common words that `typed` begins, at most `limit`, `typed` itself left out.
function M.complete(language, typed, limit)
  local book, out = ready(language), {}
  if not book or typed == "" then return out end
  local want = unicase.fold(typed)
  local list = book.buckets[head(want, 2)]
  if not list then return out end
  for _, n in ipairs(list) do
    local folded = book.folded[n]
    if folded ~= want and folded:sub(1, #want) == want then
      out[#out + 1] = book.list[n]
      if #out >= limit then break end
    end
  end
  return out
end

-- Whether `a` and `b` differ by one edit: a letter changed, missing, extra, or
-- two letters swapped.
local function near(a, b)
  local la, lb = #a, #b
  if la - lb > 1 or lb - la > 1 then return false end
  local i = 1
  while i <= la and i <= lb and a:byte(i) == b:byte(i) do i = i + 1 end
  if i > la and i > lb then return false end
  if la > lb then return a:sub(i + 1) == b:sub(i) end
  if lb > la then return a:sub(i) == b:sub(i + 1) end
  if a:sub(i + 1) == b:sub(i + 1) then return true end
  return a:byte(i) == b:byte(i + 1) and a:byte(i + 1) == b:byte(i) and a:sub(i + 2) == b:sub(i + 2)
end

--- What `typed` was probably meant to be, the likeliest first, at most `limit`.
function M.fix(language, typed, limit)
  local book, out = ready(language), {}
  if not book or typed == "" then return out end
  local want = unicase.fold(typed)
  if book.fixes[want] then out[1] = book.fixes[want] end
  local list = book.buckets[head(want, 1)]
  for _, n in ipairs(list or {}) do
    if #out >= limit then break end
    if near(want, book.folded[n]) then out[#out + 1] = book.list[n] end
  end
  return out
end

--- Forgets a loaded list, so the next load reads it again.
function M.forget(language) books[language] = nil end

return M
