-- eva-ruler's state and actions: the frozen picture, the pointer on it, the edges
-- round it, the box of bounds mode, and what is read out.
--
-- The walk reads strips: the pointer's row and column, cropped off a decoded
-- picture on an image worker and read in memory. Two sessions hold one strip
-- each; a move during a render waits, and only the newest is asked for. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local scan = require("scan")
local frozen = require("common.freeze").new("ruler")

local M = {
  picture = frozen.picture,
  overlay = frozen.overlay,
  mode = morf.signal("ruler.mode", "spacing"),
  tolerance = morf.signal("ruler.tolerance", 30),
  at = morf.signal("ruler.at", nil),
  edges = morf.signal("ruler.edges", nil),
  box = morf.signal("ruler.box", nil),
  message = morf.signal("ruler.message", ""),
  copied = morf.signal("ruler.copied", ""),
}

M.MODES = { "spacing", "horizontal", "vertical", "bounds" }
M.TOLERANCE = { step = 5, least = 0, most = 120 }

morf.effect("ruler.frozen-message", function()
  local words = frozen.message:get()
  if words ~= "" then M.message:set(words) end
end)

M.scale = frozen.scale

local row = { index = -1, path = nil, session = nil }
local column = { index = -1, path = nil, session = nil }
local busy, wanted = false, nil

local function close_sessions()
  for _, strip in ipairs { row, column } do
    if strip.session then strip.session.close() end
    strip.session, strip.path, strip.index = nil, nil, -1
  end
end

--- Picks the mode `name`, if there is one.
function M.choose(name)
  for _, mode in ipairs(M.MODES) do
    if mode == name then
      M.mode:set(name)
      M.box:set(nil)
      return true
    end
  end
  return false
end

--- Holds the screen.
function M.freeze()
  close_sessions()
  M.edges:set(nil)
  M.box:set(nil)
  M.at:set(nil)
  frozen.take()
end

--- Lets it go.
function M.thaw()
  close_sessions()
  frozen.release()
end

local function channels(path, x, y)
  local c = morf.image.pixel(path, x, y)
  if not c then return 0, 0, 0 end
  return c.r, c.g, c.b
end

-- The edges round picture pixel `px`, `py`, from the strips held.
local function measure(px, py)
  local picture = M.picture:get()
  if not picture or not row.path or not column.path then return end
  local tolerance = M.tolerance:get() / 255
  local function along(x) return channels(row.path, x, 0) end
  local function down(y) return channels(column.path, 0, y) end
  M.edges:set {
    left = scan.walk(along, px, -1, 0, tolerance), right = scan.walk(along, px, 1, picture.width - 1, tolerance),
    top = scan.walk(down, py, -1, 0, tolerance), bottom = scan.walk(down, py, 1, picture.height - 1, tolerance),
  }
end

local function render(strip, index, ops, done)
  if strip.index == index and strip.path then return done() end
  local ok, why = pcall(strip.session.render, ops, function(fine, result)
    if fine then
      strip.path, strip.index = result.path, index
    else
      M.message:set(tostring(result))
    end
    done()
  end)
  if not ok then
    M.message:set(tostring(why))
    done()
  end
end

local ask

-- Crops the row and the column of `px`, `py`, then walks.
local function fetch(px, py)
  local picture = M.picture:get()
  if not picture then return end
  busy = true
  row.session = row.session or morf.image.preview(picture.path)
  column.session = column.session or morf.image.preview(picture.path)
  render(row, py, { { "crop", 0, py, picture.width, 1 } }, function()
    render(column, px, { { "crop", px, 0, 1, picture.height } }, function()
      busy = false
      measure(px, py)
      if wanted then ask(wanted.px, wanted.py) end
    end)
  end)
end

ask = function(px, py)
  if busy then wanted = { px = px, py = py } return end
  wanted = nil
  fetch(px, py)
end

--- The pointer at surface `x`, `y`.
function M.point(x, y)
  local picture = M.picture:get()
  if not picture then return end
  local scale = M.scale()
  local px = math.max(0, math.min(picture.width - 1, math.floor(x * scale)))
  local py = math.max(0, math.min(picture.height - 1, math.floor(y * scale)))
  M.at:set { x = x, y = y, px = px, py = py }
  if M.mode:get() ~= "bounds" then ask(px, py) end
end

--- Starts a box at surface `x`, `y`.
function M.box_start(x, y)
  M.box:set { x0 = x, y0 = y, x1 = x, y1 = y }
end

--- Takes the box's far corner to `x`, `y`.
function M.box_move(x, y)
  local box = M.box:get()
  if box then M.box:set { x0 = box.x0, y0 = box.y0, x1 = x, y1 = y } end
end

--- A step of the tolerance, walked again from the same pixel.
function M.tune(by)
  local t = M.TOLERANCE
  M.tolerance:set(math.max(t.least, math.min(t.most, M.tolerance:get() + by * t.step)))
  local at = M.at:get()
  if at and not busy then measure(at.px, at.py) end
end

-- Millimetres a picture pixel across and down, where the screen says.
local function physical()
  local fake = morf.env("EVA_FAKE_SCREEN_MM")
  local screen = (morf.screens or {})[1] or {}
  local mm_w, mm_h = screen.physical_width_mm, screen.physical_height_mm
  if fake and fake ~= "" then mm_w, mm_h = fake:match("^(%d+)x(%d+)$") end
  mm_w, mm_h = tonumber(mm_w) or 0, tonumber(mm_h) or 0
  local picture = M.picture:get()
  if mm_w <= 0 or mm_h <= 0 or not picture then return nil end
  return mm_w / picture.width, mm_h / picture.height
end

--- The width and height measured, in picture pixels: nil for an axis the mode
--- leaves out.
function M.size()
  local mode = M.mode:get()
  if mode == "bounds" then
    local box = M.box:get()
    if not box then return nil, nil end
    local scale = M.scale()
    return math.floor(math.abs(box.x1 - box.x0) * scale + 0.5), math.floor(math.abs(box.y1 - box.y0) * scale + 0.5)
  end
  local edges = M.edges:get()
  if not edges then return nil, nil end
  local width, height = edges.right - edges.left + 1, edges.bottom - edges.top + 1
  if mode == "horizontal" then return width, nil end
  if mode == "vertical" then return nil, height end
  return width, height
end

local function pair(width, height, spell)
  if width and height then return spell(width) .. " × " .. spell(height) end
  return spell(width or height)
end

--- The measure in pixels, as a line.
function M.reading()
  local width, height = M.size()
  if not width and not height then return "" end
  return pair(width, height, function(n) return ("%d"):format(n) end) .. " px"
end

--- The measure in millimetres and inches, or "" where the screen does not say.
function M.physical_reading()
  local mm_x, mm_y = physical()
  local width, height = M.size()
  if not mm_x or (not width and not height) then return "" end
  local mm = pair(width and width * mm_x, height and height * mm_y, function(n) return ("%.1f"):format(n) end)
  local inches = pair(width and width * mm_x / 25.4, height and height * mm_y / 25.4,
    function(n) return ("%.2f"):format(n) end)
  return mm .. " mm · " .. inches .. " in"
end

--- The measure on the clipboard.
function M.copy()
  local words = M.reading()
  if words == "" then return false end
  sys.copy(words)
  M.copied:set(words)
  M.message:set("Copied " .. words)
  return true
end

return M
