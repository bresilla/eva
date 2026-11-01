-- eva-clipboard's history: text and pictures copied, newest first, pins on top,
-- kept in a private folder. What a password manager marks is never read.
--
-- The store, which readers outside this tool may rely on:
--
--   $XDG_STATE_HOME/eva/clipboard/history.json     mode 600, replaced atomically
--
-- A JSON array, pinned entries first, then newest first. An entry is
--
--   id      a string, unique in the file
--   kind    "text" or "image"
--   text    the words, for "text"
--   path    the picture's file beside the history, for "image"
--   mime    its type, for "image"
--   time    when it was copied, in unix milliseconds
--   pinned  true, or absent
--
-- Fields are only ever added. To put an entry back on the clipboard, set its
-- `text`, or the bytes at `path` as `mime`, with `morf.clipboard.set`; to remove
-- one, change the file by `M.remove`'s rule: an entry and its picture go
-- together. tests/clipboard_spec.lua holds this shape.
local morf = require("morf")

local M = {
  items = morf.signal("clipboard.items", {}),
  query = morf.signal("clipboard.query", ""),
  message = morf.signal("clipboard.message", ""),
}

M.LIMIT = 200
M.TEXT_LIMIT = 65536

-- The types a password manager adds to mark what it copies.
M.SECRET = {
  ["x-kde-passwordManagerHint"] = true,
  ["org.nspasteboard.ConcealedType"] = true,
  ["application/x-nspasteboard-concealed-type"] = true,
}

local function folder()
  return (morf.env("XDG_STATE_HOME") or (morf.fs.home() .. "/.local/state")) .. "/eva/clipboard"
end

local function index() return folder() .. "/history.json" end

local function dry()
  local value = morf.env("EVA_DRY_RUN")
  return value ~= nil and value ~= "" and value ~= "0"
end

local function save(list)
  M.items:set(list)
  morf.fs.write(index(), morf.json.encode(list), { atomic = true, parents = true, mode = 384 })
end

function M.load()
  local ok, list = pcall(function() return morf.json.decode(morf.fs.read(index())) end)
  if ok and type(list) == "table" then M.items:set(list) end
end

-- `list` with pins first, within the limit; what falls off loses its file.
local function trimmed(list)
  local pinned, rest = {}, {}
  for _, item in ipairs(list) do
    if item.pinned then pinned[#pinned + 1] = item else rest[#rest + 1] = item end
  end
  for i = #rest, M.LIMIT + 1, -1 do
    if rest[i].path then pcall(morf.fs.remove, rest[i].path) end
    rest[i] = nil
  end
  for _, item in ipairs(rest) do pinned[#pinned + 1] = item end
  return pinned
end

local function add(item)
  local list = { item }
  for _, old in ipairs(M.items:get()) do
    if old.kind == "text" and item.kind == "text" and old.text == item.text then item.pinned = old.pinned
    else list[#list + 1] = old end
  end
  save(trimmed(list))
end

local function fresh_id()
  return tostring(morf.time.now_ms()) .. "-" .. tostring(#M.items:get())
end

--- Whether `mime_types` hold a password manager's mark.
function M.secret(mime_types)
  for _, mime in ipairs(mime_types or {}) do
    if M.SECRET[mime] then return true end
  end
  return false
end

local function image_of(mime_types)
  for _, mime in ipairs(mime_types or {}) do
    if mime:sub(1, 6) == "image/" then return mime end
  end
end

--- Text arrived on the clipboard.
function M.text(text)
  if text == "" or #text > M.TEXT_LIMIT then return end
  add { id = fresh_id(), kind = "text", text = text, time = morf.time.now_ms() }
end

--- A picture arrived on the clipboard.
function M.image(bytes, mime)
  local id = fresh_id()
  local path = folder() .. "/" .. id .. "." .. (mime:match("image/([%w%+%-]+)") or "img")
  morf.fs.write(path, bytes, { parents = true, mode = 384 })
  add { id = id, kind = "image", path = path, mime = mime, time = morf.time.now_ms() }
end

--- What `morf.clipboard.watch` hears.
function M.offer(offer)
  if M.secret(offer.mime_types) then return end
  local image = image_of(offer.mime_types)
  offer:read(image and "image" or "text", function(bytes)
    if not bytes or #bytes == 0 then return end
    if image then M.image(bytes, image) else M.text(bytes) end
  end)
end

--- Starts hearing the clipboard.
function M.watch()
  if morf.clipboard.supported and not dry() then morf.clipboard.watch(M.offer) end
end

local function find(id)
  for _, item in ipairs(M.items:get()) do
    if item.id == id then return item end
  end
end

--- Puts entry `id` back on the clipboard.
function M.copy(id)
  local item = find(id)
  if not item then return false end
  if not dry() then
    if item.kind == "image" then morf.clipboard.set(morf.fs.read(item.path), item.mime)
    else morf.clipboard.set(item.text) end
  end
  M.message:set("Copied")
  return true
end

function M.toggle_pin(id)
  local list = {}
  for _, item in ipairs(M.items:get()) do
    local copy = {}
    for key, value in pairs(item) do copy[key] = value end
    if copy.id == id then copy.pinned = not copy.pinned or nil end
    list[#list + 1] = copy
  end
  save(trimmed(list))
end

function M.remove(id)
  local list = {}
  for _, item in ipairs(M.items:get()) do
    if item.id == id then
      if item.path then pcall(morf.fs.remove, item.path) end
    else list[#list + 1] = item end
  end
  save(list)
end

--- Empties the history, keeping what is pinned.
function M.clear()
  local list = {}
  for _, item in ipairs(M.items:get()) do
    if item.pinned then list[#list + 1] = item
    elseif item.path then pcall(morf.fs.remove, item.path) end
  end
  save(list)
end

--- The entries matching the query.
function M.found()
  local needle = M.query:get():lower()
  if needle == "" then return M.items:get() end
  local out = {}
  for _, item in ipairs(M.items:get()) do
    if item.kind == "text" and item.text:lower():find(needle, 1, true) then out[#out + 1] = item end
  end
  return out
end

return M
