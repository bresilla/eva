-- Text to reach for: snippets, kaomoji, gitmoji, spelling, and the installed fonts.
local morf = require("morf")
local registry = require("lib.shell.launcher.registry")
local rows = require("lib.shell.launcher.rows")
local run = require("lib.shell.launcher.run")
local snippets = require("lib.shell.launcher.snippets")

local M = {}

local row, note = rows.row, rows.note

local function first_clip()
  local store = require("lib.shell.clipboard.store")
  store.load()
  local item = store.items:get()[1]
  return item and item.text or ""
end

--- Fills `item` in and pastes it into the program that was in front.
local function paste(item)
  snippets.expand(item.text, first_clip(), function(text)
    run.copy(text)
    run.paste()
  end)
  return "close"
end

local function copy(item)
  snippets.expand(item.text, first_clip(), run.copy)
  return "close"
end

--- `item` as a row.
function M.snippet_row(item)
  return row {
    id = "snippet:" .. item.name, name = item.name, tag = "Snippet", material = "short_text", copy = item.text,
    description = (item.trigger and (item.trigger .. "  ·  ") or "") .. item.text:gsub("%s+", " "):sub(1, 120),
    preview = { text = item.text, title = item.name }, keywords = item.trigger,
    run = function() return paste(item) end,
    actions = {
      { name = "Paste it", material = "content_paste_go", run = function() return paste(item) end },
      { name = "Copy it", material = "content_copy", run = function() return copy(item) end },
      { name = "Edit it", material = "edit",
        run = function() return "> snip add " .. item.name .. (item.trigger and (" " .. item.trigger) or "") .. ": " .. item.text end },
      { name = "Delete it", material = "delete", run = function() snippets.remove(item.name) rows.bump() return "keep" end },
    },
  }
end

--- What `snip add` asks for: a name, an optional trigger, and the text.
function M.parse_snippet(term)
  local head, text = term:match("^add%s+([^:]+):%s*(.*)$")
  if not head then return nil end
  local name, trigger = head:match("^(.-)%s+(%p%S*)%s*$")
  if not name then name = head:match("^(.-)%s*$") end
  return name, text, trigger
end

registry.mode { id = "snippets", name = "Snippets", material = "short_text", shape = "pill", words = { "snip", "snippet", "snippets" },
  hint = "snip sig  ·  snip add sig ;sig: Kind regards", search = function(term)
    snippets.revision:get()
    local name, text, trigger = M.parse_snippet(term)
    if name and name ~= "" and text ~= "" then
      return { row { id = "snippet:new", name = "Keep “" .. name .. "”", material = "note_add",
        description = (trigger and ("Typing " .. trigger .. " expands it  ·  ") or "") .. text:sub(1, 80),
        run = function() snippets.add(name, text, trigger) return "close" end } }
    end
    if term:match("^add%s") or term == "add" then
      return { note("snippets", "Name it, then the text", "snip add sig ;sig: Kind regards, {date}", "note_add") }
    end
    local list = {}
    for _, item in ipairs(snippets.all()) do
      list[#list + 1] = { item = item, name = item.name, description = item.text }
    end
    local out = {}
    for _, found in ipairs(rows.fuzzy(list, term)) do out[#out + 1] = M.snippet_row(found.item) end
    if #out == 0 then out[1] = note("snippets", "No snippets yet", "snip add sig ;sig: Kind regards", "short_text") end
    return out
  end }

local KAOMOJI = {
  { "shrug", "¯\\_(ツ)_/¯" }, { "table flip", "(╯°□°)╯︵ ┻━┻" }, { "table back", "┬─┬ ノ( ゜-゜ノ)" }, { "lenny", "( ͡° ͜ʖ ͡°)" },
  { "disapproval", "ಠ_ಠ" }, { "happy", "(◕‿◕)" }, { "joy", "(＾▽＾)" }, { "love", "(♥‿♥)" }, { "cry", "(╥﹏╥)" },
  { "bear", "ʕ•ᴥ•ʔ" }, { "cat", "(=^･ω･^=)" }, { "dog", "▼・ᴥ・▼" }, { "sparkles", "(ﾉ◕ヮ◕)ﾉ*:･ﾟ✧" }, { "wave", "( ´ ▽ ` )ﾉ" },
  { "sleep", "(－_－) zzZ" }, { "angry", "(ノಠ益ಠ)ノ彡┻━┻" }, { "thumbs up", "(•̀ᴗ•́)و" }, { "hug", "(づ｡◕‿‿◕｡)づ" }, { "shock", "(⊙_⊙)" },
  { "cool", "(⌐■_■)" }, { "fight", "(ง •̀_•́)ง" }, { "dance", "♪┏(・o･)┛♪" }, { "cheers", "( ^_^)o自自o(^_^ )" }, { "sad", "(︶︹︺)" },
}

registry.mode { id = "kaomoji", name = "Kaomoji", material = "sentiment_very_satisfied", shape = "cookie9", words = { "kao", "kaomoji" },
  hint = "kao shrug", search = function(term)
    local list = {}
    for _, k in ipairs(KAOMOJI) do list[#list + 1] = { name = k[1], face = k[2], description = k[2] } end
    local out = {}
    for _, k in ipairs(rows.fuzzy(list, term, "name")) do
      out[#out + 1] = rows.copy("kao:" .. k.name, k.face, k.name, "sentiment_very_satisfied")
    end
    return out
  end }

local GITMOJI = {
  { "art", "🎨", "Improve structure" }, { "zap", "⚡", "Improve performance" }, { "fire", "🔥", "Remove code or files" },
  { "bug", "🐛", "Fix a bug" }, { "ambulance", "🚑", "Critical hotfix" }, { "sparkles", "✨", "Introduce new features" },
  { "memo", "📝", "Add or update documentation" }, { "rocket", "🚀", "Deploy stuff" }, { "lipstick", "💄", "Update the UI" },
  { "tada", "🎉", "Begin a project" }, { "white_check_mark", "✅", "Add or update tests" }, { "lock", "🔒", "Fix security issues" },
  { "bookmark", "🔖", "Release or version tags" }, { "rotating_light", "🚨", "Fix compiler or linter warnings" },
  { "construction", "🚧", "Work in progress" }, { "green_heart", "💚", "Fix the CI build" }, { "arrow_up", "⬆️", "Upgrade dependencies" },
  { "arrow_down", "⬇️", "Downgrade dependencies" }, { "recycle", "♻️", "Refactor code" }, { "wrench", "🔧", "Change configuration" },
  { "hammer", "🔨", "Change development scripts" }, { "globe", "🌐", "Internationalisation" }, { "pencil", "✏️", "Fix typos" },
  { "rewind", "⏪", "Revert changes" }, { "twisted_rightwards_arrows", "🔀", "Merge branches" }, { "package", "📦", "Packages" },
  { "truck", "🚚", "Move or rename" }, { "boom", "💥", "Breaking changes" }, { "wheelchair", "♿", "Improve accessibility" },
  { "bulb", "💡", "Add or update comments" }, { "wastebasket", "🗑️", "Deprecate code" }, { "coffin", "⚰️", "Remove dead code" },
}

registry.mode { id = "gitmoji", name = "Gitmoji", material = "commit", shape = "cookie9", words = { "gitmoji" }, bare = false,
  hint = "gitmoji bug", search = function(term)
    local list = {}
    for _, g in ipairs(GITMOJI) do list[#list + 1] = { name = g[1], glyph = g[2], description = g[3] } end
    local out = {}
    for _, g in ipairs(rows.fuzzy(list, term)) do
      out[#out + 1] = row { id = "gitmoji:" .. g.name, name = ":" .. g.name .. ":", description = g.description, glyph = g.glyph,
        copy = ":" .. g.name .. ":", run = function() return run.copy(":" .. g.name .. ":") end,
        actions = { { name = "Copy the emoji", material = "content_copy", run = function() return run.copy(g.glyph) end } } }
    end
    return out
  end }

--- What `aspell -a` says of the word: true when it is right, else a list.
function M.parse_spell(stdout)
  for line in stdout:gmatch("[^\n]+") do
    if line:sub(1, 1) == "*" or line:sub(1, 1) == "+" or line:sub(1, 1) == "-" then return true end
    local list = line:match("^&%s+%S+%s+%d+%s+%d+:%s*(.+)$")
    if list then
      local out = {}
      for word in list:gmatch("[^,]+") do out[#out + 1] = (word:gsub("^%s+", "")) end
      return out
    end
    if line:sub(1, 1) == "#" then return {} end
  end
  return {}
end

registry.mode { id = "spell", name = "Spelling", material = "spellcheck", shape = "pill", words = { "spell" },
  hint = "spell recieve", search = function(term)
    if term == "" then return { note("spell", "Type a word", "Whether it is right, and what it might be", "spellcheck") } end
    local program = rows.first_of { "aspell", "hunspell" }
    if not program then return { note("spell", "Needs aspell or hunspell", "Neither is on your PATH", "spellcheck") } end
    local answer = rows.ask("spell", term, function(done)
      return morf.process.run({ program, "-a" }, { stdin = term .. "\n", timeout_ms = 3000 }, function(result)
        done(M.parse_spell(tostring(result and result.stdout or "")))
      end)
    end, { debounce_ms = 200 })
    if answer == nil then return { note("spell", "Checking…", term, "spellcheck") } end
    if answer == true then return { rows.copy("spell", term, "Spelled right", "check_circle") } end
    local out = {}
    for i, word in ipairs(answer) do
      out[#out + 1] = rows.copy("spell:" .. i, word, "Instead of “" .. term .. "”", "spellcheck")
      if #out >= 10 then break end
    end
    if #out == 0 then out[1] = note("spell", "No suggestions", term, "spellcheck") end
    return out
  end }

registry.mode { id = "fonts", name = "Fonts", material = "font_download", shape = "pill", words = { "font", "fonts" },
  hint = "font mono  ·  the installed families", search = function(term)
    local ok, families = pcall(morf.text.families)
    local list = {}
    for _, name in ipairs(ok and type(families) == "table" and families or {}) do list[#list + 1] = { name = name } end
    local out = {}
    for _, f in ipairs(rows.fuzzy(list, term, "name")) do
      out[#out + 1] = rows.copy("font:" .. f.name, f.name, "Return copies its name", "font_download")
      if #out >= 40 then break end
    end
    if #out == 0 then out[1] = note("fonts", "No font by that name", term, "font_download") end
    return out
  end }

return M
