-- What the strip above the keys offers for the word at the cursor: the person's
-- shortcuts, a date for a keyword, a correction, completions, an emoji by name.
-- Each is `{ kind, text, label }`; `kind` is shortcut, keyword, fix, word or emoji.
local morf = require("morf")
local config = require("config")
local model = require("keyboard_model")
local unicase = require("lib.util.unicase")
local words = require("lib.shell.words")
local learn = require("keyboard_learn")

local M = {}

M.SLOTS = 3

local KEYWORDS = {
  today = function() return morf.time.format("%Y-%m-%d") end,
  date = function() return morf.time.format("%d %B %Y") end,
  now = function() return morf.time.format("%H:%M") end,
}

-- `word` in the case `typed` was typed in.
local function cased(typed, word)
  local chars = unicase.chars(typed)
  if #chars == 0 then return word end
  local lead = chars[1]
  local capital = unicase.upper(lead) == lead and unicase.lower(lead) ~= lead
  if not capital then return word end
  if #chars > 1 and unicase.upper(typed) == typed then return model.upper(word) end
  local first = unicase.chars(word)
  if #first == 0 then return word end
  first[1] = model.upper(first[1])
  return table.concat(first)
end

local function shortcut(word)
  local want = unicase.lower(word)
  for _, pair in ipairs(config.get("keyboard.replacements")) do
    if type(pair) == "table" and unicase.lower(tostring(pair[1])) == want then return tostring(pair[2]) end
  end
end

--- What `word` expands to, if the person set it up.
M.shortcut = shortcut

--- The list `layout` predicts from, when it has one and it is switched on.
local function list_of(layout)
  if layout.words and config.get("keyboard.predict") == true then return layout.words end
end

--- Starts loading the word list in use.
function M.prepare()
  local list = list_of(model.layout())
  if list then words.load(list) end
end

--- What to offer now, for the board `mode`.
function M.offers(mode)
  if not model.aids(mode) then return {} end
  local word = model.word()
  if word == "" or utf8.len(word) > 32 then return {} end
  local out, seen = {}, {}
  local function offer(kind, text, label)
    if #out >= M.SLOTS or seen[text] then return end
    seen[text] = true
    out[#out + 1] = { kind = kind, text = text, label = label or text }
  end
  local expanded = shortcut(word)
  if expanded then offer("shortcut", expanded) end
  if config.get("keyboard.keywords") == true then
    local keyword = KEYWORDS[word:lower()]
    if keyword then offer("keyword", keyword()) end
  end
  local list = list_of(model.layout())
  local completed = {}
  if list then
    for _, found in ipairs(learn.complete(word, M.SLOTS)) do completed[#completed + 1] = found end
    for _, found in ipairs(words.complete(list, word, M.SLOTS)) do completed[#completed + 1] = found end
    if #completed == 0 and utf8.len(word) >= 3 and not words.known(list, word) then
      for _, found in ipairs(words.fix(list, word, M.SLOTS)) do offer("fix", cased(word, found)) end
    end
  end
  local emoji = config.get("keyboard.emoji_names") == true and utf8.len(word) >= 3
    and require("lib.shell.emoji").named(word, 1)[1]
  local room = M.SLOTS - #out - (emoji and 1 or 0)
  for i = 1, math.min(room, #completed) do offer("word", cased(word, completed[i])) end
  if emoji then offer("emoji", emoji.char) end
  return out
end

--- The correction space would make to `word`, if any.
function M.correction(word)
  local list = list_of(model.layout())
  if not list or utf8.len(word) < 2 or words.known(list, word) or learn.known(word) then return nil end
  local found = words.fix(list, word, 1)[1]
  return found and cased(word, found) or nil
end

return M
