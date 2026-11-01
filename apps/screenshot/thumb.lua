-- The small picture that floats in the corner after a shot: a press opens it in
-- the editor, a press on its pin keeps it on the screen, and left alone it
-- fades. Its surface lives as long as it shows, and this module is loaded by the
-- first shot.
local morf = require("morf")
local config = require("config")
local theme = require("theme")
local S = theme.space

local M = {
  -- The file shown, while one is.
  showing = morf.signal("eva.capture.thumb", ""),
  -- The preview's picture, and whether it is on its way out.
  source = morf.signal("eva.capture.thumb.source", ""),
  leaving = morf.signal("eva.capture.thumb.leaving", false),
}

M.WIDTH = 216
M.SHORTEST = 72

local surface, preview, timer, capture_module, own_file
local serial = 0

local function private_path()
  local folder = (morf.env("XDG_RUNTIME_DIR") or "/tmp") .. "/eva"
  morf.fs.mkdir(folder)
  return ("%s/capture-thumb-%d-%d.png"):format(folder, morf.process_id, morf.time.now_ms())
end

local function stop_timer()
  if timer then timer:cancel() timer = nil end
end

local function release_preview()
  if preview then pcall(preview.close) preview = nil end
  M.source:set("")
end

local function drop_file()
  if own_file then pcall(morf.fs.remove, own_file) own_file = nil end
end

-- The surface and its picture let go; a file made for it goes unless `keep`.
local function gone(keep)
  stop_timer()
  serial = serial + 1
  local had = surface ~= nil
  if surface then
    local layer = surface
    surface = nil
    layer:close()
    morf.time.timer(1, function() layer:destroy() end, false)
  end
  release_preview()
  M.showing:set("")
  M.leaving:set(false)
  if not keep then drop_file() end
  if had and capture_module then capture_module.held:set(math.max(0, capture_module.held:get() - 1)) end
end

--- Takes it away now, as a new capture does.
function M.dismiss() gone() end

--- Starts the time it stays over.
function M.linger()
  stop_timer()
  if not surface then return end
  M.leaving:set(false)
  local seconds = tonumber(config.get("capture.thumbnail_seconds")) or 5
  timer = morf.time.timer(seconds * 1000, function()
    timer = nil
    M.leaving:set(true)
    local current = serial
    timer = morf.time.timer(theme.duration.normal, function()
      if current == serial then gone() end
    end, false)
  end, false)
end

--- The editor on it, in the place of the thumbnail.
function M.edit()
  local path, capture = M.showing:get(), capture_module
  if path == "" or not capture then return false end
  local mine = own_file
  gone(true)
  own_file = nil
  capture.present(function()
    local ok = capture.open_file(path, nil, function()
      if mine then pcall(morf.fs.remove, mine) end
    end)
    if not ok and mine then pcall(morf.fs.remove, mine) end
  end)
  return true
end

--- Keeps it on the screen as a pin, in the place of the thumbnail.
function M.pin()
  local path, capture = M.showing:get(), capture_module
  if path == "" or not capture then return false end
  local mine = own_file
  gone(true)
  own_file = nil
  return require("pin").add(capture, path, mine ~= nil)
end

local function open_preview(path, width, height)
  local current = serial
  local ok, opened = pcall(morf.image.preview, path)
  if not ok or not opened then M.source:set(path) return end
  preview = opened
  local scale = math.floor(((morf.screens or {})[1] or {}).density_scale or 1) * 120
  local queued = pcall(opened.cover, math.floor(width), math.floor(height), math.max(120, scale), function(done, result)
    if current == serial and done then M.source:set(result.path) end
  end)
  if not queued then M.source:set(path) end
end

--- Shows the shot at `saved`, or, with nothing saved, a private copy of the
--- picture at `rendered` that goes with it. Answers whether it shows.
function M.show(capture, saved, rendered)
  capture_module = capture
  gone()
  local path = saved
  if not path or path == "" then
    path = private_path()
    local ok, copied = pcall(morf.fs.copy, rendered, path)
    if not ok or not copied then return false end
    own_file = path
  end
  local ok, info = pcall(morf.image.info, path)
  if not ok or not info then drop_file() return false end
  local screen = (morf.screens or {})[1] or {}
  local width = math.min(M.WIDTH, math.floor((screen.width or 1920) * 0.5))
  local height = math.floor(width * info.height / info.width)
  height = math.max(M.SHORTEST, math.min(width, height))
  M.showing:set(path)
  M.leaving:set(false)
  open_preview(path, width, height)
  local bar = require("bar")
  local x, y, desk_width, desk_height = bar.desk()
  local view = require("themes").view("capture_thumb")
  surface = morf.window.layer {
    blend = "srgb", namespace = "eva-capture-thumb", layer = "overlay",
    anchors = { bottom = true, right = true }, exclusive_zone = -1, keyboard_focus = "none",
    margin_right = math.max(S.l, (screen.width or 0) - x - desk_width + S.l),
    margin_bottom = math.max(S.l, (screen.height or 0) - y - desk_height + S.l),
    width = width, height = height, visible = true,
    root = view.build(M, width, height),
  }
  capture.held:set(capture.held:get() + 1)
  M.linger()
  return true
end

return M
