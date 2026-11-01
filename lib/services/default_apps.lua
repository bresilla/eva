-- Which app opens what: `xdg-mime` reads and sets the defaults, and the
-- `mimeinfo.cache` every applications folder keeps says who can.
local morf = require("morf")
local host = require("lib.services.host")
local unicase = require("lib.util.unicase")

local M = {}

-- The kinds of thing a person chooses an app for: the types set together, and
-- the first is the one read.
M.KINDS = {
  { id = "browser", name = "Web browser", icon = "language",
    types = { "x-scheme-handler/http", "x-scheme-handler/https", "text/html" } },
  { id = "mail", name = "Mail", icon = "mail", types = { "x-scheme-handler/mailto" } },
  { id = "calendar", name = "Calendar", icon = "calendar_month", types = { "text/calendar" } },
  { id = "files", name = "Files", icon = "folder", types = { "inode/directory" } },
  { id = "text", name = "Text editor", icon = "edit_note", types = { "text/plain" } },
  { id = "pdf", name = "Documents", icon = "picture_as_pdf", types = { "application/pdf" } },
  { id = "images", name = "Images", icon = "image", types = { "image/png", "image/jpeg", "image/webp", "image/gif" } },
  { id = "music", name = "Music", icon = "music_note", types = { "audio/mpeg", "audio/flac", "audio/ogg" } },
  { id = "video", name = "Video", icon = "movie", types = { "video/mp4", "video/x-matroska", "video/webm" } },
  { id = "terminal", name = "Terminal", icon = "terminal", types = { "x-scheme-handler/terminal" } },
}

--- `[MIME Cache]` lines as a table: type -> list of desktop ids.
function M.parse_cache(text)
  local out = {}
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local mime, apps = line:match("^([^=%[]+)=(.*)$")
    if mime then
      out[mime] = out[mime] or {}
      for id in apps:gmatch("[^;]+") do out[mime][#out[mime] + 1] = id end
    end
  end
  return out
end

--- The applications folders, nearest first.
function M.folders()
  local home = morf.fs.home()
  local data = morf.env("XDG_DATA_HOME") or (home .. "/.local/share")
  local out = { data .. "/applications" }
  for dir in (morf.env("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"):gmatch("[^:]+") do
    out[#out + 1] = dir .. "/applications"
  end
  return out
end

--- Every type -> desktop ids the folders know.
function M.cache(folders)
  local merged = {}
  for _, folder in ipairs(folders or M.folders()) do
    local path = folder .. "/mimeinfo.cache"
    if morf.fs.exists(path) then
      local ok, text = pcall(morf.fs.read, path)
      for mime, apps in pairs(ok and M.parse_cache(text) or {}) do
        merged[mime] = merged[mime] or {}
        for _, id in ipairs(apps) do merged[mime][#merged[mime] + 1] = id end
      end
    end
  end
  return merged
end

--- `id` as an app's name: the entry `entries` has for it, or the id without
--- its suffix.
local function named(id, entries)
  local entry = entries and entries[id]
  if entry then return entry.name, entry.icon end
  return unicase.capitalise((id:gsub("%.desktop$", ""):gsub("^.*%.", "")))
end

--- The apps that can open `kind`, `{ key, id, name, icon, words }`.
function M.candidates(kind, cache, entries)
  local seen, out = {}, {}
  for _, mime in ipairs(kind.types) do
    for _, id in ipairs(cache[mime] or {}) do
      if not seen[id] then
        seen[id] = true
        local name, icon = named(id, entries)
        out[#out + 1] = { key = id, id = id, name = name, icon = icon, words = id }
      end
    end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

--- Every installed app, by desktop id.
function M.entries()
  local fake = host.fake() and require("lib.services.host_fake")
  if fake then return fake.apps() end
  local by_id = {}
  local ok, list = pcall(morf.apps.entries)
  for _, entry in ipairs(ok and type(list) == "table" and list or {}) do
    local id = entry.id or entry.desktop_id
    if id then
      id = id:find("%.desktop$") and id or (id .. ".desktop")
      by_id[id] = entry
    end
  end
  return by_id
end

--- The fixture's cache or the real one.
function M.known()
  local fake = host.fake() and require("lib.services.host_fake")
  return fake and fake.mime_cache() or M.cache()
end

--- `done(id)`: the default for `kind`, "" for none.
function M.current(kind, done)
  host.read({ "xdg-mime", "query", "default", kind.types[1] }, function(text)
    done(((text or ""):gsub("%s+", "")))
  end)
end

--- Sets `id` for every type of `kind`. `done(ok, why)`.
function M.set(kind, id, done)
  if not id:match("^[%w_%.%-]+%.desktop$") then return done(nil, "That is not an app") end
  local argv = { "xdg-mime", "default", id }
  for _, mime in ipairs(kind.types) do argv[#argv + 1] = mime end
  host.act(argv, done)
end

--- Whether `mimeapps.list` is a Home Manager link: a change would be lost on
--- the next switch.
function M.managed()
  local root = morf.env("XDG_CONFIG_HOME") or (morf.fs.home() .. "/.config")
  return host.managed(root .. "/mimeapps.list")
end

return M
