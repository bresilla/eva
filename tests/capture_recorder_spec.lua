-- The recorder's pause and replay buffer, and a recording's trim and GIF. The
-- recorder here is the stand-in of tests/fixtures/bin-see, run as a real process
-- that hears the real signals; ffmpeg and ffprobe are stubbed.
-- tools/see/capture-recorder.steps runs the real ffmpeg.
--
--     morf test --no-dbus tests/capture_recorder_spec.lua
local test = morf.test

local TOOL = "../apps/screenshot/app.lua"
local ROOT = morf.fs.join(morf.env("PWD"), "")
local LOG = morf.env("XDG_CACHE_HOME") .. "/capture-recorder/args.log"

local SOURCE = [[
  local scratch = morf.env("XDG_CACHE_HOME") .. "/capture-recorder"
  local folder = scratch .. "/shots"
  morf.fs.remove(folder, { recursive = true })
  morf.fs.mkdir(folder)
  local standin = morf.fs.join(morf.env("PWD"), "tests/fixtures/bin-see/gpu-screen-recorder")
  morf.fs.copy(morf.fs.join(morf.env("PWD"), "tests/fixtures/wallpaper.png"), folder .. "/film.mp4")
  local detached = {}
  morf.process.detach = function(argv) detached[#detached + 1] = table.concat(argv, " ") end
  local config = require("config")
  config.set("capture.folder", folder)
  local log = "RECORD_ARGS=" .. scratch .. "/args.log"
  config.set("capture.commands.record_screen", { "env", log, standin, "-w", "$OUTPUT", "-f", "$FPS", "-o", "$FILE.mp4" })
  config.set("capture.commands.record_replay", { "env", log, standin, "-w", "$OUTPUT", "-f", "$FPS", "-r", "$SECONDS", "-c", "mp4", "-o", "$FOLDER" })
  require("lib.shell.capture.read").on_path = function(program) return morf.no_ffmpeg ~= true end
  require("app")
  local env = morf.env
  morf.env = function(key) if key == "EVA_DRY_RUN" then return "0" end return env(key) end
  local capture = require("capture")
  capture.recording:set(false) capture.paused:set(false) capture.replay:set(0) capture.elapsed:set(0)
  morf.shared("eva.capture.owner", ""):set("")
  morf.ipc.flow = function()
    return { recording = capture.recording:get(), paused = capture.paused:get(), replay = capture.replay:get(),
      phase = capture.phase:get(), message = capture.message:get(), elapsed = capture.elapsed:get(), file = capture.file:get(),
      detached = detached, trim = capture.trim_open:get(), started = capture.started:get(),
      can_pause = capture.can_pause(), keyboard = morf.surface.keyboard_focus }
  end
  morf.ipc.plain_recorder = function()
    config.set("capture.commands.record_screen", { "sh", "-c", "exec sleep 30", "$FILE.mp4" })
  end
  morf.ipc.no_ffmpeg = function() morf.no_ffmpeg = true end
  morf.ipc.film = function() return folder .. "/film.mp4" end
  morf.ipc.put = function(name) morf.fs.write(folder .. "/" .. name, "stand-in") end
]]

local function tool(style, size)
  morf.fs.mkdir(morf.env("XDG_CACHE_HOME") .. "/capture-recorder")
  morf.fs.write(LOG, "")
  test.load(TOOL, { source = SOURCE, size = size or { 1920, 1080 },
    env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
end

local function logged(words)
  return test.wait(function() return (morf.fs.read(LOG) or ""):find(words, 1, true) and true or nil end, 3000, "the stand-in heard nothing: " .. words)
end

local function count(words)
  local text, found = morf.fs.read(LOG) or "", 0
  for _ in text:gmatch(words) do found = found + 1 end
  return found
end

local function recording()
  test.ipc("record", "screen") test.advance(800)
  test.truthy(test.ipc("flow").recording)
  logged("-w ")
end

local function finish()
  test.ipc("record", "stop")
  test.wait(function() return not test.ipc("flow").recording or nil end, 3000, "the recorder did not stop")
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": pauses by the recorder's own signal, the clock held, and resumes", function()
    tool(style)
    recording()
    test.ipc("capture", "open") test.advance(100) test.settle(1000)
    test.truthy(test.find { id = "capture-pause", visible = true }, "no pause while recording")
    test.click("capture-pause") test.advance(100)
    logged("pause")
    local state = test.ipc("flow")
    test.truthy(state.paused)
    local held = state.elapsed
    test.advance(2500)
    test.eq(test.ipc("flow").elapsed, held, "the clock ran while paused")
    test.click("capture-pause") test.advance(100)
    test.wait(function() return count("pause\n") == 2 or nil end, 3000, "resume sent no signal")
    state = test.ipc("flow")
    test.falsy(state.paused)
    test.truthy(state.recording, "a pause ended the recording")
    finish()
    test.eq(test.ipc("flow").message, "Recording saved.")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("hides the pause from a recorder it would end, and keeps it off the panel at rest", function()
  tool()
  test.ipc("capture", "open") test.settle(1000)
  test.falsy(test.find { id = "capture-pause", visible = true }, "a pause showed at rest")
  test.ipc("capture", "close") test.settle(800)
  test.advance(400)
  test.ipc("plain_recorder")
  test.ipc("record", "screen") test.advance(800)
  test.truthy(test.ipc("flow").recording, "no recording")
  test.falsy(test.ipc("flow").can_pause)
  test.eq(test.ipc("record", "pause"), false)
  test.ipc("capture", "open") test.advance(100) test.settle(1000)
  test.truthy(test.find { id = "capture-record", visible = true })
  test.falsy(test.find { id = "capture-pause", visible = true }, "a pause was offered to a recorder it would end")
  finish()
end)

test.it("takes pause and resume from the command line's verbs, and a pause needs a recording", function()
  tool()
  test.eq(test.ipc("record", "pause"), false)
  recording()
  test.eq(test.ipc("record", "pause"), "paused")
  logged("pause")
  test.eq(test.ipc("record", "pause"), false, "a second pause toggled it")
  test.eq(test.ipc("record", "resume"), "recording")
  finish()
end)

test.it("a stop while paused still saves", function()
  tool()
  recording()
  test.ipc("record", "pause")
  logged("pause")
  finish()
  local state = test.ipc("flow")
  test.falsy(state.paused)
  test.eq(state.message, "Recording saved.")
end)

test.it("tells the shell a pause, the clock with it", function()
  local display = (morf.env("WAYLAND_DISPLAY") or "wayland-0"):match("[^/]+$")
  local path = morf.env("XDG_RUNTIME_DIR") .. "/eva/capture-" .. display .. ".json"
  morf.fs.write(LOG, "")
  test.load(TOOL, { source = SOURCE, size = { 1920, 1080 }, env = { EVA_STYLE = "material", EVA_DRY_RUN = "0",
    LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
  recording()
  test.ipc("record", "pause")
  test.advance(100)
  test.ipc("capture", "open") test.settle(300)
  local state = morf.json.decode(morf.fs.read(path))
  test.eq(state.paused, true)
  test.truthy(state.elapsed ~= nil)
  finish()
  morf.fs.remove(path)
end)

test.it("the shell's clock stands while the tool says paused", function()
  local display = (morf.env("WAYLAND_DISPLAY") or "wayland-0"):match("[^/]+$")
  local path = morf.env("XDG_RUNTIME_DIR") .. "/eva/capture-" .. display .. ".json"
  test.load("../shell/init.lua", { source = [[
    require("init")
    local capture = require("capture")
    morf.ipc.mirrored = function() return { paused = capture.paused:get(), elapsed = capture.elapsed:get(), recording = capture.recording:get() } end
  ]], size = { 1920, 1080 }, env = { EVA_STYLE = "material", EVA_DRY_RUN = "1", EVA_WALLPAPER = "", LULE_A = "/nonexistent/lule" } })
  test.settle(800)
  morf.fs.write(path, morf.json.encode { pid = morf.process_id, recording = true, phase = "recording", paused = true, elapsed = 42,
    started = morf.time.now_ms() - 900000 }, { atomic = true, parents = true })
  local state = test.wait(function()
    local now = test.ipc("mirrored")
    return now.recording and now or nil
  end, 2000, "the state did not arrive")
  test.truthy(state.paused)
  test.eq(state.elapsed, 42)
  test.advance(2000)
  test.eq(test.ipc("mirrored").elapsed, 42, "the shell's clock ran")
  morf.fs.remove(path)
end)

test.describe("the replay buffer", function()
  test.it("keeps the seconds asked for, in the capture folder, with no file of its own", function()
    tool()
    test.ipc("record", "replay", "seconds=45") test.advance(800)
    logged("-r 45 -c mp4 -o ")
    local state = test.ipc("flow")
    test.truthy(state.recording) test.eq(state.replay, 45) test.eq(state.file, "")
    test.contains(morf.fs.read(LOG), "/capture-recorder/shots")
    test.ipc("record", "stop")
    test.wait(function() return not test.ipc("flow").recording or nil end, 3000, "it did not stop")
    state = test.ipc("flow")
    test.eq(state.message, "Replay stopped.")
    test.eq(state.replay, 0)
    test.eq(#state.detached, 0, "a stop announced a file")
  end)

  test.it("starts from the panel with the configured seconds, with no countdown", function()
    tool()
    test.ipc("capture", "open") test.settle(1000)
    test.click("capture-delay-5")
    test.click("capture-replay") test.advance(800)
    logged("-r 30 ")
    test.truthy(test.ipc("flow").recording, "it waited the panel's delay")
    test.ipc("capture", "open") test.settle(1000)
    test.truthy(test.find { id = "capture-pause", visible = true })
    test.eq(test.get("capture-status").text, "Keeping 30 s")
    test.falsy(test.ipc("flow").can_pause, "a replay buffer has no pause")
    test.click("capture-record") test.advance(100)
    test.wait(function() return not test.ipc("flow").recording or nil end, 3000, "Stop did not end it")
  end)

  test.it("saves what it holds, and runs on", function()
    tool()
    test.ipc("record", "replay") test.advance(800)
    logged("-r 30 ")
    test.truthy(test.ipc("record", "save"))
    logged("replay saved")
    local state = test.wait(function()
      local now = test.ipc("flow")
      test.advance(300)
      return now.message == "Replay saved." and now or nil
    end, 6000, "the saved file was not found")
    test.contains(state.file, "Replay_stand_in.mp4")
    test.truthy(state.recording, "a save ended the buffer")
    test.contains(state.detached[#state.detached], "--saved-recording")
    test.ipc("record", "stop")
    test.wait(function() return not test.ipc("flow").recording or nil end, 3000, "it did not stop")
  end)

  test.it("will not start over a recording, and a save needs a buffer", function()
    tool()
    test.eq(test.ipc("record", "save"), false)
    recording()
    test.eq(test.ipc("record", "replay"), "already recording")
    test.eq(test.ipc("flow").replay, 0)
    finish()
  end)
end)

test.describe("a recording in the editor", function()
  local function opened(style, size)
    test.stub_run("ffprobe", { code = 0, stdout = "12.5\n" })
    test.stub_run("ffmpeg", { code = 0 })
    tool(style, size)
    test.ipc("capture-editor", "file", test.ipc("film")) test.advance(500)
    test.truthy(test.ipc("flow").trim, "the trim did not open")
    test.truthy(test.find { id = "capture-trim", visible = true })
  end
  local function words_of(argv) return table.concat(argv, " ") end
  local function last_run(pattern)
    local found
    for _, run in ipairs(test.runs()) do
      if run[1] == "ffmpeg" and words_of(run):find(pattern) then found = words_of(run) end
    end
    return found
  end

  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. ": drags both edges, and saves that stretch beside the original", function()
      opened(style)
      test.eq(test.ipc("capture-trim", "state").duration, 12.5)
      test.eq(test.ipc("flow").keyboard, "exclusive")
      local track = test.get("capture-trim-track")
      test.click(track.x + track.width * 0.2, track.y + track.height / 2) test.advance(100)
      test.click(track.x + track.width * 0.8, track.y + track.height / 2) test.advance(100)
      local state = test.ipc("capture-trim", "state")
      test.near(state.from, 2.5, 0.2)
      test.near(state.to, 10, 0.2)
      test.click("capture-trim-save") test.advance(300)
      local run = last_run("%-c:v libx264")
      test.truthy(run, "nothing was trimmed")
      test.contains(run, "-ss 2.")
      test.contains(run, "-i " .. test.ipc("film"))
      test.contains(run, ".mp4")
      test.falsy(run:find("film.mp4 -c:v .*film.mp4"), "it wrote over the original")
      local flow = test.ipc("flow")
      test.falsy(flow.trim) test.eq(flow.phase, "ready")
      test.contains(flow.message, "Trim saved")
      test.contains(flow.detached[#flow.detached], "--saved-recording")
      test.eq(#test.logs("error"), 0)
    end)

    test.it(style .. ": fits a phone, the edges to the finger", function()
      opened(style, { 412, 915 })
      local card = test.get("capture-trim-card")
      test.truthy(card.width <= 412, "it left the phone's width")
      local track = test.get("capture-trim-track")
      test.truthy(track.height >= 44, "the timeline is too small for a finger")
      local y = track.y + track.height / 2
      test.touch("down", 1, track.x + track.width * 0.3, y) test.advance(32)
      test.touch("move", 1, track.x + track.width * 0.25, y) test.advance(32)
      test.touch("up", 1, track.x + track.width * 0.25, y) test.advance(100)
      local state = test.ipc("capture-trim", "state")
      test.near(state.from, 12.5 * 0.25, 0.5, "a finger did not move the edge")
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("makes a GIF at the set rate and width", function()
    opened()
    test.ipc("capture-trim", "from", 1) test.ipc("capture-trim", "to", 3) test.advance(100)
    test.click("capture-trim-gif") test.advance(300)
    local run = last_run("palettegen")
    test.truthy(run, "no GIF was made")
    test.contains(run, "fps=12,scale=960:-1")
    test.contains(run, "-ss 1.000 -to 3.000")
    test.contains(run, ".gif")
    test.contains(test.ipc("flow").message, "GIF saved")
  end)

  test.it("keeps the edges apart", function()
    opened()
    test.ipc("capture-trim", "to", 4) test.advance(50)
    test.ipc("capture-trim", "from", 9) test.advance(50)
    local state = test.ipc("capture-trim", "state")
    test.truthy(state.from < state.to)
    test.near(state.to - state.from, 0.2, 0.01)
  end)

  test.it("cancels with Escape and Cancel, nothing written", function()
    opened()
    test.key("Escape") test.advance(200)
    test.falsy(test.ipc("flow").trim, "Escape did not cancel")
    test.eq(test.ipc("flow").phase, "ready")
    test.falsy(last_run("%-c:v libx264"))
    test.ipc("capture-editor", "file", test.ipc("film")) test.advance(500)
    test.click("capture-trim-cancel") test.advance(200)
    test.falsy(test.ipc("flow").trim)
  end)

  test.it("ends with the tool's cancel, and gives way to the panel", function()
    opened()
    test.truthy(test.ipc("capture-editor", "cancel"))
    test.advance(200)
    test.falsy(test.ipc("flow").trim)
    test.eq(test.ipc("flow").phase, "ready")
    test.ipc("capture-editor", "file", test.ipc("film")) test.advance(500)
    test.truthy(test.ipc("flow").trim)
    test.ipc("capture", "open") test.advance(100) test.settle(800)
    test.falsy(test.ipc("flow").trim, "the panel opened under it")
    test.truthy(test.find { id = "capture-screenshot", visible = true })
  end)

  test.it("says plainly when ffmpeg is missing", function()
    tool()
    test.ipc("no_ffmpeg")
    test.ipc("capture", "open") test.settle(1000)
    test.click("capture-history-open") test.settle(800)
    test.click("capture-history-row-1") test.advance(100)
    test.click("capture-history-edit") test.advance(100)
    test.falsy(test.ipc("flow").trim)
    test.truthy(test.find { text = "ffmpeg is not installed, so a recording cannot be trimmed or made a GIF", visible = true }
      or test.find { id = "capture-history-note", visible = true })
    test.truthy(test.find { id = "capture-history", visible = true }, "the history shut on a refusal")
  end)

  test.it("says plainly when a recording cannot be read", function()
    test.stub_run("ffprobe", { code = 1, stderr = "not a video" })
    test.stub_run("ffmpeg", { code = 0 })
    tool()
    test.ipc("capture-editor", "file", test.ipc("film")) test.advance(500)
    test.eq(test.ipc("capture-trim", "state").note, "Could not read this recording")
    test.click("capture-trim-cancel") test.advance(200)
  end)
end)
