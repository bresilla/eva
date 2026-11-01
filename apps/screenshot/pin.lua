-- A shot kept floating above the windows as a reference, on a surface of its own
-- for as long as it stays: a drag moves it and a press closes it. Loaded by the
-- first pin.
local morf = require("morf")
local theme = require("theme")
local S = theme.space

local M = {
  -- The pins up: `{ path, surface, own, x, y, width, height, preview }`.
  list = {},
  count = morf.signal("eva.capture.pins", 0),
}

-- How much of the screen a pin may take at first, and how far a drag must go
-- before a press has become a move.
M.SHARE = 0.4
M.SLOP = 8

local capture
local made = 0

local function screen() return (morf.screens or {})[1] or { width = 1920, height = 1080 } end

-- What a reload brings back: a theme change must not take a reference away.
local function remember()
  local out = {}
  for i, one in ipairs(M.list) do out[i] = { path = one.path, own = one.own == true, x = one.x, y = one.y } end
  capture.pins_kept:set(#out > 0 and morf.json.encode(out) or "")
end

--- The size a picture of `width` by `height` floats at on `room`.
function M.fit(width, height, room)
  local most_w, most_h = (room.width or 1920) * M.SHARE, (room.height or 1080) * M.SHARE
  local factor = math.min(1, most_w / width, most_h / height)
  return math.max(S.TARGET * 2, math.floor(width * factor)), math.max(S.TARGET * 2, math.floor(height * factor))
end

local function held(by)
  if capture then capture.held:set(math.max(0, capture.held:get() + by)) end
  M.count:set(#M.list)
end

--- Takes pin `one` off the screen, with the private file it was made from.
function M.close(one)
  for i, each in ipairs(M.list) do
    if each == one then
      table.remove(M.list, i)
      local layer = one.surface
      one.surface = nil
      if layer then
        layer:close()
        morf.time.timer(1, function() layer:destroy() end, false)
      end
      if one.preview then pcall(one.preview.close) one.preview = nil end
      if one.own then pcall(morf.fs.remove, one.path) end
      held(-1)
      remember()
      return true
    end
  end
  return false
end

--- Every pin taken down.
function M.clear()
  while M.list[1] do M.close(M.list[1]) end
end

local function place(one)
  local room = screen()
  one.x = math.max(0, math.min((room.width or 0) - one.width, one.x))
  one.y = math.max(0, math.min((room.height or 0) - one.height, one.y))
  local surface = one.surface
  if surface then
    surface.margin_left, surface.margin_top = math.floor(one.x), math.floor(one.y)
  end
end

--- Moves pin `one` by `dx`, `dy`, kept on the screen.
function M.nudge(one, dx, dy)
  one.x, one.y = one.x + dx, one.y + dy
  place(one)
  remember()
end

--- Pins the picture at `path`; `own` says it is a private file, to go with the
--- pin. `at`, if given, is where it stood. Answers the pin, or nil and why.
function M.add(module, path, own, at)
  capture = module or capture
  local ok, info = pcall(morf.image.info, path)
  if not ok or not info then
    if own then pcall(morf.fs.remove, path) end
    return nil, "Not a picture: " .. tostring(path)
  end
  local room = screen()
  local width, height = M.fit(info.width, info.height, room)
  -- Each one a step along from the last, so none hides another.
  local step = #M.list * (S.xl + S.s)
  made = made + 1
  local one = { path = path, own = own, width = width, height = height, index = made,
    x = at and at.x or (room.width or 0) - width - S.xxl - step, y = at and at.y or S.xxl * 2 + step,
    source = morf.signal("eva.capture.pin.source." .. made, "") }
  M.list[#M.list + 1] = one
  local fine, preview = pcall(morf.image.preview, path)
  if fine and preview then
    one.preview = preview
    local scale = math.max(120, math.floor((room.density_scale or 1) * 120 + 0.5))
    local queued = pcall(preview.cover, width, height, scale, function(done, result)
      if done then one.source:set(result.path) end
    end)
    if not queued then one.source:set(path) end
  else
    one.source:set(path)
  end
  local view = require("themes").view("capture_pin")
  one.surface = morf.window.layer {
    blend = "srgb", namespace = "eva-capture-pin", layer = "top",
    anchors = { top = true, left = true }, exclusive_zone = -1, keyboard_focus = "none",
    margin_left = math.floor(math.max(0, one.x)), margin_top = math.floor(one.y),
    width = width, height = height, visible = true,
    root = view.build(M, one),
  }
  place(one)
  held(1)
  remember()
  return one
end

--- The pins of before a reload, up again.
function M.restore(module, words)
  local ok, kept = pcall(morf.json.decode, words)
  for _, each in ipairs(ok and type(kept) == "table" and kept or {}) do
    if morf.fs.exists(each.path) then M.add(module, each.path, each.own, each) end
  end
end

return M
