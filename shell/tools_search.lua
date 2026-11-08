-- Tools in the launcher's search: every page of shell/tools_registry.lua is an
-- entry, found by its name and its words, and what a page holds is one of its
-- own. Each opens the Tools window at its page; nothing of a tool loads first.
local index = require("lib.shell.launcher.search_index")

local M = {}

local function opener(key)
  return function()
    if not require("tools_model").request(key) then return "keep" end
    return "close"
  end
end

--- Registers every tool's page.
function M.register()
  local registry = require("tools_registry")
  for _, entry in ipairs(registry.entries()) do
    local page = registry.BY_KEY[entry.key]
    if entry.page then
      index.register { id = "tool:" .. entry.key .. ":" .. entry.name, name = entry.name, tag = "Tool",
        keywords = entry.keywords, description = "Tools  ·  " .. entry.page, material = entry.icon, kind = "menu",
        run = opener(entry.key) }
    elseif page.page then
      -- A tool counts as its own app did, among the apps.
      index.register { id = "tool:" .. entry.key, name = entry.name, tag = "Tool", keywords = entry.keywords,
        description = "Tools  ·  " .. page.summary, material = entry.icon, kind = "menu", boost = 1,
        run = opener(entry.key) }
    end
  end
end

return M
