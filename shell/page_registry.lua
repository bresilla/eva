-- A book of pages for one of the shell's windows (Settings, Tools): each page's
-- route, name, icon, the words it is found by and the category its home files
-- it under, and the lists and the search over them. Plain data, no nodes and
-- no signals, so anything may read it.
--
--   local book = require("page_registry").new { HOME = "home", CATEGORIES = {...}, PAGES = {...} }
--   book.list()             -- { { key, name, icon, keywords } }, every page
--   book.entries()          -- those, and each item a page holds
--   book.search("repeat")   -- entries matching, best first
--
-- A page is `{ key, name, icon, category, parent, summary, keywords, items }`;
-- `items` are what a page holds, each `{ name, keywords }`, found on their own.
local M = {}

local function row(page)
  local words = { page.keywords or "" }
  for _, item in ipairs(page.items or {}) do words[#words + 1] = item[1]:lower() .. " " .. (item[2] or "") end
  return { key = page.key, name = page.name, icon = page.icon, keywords = table.concat(words, " ") }
end

--- How well `entry` answers the lowered `words`: higher is better, 0 is not
--- at all. Every word must match.
local function score(entry, words)
  local name, keywords = entry.name:lower(), entry.keywords:lower()
  local total = 0
  for _, word in ipairs(words) do
    if name:sub(1, #word) == word then total = total + 8
    elseif name:find(" " .. word, 1, true) then total = total + 6
    elseif name:find(word, 1, true) then total = total + 4
    elseif keywords:find(word, 1, true) then total = total + 2
    else return 0 end
  end
  return total + (entry.page and 0 or 1)
end

--- Completes `book` (`HOME`, `CATEGORIES`, `PAGES`): a page for each category
--- under the home, `BY_KEY`, and the functions below. Returns it.
function M.new(book)
  for _, category in ipairs(book.CATEGORIES) do
    category.key = book.HOME .. "/" .. category.id
    book.PAGES[#book.PAGES + 1] = { key = category.key, name = category.name, icon = category.icon, parent = book.HOME }
  end
  book.BY_KEY = {}
  for _, page in ipairs(book.PAGES) do book.BY_KEY[page.key] = page end

  --- The category's pages, in order.
  function book.category(id)
    local out = {}
    for _, page in ipairs(book.PAGES) do
      if page.category == id then out[#out + 1] = page end
    end
    return out
  end

  --- Every page as `{ key, name, icon, keywords }`.
  function book.list()
    local out = {}
    for _, page in ipairs(book.PAGES) do
      if page.key ~= book.HOME then out[#out + 1] = row(page) end
    end
    return out
  end

  --- Every page and every item a page holds, each `{ key, name, icon,
  --- keywords, page }`: `page` names the page an item is on, nil for a page.
  function book.entries()
    local out = {}
    for _, page in ipairs(book.PAGES) do
      if page.key ~= book.HOME then
        out[#out + 1] = row(page)
        for _, item in ipairs(page.items or {}) do
          out[#out + 1] = { key = page.key, name = item[1], icon = page.icon, keywords = item[2] or "", page = page.name,
            present = item.present }
        end
      end
    end
    return out
  end

  --- The entries matching `query`, best first.
  function book.search(query)
    local words = {}
    for word in tostring(query or ""):lower():gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return {} end
    local found = {}
    for index, entry in ipairs(book.entries()) do
      local value = score(entry, words)
      if value > 0 then found[#found + 1] = { entry = entry, score = value, index = index } end
    end
    table.sort(found, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return a.index < b.index
    end)
    local out = {}
    for index, hit in ipairs(found) do out[index] = hit.entry end
    return out
  end

  return book
end

return M
