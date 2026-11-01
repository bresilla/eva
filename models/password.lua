-- A password being typed at a login screen, one per controller. The text is a
-- plain local, never a signal; the screen reads only how many characters it
-- has. Lengths count characters, so a dot and a Backspace are one letter
-- however many bytes it takes in UTF-8.
local morf = require("morf")
local M = { LIMIT = 256 }

--- `text` without its last character.
function M.without_last(text)
  local stop = #text
  while stop > 1 and text:byte(stop) & 0xC0 == 0x80 do stop = stop - 1 end
  return text:sub(1, stop - 1)
end

--- How many characters `text` has.
function M.count(text)
  return utf8.len(text) or #text
end

--- `name` prefixes its signal, `dots` caps what the screen is told.
function M.new(name, dots)
  local value = ""
  local self = { typed = morf.signal(name .. ".typed", 0) }
  local function show() self.typed:set(math.min(M.count(value), dots)) end
  function self.add(text)
    if #value + #text > M.LIMIT then return false end
    value = value .. text
    show()
    return true
  end
  function self.erase()
    value = M.without_last(value)
    show()
  end
  function self.clear()
    value = ""
    self.typed:set(0)
  end
  function self.empty() return value == "" end
  --- The text, once: the field is empty after it, its dots stay on show
  --- until the verdict clears them.
  function self.take()
    local secret = value
    value = ""
    return secret
  end
  return self
end

return M
