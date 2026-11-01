-- People, from a folder of vCards: what vdirsyncer keeps, or what a phone
-- exported. The cards are never written to except by `import`; what is eva's
-- own (favourites, the emergency contact, blocked numbers) lives beside them
-- in the state folder.
--
--   local book = require("lib.services.contacts").open { folder = "~/contacts", country = "+31" }
--   book.people:get()           -- { { id, name, numbers = { { number, kind } }, favourite, emergency }, ... }
--   book.person("0612345678")   -- the row a number belongs to, or nil
--   book.label("+3161...")      -- their name, or the number written out
--   book.search("ann")          -- by name or number
--   book.t9("266")              -- by the letters on a dial pad, or by number
--   book.blocked(number)
local morf = require("morf")

local M = {}

local KEYS = { abc = "2", def = "3", ghi = "4", jkl = "5", mno = "6", pqrs = "7", tuv = "8", wxyz = "9" }
local T9 = {}
for letters, digit in pairs(KEYS) do
  for i = 1, #letters do T9[letters:sub(i, i)] = digit end
end
-- A number and its local spelling share at least this many final digits.
local TAIL = 9
local KINDS = { cell = "mobile", mobile = "mobile", iphone = "mobile", home = "home", work = "work",
  main = "main", fax = "fax", pager = "pager" }

local serial = 0

local function unescape(text)
  return (text:gsub("\\[nN]", "\n"):gsub("\\([,;\\:])", "%1"))
end

--- The number as dialled: digits, with a leading + kept.
function M.digits(number)
  number = tostring(number or "")
  local plus = number:match("^%s*%+") ~= nil
  local bare = number:gsub("^tel:", ""):gsub("[^%d*#]", "")
  return (plus and "+" or "") .. bare
end

--- `number` in international form: 00 and a leading 0 become `country`'s.
function M.normal(number, country)
  local bare = M.digits(number)
  if bare:sub(1, 2) == "00" then return "+" .. bare:sub(3) end
  if bare:sub(1, 1) == "0" and country and country ~= "" then return country .. bare:sub(2) end
  return bare
end

local function tail(number)
  local bare = M.digits(number):gsub("%D", "")
  return bare:sub(-TAIL)
end

local function kind_of(params)
  for word in params:lower():gmatch("[%w]+") do
    if KINDS[word] then return KINDS[word] end
  end
  return "other"
end

--- The cards in vCard `text`: `{ { id, name, numbers, categories, source }, ... }`.
function M.parse(text)
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n"):gsub("\n[ \t]", "")
  local cards, card = {}, nil
  local started = 0
  local at = 1
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local line_start = at
    at = at + #line + 1
    local key, value = line:match("^([^:]+):(.*)$")
    if key then
      local name, params = key:match("^([^;]+);?(.*)$")
      name = name:gsub("^.-%.", ""):upper()
      if name == "BEGIN" and value:upper():match("VCARD") then
        card = { numbers = {}, categories = {} }
        started = line_start
      elseif name == "END" and card then
        card.source = text:sub(started, at - 2) .. "\n"
        if not card.name or card.name == "" then
          card.name = card.numbers[1] and card.numbers[1].number or ""
        end
        if card.name ~= "" then cards[#cards + 1] = card end
        card = nil
      elseif card then
        if name == "FN" then card.name = unescape(value)
        elseif name == "N" and not card.name then
          local family, given = value:match("^([^;]*);([^;]*)")
          if given then card.name = unescape((given .. " " .. family):gsub("^%s+", ""):gsub("%s+$", "")) end
        elseif name == "UID" then card.id = value
        elseif name == "TEL" and value ~= "" then
          card.numbers[#card.numbers + 1] = { number = value:gsub("^tel:", ""), kind = kind_of(params) }
        elseif name == "CATEGORIES" then
          for word in value:gmatch("[^,]+") do card.categories[#card.categories + 1] = word:lower() end
        end
      end
    end
  end
  for index, each in ipairs(cards) do
    each.id = each.id or (each.name .. "/" .. index)
  end
  return cards
end

local function t9_word(word)
  local out = {}
  for i = 1, #word do out[i] = T9[word:sub(i, i)] or "" end
  return table.concat(out)
end

--- `options`: `folder` (the cards), `country` (for numbers without one),
--- `state` (where eva's own marks go), `watch` (false to not follow the folder).
function M.open(options)
  options = options or {}
  serial = serial + 1
  local country = options.country or ""
  local folder = morf.fs.expand and morf.fs.expand(options.folder or "") or options.folder
  local state_file = options.state
    or ((morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/phone/contacts.json")
  local book = { people = morf.signal("eva.contacts." .. serial, {}), folder = folder, country = country }
  local marks = { favourites = {}, emergency = "", blocked = {} }
  local by_tail, cards = {}, {}

  local function read_marks()
    local ok, text = pcall(morf.fs.read, state_file)
    local fine, value = pcall(morf.json.decode, ok and text or "")
    if fine and type(value) == "table" then
      marks.favourites = value.favourites or {}
      marks.emergency = value.emergency or ""
      marks.blocked = value.blocked or {}
    end
  end
  local function save_marks()
    morf.fs.write(state_file, morf.json.encode(marks), { atomic = true, parents = true, mode = 384 })
  end

  local function publish()
    local out = {}
    by_tail = {}
    for _, card in ipairs(cards) do
      local favourite = false
      for _, id in ipairs(marks.favourites) do favourite = favourite or id == card.id end
      for _, word in ipairs(card.categories) do favourite = favourite or word == "favorites" or word == "favourites" end
      local row = { id = card.id, name = card.name, numbers = card.numbers, favourite = favourite,
        emergency = marks.emergency == card.id }
      out[#out + 1] = row
      for _, entry in ipairs(card.numbers) do
        local key = tail(entry.number)
        if key ~= "" then by_tail[key] = by_tail[key] or row end
      end
    end
    table.sort(out, function(a, b)
      local x, y = a.name:lower(), b.name:lower()
      if x ~= y then return x < y end
      return a.id < b.id
    end)
    book.people:set(out)
  end

  --- Reads the folder again.
  function book.reload()
    cards = {}
    local ok, entries = pcall(morf.fs.list, folder or "")
    for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
      local name = entry.name or ""
      if name:lower():match("%.vcf$") or name:lower():match("%.vcard$") then
        local fine, text = pcall(morf.fs.read, folder .. "/" .. name)
        if fine and type(text) == "string" then
          for _, card in ipairs(M.parse(text)) do cards[#cards + 1] = card end
        end
      end
    end
    publish()
  end

  --- The row `number` belongs to, or nil.
  function book.person(number)
    local key = tail(number)
    return key ~= "" and by_tail[key] or nil
  end

  --- What to call `number`: a name, or the number as it came.
  function book.label(number)
    local row = book.person(number)
    if row then return row.name end
    if tostring(number or "") == "" then return "Unknown" end
    return tostring(number)
  end

  --- Rows matching `query` in a name or a number.
  function book.search(query)
    local needle = (query or ""):lower()
    if needle == "" then return book.people:get() end
    local bare = needle:gsub("%D", "")
    local out = {}
    for _, row in ipairs(book.people:get()) do
      local hit = row.name:lower():find(needle, 1, true) ~= nil
      for _, entry in ipairs(row.numbers) do
        hit = hit or (bare ~= "" and M.digits(entry.number):find(bare, 1, true) ~= nil)
      end
      if hit then out[#out + 1] = row end
    end
    return out
  end

  --- Rows whose name starts a word with `digits` on a dial pad, or whose
  --- number holds them.
  function book.t9(digits)
    if not digits or digits == "" then return {} end
    local out = {}
    for _, row in ipairs(book.people:get()) do
      local hit = false
      for word in row.name:lower():gmatch("%a+") do
        hit = hit or t9_word(word):sub(1, #digits) == digits
      end
      for _, entry in ipairs(row.numbers) do
        hit = hit or M.digits(entry.number):find(digits, 1, true) ~= nil
      end
      if hit then out[#out + 1] = row end
    end
    return out
  end

  function book.favourites()
    local out = {}
    for _, row in ipairs(book.people:get()) do
      if row.favourite then out[#out + 1] = row end
    end
    return out
  end

  --- The person flagged for emergencies, or nil.
  function book.emergency()
    for _, row in ipairs(book.people:get()) do
      if row.emergency then return row end
    end
  end

  function book.set_favourite(id, on)
    local out = {}
    for _, each in ipairs(marks.favourites) do
      if each ~= id then out[#out + 1] = each end
    end
    if on then out[#out + 1] = id end
    marks.favourites = out
    save_marks()
    publish()
  end

  function book.set_emergency(id, on)
    marks.emergency = on and id or ""
    save_marks()
    publish()
  end

  --- Whether calls and texts from `number` are turned away.
  function book.blocked(number)
    local key = tail(number)
    for _, each in ipairs(marks.blocked) do
      if tail(each) == key then return true end
    end
    return false
  end

  function book.block(number, on)
    local out, key = {}, tail(number)
    for _, each in ipairs(marks.blocked) do
      if tail(each) ~= key then out[#out + 1] = each end
    end
    if on then out[#out + 1] = M.digits(number) end
    marks.blocked = out
    save_marks()
  end

  function book.blocked_numbers() return marks.blocked end

  --- Copies each card in the vCard file at `path` into the folder; how many.
  function book.import(path)
    local ok, text = pcall(morf.fs.read, path)
    if not ok or type(text) ~= "string" or not folder then return 0 end
    local parsed = M.parse(text)
    for _, card in ipairs(parsed) do
      local file = card.id:gsub("[^%w%-_.]", "_") .. ".vcf"
      morf.fs.write(folder .. "/" .. file, card.source, { atomic = true, parents = true, mode = 384 })
    end
    book.reload()
    return #parsed
  end

  --- Writes every card into one file at `path`; how many.
  function book.export(path)
    local parts = {}
    for _, card in ipairs(cards) do parts[#parts + 1] = card.source end
    morf.fs.write(path, table.concat(parts), { atomic = true, parents = true, mode = 384 })
    return #parts
  end

  read_marks()
  book.reload()
  if options.watch ~= false and folder and folder ~= "" then
    local ok, watch = pcall(morf.fs.watch, folder, function() book.reload() end)
    book.watch = ok and watch or nil
  end
  return book
end

return M
