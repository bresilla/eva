-- Desktop Entry files as text, for the tools that read and write them: the
-- spec's escaping, the keys of the `[Desktop Entry]` group, one key changed with
-- the rest of the file left as it was.
local M = {}

local GROUP = "[Desktop Entry]"

--- `value` as a string key holds it.
function M.escape(value)
  return (tostring(value):gsub("\\", "\\\\"):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r"))
end

local UNESCAPED = { ["\\"] = "\\", n = "\n", t = "\t", r = "\r", s = " " }

--- The string a key's value says.
function M.unescape(value)
  return (value:gsub("\\(.)", function(char) return UNESCAPED[char] or ("\\" .. char) end))
end

--- One word of an `Exec` line: `%` doubled, quoted where it holds a reserved
--- character.
function M.exec_word(word)
  local plain = tostring(word):gsub("%%", "%%%%")
  if plain:match("^[%w%-_./:=+,@%%]+$") then return plain end
  return '"' .. plain:gsub('[\\"`$]', "\\%0") .. '"'
end

--- `words` as an `Exec` line, for `M.set`.
function M.exec(words)
  local out = {}
  for index, word in ipairs(words) do out[index] = M.exec_word(word) end
  return table.concat(out, " ")
end

--- The keys of the file's `[Desktop Entry]` group, unescaped. Translated keys
--- are left out.
function M.parse(text)
  local keys, inside = {}, false
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\r?\n") do
    local group = line:match("^%[(.-)%]%s*$")
    if group then
      inside = line:match("^%s*(.-)%s*$") == GROUP
    elseif inside and not line:match("^%s*#") then
      local key, value = line:match("^([%w%-]+)%s*=%s*(.*)$")
      if key then keys[key] = M.unescape(value) end
    end
  end
  return keys
end

-- The lines of `text`, and where the group's own lines end.
local function lines_of(text)
  local lines, last, inside = {}, nil, false
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
    local group = line:match("^%[(.-)%]%s*$")
    if group then inside = line:match("^%s*(.-)%s*$") == GROUP end
    if inside and line ~= "" then last = #lines end
  end
  while lines[#lines] == "" do lines[#lines] = nil end
  return lines, last
end

--- `text` with `key` set to `value`, or left out where `value` is nil.
function M.set(text, key, value)
  local lines, last = lines_of(text)
  local inside, found = false, false
  local out = {}
  for index, line in ipairs(lines) do
    local group = line:match("^%[(.-)%]%s*$")
    if group then inside = line:match("^%s*(.-)%s*$") == GROUP end
    local here = inside and line:match("^([%w%-]+)%s*=") == key
    if here then
      if value ~= nil and not found then out[#out + 1] = key .. "=" .. M.escape(value) end
      found = true
    else
      out[#out + 1] = line
    end
    if index == last and not found and value ~= nil then
      out[#out + 1] = key .. "=" .. M.escape(value)
      found = true
    end
  end
  if not last and value ~= nil then
    out[#out + 1] = GROUP
    out[#out + 1] = key .. "=" .. M.escape(value)
  end
  return table.concat(out, "\n") .. "\n"
end

return M
