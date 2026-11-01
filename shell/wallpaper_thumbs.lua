-- Small copies of pictures, made once on an image worker and kept in the cache.
-- A thumbnail is asked for only while its tile is built, so a folder of
-- thousands costs the tiles on show.
local morf = require("morf")
local M = { SIZE = 320 }

-- Counts finished thumbnails: a tile reads it and looks again.
M.made = morf.signal("eva.wallpaper.thumbs", 0)

local BUSY = 6
local folder = morf.paths.cache("eva-thumbs")
local pending, waiting, working = {}, {}, 0

local function target(path, modified)
  local stamp = morf.encoding.sha1(path .. "\n" .. tostring(modified or ""))
  return morf.fs.join(folder, stamp .. ".jpg")
end

local pump
local function start(job)
  working = working + 1
  local function done()
    working = working - 1
    pending[job.out] = nil
    M.made:set(M.made:get() + 1)
    pump()
  end
  local ok, queued = pcall(morf.image.process, { source = job.path, output = job.out, quality = 80,
    ops = { { "resize", M.SIZE, M.SIZE, "fit" } }, on_done = done })
  if not ok or not queued then done() end
end

pump = function()
  while working < BUSY and #waiting > 0 do start(table.remove(waiting, 1)) end
end

--- The thumbnail of `path`, or "" while it is being made.
function M.get(path, modified)
  if not path or path == "" then return "" end
  local out = target(path, modified)
  if morf.fs.is_file(out) then return out end
  if not pending[out] then
    pending[out] = true
    morf.fs.mkdir(folder, { parents = true })
    waiting[#waiting + 1] = { path = path, out = out }
    pump()
  end
  return ""
end

return M
