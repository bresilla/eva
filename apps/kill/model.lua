-- eva-kill's state and actions: the windows on the screen, the one under the
-- pointer, and ending it the way the window menu's Force quit does. No nodes.
local morf = require("morf")
local capture = require("lib.shell.capture")
local dispatch = require("lib.shell.window_dispatch")
local pointer = require("lib.shell.pointer")
local sys = require("common.sys")

local M = {
  windows = morf.signal("kill.windows", {}),
  hover = morf.signal("kill.hover", nil),
  armed = morf.signal("kill.armed", false),
  leaving = morf.signal("kill.leaving", false),
  ended = morf.signal("kill.ended", ""),
  message = morf.signal("kill.message", ""),
}

-- How long it takes to go.
M.GONE = 420

local function name_of(window)
  local title = window.title or ""
  if title ~= "" then return title end
  return window.app or "Window"
end

-- The compositor's rectangles on this screen, in surface pixels.
local function on_surface(windows)
  local scale, out = pointer.scale(), {}
  for _, window in ipairs(windows or {}) do
    local row = {}
    for key, value in pairs(window) do row[key] = value end
    row.x, row.y = pointer.to_surface(window.x, window.y)
    row.w, row.h = window.w * scale, window.h * scale
    out[#out + 1] = row
  end
  return out
end

--- Whether this compositor can end a window from here.
function M.supported()
  local kind = capture.kind()
  return kind == "hyprland" or kind == "sway"
end

--- Reads the windows, and picks the one under the pointer's first position.
function M.load(done)
  capture.windows(function(windows)
    M.windows:set(on_surface(windows))
    pointer.start(function(x, y, known)
      if known then M.point(x, y) end
      if done then done() end
    end)
  end)
end

--- The pointer moved to `x`, `y`.
function M.point(x, y)
  local window = capture.window_at(M.windows:get(), x, y)
  local now = M.hover:get()
  if (window and window.title) ~= (now and now.title) or (window and window.x) ~= (now and now.x) then
    M.armed:set(false)
  end
  M.hover:set(window)
end

-- Ends `window`, then `done(ok)`.
local function finish(window, done)
  if capture.kind() == "hyprland" then
    dispatch.run(window.address, { dispatch.KILL }, done)
    return
  end
  sys.run({ "swaymsg", ("[con_id=%d] kill"):format(math.floor(window.id)) }, {}, function(result)
    done(result.ok or result.dry == true)
  end)
end

local function leave()
  M.leaving:set(true)
  morf.time.timer(M.GONE, function() morf.quit() end, false)
end

--- Ends the window under the pointer, and the tool with it.
function M.kill()
  local window = M.hover:get()
  if not window or M.leaving:get() then return false end
  M.ended:set(name_of(window))
  finish(window, function(ok)
    if not ok then morf.log("warn", "eva-kill: the compositor did not end " .. name_of(window)) end
    leave()
  end)
  return true
end

--- A press at `x`, `y`: at once with a pointer; `touch` asks for a second tap,
--- as a finger shows no hover first.
function M.press(x, y, touch)
  M.point(x, y)
  if not M.hover:get() then return false end
  if touch and not M.armed:get() then
    M.armed:set(true)
    return false
  end
  return M.kill()
end

--- Ends nothing, and goes.
function M.cancel()
  if M.leaving:get() then return end
  leave()
end

--- Ends the focused window with no overlay.
function M.active()
  if not M.supported() then
    morf.log("warn", "eva-kill: no way to end a window on this compositor")
    return morf.quit()
  end
  capture.windows(function(windows)
    local focused
    for _, window in ipairs(windows or {}) do
      if window.focused then focused = window end
    end
    if not focused then return morf.quit() end
    M.ended:set(name_of(focused))
    finish(focused, function() morf.quit() end)
  end)
end

return M
