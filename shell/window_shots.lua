-- Pictures of windows: what the workspace gesture, the overview and the
-- switcher all draw. `take` works through a queue one window at a time.
-- The cache keeps each window's latest picture.
local morf = require("morf")
local M = {}

--- The compositor's identifier for `client`, by its class and title; nil
--- when two windows share them.
function M.toplevel(client)
  if client.toplevel then return client.toplevel end
  local found
  for _, window in ipairs(morf.windows or {}) do
    if window.app_id == client.class and window.title == client.title then
      if found then return nil end
      found = window.identifier
    end
  end
  return found
end

--- Whether pictures stay on the GPU: not on a software renderer.
local function on_gpu()
  local software = morf.env and morf.env("LIBGL_ALWAYS_SOFTWARE")
  return not (software and software ~= "" and software ~= "0")
end

--- Lets a picture go.
function M.release(source)
  if source and source ~= "" and morf.screencopy then pcall(morf.screencopy.release, source) end
end

--- Captures each `{ identifier, deliver }` of `queue` in turn: `deliver` gets
--- the picture's source. `wanted()` going false stops the queue and lets any
--- later picture go.
function M.take(queue, wanted)
  local index = 0
  local function next_one()
    if wanted and not wanted() then return end
    if M.paused then return end
    index = index + 1
    local item = queue[index]
    if not item or not morf.screencopy or not morf.screencopy.capture_window then return end
    local ok = pcall(morf.screencopy.capture_window, item.identifier, function(frame, why)
      if frame and frame.source then
        if wanted and not wanted() then M.release(frame.source) return end
        item.deliver(frame.source)
      elseif why then M.refused = tostring(why) end
      next_one()
    end, { gpu = on_gpu() })
    if not ok then next_one() end
  end
  next_one()
end

--- Holds every capture back for `ms`: the compositor ends the connection over
--- a capture of a window it has just destroyed (NEEDS.md).
M.paused = false
local paused_by
function M.pause(ms)
  M.paused = true
  if paused_by then paused_by:cancel() end
  paused_by = morf.time.timer(ms or 1500, function()
    paused_by = nil
    M.paused = false
  end, false)
end

-- ------------------------------------------------------------------ cache --

local cache = {}
local revision = morf.signal("eva.window_shots.revision", 0)
local running = false

--- The latest picture of `address` ("" for none); a binding follows it.
function M.source(address)
  revision:get()
  local entry = cache[address]
  return entry and entry.source or ""
end

--- When `address` was last captured, 0 for never.
function M.age(address)
  local entry = cache[address]
  return entry and entry.at or 0
end

--- Forgets a window that has gone.
function M.forget(address)
  local entry = cache[address]
  if not entry then return end
  M.release(entry.source)
  cache[address] = nil
  revision:set(revision:get() + 1)
end

--- Captures `clients` into the cache, those longest unseen first; false
--- while a pass is running.
function M.refresh(clients)
  if running or M.paused then return false end
  local ordered = {}
  for _, c in ipairs(clients) do
    local identifier = M.toplevel(c)
    if identifier then ordered[#ordered + 1] = { c = c, identifier = identifier } end
  end
  table.sort(ordered, function(a, b) return M.age(a.c.address) < M.age(b.c.address) end)
  local queue = {}
  for i, item in ipairs(ordered) do
    local address = item.c.address
    queue[i] = { identifier = item.identifier, deliver = function(source)
      local entry = cache[address]
      if entry then M.release(entry.source) end
      cache[address] = { source = source, at = morf.time.now_ms() }
      revision:set(revision:get() + 1)
      if i == #ordered then running = false end
    end }
  end
  if #queue == 0 then return true end
  running = true
  M.take(queue)
  -- A pass ends by itself after two seconds, answered or not.
  morf.time.timer(2000, function() running = false end, false)
  return true
end

return M
