-- What the captures folder holds, newest first: the panel's history. The files
-- are all it keeps. Its small pictures are scratch, gone when it shuts, and the
-- only thing it writes is the text read from a shot. Loaded the first time the
-- history opens.
local morf = require("morf")
local backend = require("lib.shell.capture")
local read = require("lib.shell.capture.read")

local M = {
  query = morf.signal("eva.capture.recent.query", ""),
  -- The rows shown, the row chosen, and how many the folder holds.
  rows = morf.signal("eva.capture.recent.rows", {}),
  chosen = morf.signal("eva.capture.recent.chosen", 0),
  total = morf.signal("eva.capture.recent.total", 0),
  -- A small picture by path, what a press last did, and a delete waiting for
  -- its second press.
  small = morf.signal("eva.capture.recent.small", {}),
  note = morf.signal("eva.capture.recent.note", ""),
  armed = morf.signal("eva.capture.recent.armed", false),
  -- The shot whose text is open, what it read, and whether that is being read.
  reading = morf.signal("eva.capture.recent.reading", false),
  words = morf.signal("eva.capture.recent.words", ""),
  busy = morf.signal("eva.capture.recent.busy", false),
  -- The shots of a search through text still to read.
  unread = morf.signal("eva.capture.recent.unread", 0),
}

-- Rows shown of a search, and files a search looks through.
M.LIMIT, M.KEPT = 40, 500
M.SMALL_W, M.SMALL_H = 72, 48
M.MISSING = "tesseract is not installed, so no text can be read from a shot"
M.MISSING_SEARCH = "tesseract is not installed: only names and dates are searched"

local SHOTS = { png = true, jpg = true, jpeg = true, webp = true }
local MOVING = { mp4 = true, mkv = true, webm = true, mov = true, gif = true }

local capture, session, entries, texts
local serial = 0

-- ---------------------------------------------------------------- the listing --

--- "shot" or "recording" for a file's name; nil for anything else.
function M.kind(name)
  local extension = tostring(name):lower():match("%.(%w+)$")
  if SHOTS[extension] then return "shot" end
  if MOVING[extension] then return "recording" end
end

--- The captures in `folder`, newest first; empty for a folder that is not
--- there, which it does not make.
function M.list(folder)
  local ok, found = pcall(morf.fs.list, folder)
  local out = {}
  for _, entry in ipairs(ok and type(found) == "table" and found or {}) do
    local kind = not entry.is_dir and M.kind(entry.name)
    if kind then
      out[#out + 1] = { path = entry.path, name = entry.name, size = entry.size or 0,
        modified = entry.modified or 0, kind = kind }
    end
  end
  table.sort(out, function(a, b)
    if a.modified == b.modified then return a.name > b.name end
    return a.modified > b.modified
  end)
  return out
end

local function day(when) return morf.time.format("%Y-%m-%d", when) end

--- How a row names its time: "Today 16:22", "Yesterday 09:10", "3 Nov 2026 12:01".
function M.label(entry, now)
  now = now or morf.time.now()
  local date, clock = day(entry.modified), morf.time.format("%H:%M", entry.modified)
  if date == day(now) then return "Today " .. clock end
  if date == day(now - 86400) then return "Yesterday " .. clock end
  return morf.time.format("%-d %b %Y", entry.modified) .. " " .. clock
end

--- Every word a search can find the entry by: its name and its date, whole and
--- in the ways it is said, and any text read from it.
function M.words_of(entry, now, text)
  now = now or morf.time.now()
  local parts = { entry.name, entry.kind, morf.time.format("%Y-%m-%d %H:%M %-d %B %b %A %Y", entry.modified) }
  local date = day(entry.modified)
  if date == day(now) then parts[#parts + 1] = "today" end
  if date == day(now - 86400) then parts[#parts + 1] = "yesterday" end
  if text then parts[#parts + 1] = text end
  return table.concat(parts, " "):lower()
end

--- The entries every word of `query` is found in. `known` gives an entry's text
--- by its path; each entry keeps its words until `known` has more to say.
function M.filter(list, query, now, known)
  local wanted = {}
  for word in tostring(query or ""):lower():gmatch("%S+") do wanted[#wanted + 1] = word end
  local out = {}
  for _, entry in ipairs(list) do
    local text = known and known[entry.path] or nil
    if not entry.words or entry.read ~= text then
      entry.words, entry.read = M.words_of(entry, now, text), text
    end
    local all = true
    for _, word in ipairs(wanted) do
      if not entry.words:find(word, 1, true) then all = false break end
    end
    if all then out[#out + 1] = entry end
  end
  return out
end

--- A file's size in words.
function M.size(bytes)
  if bytes >= 1048576 then return ("%.1f MB"):format(bytes / 1048576) end
  return ("%d KB"):format(math.max(1, bytes // 1024))
end

-- ---------------------------------------------------------------- what is read --

local function text_folder()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/capture/text"
end

local function text_path(entry)
  local mark = ("%s|%s|%s"):format(entry.path, entry.modified, entry.size)
  return text_folder() .. "/" .. morf.encoding.sha1(mark) .. ".txt"
end

-- What is on disk for each entry, found once when the history opens.
local function gather_texts()
  texts = {}
  local ok, found = pcall(morf.fs.list, text_folder())
  if not ok or type(found) ~= "table" or #found == 0 then return end
  local have = {}
  for _, file in ipairs(found) do have[file.name] = file.path end
  for _, entry in ipairs(entries) do
    local path = have[text_path(entry):match("[^/]+$")]
    if path then
      local fine, text = pcall(morf.fs.read, path)
      if fine and type(text) == "string" then texts[entry.path] = text end
    end
  end
end

local function known_text(entry) return texts[entry.path] end

local function readable()
  return capture ~= nil and capture.editor.readers:get().ocr == true
end

local function count_unread()
  local count = 0
  for _, entry in ipairs(entries or {}) do
    if entry.kind == "shot" and not known_text(entry) then count = count + 1 end
  end
  M.unread:set(M.query:get() ~= "" and readable() and count or 0)
end

--- The text in `entry`, from what was read before or from tesseract:
--- `cb(words)`, or `cb(nil, why)`.
function M.text_of(entry, cb)
  local known = known_text(entry)
  if known then cb(known) return end
  if not readable() then cb(nil, M.MISSING) return end
  read.text(entry.path, function(words, why)
    if not words then cb(nil, why) return end
    morf.fs.write(text_path(entry), words, { atomic = true, parents = true })
    texts[entry.path] = words
    cb(words)
  end)
end

-- ----------------------------------------------------------------- the rows --

local function refilter()
  local list = M.filter(entries or {}, M.query:get(), nil, texts)
  local shown = {}
  for i = 1, math.min(#list, M.LIMIT) do shown[i] = list[i] end
  M.rows:set(shown)
  M.chosen:set(0)
  M.armed:set(false)
  count_unread()
end

-- Small pictures, one at a time, for the rows shown.
local function next_small(current)
  if current ~= serial or not session then return end
  for _, entry in ipairs(M.rows:get()) do
    if entry.kind == "shot" and M.small:get()[entry.path] == nil then
      local table_now = M.small:get()
      table_now[entry.path] = false
      session.render(entry.path, { { "resize", M.SMALL_W * 2, M.SMALL_H * 2, "fill" } }, function(ok, small)
        if current ~= serial then return end
        if ok then
          local out = {}
          for key, value in pairs(M.small:get()) do out[key] = value end
          out[entry.path] = small
          M.small:set(out)
        end
        next_small(current)
      end)
      return
    end
  end
end

--- Reads the folder again, the newest `KEPT` of it.
function M.refresh()
  entries = M.list(capture.folder())
  for i = #entries, M.KEPT + 1, -1 do entries[i] = nil end
  M.total:set(#entries)
  gather_texts()
  refilter()
  next_small(serial)
end

--- The history over `capture`, from the folder as it is now.
function M.open(module)
  capture = module
  serial = serial + 1
  entries, texts = {}, {}
  session = backend.session {}
  M.small:set({}) M.note:set("") M.query:set("") M.reading:set(false) M.words:set("")
  M.refresh()
  return M
end

--- Lets go of the scratch pictures.
function M.close()
  serial = serial + 1
  if session then session.close() session = nil end
  M.small:set({}) M.rows:set({}) M.reading:set(false)
end

function M.search(words)
  M.query:set(words or "")
  if M.reading:get() then return end
  refilter()
  next_small(serial)
end

function M.entry()
  return M.rows:get()[M.chosen:get()]
end

--- A press on a row: the first chooses it, a second opens it.
function M.press(index)
  if M.chosen:get() == index then M.edit() return end
  M.chosen:set(index)
  M.armed:set(false)
  M.note:set("")
end

-- ---------------------------------------------------------------- what it does --

--- The chosen one in the editor: a shot's marks, or a recording's trim.
function M.edit()
  local entry = M.entry()
  if not entry then return false end
  capture.drawer.set(false)
  capture.present(function()
    if entry.kind == "recording" then require("trim").open(capture, entry.path)
    else capture.open_file(entry.path) end
  end)
  return true
end

--- On the clipboard: the picture of a shot, the file of a recording.
function M.copy()
  local entry = M.entry()
  if not entry then return false end
  if entry.kind == "recording" then
    morf.clipboard.set("file://" .. entry.path, "text/uri-list")
    M.note:set("The file is on the clipboard")
    return true
  end
  backend.copy(entry.path, function(ok, why)
    M.note:set(ok and "Copied" or tostring(why or "Could not copy"))
  end)
  return true
end

--- Pinned over the windows, from its file.
function M.pin()
  local entry = M.entry()
  if not entry then return false end
  if entry.kind ~= "shot" then M.note:set("Only a picture can be pinned") return false end
  capture.drawer.set(false)
  return require("pin").add(capture, entry.path)
end

--- The first press asks, the second takes the file away.
function M.delete()
  local entry = M.entry()
  if not entry then return false end
  if M.armed:get() ~= entry.path then
    M.armed:set(entry.path)
    M.note:set("Press again to delete it for good")
    return false
  end
  pcall(morf.fs.remove, text_path(entry))
  local ok, why = pcall(morf.fs.remove, entry.path)
  M.armed:set(false)
  if not ok then M.note:set(tostring(why)) return false end
  M.note:set("Deleted " .. entry.name)
  M.refresh()
  return true
end

--- The text of the chosen shot, in the place of the list.
function M.read()
  local entry = M.entry()
  if not entry then return false end
  if entry.kind ~= "shot" then M.note:set("Text is read from pictures") return false end
  if not readable() then M.note:set(M.MISSING) return false end
  M.query:set("")
  if M.on_cleared then M.on_cleared() end
  M.reading:set(entry) M.words:set("") M.busy:set(true)
  M.note:set("Reading…")
  local current = serial
  M.text_of(entry, function(words, why)
    if current ~= serial then return end
    M.busy:set(false)
    M.words:set(words or "")
    M.note:set(words and "" or tostring(why))
  end)
  return true
end

--- Back from a shot's text to the list.
function M.back()
  M.reading:set(false) M.words:set("") M.note:set("")
  M.query:set("")
  if M.on_cleared then M.on_cleared() end
  refilter()
  next_small(serial)
end

--- The lines of the text the search leaves.
function M.lines()
  local wanted = M.query:get():lower()
  local out = {}
  for line in (M.words:get() .. "\n"):gmatch("(.-)\n") do
    if line:match("%S") and (wanted == "" or line:lower():find(wanted, 1, true)) then out[#out + 1] = line end
  end
  return out
end

--- The text shown, on the clipboard.
function M.copy_text()
  local lines = M.lines()
  if #lines == 0 then return false end
  morf.clipboard.set(table.concat(lines, "\n"))
  M.note:set(#lines == 1 and "A line copied" or #lines .. " lines copied")
  return true
end

--- Reads the shots not yet read, one at a time, so a search finds their text.
function M.read_all()
  if not readable() then M.note:set(M.MISSING) return false end
  local list = {}
  for _, entry in ipairs(entries or {}) do
    if entry.kind == "shot" and not known_text(entry) then list[#list + 1] = entry end
  end
  local current, index = serial, 0
  local function step()
    if current ~= serial then return end
    index = index + 1
    if index > #list then
      M.busy:set(false)
      M.note:set("")
      refilter()
      return
    end
    M.note:set(("Reading %d of %d…"):format(index, #list))
    M.text_of(list[index], function(words)
      if not words then texts[list[index].path] = " " end
      step()
    end)
  end
  M.busy:set(true)
  step()
  return true
end

return M
