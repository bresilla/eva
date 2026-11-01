-- The ways a window can be other than tiled in its workspace: two windows side
-- by side, one floating over the rest, and a video in a small window of its own
-- that stays on every workspace.
local morf = require("morf")
local services = require("services")
local windows = require("windows_model")
local snap_model = require("snap_model")
local session = require("themes.session")
local M = {}

local steps = windows.steps

-- The window in picture in picture ("" for none), and its box when small.
M.pip = session.keep("eva.windows.pip", "")
M.pip_large = morf.signal("eva.windows.pip_large", false)
-- Which edge a stashed picture in picture is tucked behind ("" for none).
M.stashed = morf.signal("eva.windows.pip_stashed", "")
M.controls = morf.signal("eva.windows.pip_controls", false)
M.split = session.keep("eva.windows.split", {})

local PIP_W, PIP_W_LARGE, PIP_ASPECT, PIP_MARGIN, STASH_SHOWN = .3, .45, 9 / 16, 24, 28
local VIDEO = { mpv = true, vlc = true, ["org.videolan.vlc"] = true, celluloid = true, ["io.github.celluloid_player.celluloid"] = true }

--- Whether a window shows a video: its class, or a browser's own small player.
function M.is_video(c)
  return VIDEO[(c.class or ""):lower()] == true or (c.title or ""):find("Picture%-in%-Picture") ~= nil
    or (c.title or ""):find("Picture in picture", 1, true) ~= nil
end

local function area(c) return snap_model.area(windows.monitor_of(c) or {}) end

-- -------------------------------------------------------------------- split --

--- Puts the window `address` beside the focused one, tiled, on this workspace:
--- the two share the screen. Without another window it stays as it is.
function M.split_with(address)
  local c = windows.get(address)
  if not c then return false end
  local here = windows.int(services.workspace.active())
  local other
  for _, w in ipairs(windows.recent()) do
    if w.address ~= address and w.workspace == here then other = w break end
  end
  if not other then
    for _, w in ipairs(windows.recent()) do
      if w.address ~= address and w.workspace > 0 then other = w break end
    end
  end
  if not other then return false end
  local list = steps.float(false)
  if c.workspace ~= here then table.insert(list, 1, steps.to_workspace(here, false)[1]) end
  windows.run(address, list)
  local second = steps.float(false)
  if other.workspace ~= here then table.insert(second, 1, steps.to_workspace(here, false)[1]) end
  windows.run(other.address, second)
  M.split:set { first = other.address, second = address }
  return true
end

--- Moves the divider between the two by `delta`, a fraction of the screen. The
--- compositor's ratio runs 0 to 2, so 0.1 of the screen is 0.2 of it.
function M.nudge(delta)
  local message = ("splitratio %+.3f"):format(delta * 2)
  return windows.send(("hl.dispatch(hl.dsp.layout(%q))"):format(message), "layoutmsg", message)
end

--- The stops a let-go divider rests on, as the first window's share.
M.STOPS = { .3, .5, .7 }

--- Rests the divider on the stop nearest `share`, from where it stands now.
function M.settle_divider(share, now)
  local best = M.STOPS[1]
  for _, stop in ipairs(M.STOPS) do
    if math.abs(stop - share) < math.abs(best - share) then best = stop end
  end
  if math.abs(best - now) < .01 then return false end
  return M.nudge(best - now)
end

--- The two tiled windows sharing this workspace, or nil.
function M.pair()
  local tiled = {}
  for _, c in ipairs(windows.on(windows.int(services.workspace.active()))) do
    if not c.floating and (c.fullscreen or 0) == 0 then tiled[#tiled + 1] = c end
  end
  if #tiled == 2 then return tiled[1], tiled[2] end
end

--- Where the divider of a pair stands on this surface: `x, y, along` for one
--- across the screen, `vertical` when the two lie side by side.
function M.divider()
  local a, b = M.pair()
  if not a then return nil end
  local ra, rb = windows.rect(a), windows.rect(b)
  if rb.x < ra.x then ra, rb = rb, ra end
  if ra.x + ra.width <= rb.x + 1 then
    return { vertical = true, x = (ra.x + ra.width + rb.x) / 2, y = ra.y, length = ra.height,
      first = ra.width, total = ra.width + rb.width }
  end
  if rb.y < ra.y then ra, rb = rb, ra end
  return { vertical = false, x = ra.x, y = (ra.y + ra.height + rb.y) / 2, length = ra.width,
    first = ra.height, total = ra.height + rb.height }
end

-- ------------------------------------------------------------------ floating --

--- Floats a window in the middle of the screen, a touch over the others:
--- a tablet's windows, or a phone's pop-up. Again, it goes back to the tiles.
function M.toggle_float(address)
  local c = windows.get(address)
  if not c then return false end
  if c.floating then return windows.run(address, steps.float(false)) end
  local a = area(c)
  local w, h = a.width * .78, a.height * .62
  return windows.run(address, steps.box(a.x + (a.width - w) / 2, a.y + (a.height - h) / 2, w, h))
end

-- -------------------------------------------------------- picture in picture --

local function pip_box(c, large)
  local a = area(c)
  local w = a.width * (large and PIP_W_LARGE or PIP_W)
  local h = w * PIP_ASPECT
  return a.x + a.width - w - PIP_MARGIN, a.y + a.height - h - PIP_MARGIN, w, h
end

--- Puts a window in picture in picture: small, in a corner, on every
--- workspace; or takes it back out.
function M.toggle_pip(address)
  address = address or M.pip:get()
  local c = windows.get(address)
  if not c then return false end
  if M.pip:get() == address then
    M.pip:set("")
    M.stashed:set("")
    M.controls:set(false)
    local list = steps.pin()
    list[#list + 1] = steps.float(false)[1]
    return windows.run(address, list)
  end
  local x, y, w, h = pip_box(c, false)
  local list = steps.box(x, y, w, h)
  if not c.pinned then list[#list + 1] = steps.pin()[1] end
  M.pip:set(address)
  M.pip_large:set(false)
  M.stashed:set("")
  return windows.run(address, list)
end

--- A double tap: the larger size, or back.
function M.resize_pip()
  local c = windows.get(M.pip:get())
  if not c then return false end
  M.pip_large:set(not M.pip_large:get())
  local x, y, w, h = pip_box(c, M.pip_large:get())
  return windows.run(c.address, steps.box(x, y, w, h))
end

--- Moves the picture by the pointer: `x, y` its top left, in the compositor's
--- pixels. Off either side it tucks away, leaving a tab.
function M.move_pip(x, y)
  local c = windows.get(M.pip:get())
  if not c then return false end
  return windows.run(c.address, steps.place(x, y))
end

--- Where a released picture rests: tucked behind an edge when thrown past it.
function M.rest_pip(x, y)
  local c = windows.get(M.pip:get())
  if not c then return false end
  local a = area(c)
  local tuck = ""
  if x + c.width / 2 < a.x then tuck = "left"
  elseif x + c.width / 2 > a.x + a.width then tuck = "right" end
  M.stashed:set(tuck)
  local to_x = math.max(a.x + PIP_MARGIN, math.min(a.x + a.width - c.width - PIP_MARGIN, x))
  if tuck == "left" then to_x = a.x - c.width + STASH_SHOWN
  elseif tuck == "right" then to_x = a.x + a.width - STASH_SHOWN end
  local to_y = math.max(a.y + PIP_MARGIN, math.min(a.y + a.height - c.height - PIP_MARGIN, y))
  return windows.run(c.address, steps.place(to_x, to_y))
end

--- Brings a tucked picture back.
function M.unstash()
  local c = windows.get(M.pip:get())
  if not c then return false end
  local x, y = pip_box(c, M.pip_large:get())
  M.stashed:set("")
  return windows.run(c.address, steps.place(x, c.y or y))
end

--- Closes the picture's window.
function M.close_pip()
  local address = M.pip:get()
  M.pip:set("")
  M.controls:set(false)
  return windows.close(address)
end

function M.toggle_controls() M.controls:set(not M.controls:get()) end

--- Plays or pauses what is playing.
function M.play_pause()
  local media = services.media
  if media and media.state.available then media.play_pause() return true end
  return false
end

-- The window gone, its picture goes.
morf.effect("eva.windows.pip.gone", function()
  local address = M.pip:get()
  if address ~= "" and not windows.get(address) then
    M.pip:set("")
    M.controls:set(false)
  end
end)

-- With its setting on, leaving the workspace a playing video is on takes the
-- video along, small.
local was_on
morf.effect("eva.windows.pip.auto", function()
  local here = windows.int(services.workspace.active())
  local left = was_on
  was_on = here
  if left == nil or left == here or require("config").get("windows.pip_auto") ~= true then return end
  if M.pip:get() ~= "" or not services.player().playing then return end
  for _, c in ipairs(windows.on(left)) do
    if M.is_video(c) then
      morf.time.timer(1, function() M.toggle_pip(c.address) end, false)
      return
    end
  end
end)

--- The picture's box on this surface, or nil.
function M.pip_rect()
  local c = windows.get(M.pip:get())
  return c and windows.rect(c) or nil
end

-- A surface's pixels to the compositor's, for the picture's position.
local function layout_point(x, y)
  local c = windows.get(M.pip:get())
  local m = windows.monitor_of(c) or {}
  local ratio = windows.ratio(m)
  return x / ratio + (m.x or 0), y / ratio + (m.y or 0)
end

function M.move_to(x, y) return M.move_pip(layout_point(x, y)) end
function M.drop_at(x, y) return M.rest_pip(layout_point(x, y)) end

local view = require("themes").view("window_modes").build(M)
M.node = view.node

return M
