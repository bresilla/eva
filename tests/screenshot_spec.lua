-- eva-screenshot: its command line against stand-in programs, and the editor:
-- solid redaction, the last region, a picture from a file, reading a picture.
-- The tool itself is tests/capture_tool_spec.lua.
--
--     morf test --no-dbus tests/screenshot_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local function host()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
end

-- The real script, with the stand-ins first on PATH.
local function cli(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/shot-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "STUB_LOG=" .. log, "MORF=" .. BIN .. "/morf",
    "WAYLAND_DISPLAY=wayland-1", "HOME=" .. state, "XDG_STATE_HOME=" .. state,
    "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/screenshot/cli"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  local result = test.wait(function() return test.ipc("result") end, 5000, "the tool answered")
  return result, morf.fs.read(log) or ""
end

local function untouched(calls)
  test.falsy(calls:find("slurp", 1, true), "slurp ran")
  test.falsy(calls:find("grim", 1, true), "grim ran")
end

test.it("shows the panel with no arguments", function()
  host()
  local result, calls = cli {}
  test.truthy(result.ok)
  test.contains(calls, "-i wayland-1-screenshot")
  test.contains(calls, "-- capture open")
  untouched(calls)
end)

test.it("copies a region through the selection", function()
  host()
  local result, calls = cli { "region", "--copy" }
  test.truthy(result.ok)
  test.contains(calls, "screenshot region how=copy")
  untouched(calls)
end)

test.it("saves through the selection and says where", function()
  host()
  local result, calls = cli { "screen", "--save" }
  test.truthy(result.ok)
  test.contains(result.stdout, "Pictures/Captures/capture_")
  test.contains(calls, "screenshot screen how=save")
  untouched(calls)
end)

test.it("takes a window through the selection", function()
  host()
  local _, calls = cli { "window", "--copy" }
  test.contains(calls, "screenshot window how=copy")
  untouched(calls)
end)

test.it("restores the last region", function()
  host()
  local result, calls = cli { "region", "--copy", "--last" }
  test.truthy(result.ok)
  test.contains(calls, "last=1")
  untouched(calls)
end)

test.it("waits the delay in the tool", function()
  host()
  local _, calls = cli { "region", "--delay", "3" }
  test.contains(calls, "screenshot region how=edit delay=3")
end)

test.it("reads text through the selection", function()
  host()
  local result, calls = cli { "ocr", "region" }
  test.truthy(result.ok)
  test.contains(calls, "screenshot region how=ocr")
  untouched(calls)
end)

test.it("reads a QR code, and says so when there is nothing to read", function()
  host()
  local _, calls = cli { "qr" }
  test.contains(calls, "screenshot region how=qr")
  local result = cli({ "qr", "region" }, { "STUB_RESULT=no\\nNo code found\\n" })
  test.falsy(result.ok)
  test.contains(result.stderr, "No code found")
end)

test.it("opens the editor on a picture", function()
  host()
  local _, calls = cli { "--edit-file", "/tmp/picture.png" }
  test.contains(calls, "capture-editor file /tmp/picture.png")
  untouched(calls)
end)

test.it("holds back under EVA_DRY_RUN", function()
  host()
  local result, calls = cli({ "screen", "--save" }, { "EVA_DRY_RUN=1" })
  test.truthy(result.ok)
  test.falsy(calls:find("app.lua", 1, true))
  test.contains(result.stderr, "dry run")
end)

test.it("asks the tool that is running", function()
  host()
  local _, calls = cli({ "region", "--edit" }, { "STUB_TOOL=1" })
  test.contains(calls, "-i wayland-1-screenshot ipc call screenshot region how=edit")
  test.falsy(calls:find("app.lua", 1, true))
end)

test.it("keeps the tool ready for a verb the shell asks", function()
  host()
  local _, calls = cli({ "--ask", "capture", "toggle" }, { "STUB_UP=1" })
  test.contains(calls, "-- standby capture toggle")
  local _, idle = cli({ "--ask", "standby" }, { "STUB_UP=1" })
  test.contains(idle, "app.lua -- standby")
  test.falsy(idle:find("standby standby", 1, true))
  local _, none = cli { "--ask", "capture", "close" }
  test.falsy(none:find("app.lua", 1, true), "a close started the tool")
end)

test.it("does one thing and ends when there is no shell to keep it ready", function()
  host()
  local _, calls = cli { "--ask", "record", "region" }
  test.contains(calls, "app.lua -- record region")
  test.falsy(calls:find("standby", 1, true))
end)

test.it("refuses what it does not know", function()
  host()
  local result = cli { "region", "--delay", "soon" }
  test.falsy(result.ok)
  test.contains(result.stderr, "whole seconds")
end)

-- ---------------------------------------------------------------- the editor --

local EDITOR = [[
local morf = require("morf")
require("morf.ui").Item { anchors = { fill = true } }
local annotation = require("lib.shell.capture.annotation")
local read = require("lib.shell.capture.read")
local editor = require("capture_editor")
morf.ipc.redact = function()
  local d = annotation.new(100, 100)
  d.choose("redact")
  d.begin(10, 10)
  d.update(40, 40)
  d.finish()
  local a = d.items[1]
  return { type = a.type, filled = a.filled, color = a.color, ops = #annotation.ops(d, false, false) }
end
morf.ipc.read = function(kind, path)
  local answer
  read.read(kind, path, function(ok, words) answer = { ok = ok, words = words } end)
  return true, morf.ipc.answer
end
local last
morf.ipc.read_now = function(kind, path)
  read.read(kind, path, function(ok, words) last = { ok = ok, words = words } end)
  return true
end
morf.ipc.read_last = function() return last end
morf.ipc.open_file = function(path)
  local ok, why = editor.open_file(path)
  return { ok = ok, why = why, phase = editor.phase:get(), open = editor.active:get() }
end
morf.ipc.region = function(x, y, w, h)
  editor.document.set_crop(tonumber(x), tonumber(y), tonumber(w), tonumber(h))
  editor.confirm_selection()
  return true
end
morf.ipc.restore = function()
  editor.document.set_crop(0, 0, 10, 10)
  local ok = editor.restore_last()
  local c = editor.document.crop
  return { ok = ok, x = c.x, y = c.y, w = c.w, h = c.h }
end
]]

local PICTURE = ROOT .. "tests/fixtures/wallpaper.png"

local function editor_host()
  test.load("../apps/screenshot/app.lua", { source = EDITOR, env = { EVA_SETTINGS = "/nonexistent/eva.json", EVA_DRY_RUN = "1" } })
end

test.it("offers solid redaction as an opaque filled rectangle", function()
  editor_host()
  local a = test.ipc("redact")
  test.eq(a.type, "rect")
  test.truthy(a.filled)
  test.eq(a.color, "#000000")
  test.truthy(a.ops >= 1)
end)

test.it("opens a picture from a file, all of it selected", function()
  editor_host()
  local opened = test.ipc("open_file", PICTURE)
  test.truthy(opened.ok)
  test.truthy(opened.open)
  test.eq(opened.phase, "editing")
  test.falsy(test.ipc("open_file", "/nonexistent/picture.png").ok)
end)

test.it("selects the region confirmed last", function()
  editor_host()
  test.ipc("open_file", PICTURE)
  test.ipc("region", "20", "30", "200", "100")
  local restored = test.ipc("restore")
  test.truthy(restored.ok)
  test.eq(restored.x, 20)
  test.eq(restored.y, 30)
  test.eq(restored.w, 200)
  test.eq(restored.h, 100)
end)

test.it("hands back what a picture says, or that it says nothing", function()
  test.stub_run("tesseract", { code = 0, stdout = "  some words \n" })
  test.stub_run("zbarimg", { code = 4, stdout = "" })
  editor_host()
  test.ipc("read_now", "ocr", "/tmp/picture.png")
  test.settle(100)
  test.eq(test.ipc("read_last").words, "some words")
  test.ipc("read_now", "qr", "/tmp/picture.png")
  test.settle(100)
  local nothing = test.ipc("read_last")
  test.falsy(nothing.ok)
  test.eq(nothing.words, "No code found")
end)
