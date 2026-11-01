-- What the launcher answers besides its prefixes: a word and what follows it,
-- and pages the system list opens. Each row is a launcher row (providers.lua).
--
--   ai <question>    asks the assistant
--   note <text>      adds a line to the quick notes
local M = {}

local function row(t)
  t.kind = "menu"
  return t
end

local WORDS = {
  ai = function(rest)
    local assistant = require("assistant_model")
    return row { id = "word:ai", name = rest, material = "auto_awesome",
      description = "Ask the assistant  ·  " .. assistant.summary(),
      run = function() assistant.ask(rest) return "close" end }
  end,
  note = function(rest)
    return row { id = "word:note", name = rest, material = "sticky_note_2",
      description = "Add to the quick notes",
      run = function() require("notes_model").quick(rest) return "close" end }
  end,
}

--- The rows for a query that starts with a word of `WORDS`, or nil.
function M.search(query)
  local word, rest = query:match("^(%a+)%s+(%S.*)$")
  local answer = word and WORDS[word:lower()]
  if answer then return { answer(rest) } end
  return nil
end

--- Pages for the system list (`!`), in the shape that list keeps.
function M.system()
  local function page(id, name, material)
    return { id = id, name = name, material = material,
      run = function() require("pages").open(id) return "close" end }
  end
  return { page("drop", "Drop", "forum"), page("notes", "Notes", "sticky_note_2"), page("phone", "Phone", "smartphone") }
end

return M
