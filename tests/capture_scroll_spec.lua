-- A long picture of a window as it scrolls: frames cut from a long page by the
-- real image workers, read and joined the real way, and the join held against
-- the page. tools/see/capture-scroll.steps runs it on a real window.
--
--     morf test --no-dbus tests/capture_scroll_spec.lua
local test = morf.test

local TOOL = "../apps/screenshot/app.lua"

local SOURCE = [[
  local scratch = morf.env("XDG_CACHE_HOME") .. "/capture-scroll"
  morf.fs.remove(scratch, { recursive = true })
  morf.fs.mkdir(scratch .. "/shots")
  local W, H, LONG = 300, 400, 1600
  local parts = { ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">'):format(W, LONG) }
  for y = 0, LONG - 1 do
    local r, g, b = y % 251, (y * 7) % 241, (y * 13) % 239
    parts[#parts + 1] = ('<rect x="0" y="%d" width="%d" height="1" fill="rgb(%d,%d,%d)"/>'):format(y, W // 2, r, g, b)
    parts[#parts + 1] = ('<rect x="%d" y="%d" width="%d" height="1" fill="rgb(%d,%d,%d)"/>'):format(W // 2, y, W // 2, b, r, g)
  end
  parts[#parts + 1] = "</svg>"
  local page = scratch .. "/page.png"
  local ready = false
  morf.image.process { source = table.concat(parts), output = page, ops = {}, on_done = function() ready = true end }
  local detached, at, presses, step = {}, 0, 0, 240
  morf.process.detach = function(argv) detached[#detached + 1] = table.concat(argv, " ") end
  require("config").set("capture.folder", scratch .. "/shots")
  require("config").set("capture.thumbnail", false)
  require("app")
  local env = morf.env
  morf.env = function(key) if key == "EVA_DRY_RUN" then return "0" end return env(key) end
  local capture = require("capture")
  morf.shared("eva.capture.owner", ""):set("")
  local real_keyboard = morf.virtual_keyboard
  morf.virtual_keyboard = { key = function(code, down)
    if code == 109 and down then presses = presses + 1 at = math.min(LONG - H, at + step) end
  end }
  morf.ipc.prepare = function()
    local scroll = require("scroll")
    scroll.grab = function(path, _, done)
      morf.image.process { source = page, output = path, ops = { { "crop", 0, at, W, H } }, on_done = function(ok, why) done(ok, why) end }
    end
    return ready
  end
  morf.ipc.to = function(y) at = tonumber(y) return at end
  morf.ipc.step = function(rows) step = tonumber(rows) return step end
  morf.ipc.frames_kept = function()
    local count = 0
    for _, folder in ipairs(morf.fs.list(morf.env("XDG_RUNTIME_DIR") .. "/morf") or {}) do
      for _, file in ipairs(folder.is_dir and morf.fs.list(folder.path) or {}) do
        if file.name:match("^frame%-") then count = count + 1 end
      end
    end
    return count
  end
  morf.ipc.flow = function()
    local scroll = package.loaded.scroll
    local long = {}
    for _, entry in ipairs(morf.fs.list(scratch .. "/shots") or {}) do long[#long + 1] = entry.path end
    return { state = scroll and scroll.state:get() or "", rows = scroll and scroll.rows:get() or 0, frames = scroll and scroll.frames:get() or 0,
      loaded = scroll ~= nil, phase = capture.phase:get(), message = capture.message:get(), held = capture.held:get(), files = long,
      presses = presses, detached = detached }
  end
  morf.ipc.same_as_page = function(path, y, from)
    local a = morf.image.pixel(path, 40, y)
    local b = morf.image.pixel(page, 40, from)
    local c = morf.image.pixel(path, 200, y)
    local d = morf.image.pixel(page, 200, from)
    return tostring(a) == tostring(b) and tostring(c) == tostring(d)
  end
  morf.ipc.size = function(path)
    local info = morf.image.info(path)
    return { info.width, info.height }
  end
  morf.ipc.no_reader = function()
    morf.screencopy = nil
    require("lib.shell.capture.read").on_path = function() return false end
  end
]]

local function tool(style, size)
  test.load(TOOL, { source = SOURCE, size = size or { 1200, 800 },
    env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
  test.wait(function() return test.ipc("prepare") or nil end, 5000, "the page was not made")
end

-- The page's frames are made by real workers, in real time.
local function until_true(check, what)
  return test.wait(function()
    test.advance(50)
    return check() or nil
  end, 20000, "timed out: " .. what)
end

-- Waits for the join to reach `at` rows down the page.
local function reached(at)
  until_true(function() return test.ipc("flow").rows >= at + 400 end, at .. " rows")
end

local function following()
  test.ipc("capture-scroll", "screen") test.advance(400)
  until_true(function() return test.ipc("flow").state == "following" end, "it to start")
  until_true(function() return test.ipc("flow").frames >= 1 end, "its first frame")
end

local function ended()
  return until_true(function()
    local now = test.ipc("flow")
    return now.state == "" and now or nil
  end, "it to end")
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": follows a window scrolled by hand and joins it row for row", function()
    tool(style)
    following()
    test.ipc("to", 240)
    reached(240)
    test.ipc("to", 480)
    reached(480)
    test.ipc("to", 700)
    test.truthy(test.find { id = "capture-scroll-pill", visible = true })
    test.ipc("capture-scroll", "done")
    local state = ended()
    test.eq(state.phase, "ready")
    test.eq(state.message, "Long capture saved.")
    test.eq(state.held, 0, "the pill's hold stayed")
    test.eq(#state.files, 1)
    test.contains(state.files[1], "_long.png")
    test.eq(test.ipc("size", state.files[1]), { 300, 700 + 400 })
    for _, y in ipairs { 0, 1, 399, 400, 401, 640, 880, 1099 } do
      test.truthy(test.ipc("same_as_page", state.files[1], y, y), "row " .. y .. " is not the page's")
    end
    test.contains(state.detached[#state.detached], "--saved-picture")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("is not loaded until it is asked for", function()
  test.load(TOOL, { source = [[
    require("app")
    morf.ipc.loaded = function() return { scroll = package.loaded.scroll ~= nil, stitch = package.loaded["lib.shell.capture.stitch"] ~= nil,
      trim = package.loaded.trim ~= nil, recent = package.loaded.recent ~= nil, pin = package.loaded.pin ~= nil, thumb = package.loaded.thumb ~= nil } end
  ]], size = { 1200, 800 }, env = { EVA_STYLE = "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
  test.eq(test.ipc("loaded"), { scroll = false, stitch = false, trim = false, recent = false, pin = false, thumb = false })
end)

test.it("takes a last short move at the end", function()
  tool()
  following()
  test.ipc("to", 240)
  reached(240)
  test.ipc("to", 260)
  test.ipc("capture-scroll", "done")
  local state = ended()
  test.eq(test.ipc("size", state.files[1]), { 300, 260 + 400 })
  test.truthy(test.ipc("same_as_page", state.files[1], 659, 659))
end)

test.it("goes back up and on again without a seam", function()
  tool()
  following()
  test.ipc("to", 240)
  reached(240)
  test.ipc("to", 100)
  local seen = test.ipc("flow").frames
  until_true(function() return test.ipc("flow").frames > seen + 1 end, "a frame gone back up")
  test.ipc("to", 480)
  reached(480)
  test.ipc("capture-scroll", "done")
  local state = ended()
  test.eq(test.ipc("size", state.files[1]), { 300, 480 + 400 })
  for _, y in ipairs { 300, 640, 700, 879 } do
    test.truthy(test.ipc("same_as_page", state.files[1], y, y), "row " .. y)
  end
end)

test.it("presses Page Down itself, and stops at the end of the page", function()
  tool()
  following()
  test.truthy(test.ipc("capture-scroll", "auto"))
  local state = ended()
  test.truthy(state.presses >= 5, "it pressed the key " .. state.presses .. " times")
  test.eq(#state.files, 1)
  test.eq(test.ipc("size", state.files[1]), { 300, 1600 })
  for _, y in ipairs { 0, 500, 1000, 1599 } do
    test.truthy(test.ipc("same_as_page", state.files[1], y, y), "row " .. y)
  end
end)

test.it("stops at a page end that comes in a short last move", function()
  tool()
  following()
  test.ipc("step", 350)
  test.truthy(test.ipc("capture-scroll", "auto"))
  local state = ended()
  test.eq(state.message, "Long capture saved.")
  test.eq(test.ipc("size", state.files[1]), { 300, 1600 })
  test.truthy(test.ipc("same_as_page", state.files[1], 1599, 1599))
end)

test.it("takes its first frame before the pill stands over the picture", function()
  tool()
  test.ipc("capture-scroll", "screen") test.advance(400)
  until_true(function() return test.ipc("flow").state == "following" end, "it to start")
  test.falsy(test.find { id = "capture-scroll-pill" }, "the pill came before the first frame")
  until_true(function() return test.ipc("flow").frames >= 1 end, "its first frame")
  test.advance(100)
  test.truthy(test.find { id = "capture-scroll-pill" }, "no pill after it")
  test.ipc("capture-scroll", "cancel")
  ended()
end)

test.it("stops at a jump it cannot follow, says so, and keeps what is sound", function()
  tool()
  following()
  test.ipc("to", 240)
  reached(240)
  test.ipc("to", 1100)
  local state = ended()
  test.contains(state.message, "scroll more slowly")
  test.eq(test.ipc("size", state.files[1]), { 300, 240 + 400 })
  test.truthy(test.ipc("same_as_page", state.files[1], 639, 639), "the last sound row is wrong")
end)

test.it("says nothing was saved when it is lost on the first move", function()
  tool()
  following()
  test.ipc("to", 1100)
  local state = ended()
  test.contains(state.message, "Nothing was saved")
  test.eq(#state.files, 0)
end)

test.it("keeps no more whole frames than it stands on", function()
  tool()
  following()
  for _, at in ipairs { 120, 240, 360, 480, 600, 720, 840 } do
    test.ipc("to", at)
    reached(at)
    test.advance(300)
  end
  until_true(function() return test.ipc("frames_kept") <= 2 end, "the frames to go")
  test.ipc("capture-scroll", "done")
  local state = ended()
  test.eq(test.ipc("size", state.files[1]), { 300, 840 + 400 })
  test.truthy(test.ipc("same_as_page", state.files[1], 1239, 1239))
end)

test.it("says so when nothing scrolled, and writes nothing", function()
  tool()
  following()
  test.advance(600)
  test.ipc("capture-scroll", "done")
  local state = ended()
  test.contains(state.message, "did not scroll")
  test.eq(#state.files, 0)
end)

test.it("cancels with nothing saved", function()
  tool()
  following()
  test.ipc("to", 240)
  reached(240)
  test.ipc("capture-scroll", "cancel")
  local state = ended()
  test.eq(#state.files, 0)
  test.eq(state.held, 0)
  test.eq(state.phase, "ready")
end)

test.it("ends with the tool's cancel, as the shell asks before a password prompt", function()
  tool()
  following()
  test.truthy(test.ipc("capture-editor", "cancel"))
  local state = ended()
  test.eq(#state.files, 0)
  test.eq(state.phase, "ready")
end)

test.it("says plainly when the screen cannot be read", function()
  tool()
  test.ipc("no_reader")
  test.ipc("capture-scroll", "screen") test.advance(600)
  local state = test.ipc("flow")
  test.contains(state.message, "grim")
  test.eq(state.phase, "error")
end)

test.it("stands its pill off the picture, and fits a phone without Page Down", function()
  tool("tsugumori", { 412, 915 })
  following()
  local pill
  for _, one in ipairs(test.surfaces()) do
    if tostring(one.label):find("eva-capture-scroll", 1, true) then pill = one end
  end
  test.truthy(pill, "no pill")
  test.truthy(pill.x >= 0 and pill.x + pill.width <= 412, "it left the phone's width")
  test.falsy(test.find { id = "capture-scroll-auto", visible = true }, "Page Down offered on a phone")
  test.truthy(test.find { id = "capture-scroll-done", visible = true })
  test.ipc("capture-scroll", "cancel")
  ended()
end)
