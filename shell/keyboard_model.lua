-- The on-screen keyboard's state: what the text field holds and what it is
-- for, the language, and which pane is up. No nodes.
--
-- A field's purpose comes from the first of: what the input method says
-- (`update`'s `purpose` and `hints`), what a tool of eva's own asked for
-- (`ask`), and the focused window's class (`keyboard.classes` in the settings).
local morf = require("morf")
local config = require("config")
local layouts = require("keyboard_layouts")
local unicase = require("lib.util.unicase")

local M = {}

-- Each purpose: the board it brings up, whether the typing aids apply, whether
-- it keeps what is typed out of everything, and what the comma key types.
M.PURPOSES = {
  normal = { mode = "full", aids = true }, name = { mode = "full", aids = true },
  alpha = { mode = "letters", aids = true },
  digits = { mode = "numbers" }, number = { mode = "numbers" },
  date = { mode = "numbers" }, time = { mode = "numbers" }, datetime = { mode = "numbers" },
  phone = { mode = "phone" }, url = { mode = "full", comma = "/" }, email = { mode = "full", comma = "@" },
  password = { mode = "full", private = true }, pin = { mode = "numbers", private = true },
  terminal = { mode = "dev" }, dev = { mode = "dev" },
}
-- Content hints that mean a field's text is secret.
local SECRET_HINTS = { hidden_text = true, sensitive_data = true }
-- What a field shows for each character of a password.
local MASKS = { ["•"] = true, ["●"] = true, ["∙"] = true, ["*"] = true, ["◦"] = true, ["·"] = true }

M.field = morf.signal("eva.keyboard.field", { active = false, cursor = 0, anchor = 0 })
M.memo = morf.signal("eva.keyboard.memo", "")
M.revision = morf.signal("eva.keyboard.revision", 0)
M.reported = morf.signal("eva.keyboard.reported", "")
M.secret_hints = morf.signal("eva.keyboard.secret_hints", false)
M.asked = morf.signal("eva.keyboard.asked", "")
M.app = morf.signal("eva.keyboard.app", "")
M.pane = morf.signal("eva.keyboard.pane", "keys")
M.tray = morf.signal("eva.keyboard.tray", "words")
M.private = morf.signal("eva.keyboard.private", false)
M.trackpad = morf.signal("eva.keyboard.trackpad", false)
M.candidates = morf.signal("eva.keyboard.candidates", {})
M.query = morf.signal("eva.keyboard.emoji_query", "")

local function bump() M.revision:set(M.revision:get() + 1) end

-- ----------------------------------------------------------- the purpose --

--- What the focused field is for.
function M.purpose()
  local reported = M.reported:get()
  if reported ~= "" and M.PURPOSES[reported] then return reported end
  local asked = M.asked:get()
  if asked ~= "" and M.PURPOSES[asked] then return asked end
  local app = M.app:get()
  local classes = config.get("keyboard.classes")
  local wanted = app ~= "" and classes and classes[app]
  if wanted and M.PURPOSES[wanted] then return wanted end
  return "normal"
end

--- The purpose's description.
function M.intent() return M.PURPOSES[M.purpose()] end

--- A tool of eva's own says what its field is for; "" or nil lets go.
function M.ask(purpose)
  if purpose and purpose ~= "" and not M.PURPOSES[purpose] then return false end
  M.asked:set(purpose or "")
  return true
end

-- ------------------------------------------------------------- the field --

--- Whether what the field holds came from the field itself.
function M.known() return M.field:get().text ~= nil end

--- The text before the cursor, or before the selection.
function M.before()
  local f = M.field:get()
  if f.text then return f.text:sub(1, math.min(f.cursor, f.anchor)) end
  return M.memo:get()
end

local function secret_shown(before)
  if before == "" then return false end
  for _, cp in utf8.codes(before, true) do
    if not MASKS[utf8.char(cp)] then return false end
  end
  return true
end

--- Whether the text before the cursor is a field's mask over a password.
function M.masked() return secret_shown(M.before()) end

--- Whether nothing typed now may be predicted from, corrected or remembered.
function M.is_private()
  return M.private:get() or M.intent().private == true or M.secret_hints:get() or M.masked()
end

-- Whether the character `ch` can be part of a word.
local function letter(ch)
  if #ch == 1 then return ch:match("[%a']") ~= nil end
  local cp = utf8.codepoint(ch)
  if cp == 0x2019 then return true end
  return cp < 0x2000 or (cp >= 0x2C00 and cp < 0x3000) or (cp >= 0x3040 and cp < 0xFE00)
end

-- The run of word characters that ends `text`.
local function tail(text)
  local i, stop = #text, #text
  while i > 0 and stop - i < 64 do
    local start = i
    while start > 1 and text:byte(start) >= 0x80 and text:byte(start) < 0xC0 do start = start - 1 end
    if not letter(text:sub(start, i)) then break end
    i = start - 1
  end
  return (text:sub(i + 1, stop):gsub("^'+", ""))
end
M.tail = tail

--- The word the cursor stands at the end of, "" between words.
function M.word() return tail(M.before()) end

--- Whether a sentence begins at the cursor.
function M.sentence_start()
  local before = M.before()
  if before == "" or before:sub(-1) == "\n" then return true end
  local stripped = before:gsub("%s+$", "")
  if stripped == "" then return true end
  if stripped == before then return false end
  return stripped:match("[%.!%?]$") ~= nil or stripped:sub(-3) == "…"
end

--- Whether the typing aids apply here, on the board `mode`.
function M.aids(mode)
  return M.intent().aids == true and not M.is_private() and (mode == "full" or mode == "letters")
end

local flying, settle = 0, nil

--- What the input method says. A later engine fills in `purpose` and `hints`.
function M.update(active, text, cursor, anchor, purpose, hints)
  local was = M.field:get().active
  if not active or not was then
    flying = 0
    M.memo:set("")
  end
  M.reported:set(type(purpose) == "string" and purpose or "")
  local secret = false
  for _, hint in ipairs(type(hints) == "table" and hints or {}) do
    if SECRET_HINTS[hint] then secret = true end
  end
  M.secret_hints:set(secret)
  if active and flying > 0 then
    flying = flying - 1
    if flying > 0 then return end
  end
  M.field:set { active = active == true, text = active and text or nil, cursor = cursor or 0, anchor = anchor or cursor or 0 }
  bump()
end

--- Forgets what was typed where the field does not say what it holds.
function M.forget()
  M.memo:set("")
  bump()
end

--- What the keyboard itself just did to the field: `cut` bytes gone before the
--- cursor and `text` in their place, ahead of the field saying so.
function M.echo(cut, text)
  local f = M.field:get()
  if f.text then
    local from = math.max(0, math.min(f.cursor, f.anchor) - cut)
    local to = math.max(f.cursor, f.anchor)
    f.text = f.text:sub(1, from) .. text .. f.text:sub(to + 1)
    f.cursor = from + #text
    f.anchor = f.cursor
    M.field:set(f)
    flying = flying + 1
    if settle then settle:cancel() end
    settle = morf.time.timer(400, function() settle = nil flying = 0 end, false)
  else
    local memo = M.memo:get()
    M.memo:set(memo:sub(1, math.max(0, #memo - cut)) .. text)
  end
  bump()
end

--- How many bytes the last character before the cursor takes.
function M.last_char()
  local before = M.before()
  local i = #before
  while i > 1 and before:byte(i) >= 0x80 and before:byte(i) < 0xC0 do i = i - 1 end
  return #before - i + 1
end

-- ---------------------------------------------------------- the languages --

--- The languages to switch between, in order.
function M.languages()
  local out, seen = {}, {}
  local function take(layout)
    if layout and not seen[layout.id] then
      seen[layout.id] = true
      out[#out + 1] = layout
    end
  end
  for _, id in ipairs(config.get("keyboard.languages")) do take(layouts.get(id)) end
  if #out == 0 then
    take(layouts.from_locale(morf.env("LC_ALL")))
    take(layouts.from_locale(morf.env("LC_MESSAGES")))
    take(layouts.from_locale(morf.env("LANG")))
    take(layouts.get("en"))
  end
  return out
end

--- The language in use.
function M.layout()
  local list = M.languages()
  local id = config.get("keyboard.language")
  for _, layout in ipairs(list) do if layout.id == id then return layout end end
  return list[1]
end

--- Moves to the next language in the list.
function M.next_language()
  local list, now = M.languages(), M.layout()
  for i, layout in ipairs(list) do
    if layout.id == now.id then
      config.set("keyboard.language", list[i % #list + 1].id)
      return
    end
  end
end

--- Uses language `id`.
function M.use_language(id)
  if not layouts.get(id) then return false end
  config.set("keyboard.language", id)
  return true
end

--- The word in `layout`'s capitals.
function M.upper(text) return layouts.upper(M.layout(), text) end

-- --------------------------------------------------------------- the panes --

--- Puts a pane in place of the keys: "keys" or "emoji".
function M.show_pane(name)
  M.pane:set(name)
  if name == "keys" then M.query:set("") end
end

--- Whether the keys are typing into the emoji search.
M.searching = morf.signal("eva.keyboard.searching", false)

--- Ends everything that belonged to the last field.
function M.leave()
  M.pane:set("keys")
  M.tray:set("words")
  M.searching:set(false)
  M.query:set("")
  M.asked:set("")
end

return M
