-- Text from a shot: read with tesseract on this machine, searched and copied in
-- the history, kept beside no picture, and said plainly when tesseract is missing.
-- tesseract is stubbed here; tools/see/capture-text.steps runs the real one.
--
--     morf test --no-dbus tests/capture_text_spec.lua
local test = morf.test

local TOOL = "../apps/screenshot/app.lua"
local WORDS = "Invoice 42\nTotal due 99 euro\nThank you\n"

local SOURCE = [[
  local backend = require("lib.shell.capture")
  local scratch = morf.env("XDG_CACHE_HOME") .. "/capture-text"
  local folder = scratch .. "/shots"
  morf.fs.remove(scratch, { recursive = true })
  morf.fs.mkdir(folder)
  local picture = morf.fs.join(morf.env("PWD"), "tests/fixtures/wallpaper.png")
  for _, name in ipairs { "a.png", "b.png" } do morf.fs.copy(picture, folder .. "/" .. name) end
  morf.fs.copy(picture, folder .. "/film.mp4")
  local clipped = {}
  morf.clipboard.set = function(words) clipped[#clipped + 1] = words end
  backend.windows = function(cb) cb({}) end
  morf.process.detach = function() end
  require("config").set("capture.folder", folder)
  require("app")
  local capture = require("capture")
  morf.shared("eva.capture.owner", ""):set("")
  capture.editor.readers:set({ ocr = true, qr = false })
  morf.ipc.missing = function() capture.editor.readers:set({ ocr = false, qr = false }) end
  morf.ipc.flow = function()
    local recent = package.loaded.recent
    return { note = recent.note:get(), rows = #recent.rows:get(), words = recent.words:get(),
      reading = recent.reading:get() ~= false, lines = recent.lines(), unread = recent.unread:get(),
      clipped = clipped, busy = recent.busy:get() }
  end
  morf.ipc.search = function(words) package.loaded.recent.search(words) return true end
  morf.ipc.choose_named = function(name)
    local recent = package.loaded.recent
    recent.search(name)
    recent.chosen:set(1)
    return recent.entry().name
  end
  morf.ipc.state_files = function()
    local found = morf.fs.list((morf.env("XDG_STATE_HOME")) .. "/eva/capture/text") or {}
    return #found
  end
  morf.ipc.forget = function() morf.fs.remove(morf.env("XDG_STATE_HOME") .. "/eva/capture/text", { recursive = true }) end
]]

local function runs(program)
  local count = 0
  for _, run in ipairs(test.runs()) do if run[1] == program then count = count + 1 end end
  return count
end

local function tool(style, size)
  test.stub_run("tesseract", { code = 0, stdout = WORDS })
  test.load(TOOL, { source = SOURCE, size = size or { 1920, 1080 },
    env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
  test.ipc("forget")
  test.ipc("capture", "open") test.settle(1000)
  test.click("capture-history-open") test.settle(800)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": reads a shot in the place of the list, and searches its lines", function()
    tool(style)
    test.ipc("choose_named", "a.png")
    test.click("capture-history-text") test.advance(200)
    local state = test.ipc("flow")
    test.truthy(state.reading) test.eq(#state.lines, 3)
    test.truthy(test.find { id = "capture-history-words", visible = true })
    test.falsy(test.find { id = "capture-history-list", visible = true }, "the list stayed under it")
    test.eq(runs("tesseract"), 1)
    test.ipc("search", "total")
    test.eq(test.ipc("flow").lines, { "Total due 99 euro" })
    test.click("capture-history-copy-text") test.advance(50)
    state = test.ipc("flow")
    test.eq(state.clipped[#state.clipped], "Total due 99 euro")
    test.contains(state.note, "line")
    test.click("capture-history-back") test.advance(100)
    state = test.ipc("flow")
    test.falsy(state.reading)
    test.truthy(test.find { id = "capture-history-list", visible = true })
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("copies the whole text when nothing narrows it", function()
  tool()
  test.ipc("choose_named", "a.png")
  test.click("capture-history-text") test.advance(200)
  test.click("capture-history-copy-text") test.advance(50)
  local state = test.ipc("flow")
  test.eq(state.clipped[1], "Invoice 42\nTotal due 99 euro\nThank you")
end)

test.it("reads a shot once, and asks for nothing but tesseract", function()
  tool()
  test.ipc("choose_named", "b.png")
  test.click("capture-history-text") test.advance(200)
  test.click("capture-history-back") test.advance(100)
  test.ipc("choose_named", "b.png")
  test.click("capture-history-text") test.advance(200)
  test.eq(runs("tesseract"), 1, "it read the same shot twice")
  test.eq(test.ipc("state_files"), 1)
  for _, run in ipairs(test.runs()) do
    test.falsy(run[1] == "curl" or run[1] == "wget", "text left the machine")
  end
end)

test.it("a search of the history finds what has been read", function()
  tool()
  test.ipc("search", "invoice")
  test.eq(test.ipc("flow").rows, 0)
  test.eq(test.ipc("flow").unread, 2)
  test.click("capture-history-look") test.advance(400)
  test.eq(runs("tesseract"), 2)
  local state = test.ipc("flow")
  test.eq(state.rows, 2, "the text it read was not searched")
  test.eq(state.unread, 0)
end)

test.it("deleting a shot takes its text with it", function()
  tool()
  test.ipc("choose_named", "a.png")
  test.click("capture-history-text") test.advance(200)
  test.click("capture-history-back") test.advance(100)
  test.eq(test.ipc("state_files"), 1)
  test.ipc("choose_named", "a.png")
  test.click("capture-history-delete") test.advance(50)
  test.click("capture-history-delete") test.advance(50)
  test.eq(test.ipc("state_files"), 0, "the text of a deleted shot stayed")
end)

test.it("a recording has no text to read", function()
  tool()
  test.ipc("choose_named", "film")
  test.click("capture-history-text") test.advance(100)
  test.falsy(test.ipc("flow").reading)
  test.eq(runs("tesseract"), 0)
end)

test.it("says plainly when tesseract is missing", function()
  tool()
  test.ipc("missing")
  test.ipc("choose_named", "a.png")
  test.click("capture-history-text") test.advance(100)
  local state = test.ipc("flow")
  test.eq(state.note, "tesseract is not installed, so no text can be read from a shot")
  test.falsy(state.reading)
  test.eq(runs("tesseract"), 0)
end)

test.it("a search says so too, and offers no reading", function()
  tool()
  test.ipc("missing")
  test.ipc("search", "invoice")
  test.eq(test.ipc("flow").unread, 0)
  test.truthy(test.find { text = "tesseract is not installed: only names and dates are searched", visible = true }
    or test.find { id = "capture-history-note", visible = true })
  test.falsy(test.find { id = "capture-history-look", visible = true })
end)

test.it("says so when a shot holds no words", function()
  test.stub_run("tesseract", { code = 0, stdout = "\n" })
  test.load(TOOL, { source = SOURCE, size = { 1920, 1080 },
    env = { EVA_STYLE = "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
  test.ipc("forget")
  test.ipc("capture", "open") test.settle(1000)
  test.click("capture-history-open") test.settle(800)
  test.ipc("choose_named", "a.png")
  test.click("capture-history-text") test.advance(200)
  test.eq(test.ipc("flow").note, "No text found")
end)

test.it("reads on a phone", function()
  tool("tsugumori", { 412, 915 })
  test.ipc("choose_named", "a.png")
  test.click("capture-history-text") test.advance(200)
  local box = test.get("capture-history-words")
  test.truthy(box.width <= 412 - 20)
  test.truthy(test.find { id = "capture-history-copy-text", visible = true })
end)
