-- Quick notes: plain files in one folder (`notes.folder`), found by their
-- names, written a moment after the typing stops, and followed when another
-- program changes them. One model, whichever panel shows the page. No nodes.
local morf = require("morf")
local config = require("config")
local M = {
  rows = morf.list_model({}),
  selected = morf.signal("eva.notes.selected", ""),
  text = morf.signal("eva.notes.text", ""),
  query = morf.signal("eva.notes.query", ""),
  said = morf.signal("eva.notes.said", ""),
  deleting = morf.signal("eva.notes.deleting", ""),
  revision = morf.signal("eva.notes.revision", 0),
  SAVE_AFTER_MS = 500,
  QUICK = "Quick notes.md",
  EXTENSIONS = { md = true, txt = true, org = true },
}
local watcher, timer, unsaved

--- The folder, `~` expanded.
function M.folder() return (morf.fs.expand(config.get("notes.folder") or "~/Notes")) end

-- A file name from a title: no folders, nothing hidden.
local function file_name(title)
  local name = tostring(title):gsub("[%c/\\:]", " "):gsub("%s+", " "):gsub("^[%.%s]+", ""):gsub("%s+$", "")
  if name == "" then name = "Note " .. morf.time.format("%Y-%m-%d %H-%M") end
  if not name:match("%.%w+$") then name = name .. ".md" end
  return name
end

local function within(name)
  return type(name) == "string" and name ~= "" and not name:find("/", 1, true) and name ~= ".." and name ~= "."
end
local function path_of(name) return M.folder() .. "/" .. name end

local function when(modified)
  return modified and morf.time.format("%-d %b %H:%M", modified) or ""
end

--- Reads the folder again, newest first, through the search.
function M.refresh()
  local ok, entries = pcall(morf.fs.list, M.folder())
  local notes = {}
  for _, entry in ipairs(ok and entries or {}) do
    if entry.is_file and M.EXTENSIONS[(entry.extension or ""):lower():gsub("^%.", "")] then
      notes[#notes + 1] = { id = entry.name, name = entry.name, modified = entry.modified, when = when(entry.modified) }
    end
  end
  table.sort(notes, function(a, b) return (a.modified or 0) > (b.modified or 0) end)
  local term = M.query:get()
  if term ~= "" then
    local found = {}
    for _, hit in ipairs(morf.text.fuzzy(term, notes, { key = "name" })) do found[#found + 1] = hit.item end
    notes = found
  end
  M.rows:replace(notes, "id")
end

local function write_now()
  if timer then timer:cancel() timer = nil end
  if unsaved == nil then return true end
  local name, text = M.selected:get(), unsaved
  unsaved = nil
  if not within(name) then return true end
  local ok, why = morf.fs.write(path_of(name), text)
  if not ok then
    M.said:set("It could not be saved: " .. tostring(why))
    return false
  end
  M.said:set("Saved")
  M.refresh()
  return true
end

--- Whatever is unsaved goes to disk.
function M.flush() return write_now() end

--- Opens a note.
function M.open(name)
  write_now()
  if not within(name) then return end
  local ok, text = pcall(morf.fs.read, path_of(name))
  if not ok or type(text) ~= "string" then
    M.said:set("That note could not be read.")
    return
  end
  M.selected:set(name)
  M.text:set(text)
  M.said:set("")
  M.deleting:set("")
  M.revision:set(M.revision:get() + 1)
end

--- Back to the list.
function M.close()
  write_now()
  M.selected:set("")
  M.deleting:set("")
end

--- Keeps the notes in `path` from now on.
function M.set_folder(path)
  path = tostring(path or ""):match("^%s*(.-)%s*$")
  if path == "" or path == config.get("notes.folder") then return end
  write_now()
  config.set("notes.folder", path)
  M.selected:set("")
  if watcher then M.watch(true) else M.refresh() end
end

--- The note on show was edited to `text`.
function M.edited(text)
  if M.selected:get() == "" or text == M.text:get() then return end
  M.text:set(text)
  unsaved = text
  M.said:set("Saving…")
  if timer then timer:cancel() end
  timer = morf.time.timer(M.SAVE_AFTER_MS, write_now, false)
end

--- Makes a note called `title`, or opens the one already called that.
function M.create(title)
  write_now()
  local name = file_name(title)
  if not morf.fs.exists(path_of(name)) then
    local ok, why = morf.fs.write(path_of(name), "", { parents = true })
    if not ok then M.said:set("It could not be made: " .. tostring(why)) return false end
  end
  M.refresh()
  M.open(name)
  return name
end

--- Where the quick notes are.
function M.quick_path() return path_of(M.QUICK) end

--- The quick notes' lines, oldest first, without their mark and time.
function M.quick_lines()
  local ok, text = pcall(morf.fs.read, path_of(M.QUICK))
  local lines = {}
  for line in tostring(ok and text or ""):gmatch("[^\n]+") do
    lines[#lines + 1] = (line:gsub("^%- ", ""):gsub("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d  ", ""))
  end
  return lines
end

--- Adds a line to the quick notes, with the time: the launcher's `note`.
function M.quick(text)
  text = tostring(text or ""):match("^%s*(.-)%s*$")
  if text == "" then return false end
  local line = ("- %s  %s\n"):format(morf.time.format("%Y-%m-%d %H:%M"), text)
  local ok, why = morf.fs.write(path_of(M.QUICK), line, { append = true, parents = true })
  if not ok then M.said:set("It could not be saved: " .. tostring(why)) return false end
  M.refresh()
  if M.selected:get() == M.QUICK then M.open(M.QUICK) end
  return true
end

--- Removes a note: the first press asks, the second does it.
function M.delete(name)
  if not within(name) then return false end
  if M.deleting:get() ~= name then M.deleting:set(name) return false end
  M.deleting:set("")
  if timer then timer:cancel() timer = nil end
  unsaved = nil
  pcall(morf.fs.remove, path_of(name))
  if M.selected:get() == name then
    M.selected:set("")
    M.text:set("")
  end
  M.refresh()
  return true
end

function M.search(term)
  M.query:set(term)
  M.refresh()
end

--- Follows the folder while the page is on show.
function M.watch(on)
  if watcher then watcher:close() watcher = nil end
  if not on then write_now() return end
  M.refresh()
  watcher = morf.fs.watch(M.folder(), function(event)
    M.refresh()
    local name = M.selected:get()
    if name ~= "" and unsaved == nil and event.name == name and morf.fs.exists(path_of(name)) then
      local ok, text = pcall(morf.fs.read, path_of(name))
      if ok and type(text) == "string" and text ~= M.text:get() then
        M.text:set(text)
        M.revision:set(M.revision:get() + 1)
      end
    end
  end)
end

return M
