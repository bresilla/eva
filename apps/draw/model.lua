-- eva-draw's state: the marks on the screen, the stroke under way, the pen. A
-- stroke's outline comes from `morf.image.annotation_path`, the capture editor's
-- own geometry for a pen. No nodes.
local morf = require("morf")

local M = {
  marks = morf.list_model({}),
  draft = morf.signal("draw.draft", nil),
  typing = morf.signal("draw.typing", nil),
  pen = morf.signal("draw.pen", "r"),
  width = morf.signal("draw.width", 2),
  writing = morf.signal("draw.writing", false),
  board = morf.signal("draw.board", false),
  drawing = morf.signal("draw.drawing", false),
}

-- The pens by the key that picks them; `signal` names the theme's colour.
M.PENS = {
  { key = "r", name = "Alert", signal = "alert" },
  { key = "y", name = "Warm", signal = "warn" },
  { key = "g", name = "Good", signal = "ok" },
  { key = "c", name = "Cool", signal = "info" },
  { key = "b", name = "Accent", signal = "accent" },
  { key = "p", name = "Extra", signal = "extra" },
}
M.WIDTHS = { 2, 4, 8, 16 }
-- The least move kept of a stroke, and how many points one piece of it holds.
M.STEP = 1.5
M.PIECE = 512
-- A letter's size to a pen's width.
M.TEXT = 6

local serial = 0

local function key()
  serial = serial + 1
  return tostring(serial)
end

local function pen_width() return M.WIDTHS[M.width:get()] end

-- A stroke's outline and the box it stands in, at the screen's pixels.
local function outline(points, width)
  local line = points
  if #line == 1 then line = { line[1], { x = line[1].x + 0.01, y = line[1].y } } end
  local mark = { type = "pen", points = line, color = "#000000", width = math.max(1, width) }
  local box = morf.image.annotation_bounds(mark)
  local pad = width
  return {
    d = morf.image.annotation_path(mark).stroke, width = width,
    x = box.x - pad, y = box.y - pad, w = box.w + 2 * pad, h = box.h + 2 * pad,
  }
end

local function keep(path, pen)
  path.kind, path.key, path.pen = "stroke", key(), pen
  M.marks:insert(M.marks:len() + 1, path)
end

local points

--- Starts a stroke at `x`, `y`.
function M.begin(x, y)
  points = { { x = x, y = y } }
  M.drawing:set(true)
  M.draft:set(outline(points, pen_width()))
end

--- Takes the stroke on to `x`, `y`, keeping a long one in pieces.
function M.move(x, y)
  if not points then return end
  local last = points[#points]
  local dx, dy = x - last.x, y - last.y
  if dx * dx + dy * dy < M.STEP * M.STEP then return end
  points[#points + 1] = { x = x, y = y }
  if #points >= M.PIECE then
    keep(outline(points, pen_width()), M.pen:get())
    points = { { x = x, y = y } }
  end
  M.draft:set(outline(points, pen_width()))
end

--- Ends the stroke.
function M.finish()
  if not points then return end
  keep(outline(points, pen_width()), M.pen:get())
  points = nil
  M.draft:set(nil)
  M.drawing:set(false)
end

--- A place for words at `x`, `y`.
function M.place(x, y)
  M.commit()
  M.typing:set { x = x, y = y, text = "" }
end

--- Adds `text` to the words under way.
function M.type(text)
  local now = M.typing:get()
  if now then M.typing:set { x = now.x, y = now.y, text = now.text .. text } end
end

--- Takes back the last character of the words under way.
function M.erase()
  local now = M.typing:get()
  if not now or now.text == "" then return end
  local last = utf8.offset(now.text, -1)
  M.typing:set { x = now.x, y = now.y, text = now.text:sub(1, last - 1) }
end

--- Keeps the words under way.
function M.commit()
  local now = M.typing:get()
  M.typing:set(nil)
  if not now or now.text == "" then return end
  M.marks:insert(M.marks:len() + 1, { kind = "text", key = key(), pen = M.pen:get(), x = now.x, y = now.y,
    text = now.text, size = pen_width() * M.TEXT })
end

--- Leaves the words under way, kept or not.
function M.cancel_text()
  M.typing:set(nil)
end

--- Takes back the last mark.
function M.undo()
  local count = M.marks:len()
  if count > 0 then M.marks:remove(count) end
end

--- Takes every mark back.
function M.clear()
  M.commit()
  M.marks:replace({})
end

--- One step of the pen's width, `by` -1 or 1.
function M.widen(by)
  M.width:set(math.max(1, math.min(#M.WIDTHS, M.width:get() + by)))
end

--- Picks the pen of `name`, if there is one.
function M.choose(name)
  for _, pen in ipairs(M.PENS) do
    if pen.key == name then M.pen:set(name) return true end
  end
  return false
end

--- Between marks and words.
function M.toggle_writing()
  M.commit()
  M.writing:set(not M.writing:get())
end

return M
