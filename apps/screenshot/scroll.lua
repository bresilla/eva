-- A long picture of a window as it scrolls. Frames of one place on the screen are
-- taken while the person scrolls, or while Page Down is pressed for them, each is
-- lined up on the last by lib.shell.capture.stitch, and the new rows of each are
-- kept and joined at the end. A frame that cannot be lined up ends the capture
-- with what is sound so far. Loaded the first time a scrolling capture starts.
local morf = require("morf")
local config = require("config")
local backend = require("lib.shell.capture")
local stitch = require("lib.shell.capture.stitch")
local read = require("lib.shell.capture.read")

local M = {
  -- "following" while frames are taken, "joining" at the end, "" otherwise.
  state = morf.signal("eva.capture.scroll", ""),
  rows = morf.signal("eva.capture.scroll.rows", 0),
  frames = morf.signal("eva.capture.scroll.frames", 0),
  strips = morf.signal("eva.capture.scroll.strips", 0),
  -- What the last frame came to.
  verdict = morf.signal("eva.capture.scroll.verdict", ""),
  auto = morf.signal("eva.capture.scroll.auto", false),
}

-- A row's signature: one column for this many pixels, between these bounds, fine
-- enough to tell two lines of text that differ by a digit. The last column is left
-- out, where a scroll bar moves.
M.COLUMN_WIDTH = 16
M.LEAST_COLUMNS, M.MOST_COLUMNS = 32, 128
-- Pixels read a turn, within what one handler may spend; a frame every so many ms;
-- how long a page takes to settle after a key; and how long a frame may take.
M.PIXELS_A_TURN = 3000
M.EVERY = 200
M.SETTLE = 450
M.FRAME_LIMIT = 8000
-- The share of a frame that must move to keep a strip, the most strips a join
-- takes, and how many still frames end the automatic scroll.
M.SHARE = 0.125
M.MOST_STRIPS = 240
M.STILL_FRAMES = 3
-- Linux's code for Page Down.
M.PAGE_DOWN = 109
M.TOO_FAST = "Lost the page: scroll more slowly. Saved up to there"
M.TOO_SOON = "Lost the page: scroll more slowly. Nothing was saved"
M.NOTHING = "The window did not scroll, so there is nothing to join"

local capture, session, run, box, pill, timer, waiting, broken, finishing, holding
local using = {}
local serial, sequence, strips, first_path, last_path, latest, still, stopping, cutting = 0, 0, {}, nil, nil, nil, 0, false, 0
local no_screencopy = false

--- Whether the screen can be read from here at all.
function M.available()
  return morf.screencopy ~= nil or read.on_path("grim")
end

--- Writes the place `area` of the screen to `path`: `done(ok, why)`. Through the
--- compositor where it can, by grim where it cannot.
function M.grab(path, area, done)
  local screen = (morf.screens or {})[1] or {}
  local scale = screen.density_scale or 1
  local function by_grim()
    no_screencopy = true
    local where = ("%d,%d %dx%d"):format(area.x, area.y, area.w, area.h)
    local ok = pcall(morf.process.run, { "grim", "-l", "1", "-g", where, path }, {}, function(result)
      done(result and result.ok == true, result and (result.error or result.stderr))
    end)
    if not ok then done(false, "grim is not installed") end
  end
  if no_screencopy then by_grim() return end
  local ok = pcall(morf.screencopy.save, { path = path, output = screen.name,
    region = { x = math.floor((area.x - (screen.x or 0)) * scale), y = math.floor((area.y - (screen.y or 0)) * scale),
      w = math.floor(area.w * scale), h = math.floor(area.h * scale) },
    on_done = function(good) if good then done(true) else by_grim() end end })
  if not ok then by_grim() end
end

--- Reads the signatures of the picture at `path`, in turns: `done(rows)`, or
--- `done(nil, why)`.
function M.signature(path, done)
  local info, why = morf.image.info(path)
  if not info then done(nil, why) return end
  local preview = morf.image.preview(path)
  local current = serial
  local columns = math.max(M.LEAST_COLUMNS, math.min(M.MOST_COLUMNS, info.width // M.COLUMN_WIDTH))
  local queued = preview.render({ { "resize", columns, info.height, "exact" } }, function(ok, result)
    if not ok or current ~= serial then
      pcall(preview.close)
      done(nil, ok and "stopped" or result)
      return
    end
    local source, rows, y = result.path, {}, 0
    local rows_a_turn = math.max(1, M.PIXELS_A_TURN // columns)
    local function turn()
      if current ~= serial then pcall(preview.close) return end
      local stop = math.min(info.height, y + rows_a_turn)
      while y < stop do
        local parts = {}
        for x = 0, columns - 2 do parts[x + 1] = tostring(morf.image.pixel(source, x, y)) end
        y = y + 1
        rows[y] = table.concat(parts)
      end
      if y < info.height then morf.time.timer(1, turn, false) return end
      pcall(preview.close)
      done(rows)
    end
    turn()
  end)
  if not queued then pcall(preview.close) done(nil, "The picture queue is full") end
end

-- A frame goes once nothing is cut from it and the run no longer stands on it.
local function retire(path)
  if (using[path] or 0) == 0 and path ~= last_path and path ~= first_path then
    using[path] = nil
    session.remove(path)
  end
end

-- The rows `strip` of the frame at `path`, kept as a picture of their own. A join
-- waits for every one of them, and one that fails ends it: no gap is left.
local function cut(path, strip)
  cutting = cutting + 1
  using[path] = (using[path] or 0) + 1
  session.render(path, { { "crop", 0, strip.from, box.pixels, strip.height } }, function(ok, out)
    cutting = cutting - 1
    using[path] = using[path] - 1
    retire(path)
    if ok then
      strips[#strips + 1] = { path = out, y = strip.y }
      M.strips:set(#strips)
    else
      broken = tostring(out)
    end
    if cutting == 0 and waiting then
      local next_step = waiting
      waiting = nil
      next_step()
    end
  end)
end

local function stop_timer()
  if timer then timer:cancel() timer = nil end
end

-- The pill, after the first frame: off the place captured where there is room,
-- else over its top rows, which are then left out of comparing.
local function show_pill()
  local view = require("themes").view("capture_scroll")
  local width, height = view.size()
  local gap = require("theme").space.s
  local screen = (morf.screens or {})[1] or { width = 1920, height = 1080 }
  local top = box.y - (screen.y or 0)
  local edge = "top"
  if top < height + gap and (screen.height or 0) - top - box.h >= height + gap then edge = "bottom" end
  if edge == "top" and top < height + gap then
    run.guard = math.ceil((height + gap - top) * (box.pixels_h or box.h) / box.h)
  end
  pill = morf.window.layer {
    blend = "srgb", namespace = "eva-capture-scroll", layer = "overlay", exclusive_zone = -1, keyboard_focus = "none",
    anchors = { [edge] = true }, ["margin_" .. edge] = gap, width = width, height = height, visible = true,
    root = view.build(M),
  }
end

local function take_down()
  stop_timer()
  serial = serial + 1
  if pill then
    local layer = pill
    pill = nil
    layer:close()
    morf.time.timer(1, function() layer:destroy() end, false)
  end
  if holding then
    holding = false
    capture.held:set(math.max(0, capture.held:get() - 1))
  end
  if session then session.close() session = nil end
  M.state:set("") M.auto:set(false)
  if capture.phase:get() == "scrolling" then capture.phase:set("ready") end
end

local function finished(message)
  take_down()
  capture.message:set(message or "")
end

-- The picture of all of it, saved as a shot is.
local function join(height, message)
  if broken then finished(broken) return end
  local ops = {}
  for _, strip in ipairs(strips) do ops[#ops + 1] = { "overlay", strip.path, 0, strip.y } end
  session.compose(box.pixels, height, ops, function(ok, picture)
    if not ok then finished(tostring(picture)) return end
    local target = capture.folder() .. "/capture_" .. morf.time.format("%Y%m%d_%H-%M-%S") .. "_long.png"
    morf.fs.mkdir(capture.folder())
    backend.save(picture, target, function(good, saved)
      if not good then finished(tostring(saved)) return end
      finished(message or "Long capture saved.")
      if capture.editor.on_export then capture.editor.on_export("save", saved) end
      if config.get("capture.thumbnail") then require("thumb").show(capture, saved) end
    end)
  end)
end

local function wrap_up(message)
  if stopping then return end
  stopping = true
  stop_timer()
  serial = serial + 1
  if not run then finished(M.NOTHING) return end
  if latest and run.fits(latest.found) then
    local kept = run.accept(latest.rows, latest.found)
    if kept.first then
      cut(first_path, { from = 0, height = kept.first, y = 0 })
      first_path = nil
    end
    if kept.strip then cut(latest.path, kept.strip) end
    last_path = latest.path
  end
  latest = nil
  local tail, height = run.finish()
  if not tail then
    finished(message == M.TOO_FAST and M.TOO_SOON or message or M.NOTHING)
    return
  end
  M.state:set("joining")
  if tail.height > 0 then cut(last_path, tail) end
  local function go() join(height, message) end
  if cutting > 0 then waiting = go else go() end
end

--- Ends it and joins what it has, one last frame first: the last of the
--- scrolling may have come after the last frame.
function M.done()
  if finishing or stopping then return end
  finishing = true
  if timer then
    stop_timer()
    M.step()
  end
end

--- Ends it with nothing saved.
function M.cancel()
  stopping = true
  finished("")
end

local function press_page()
  local keyboard = morf.virtual_keyboard
  if keyboard then
    pcall(keyboard.key, M.PAGE_DOWN, true)
    pcall(keyboard.key, M.PAGE_DOWN, false)
  end
end

--- Page Down pressed for the person, from now on, until the page ends.
function M.follow_keys()
  if M.state:get() ~= "following" then return false end
  M.auto:set(not M.auto:get())
  still = 0
  return M.auto:get()
end

local function again()
  if finishing then wrap_up() return end
  local current = serial
  local wait = M.EVERY
  if M.auto:get() then
    press_page()
    wait = M.SETTLE
  end
  timer = morf.time.timer(wait, function()
    timer = nil
    if current == serial then M.step() end
  end, false)
end

local function take_in(path, rows)
  M.frames:set(M.frames:get() + 1)
  local verdict = run.add(rows)
  local kind = verdict.kind
  M.verdict:set(kind .. (verdict.shift and (" " .. verdict.shift) or ""))
  if kind == "first" then
    first_path, last_path = path, path
    show_pill()
  elseif kind == "moved" then
    if latest then session.remove(latest.path) end
    still, latest = 0, nil
    local previous = last_path
    if verdict.first then
      cut(first_path, { from = 0, height = verdict.first, y = 0 })
      first_path = nil
    end
    if verdict.strip then
      cut(path, verdict.strip)
      M.rows:set(verdict.strip.y + verdict.strip.height)
    end
    last_path = path
    retire(previous)
    if #strips >= M.MOST_STRIPS or (run.covered + box.pixels_h) * box.pixels * 4 >= morf.image.limits.max_decoded_bytes
      or run.covered + box.pixels_h >= morf.image.limits.max_dimension then
      wrap_up("The picture is as long as it can be")
      return
    end
  elseif kind == "small" then
    -- The same short move again is a page at its end.
    still = latest and latest.found.shift == verdict.found.shift and still + 1 or 0
    if latest then session.remove(latest.path) end
    latest = { path = path, rows = verdict.rows, found = verdict.found }
    if M.auto:get() and still >= M.STILL_FRAMES then
      wrap_up()
      return
    end
  elseif kind == "lost" then
    session.remove(path)
    wrap_up(M.TOO_FAST)
    return
  else
    session.remove(path)
    if kind == "same" then still = still + 1 end
    if M.auto:get() and still >= M.STILL_FRAMES then
      wrap_up()
      return
    end
  end
  again()
end

--- Takes the next frame.
function M.step()
  if not session or stopping then return end
  sequence = sequence + 1
  local path = session.path("frame-" .. sequence .. ".png")
  local current = serial
  local mine = sequence
  -- A frame that never comes ends it out loud.
  morf.time.timer(M.FRAME_LIMIT, function()
    if current == serial and mine == sequence and session then
      finished("The screen stopped answering")
    end
  end, false)
  M.grab(path, box, function(ok, why)
    if current ~= serial then return end
    if not ok then finished("Could not read the screen: " .. tostring(why)) return end
    M.signature(path, function(rows, trouble)
      if current ~= serial then return end
      if not rows then finished(tostring(trouble)) return end
      if not box.pixels then
        local info = morf.image.info(path)
        box.pixels, box.pixels_h = info.width, info.height
        run = stitch.new(math.max(1, math.floor(info.height * M.SHARE)))
      end
      take_in(path, rows)
    end)
  end)
end

--- Starts following `area`, `{ x, y, w, h }` in layout pixels of the whole desk.
function M.start(module, area)
  capture = module
  if not M.available() then return false, "Neither the compositor nor grim can read the screen here" end
  serial, sequence = serial + 1, 0
  box, strips, first_path, last_path, latest, still, stopping = area, {}, nil, nil, nil, 0, false
  run, waiting, broken, finishing, cutting, using = nil, nil, nil, false, 0, {}
  session = backend.session {}
  M.rows:set(0) M.strips:set(0) M.frames:set(0) M.verdict:set("") M.auto:set(false)
  M.state:set("following")
  capture.held:set(capture.held:get() + 1)
  holding = true
  -- The first frame, once the panel or the selection has left the screen.
  timer = morf.time.timer(M.SETTLE, function() timer = nil M.step() end, false)
  return true
end

return M
