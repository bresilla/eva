-- Emoji by name: every one lib/shell/emoji/data.lua knows (Unicode's own names),
-- searched fuzzily.
--
--   local emoji = require("lib.shell.emoji")
--   for _, hit in ipairs(emoji.search("party", 20)) do print(hit.char, hit.name) end

local morf = require("morf")

local emoji = {}

local all -- { char, name } rows, read on first use

local function load()
  if all then return all end
  all = {}
  for i, row in ipairs(require("lib.shell.emoji.data")) do
    all[i] = { char = row[1], name = row[2] }
  end
  return all
end

local names -- word of a name to the rows holding it, made on first use

local function named_rows()
  if names then return names end
  names = {}
  for _, row in ipairs(load()) do
    for word in row.name:gmatch("%a+") do
      local rows = names[word]
      if not rows then
        rows = {}
        names[word] = rows
      end
      rows[#rows + 1] = row
    end
  end
  return names
end

--- The emoji with `word` among the words of its name, at most `limit`.
function emoji.named(word, limit)
  local rows = named_rows()[word:lower()] or {}
  local out = {}
  for i = 1, math.min(limit or #rows, #rows) do out[i] = rows[i] end
  return out
end

-- The sets a picker shows: a name, an icon and the code point ranges each holds.
emoji.GROUPS = {
  { id = "faces", name = "Faces", icon = "mood",
    ranges = { { 0x1F600, 0x1F64F }, { 0x1F910, 0x1F92F }, { 0x1F970, 0x1F97F }, { 0x1F9D0, 0x1F9DF } } },
  { id = "people", name = "People", icon = "emoji_people",
    ranges = { { 0x1F440, 0x1F4AA }, { 0x1F590, 0x1F596 }, { 0x1F930, 0x1F94F }, { 0x1F9B0, 0x1F9CF } } },
  { id = "nature", name = "Nature", icon = "emoji_nature",
    ranges = { { 0x1F300, 0x1F344 }, { 0x1F400, 0x1F43F }, { 0x1F980, 0x1F9AF } } },
  { id = "food", name = "Food", icon = "emoji_food_beverage",
    ranges = { { 0x1F345, 0x1F37F }, { 0x1F950, 0x1F96F }, { 0x1F9C0, 0x1F9CF } } },
  { id = "activity", name = "Activity", icon = "emoji_events",
    ranges = { { 0x1F380, 0x1F3FF }, { 0x26BD, 0x26F5 } } },
  { id = "travel", name = "Travel", icon = "emoji_transportation",
    ranges = { { 0x1F680, 0x1F6FF } } },
  { id = "objects", name = "Objects", icon = "emoji_objects",
    ranges = { { 0x1F4AB, 0x1F58F }, { 0x1F597, 0x1F5FF }, { 0x1F9E0, 0x1F9FF } } },
  { id = "symbols", name = "Symbols", icon = "emoji_symbols",
    ranges = { { 0x2190, 0x26BC }, { 0x26F6, 0x2BFF }, { 0x3000, 0x33FF }, { 0x1F100, 0x1F2FF } } },
}

local grouped -- group id to its rows, made on first use

--- The emoji of the group `id`, each `{ char, name }`.
function emoji.group(id)
  if not grouped then
    grouped = {}
    for _, group in ipairs(emoji.GROUPS) do grouped[group.id] = {} end
    for _, row in ipairs(load()) do
      local cp = utf8.codepoint(row.char)
      for _, group in ipairs(emoji.GROUPS) do
        local found = false
        for _, range in ipairs(group.ranges) do
          if cp >= range[1] and cp <= range[2] then found = true end
        end
        if found then
          local rows = grouped[group.id]
          rows[#rows + 1] = row
          break
        end
      end
    end
  end
  return grouped[id] or {}
end

--- The emoji whose names match `term`, best first, at most `limit`.
function emoji.search(term, limit)
  local list = load()
  local out = {}
  if (term or "") == "" then
    for i = 1, math.min(limit or #list, #list) do out[i] = list[i] end
    return out
  end
  for _, hit in ipairs(morf.text.fuzzy(term, list, { key = "name" })) do
    out[#out + 1] = hit.item
    if limit and #out >= limit then break end
  end
  return out
end

return emoji
