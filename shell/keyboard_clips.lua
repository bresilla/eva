-- The strip's clipboard: what eva-clipboard's store holds, read while the
-- keyboard is up and never while the session is locked. The store is the
-- tool's alone to write.
local morf = require("morf")
local config = require("config")
local store = require("lib.shell.clipboard.store")

local M = { items = morf.signal("eva.keyboard.clips", {}) }

local SHOWN = 12
-- How long a copy counts as just made, in ms.
local FRESH = 60000

local function locked()
  local lock = morf.lock and morf.lock.state
  return lock ~= nil and lock:get() ~= "unlocked"
end

local function read()
  if config.get("keyboard.clipboard") ~= true or locked() then
    M.items:set({})
    return
  end
  local out = {}
  for _, item in ipairs(store.read() or {}) do
    if item.kind == "text" and type(item.text) == "string" then
      out[#out + 1] = { id = item.id, text = item.text, pinned = item.pinned == true, time = item.time }
      if #out >= SHOWN then break end
    end
  end
  M.items:set(out)
end

local watch

--- Follows the store while the keyboard is up.
function M.follow(on)
  if on then
    read()
    if not watch and morf.fs.watch then
      local ok, handle = pcall(morf.fs.watch, store.index(), read)
      if ok then watch = handle end
    end
  else
    if watch then watch:close() watch = nil end
    M.items:set({})
  end
end

--- The newest entry, when it was copied a moment ago.
function M.fresh()
  local first
  for _, item in ipairs(M.items:get()) do
    if not item.pinned then first = item break end
  end
  if first and first.time and morf.time.now_ms() - first.time < FRESH then return first end
end

--- One line of an entry, for a chip.
function M.line(item)
  return (item.text:gsub("%s+", " "):sub(1, 200))
end

return M
