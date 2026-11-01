-- What the web and the machine's word tools answer: translations, definitions,
-- Wikipedia, and bookmarks. Each asks once the typing has paused.
local morf = require("morf")
local config = require("config")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")
local translate = require("lib.services.translate")

local M = {}

local row, note = rows.row, rows.note

--- Asks `url` for JSON and hands it through `parse`.
local function ask_json(slot, question, url, parse)
  return rows.ask(slot, question, function(done)
    morf.http.get(url, { timeout_ms = 8000 }, function(r)
      local ok, body = pcall(function() return r.ok and r.json() end)
      if ok and body then
        local fine, value = pcall(parse, body)
        done(fine and value or { error = "It answered in a way I cannot read" })
      else
        done { error = "It could not be reached" }
      end
    end)
    return true
  end, { debounce_ms = 350 })
end

-- -------------------------------------------------------------- translate --

--- Splits "es hello world" into its target and its text; a text with no language
--- first goes to the setting `launcher.translate_to`.
function M.parse_translation(term)
  local first, rest = term:match("^(%S+)%s+(.+)$")
  local code = first and translate.language(first)
  if code then return code, rest end
  return config.get("launcher.translate_to"), term
end

local function translated(target, text)
  local engine = translate.detecting()
  local request = { text = text, source = "auto", target = target }
  local why = translate.refusal(engine, request)
  if why then return { error = why } end
  return rows.ask("translate", target .. ":" .. text, function(done)
    translate.send(engine, request, function(words, reason)
      done(words and { text = words } or { error = reason })
    end)
    return true
  end, { debounce_ms = 350 })
end

local function title_of(target) return (translate.name_of(target) or target):lower() end

registry.mode { id = "translate", name = "Translate", material = "translate", shape = "soft_burst",
  words = { "translate", "tr" }, hint = "tr es hello  ·  tr french good morning",
  search = function(term)
    if term == "" then return { note("translate", "Type what to translate", "tr es hello  ·  tr french good morning", "translate") } end
    local target, text = M.parse_translation(term)
    local answer = translated(target, text)
    if not answer then return { note("translate", "Translating…", text, "translate") } end
    if answer.error then return { note("translate", answer.error, text, "translate") } end
    local value = answer.text or ""
    local engine = require("web").engine("tr")
    return { row {
      id = "translate", name = value, description = title_of(target) .. "  ·  " .. text .. "  ·  Return copies",
      material = "translate", copy = value, preview = { text = value, title = title_of(target) },
      run = function() return run.copy(value) end,
      actions = { { name = "Paste it", material = "content_paste_go", run = function()
        run.copy(value)
        run.paste()
        return "close"
      end }, engine and { name = "Open in " .. engine.name, material = "open_in_new",
        run = function() return run.browse(require("web").search_url(engine, text)) end } or nil },
    } }
  end }

-- ------------------------------------------------------------- dictionary --

--- The meanings in dictionaryapi.dev's answer: `{ part, text }` each.
function M.parse_definitions(body)
  local out = {}
  for _, entry in ipairs(body) do
    for _, meaning in ipairs(entry.meanings or {}) do
      for _, definition in ipairs(meaning.definitions or {}) do
        out[#out + 1] = { part = meaning.partOfSpeech or "", text = definition.definition or "" }
      end
    end
  end
  return out
end

local function definitions(word)
  local question = word:lower()
  if run.has("dict") then
    return rows.ask_run("define", question, { "dict", "--", word }, function(stdout)
      local out = {}
      for line in stdout:gmatch("[^\n]+") do
        local text = line:match("^%s+(.+)$")
        if text and not text:match("^%d+ definition") and not text:match("^From ") then out[#out + 1] = { part = "", text = text } end
      end
      return out
    end, { debounce_ms = 300, any_exit = true })
  end
  return ask_json("define", question, "https://api.dictionaryapi.dev/api/v2/entries/en/" .. morf.encoding.url_encode(word),
    M.parse_definitions)
end

registry.mode { id = "define", name = "Dictionary", material = "dictionary", shape = "pill", words = { "define", "dict", "meaning" },
  hint = "define ephemeral", search = function(term)
    if term == "" then return { note("define", "Type a word", "Its meanings", "dictionary") } end
    local found = definitions(term)
    if not found then return { note("define", "Looking it up…", term, "dictionary") } end
    if found.error then return { note("define", found.error, term, "dictionary") } end
    local out = {}
    for i, d in ipairs(found) do
      out[#out + 1] = rows.copy("define:" .. i, d.text, d.part ~= "" and (term .. "  ·  " .. d.part) or term, "dictionary")
      out[#out].preview = { text = d.text, title = term }
      if #out >= 12 then break end
    end
    if #out == 0 then out[1] = note("define", "No such word here", term, "dictionary") end
    return out
  end }

-- -------------------------------------------------------------- wikipedia --

registry.mode { id = "wiki", name = "Wikipedia", material = "public", shape = "pill", words = { "wiki", "wikipedia" },
  hint = "wiki linux  ·  a summary, here", search = function(term)
    if term == "" then return { note("wiki", "Type a subject", "A summary, here", "public") } end
    local language = config.get("launcher.wiki_language")
    local url = "https://" .. language .. ".wikipedia.org/api/rest_v1/page/summary/" .. morf.encoding.url_encode(term)
    local page = ask_json("wiki", term, url, function(body)
      return { title = body.title, text = body.extract, url = body.content_urls and body.content_urls.desktop.page }
    end)
    if not page then return { note("wiki", "Looking…", term, "public") } end
    if page.error then return { note("wiki", page.error, term, "public") } end
    local link = page.url
    return { row {
      id = "wiki", name = page.title or term, description = page.text or "", material = "public", copy = page.text,
      preview = { text = page.text or "", title = page.title }, auto_preview = true,
      run = function() return link and run.browse(link) or "keep" end,
      actions = { { name = "Copy the summary", material = "content_copy", run = function() return run.copy(page.text or "") end } },
    } }
  end }

-- -------------------------------------------------------------- bookmarks --

local library = require("lib.shell.launcher.bookmarks")

local function tool_dir() return rows.untilde(config.get("launcher.menus.bookmarks")) end

local NONE = {}

--- Every bookmark, off the loop, kept a minute.
function M.bookmarks()
  local list = rows.ask("bookmarks", "all", function(done) return library.read(tool_dir(), done) end,
    { debounce_ms = 0, ttl_ms = 60000 })
  return list or NONE
end

--- `mark` as a row.
function M.mark_row(mark)
  return row {
    id = "mark:" .. mark.url, name = mark.name, description = mark.url, material = "bookmark", tag = "Bookmark",
    pin = "url:" .. mark.url, copy = mark.url, keywords = mark.folder,
    run = function() return run.browse(mark.url) end,
    actions = { { name = "Copy the address", material = "content_copy", run = function() return run.copy(mark.url) end } },
  }
end

registry.mode { id = "bookmarks", name = "Bookmarks", material = "bookmark", shape = "pill", words = { "mark", "marks", "bookmark", "bookmarks" },
  hint = "mark rust book  ·  mark add https://… a name", search = function(term)
    local url, name = term:match("^add%s+(%S+)%s*(.*)$")
    if url then
      return { row { id = "mark:add", name = "Add “" .. (name ~= "" and name or url) .. "”", description = url, material = "bookmark_add",
        run = function()
          local list = {}
          for i, mark in ipairs(config.get("launcher.bookmarks")) do list[i] = mark end
          list[#list + 1] = { name = name ~= "" and name or url, url = url, folder = "" }
          config.set("launcher.bookmarks", list)
          rows.ask.forget("bookmarks")
          return "close"
        end } }
    end
    local out = {}
    for _, mark in ipairs(rows.fuzzy(M.bookmarks(), term, { "name", { "url", 0.5 } })) do
      out[#out + 1] = M.mark_row(mark)
      if #out >= 60 then break end
    end
    if #out == 0 then out[1] = note("bookmarks", "No bookmarks found", "From Firefox, Chromium and launcher.bookmarks", "bookmark") end
    return out
  end }

registry.mode { id = "links", name = "Quick links", material = "link", shape = "pill", words = { "link", "links" },
  hint = "link docs  ·  your saved addresses, with {query}", search = function(term)
    local first, rest = term:match("^(%S+)%s*(.*)$")
    local out = {}
    for _, link in ipairs(config.get("launcher.quicklinks")) do
      if type(link) == "table" and link.name and link.url then
        local wants = link.url:find("{query}", 1, true) ~= nil
        local matches = term == "" or link.name:lower():find((first or ""):lower(), 1, true)
        if matches then
          local arg = (first and link.name:lower():find(first:lower(), 1, true)) and rest or ""
          out[#out + 1] = row { id = "link:" .. link.name, name = link.name, description = link.url, material = "link", tag = "Link",
            complete = wants and ("> link " .. link.name .. " ") or nil,
            run = function()
              if wants and arg == "" then return "> link " .. link.name .. " " end
              local url = link.url:gsub("{query}", function() return morf.encoding.url_encode(arg) end)
              return run.browse(url)
            end }
        end
      end
    end
    if #out == 0 then out[1] = note("links", "No quick links", "Set launcher.quicklinks: { name, url }", "link") end
    return out
  end }

return M
