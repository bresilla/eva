-- eva-screenshot's window: what to take, and the recent pictures. No nodes.
local morf = require("morf")
local config = require("config")
local capture = require("lib.shell.capture")
local read = require("lib.shell.capture.read")

local M = {
  delay = morf.signal("screenshot.delay", 0),
  how = morf.signal("screenshot.how", "edit"),
  recent = morf.signal("screenshot.recent", {}),
  readers = morf.signal("screenshot.readers", {}),
}

M.DELAYS = { 0, 3, 5, 10 }
M.RECENT = 6

function M.folder() return (capture.expand(config.get("capture.folder"))) end

--- The newest pictures in the captures folder.
function M.load()
  local list = {}
  for _, entry in ipairs(morf.fs.list(M.folder()) or {}) do
    if entry.name:match("%.png$") then list[#list + 1] = entry end
  end
  table.sort(list, function(a, b) return a.name > b.name end)
  local recent = {}
  for i = 1, math.min(M.RECENT, #list) do recent[i] = { name = list[i].name, path = list[i].path } end
  M.recent:set(recent)
  read.available(function(found) M.readers:set(found) end)
end

local function command(words)
  local argv = { "sh", morf.paths.shell("cli") }
  for _, word in ipairs(words) do argv[#argv + 1] = word end
  return argv
end

-- The command runs once this window has gone, so it is not in the picture.
local function leave_and(words)
  morf.process.detach(command(words))
  morf.time.timer(50, function() morf.quit() end, false)
end

--- Takes `target` the way the window says.
function M.take(target)
  local words = { target, "--" .. M.how:get(), "--delay", tostring(M.delay:get() + 1) }
  leave_and(words)
end

--- Reads `kind` ("ocr" or "qr") from a region.
function M.read(kind) leave_and { kind, "region", "--delay", "1" } end

function M.open(path) morf.process.detach { "xdg-open", path } end

return M
