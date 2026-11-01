#!/usr/bin/env lua
-- Builds shell/assets/words/<language>.txt from a published word list: `#`
-- lines naming the source, the words most common first, then `typed>word`
-- lines for what a list says a slip should become.
--
--   lua tools/words.lua aosp   INPUT OUTPUT COUNT "SOURCE"  -- Android's .combined
--   lua tools/words.lua counts INPUT OUTPUT COUNT "SOURCE"  -- `word count` lines

local kind, input, output, count, source = arg[1], arg[2], arg[3], tonumber(arg[4]), arg[5]
if not (kind and input and output and count and source) then
  io.stderr:write("usage: words.lua aosp|counts INPUT OUTPUT COUNT SOURCE\n")
  os.exit(2)
end

-- Letters, an apostrophe or a hyphen: anything else is no word to offer.
local function plain(word)
  if word:find("[%z\1-\38\40-\44\46-\64\91-\96\123-\127]") then return false end
  return word:match("^[%a\128-\255]") ~= nil
end

local words, fixes = {}, {}

local function aosp()
  local last
  for line in io.lines(input) do
    local word = line:match("^ word=([^,]+),")
    local shortcut = line:match("^  shortcut=([^,]+),f=whitelist")
    if word then
      local f = tonumber(line:match(",f=(%d+)")) or 0
      local bad = line:find("possibly_offensive=true", 1, true) or line:find("flags=offensive", 1, true)
        or line:find("flags=nonword", 1, true)
      local hidden = line:find("not_a_word=true", 1, true)
      last = word
      if f > 0 and not bad and not hidden and plain(word) then
        words[#words + 1] = { word = word, f = f, order = #words }
      end
    elseif shortcut and last and last ~= shortcut then
      fixes[#fixes + 1] = last .. ">" .. shortcut
    end
  end
  table.sort(words, function(a, b)
    if a.f ~= b.f then return a.f > b.f end
    return a.order < b.order
  end)
end

local function counts()
  for line in io.lines(input) do
    local word, n = line:match("^(%S+) (%d+)$")
    if word and plain(word) then words[#words + 1] = { word = word } end
  end
end

if kind == "aosp" then aosp() elseif kind == "counts" then counts() else error("unknown kind " .. kind) end

local out = assert(io.open(output, "w"))
out:write("# ", source, "\n")
for i = 1, math.min(count, #words) do out:write(words[i].word, "\n") end
for _, fix in ipairs(fixes) do out:write(fix, "\n") end
out:close()
