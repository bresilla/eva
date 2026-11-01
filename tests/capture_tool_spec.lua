-- eva-screenshot as a program: the panel, the selection and the one recorder in
-- the tool's own process, how it stands and ends, and every door the shell has
-- into it.
--
--     morf test --no-dbus tests/capture_tool_spec.lua

local test = morf.test

local TOOL = "../apps/screenshot/app.lua"

local function state_file()
  local display = (morf.env("WAYLAND_DISPLAY") or "wayland-0"):match("[^/]+$")
  return morf.env("XDG_RUNTIME_DIR") .. "/eva/capture-" .. display .. ".json"
end

local SOURCE = [[
  local backend = require("lib.shell.capture")
  local fixture = '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800"><rect width="1200" height="800" fill="#37474f"/></svg>'
  local copies, saves, detached, quits, reads = {}, {}, {}, 0, {}
  backend.windows = function(cb) cb({ { x = 100, y = 100, w = 500, h = 350 } }) end
  backend.focused_window = function(cb) cb(morf.focused_stub) end
  backend.session = function()
    return { snapshot = function(_, cb) cb(true, { source = fixture, width = 1200, height = 800 }) end,
      render = function(_, _, cb) morf.time.timer(20, function() cb(true, fixture) end, false) end,
      close = function() end, remove = function() end }
  end
  backend.copy = function(path, cb) copies[#copies + 1] = path cb(true) end
  backend.save = function(_, target, cb) saves[#saves + 1] = target cb(true, target) end
  local read = require("lib.shell.capture.read")
  read.read = function(kind, _, cb) reads[#reads + 1] = kind cb(morf.read_stub ~= false, morf.read_stub == false and "No text found" or "the words") end
  morf.process.detach = function(argv) detached[#detached + 1] = table.concat(argv, " ") end
  morf.quit = function() quits = quits + 1 end
  require("app")
  local env = morf.env
  morf.env = function(key) if key == "EVA_DRY_RUN" then return morf.dry_stub or "0" end return env(key) end
  local capture = require("capture")
  local host = require("host")
  -- What the screens share outlives a test's load.
  capture.recording:set(false) capture.elapsed:set(0) capture.started:set(0) capture.file:set("")
  morf.shared("eva.capture.owner", ""):set("")
  morf.ipc.flow = function()
    return { panel = capture.drawer.open:get(), visible = capture.drawer.panel.visible, active = capture.editor.active:get(),
      quiet = capture.editor.quiet:get(), stage = capture.editor.phase:get(), phase = capture.phase:get(),
      recording = capture.recording:get(), message = capture.message:get(), copies = #copies, saves = #saves,
      reads = #reads, detached = detached, quits = quits, posture = host.now, layer = morf.surface.layer,
      keyboard = morf.surface.keyboard_focus, file = capture.file:get() }
  end
  morf.ipc.focus_on = function() morf.focused_stub = { x = 5, y = 6, w = 70, h = 80 } end
  morf.ipc.nothing_to_read = function() morf.read_stub = false end
  morf.ipc.dry = function() morf.dry_stub = "1" end
  morf.ipc.delay = function() return capture.delay:get() end
  morf.ipc.option = function(key, value) require("config").set("capture." .. key, value == "true") end
  morf.ipc.picking = function() return capture.editor.picker:get() ~= false end
  morf.ipc.screen_name = function() return morf.screens[1].name end
  morf.ipc.framed = function() return host.framed:get() end
]]

local function tool(style, options)
  options = options or {}
  test.load(TOOL, { source = SOURCE, size = options.size or { 1200, 800 }, args = options.args,
    env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
end

local function select_area()
  test.press(150, 120) test.move(700, 450) test.release(700, 450) test.advance(250)
end

local function runs_of(program)
  local found = {}
  for _, run in ipairs(test.runs()) do
    if run[1] == program then found[#found + 1] = run end
  end
  return found
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " panel", function()
    test.it("stands on the bottom edge, every control shown", function()
      tool(style, { size = { 1920, 1080 } })
      test.falsy(test.get("drawer-capture").visible, "capture must only open explicitly")
      test.ipc("capture", "open") test.settle(1000)
      local d = test.get("drawer-capture")
      test.near(d.y + d.height, 1080 - 10, 1)
      test.truthy(d.width <= 480)
      test.truthy(d.height <= 264)
      for _, id in ipairs { "capture-target-region", "capture-target-window", "capture-target-screen",
        "capture-screenshot", "capture-record" } do
        test.truthy(test.find { id = id, visible = true }, id .. " not shown")
      end
      test.falsy(test.find { id = "capture-library" })
      test.falsy(test.find { id = "capture-close" })
      test.eq(#test.logs("error"), 0)
    end)

    test.it("moves the target selector, and shuts on a press outside", function()
      tool(style, { size = { 1920, 1080 } })
      test.ipc("capture", "open") test.settle(1000)
      local resting_width = test.get("capture-selection").width
      test.click("capture-target-screen") test.advance(160)
      -- (Material stretches it; a square theme's elastic is its own.)
      if style == "material" then
        test.truthy(test.get("capture-selection").width > resting_width + 20,
          "the target selection did not stretch during its transition")
      end
      test.advance(650)
      test.near(test.get("capture-selection").width, resting_width, 1)
      test.click(100, 100) test.settle(800)
      test.falsy(test.get("drawer-capture").visible)
    end)

    test.it("waits the chosen delay, then takes the chosen target", function()
      tool(style, { size = { 1920, 1080 } })
      test.ipc("dry")
      test.ipc("capture", "open") test.settle(1000)
      test.clear_logs()
      test.click { id = "capture-delay-3" }
      test.click { id = "capture-target-screen" }
      test.click { id = "capture-screenshot" }
      test.settle(1000)
      test.falsy(test.get("drawer-capture").visible, "it stayed in the picture")
      local said = function()
        for _, l in ipairs(test.logs("info")) do
          if l.message:find("capture screenshot_screen (dry run)", 1, true) then return true end
        end
        return false
      end
      test.falsy(said(), "it did not wait the delay")
      test.advance(3500)
      test.truthy(said(), "the screenshot was not taken")
    end)

    test.it("records from the same place: Record, then Stop", function()
      tool(style, { size = { 1920, 1080 } })
      test.ipc("dry")
      test.ipc("capture", "open") test.settle(1000)
      test.click { id = "capture-target-screen" }
      test.click { id = "capture-record" }
      test.advance(3500)
      test.ipc("capture", "open") test.advance(100) test.settle(1500)
      test.truthy(test.find { text = "Stop", visible = true }, "not recording")
      test.click { id = "capture-record" }
      test.settle(300)
      test.truthy(test.find { text = "Record", visible = true }, "not stopped")
    end)

    test.it("a queued recording cancels without starting a recorder", function()
      tool(style, { size = { 1920, 1080 } })
      test.ipc("dry")
      test.ipc("capture", "open") test.settle(800)
      test.click("capture-delay-5")
      test.ipc("record", "screen")
      test.eq(test.ipc("flow").phase, "countdown")
      test.ipc("record")
      test.advance(6500)
      test.eq(test.ipc("flow").recording, false)
      test.eq(test.ipc("flow").phase, "ready")
      for _, log in ipairs(test.logs("info")) do
        test.falsy(log.message:find("capture record_screen", 1, true), "cancelled recording still started")
      end
    end)

    test.it("joins the frame in a field of the theme's own paint", function()
      tool(style, { size = { 1920, 1080 } })
      test.ipc("capture", "open") test.settle(1000)
      test.get("capture-frame")
      test.get("capture-frame-edge")
      test.get("drawer-capture-background")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("fits a phone", function()
      tool(style, { size = { 412, 915 } })
      test.ipc("capture", "open") test.settle(1200)
      local d = test.get("drawer-capture")
      test.truthy(d.width <= 412 - 20)
      test.truthy(d.x >= 0)
      test.truthy(test.find { id = "capture-screenshot", visible = true })
      test.eq(#test.logs("error"), 0)
    end)
  end)
end

test.it("every tool is on the palette", function()
  tool()
  test.ipc("screenshot", "screen") test.advance(600)
  test.eq(test.ipc("flow").stage, "editing")
  test.click("capture-editor-draw") test.advance(220)
  local tools = require("lib.shell.capture.annotation").tools
  test.eq(#tools, 13)
  for _, t in ipairs(tools) do test.get("capture-tool-" .. t[1]) end
end)

-- ---------------------------------------------------------- straight through --

test.describe("through the selection", function()
  test.it("copies what was selected, the toolbar left out", function()
    tool()
    test.ipc("screenshot", "region", "how=copy") test.advance(600)
    local state = test.ipc("flow")
    test.truthy(state.active) test.eq(state.stage, "selecting") test.truthy(state.quiet)
    select_area()
    test.falsy(test.get("capture-editor-toolbar").visible)
    test.advance(300)
    state = test.ipc("flow")
    test.eq(state.copies, 1) test.falsy(state.active) test.falsy(state.quiet)
  end)

  test.it("saves a screen with nothing to select", function()
    tool()
    test.ipc("screenshot", "screen", "how=save") test.advance(800)
    local state = test.ipc("flow")
    test.eq(state.saves, 1) test.falsy(state.active)
    test.contains(state.detached[1], "--saved-picture")
  end)

  test.it("skips the save dialog for a save asked for directly", function()
    tool()
    test.ipc("option", "save_dialog", "true")
    test.ipc("screenshot", "region", "how=save") test.advance(600)
    select_area()
    test.advance(300)
    test.falsy(test.ipc("picking"), "--save asked where")
    test.eq(test.ipc("flow").saves, 1)
    test.ipc("option", "save_dialog", "false")
  end)

  test.it("takes a window with a click on it", function()
    tool()
    test.ipc("screenshot", "window", "how=copy") test.advance(600)
    test.eq(test.ipc("flow").stage, "selecting")
    test.click(300, 300) test.advance(400)
    test.eq(test.ipc("flow").copies, 1)
  end)

  test.it("reads a selection to the clipboard", function()
    tool()
    test.ipc("screenshot", "region", "how=ocr") test.advance(600)
    select_area()
    test.advance(300)
    local state = test.ipc("flow")
    test.eq(state.reads, 1) test.falsy(state.active)
  end)

  test.it("ends quietly when a read finds nothing", function()
    tool()
    test.ipc("nothing_to_read")
    test.ipc("screenshot", "region", "how=ocr", "result=" .. morf.env("XDG_STATE_HOME") .. "/read.txt") test.advance(600)
    select_area()
    test.advance(300)
    local state = test.ipc("flow")
    test.falsy(state.active) test.eq(state.phase, "ready")
    test.contains(morf.fs.read(morf.env("XDG_STATE_HOME") .. "/read.txt"), "No text found")
  end)

  test.it("answers a save with where it went, copied or not", function()
    tool()
    local path = morf.env("XDG_STATE_HOME") .. "/saved.txt"
    test.ipc("screenshot", "screen", "how=save", "result=" .. path) test.advance(800)
    local answer = morf.fs.read(path)
    test.contains(answer, "ok\n")
    test.contains(answer, ".png")
  end)

  test.it("takes the region taken last", function()
    tool()
    test.ipc("screenshot", "region", "how=copy") test.advance(600)
    select_area()
    test.advance(300)
    test.eq(test.ipc("flow").copies, 1)
    test.ipc("screenshot", "region", "how=copy", "last=1") test.advance(1000)
    test.eq(test.ipc("flow").copies, 2)
  end)

  test.it("waits a delay given with the order, leaving the panel's alone", function()
    tool()
    test.ipc("screenshot", "screen", "how=copy", "delay=2") test.advance(1500)
    test.eq(test.ipc("flow").copies, 0)
    test.advance(1500)
    test.eq(test.ipc("flow").copies, 1)
    test.eq(test.ipc("delay"), 0)
  end)

  test.it("goes straight through for quick, and with the editor off", function()
    tool()
    test.ipc("screenshot", "screen", "quick") test.advance(800)
    test.eq(test.ipc("flow").saves, 1)
  end)

  test.it("says a cancelled selection is not a result", function()
    tool()
    local path = morf.env("XDG_STATE_HOME") .. "/cancel.txt"
    test.ipc("screenshot", "region", "how=copy", "result=" .. path) test.advance(600)
    test.key("Escape") test.advance(100)
    test.contains(morf.fs.read(path), "no\n")
    test.eq(test.ipc("flow").phase, "ready")
  end)
end)

-- ----------------------------------------------------------------- the recorder --

test.describe("the one recorder", function()
  test.it("records the selection, not slurp's", function()
    test.stub_run("gpu-screen-recorder", { code = 0 })
    tool()
    test.ipc("record", "region", "fps=30", "audio=default_output") test.advance(600)
    test.truthy(test.ipc("flow").recording)
    test.eq(#runs_of("gpu-screen-recorder"), 0, "it started before the selection")
    select_area()
    local run = runs_of("gpu-screen-recorder")[1]
    test.truthy(run, "the recorder did not start")
    local words = table.concat(run, " ")
    test.contains(words, "-w region -region 550x330+150+120")
    test.contains(words, "-f 30")
    test.contains(words, "-a default_output")
    test.contains(words, ".mp4")
    test.eq(#runs_of("slurp"), 0)
  end)

  test.it("cancelling the selection records nothing", function()
    test.stub_run("gpu-screen-recorder", { code = 0 })
    tool()
    test.ipc("record", "region") test.advance(600)
    test.key("Escape") test.advance(100)
    local state = test.ipc("flow")
    test.falsy(state.recording) test.eq(state.phase, "ready")
    test.eq(#runs_of("gpu-screen-recorder"), 0)
  end)

  test.it("records the focused window by its geometry, and never -w focused", function()
    test.stub_run("gpu-screen-recorder", { code = 0 })
    tool()
    test.ipc("focus_on")
    test.ipc("record", "window") test.advance(600)
    local words = table.concat(runs_of("gpu-screen-recorder")[1], " ")
    test.contains(words, "-w region -region 70x80+5+6")
    test.falsy(words:find("focused", 1, true))
  end)

  test.it("goes through the portal when the window's place cannot be read", function()
    test.stub_run("gpu-screen-recorder", { code = 0 })
    tool()
    test.ipc("record", "window") test.advance(600)
    test.contains(table.concat(runs_of("gpu-screen-recorder")[1], " "), "-w portal")
  end)

  test.it("records this screen by its name", function()
    test.stub_run("gpu-screen-recorder", { code = 0 })
    tool()
    test.ipc("record", "screen") test.advance(600)
    test.contains(table.concat(runs_of("gpu-screen-recorder")[1], " "), "-w " .. test.ipc("screen_name"))
  end)

  test.it("shows recorder failures and clears recording state", function()
    test.stub_run("gpu-screen-recorder", { code = 1, stderr = "Recorder could not start" })
    tool()
    test.ipc("record", "screen") test.advance(1000)
    local state = test.ipc("flow")
    test.eq(state.recording, false)
    test.eq(state.phase, "error")
    test.eq(state.message, "Recorder could not start")
  end)

  test.it("refuses a second start and stops by the same verb the panel uses", function()
    tool()
    test.ipc("dry")
    test.ipc("record", "screen") test.advance(600)
    test.truthy(test.ipc("flow").recording)
    test.eq(test.ipc("record", "screen", "start=1"), "already recording")
    test.truthy(test.ipc("flow").recording)
    test.ipc("record", "stop")
    test.falsy(test.ipc("flow").recording)
  end)
end)

-- ----------------------------------------------------- standing and ending --

test.describe("the process", function()
  test.it("does its first order and ends", function()
    tool("material", { args = { "capture", "open" } })
    test.settle(1000)
    test.truthy(test.ipc("flow").panel, "the panel did not open")
    test.ipc("capture", "close") test.settle(1000)
    test.advance(400)
    test.eq(test.ipc("flow").quits, 1)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("stays out of sight on standby, grows for an order, and goes back", function()
    tool("material", { args = { "standby" } })
    local state = test.ipc("flow")
    test.eq(state.posture, "hidden") test.eq(state.layer, "background")
    test.ipc("capture", "open") test.advance(100) test.settle(1000)
    state = test.ipc("flow")
    test.truthy(state.panel) test.eq(state.posture, "full") test.eq(state.layer, "overlay")
    test.ipc("capture", "close") test.settle(1000)
    test.advance(400)
    state = test.ipc("flow")
    test.eq(state.posture, "hidden") test.eq(state.quits, 0)
  end)

  test.it("does a first order and stays when the shell started it", function()
    tool("material", { args = { "standby", "capture", "open" } })
    test.settle(1000)
    test.truthy(test.ipc("flow").panel)
    test.ipc("capture", "close") test.settle(1000)
    test.advance(400)
    local state = test.ipc("flow")
    test.eq(state.posture, "hidden") test.eq(state.quits, 0)
  end)

  test.it("opens a picture as its first order, and ends with the editor", function()
    tool("material", { args = { "capture-editor", "file", morf.fs.join(morf.env("PWD"), "tests/fixtures/wallpaper.png") } })
    test.advance(300)
    local state = test.ipc("flow")
    test.truthy(state.active, "the editor did not open")
    test.eq(state.stage, "editing")
    test.eq(state.quits, 0)
    test.key("Escape") test.advance(600)
    test.eq(test.ipc("flow").quits, 1)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("runs the keyboard the editor needs and lets it go", function()
    tool()
    test.ipc("screenshot", "region") test.advance(600)
    test.eq(test.ipc("flow").keyboard, "exclusive")
    test.key("Escape") test.advance(100)
    test.eq(test.ipc("flow").keyboard, "none")
  end)

  test.it("stays for a recording it started, out of the way", function()
    test.stub_run("gpu-screen-recorder", { code = 0, delay_ms = 60000 })
    tool("material", { args = { "standby" } })
    test.ipc("dry")
    test.ipc("record", "screen") test.advance(100) test.advance(800)
    test.advance(400)
    test.eq(test.ipc("flow").posture, "strip", "a recording with no shell keeps its pill")
    test.get("record-indicator")
    test.truthy(test.get("record-indicator").visible)
  end)

  test.it("publishes what the shell shows, and a dry run publishes nothing", function()
    local path = state_file()
    morf.fs.remove(path)
    tool()
    test.ipc("capture", "open") test.settle(1000)
    test.falsy(morf.fs.exists(path), "a dry run told the shell")
    test.load(TOOL, { source = SOURCE, size = { 1200, 800 }, env = { EVA_STYLE = "material", EVA_DRY_RUN = "0",
      LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
    test.advance(300)
    test.ipc("capture", "open") test.settle(1000)
    local state = morf.json.decode(morf.fs.read(path))
    test.truthy(state.panel) test.eq(state.phase, "ready") test.falsy(state.recording)
    test.truthy(state.pid > 0)
    morf.fs.remove(path)
  end)

  test.it("reads the shell as gone when its process is, whatever it left behind", function()
    local display = (morf.env("WAYLAND_DISPLAY") or "wayland-0"):match("[^/]+$")
    local pid = morf.env("XDG_RUNTIME_DIR") .. "/eva/shell-" .. display .. ".pid"
    morf.fs.write(pid, tostring(morf.process_id), { atomic = true, parents = true })
    tool()
    test.ipc("capture", "open") test.settle(800)
    test.truthy(test.ipc("framed"), "a live shell did not count")
    test.ipc("capture", "close") test.settle(800)
    morf.fs.write(pid, tostring(2 ^ 31 - 1), { atomic = true })
    test.ipc("capture", "open") test.settle(800)
    test.falsy(test.ipc("framed"), "a dead shell still counted")
    morf.fs.remove(pid)
  end)

  test.it("lets another screen's order shut this one", function()
    tool()
    test.ipc("capture", "open") test.settle(1000)
    test.truthy(test.ipc("flow").panel)
    test.ipc("capture-claim", "ANOTHER-1") test.settle(1000)
    test.falsy(test.ipc("flow").panel)
  end)
end)

-- ------------------------------------------------------- the shell's doors --

test.describe("the shell", function()
  local SHELL = [[
    require("init")
    local capture = require("capture")
    morf.ipc.door = function(name)
      if name == "launcher" then
        for _, query in ipairs { "!screenshot or", "!screenshot a" } do
          require("providers").search(query)[1].run()
        end
      elseif name == "tile" then
        local utilities = require("utilities")
        utilities.CONTROLS.screenshot.set(true)
      end
      return true
    end
    morf.ipc.mirrored = function()
      return { panel = capture.panel:get(), editing = capture.editor.running(), phase = capture.phase:get(),
        recording = capture.recording:get(), elapsed = capture.elapsed:get(), bottom = require("bottom").drawer.open:get() }
    end
  ]]
  local function shell()
    test.load("../shell/init.lua", { source = SHELL, size = { 1920, 1080 },
      env = { EVA_STYLE = "material", EVA_DRY_RUN = "1", EVA_WALLPAPER = "", LULE_A = "/nonexistent/lule" } })
    test.settle(800)
    test.clear_logs()
  end
  local function asked(words)
    for _, l in ipairs(test.logs("info")) do
      if l.message:find("capture " .. words .. " (dry run)", 1, true) then return true end
    end
    return false
  end
  local function publish(state)
    state.pid = state.pid or morf.process_id
    morf.fs.write(state_file(), morf.json.encode(state), { atomic = true, parents = true })
  end

  test.it("holds no panel, no selection and no editor of its own", function()
    shell()
    test.falsy(test.find { id = "drawer-capture" })
    test.falsy(test.find { id = "capture-editor" })
    test.falsy(package.loaded.capture_editor)
    test.falsy(package.loaded.capture_view)
  end)

  test.it("passes on the capture verbs", function()
    shell()
    test.ipc("capture", "open")
    test.truthy(asked("capture open"))
    test.ipc("capture", "toggle")
    test.truthy(asked("capture toggle"))
    test.ipc("screenshot", "region")
    test.truthy(asked("screenshot region"))
    test.ipc("screenshot", "screen", "quick")
    test.truthy(asked("screenshot screen quick"))
    test.ipc("record", "window")
    test.truthy(asked("record window"))
    test.ipc("capture-editor", "tool", "rect")
    test.truthy(asked("capture-editor tool rect"))
    test.ipc("capture-editor", "file", "/tmp/picture.png")
    test.truthy(asked("capture-editor file /tmp/picture.png"))
    test.ipc("capture-claim", "DP-2")
    test.truthy(asked("capture-claim DP-2"))
    test.eq(#test.logs("error"), 0)
  end)

  test.it("counts the tool's panel among the drawers, and shuts it with the rest", function()
    shell()
    publish { panel = true, phase = "ready" }
    test.wait(function() return test.ipc("mirrored").panel end, 2000, "the panel state did not arrive")
    test.contains(test.ipc("drawers"), "capture")
    test.clear_logs()
    test.ipc("drawers", "close", "capture")
    test.truthy(asked("capture close"))
    test.clear_logs()
    test.ipc("close")
    test.truthy(asked("capture close"))
    morf.fs.remove(state_file())
  end)

  test.it("refuses what it refused before", function()
    shell()
    test.falsy(pcall(test.ipc, "screenshot", "nowhere"))
    test.falsy(pcall(test.ipc, "capture", "sideways"))
  end)

  test.it("opens it from the Screenshot / Record button", function()
    shell()
    test.ipc("utilities", "open") test.settle(800)
    test.click("utilities-capture") test.settle(300)
    test.truthy(asked("capture open"))
  end)

  test.it("opens it from ctrl+shift+s", function()
    shell()
    test.ipc("launcher", "open") test.settle(800)
    test.clear_logs()
    test.key("s", "ctrl+shift") test.settle(300)
    test.truthy(asked("capture toggle"))
  end)

  test.it("opens it from the launcher's rows and the screenshot tile", function()
    shell()
    test.ipc("door", "launcher")
    test.truthy(asked("capture open"))
    test.truthy(asked("screenshot region"))
    test.clear_logs()
    test.ipc("door", "tile") test.settle(300)
    test.truthy(asked("screenshot region"))
  end)

  test.it("binds the Hyprland key to the verb it passes on", function()
    local plan = require("lib.shell.capture").binding_plan("Print", "Print", "conf")
    test.contains(plan.bind, "morf ipc call capture open")
  end)

  test.it("follows what the tool publishes, and notices it going", function()
    shell()
    publish { panel = true, phase = "ready" }
    test.wait(function() return test.ipc("mirrored").panel end, 2000, "the panel state did not arrive")
    test.truthy(test.ipc("capture", "state"))
    publish { editing = true, phase = "editing" }
    test.wait(function() return test.ipc("mirrored").editing end, 2000, "the editing state did not arrive")
    publish { recording = true, phase = "recording", started = morf.time.now_ms() - 65000 }
    local state = test.wait(function()
      local now = test.ipc("mirrored")
      return now.recording and now or nil
    end, 2000, "the recording did not arrive")
    test.truthy(state.elapsed >= 64)
    publish { pid = 2 ^ 31 - 1, recording = true }
    test.wait(function() return not test.ipc("mirrored").recording end, 2000, "a dead tool still reads as recording")
    morf.fs.remove(state_file())
  end)

  test.it("gives the edge up to a panel the tool opened", function()
    shell()
    test.ipc("bottom", "open") test.settle(800)
    test.truthy(test.ipc("mirrored").bottom)
    publish { panel = true, phase = "ready" }
    test.wait(function() return not test.ipc("mirrored").bottom end, 2000, "the assistant stayed under the panel")
    morf.fs.remove(state_file())
  end)

  test.it("cancels editing for authentication", function()
    shell()
    publish { editing = true, phase = "editing" }
    test.wait(function() return test.ipc("mirrored").editing end, 2000, "the editing state did not arrive")
    test.clear_logs()
    test.ipc("polkit", "demo") test.settle(300)
    test.truthy(asked("capture-editor cancel"))
    morf.fs.remove(state_file())
  end)
end)
