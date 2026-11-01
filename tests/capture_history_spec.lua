-- The history in the panel: the captures folder as it stands, searched by name
-- and date, a chosen one reopened, copied or deleted. Files only: a spec's folder,
-- never the real home.
--
--     morf test --no-dbus tests/capture_history_spec.lua
local test = morf.test

local TOOL = "../apps/screenshot/app.lua"

local SOURCE = [[
  local backend = require("lib.shell.capture")
  local scratch = morf.env("XDG_CACHE_HOME") .. "/capture-history"
  local folder = scratch .. "/shots"
  morf.fs.remove(scratch, { recursive = true })
  morf.fs.mkdir(folder)
  local picture = morf.fs.join(morf.env("PWD"), "tests/fixtures/wallpaper.png")
  local names = { "capture_20261101_09-00-00_001.png", "capture_20261030_12-30-00_002.png", "Replay_2026-10-01.mp4", "notes.txt" }
  for _, name in ipairs(names) do morf.fs.copy(picture, folder .. "/" .. name) end
  local copies, renders = {}, 0
  backend.windows = function(cb) cb({}) end
  local real = backend.session
  backend.copy = function(path, cb) copies[#copies + 1] = path cb(true) end
  morf.process.detach = function() end
  require("config").set("capture.folder", folder)
  require("app")
  local env = morf.env
  morf.env = function(key) if key == "EVA_DRY_RUN" then return "0" end return env(key) end
  local capture = require("capture")
  morf.shared("eva.capture.owner", ""):set("")
  morf.ipc.state = nil
  morf.ipc.flow = function()
    local recent = package.loaded.recent
    return { open = capture.history_open:get(), loaded = recent ~= nil, panel = capture.drawer.open:get(),
      height = capture.height(), rows = recent and #recent.rows:get() or 0, total = recent and recent.total:get() or 0,
      note = recent and recent.note:get() or "", editing = capture.editor.active:get(), copies = #copies,
      keyboard = morf.surface.keyboard_focus }
  end
  morf.ipc.names = function()
    local out = {}
    for i, row in ipairs(package.loaded.recent.rows:get()) do out[i] = row.name end
    return out
  end
  morf.ipc.exists = function(name) return morf.fs.exists(folder .. "/" .. name) end
  morf.ipc.folder_to = function(path) require("config").set("capture.folder", path) end
  morf.ipc.search = function(words) package.loaded.recent.search(words) return true end
  morf.ipc.words = function()
    local recent = package.loaded.recent
    local when, list = 1793000000, nil
    local function fresh() return { { name = "a.png", kind = "shot", modified = when, size = 2048 } } end
    local now = when + 2 * 86400
    return { date = #recent.filter(fresh(), morf.time.format("%Y-%m-%d", when), now),
      month = #recent.filter(fresh(), morf.time.format("%B", when), now),
      short = #recent.filter(fresh(), morf.time.format("%-d %b", when), now),
      two = #recent.filter(fresh(), "a.png " .. morf.time.format("%A", when), now),
      wrong = #recent.filter(fresh(), "yesterday", now),
      label = recent.label(fresh()[1], when + 60), size = recent.size(2048), big = recent.size(3145728) }
  end
]]

local function tool(style, size)
  test.load(TOOL, { source = SOURCE, size = size or { 1920, 1080 },
    env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "" } })
  test.advance(300)
end

local function history()
  test.ipc("capture", "open") test.settle(1000)
  test.click("capture-history-open") test.settle(800)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the panel keeps its height until the history is asked for", function()
    tool(style)
    test.ipc("capture", "open") test.settle(1000)
    test.truthy(test.get("drawer-capture").height <= 264)
    test.falsy(test.ipc("flow").loaded, "the history was loaded at rest")
    test.falsy(test.find { id = "capture-history" })
    test.click("capture-history-open") test.settle(800)
    local state = test.ipc("flow")
    test.truthy(state.open)
    test.truthy(test.get("drawer-capture").height > 264)
    test.truthy(test.find { id = "capture-history", visible = true })
    test.falsy(test.find { id = "capture-controls", visible = true }, "the controls stayed under it")
    test.eq(state.keyboard, "exclusive")
    test.click("capture-history-open") test.settle(800)
    test.falsy(test.find { id = "capture-history" }, "it stayed built")
    test.truthy(test.find { id = "capture-screenshot", visible = true })
    test.near(test.get("drawer-capture").height, 264, 1)
    test.eq(test.ipc("flow").keyboard, "none")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": lists shots and recordings, not what else is in the folder", function()
    tool(style)
    history()
    local state = test.ipc("flow")
    test.eq(state.total, 3)
    test.eq(state.rows, 3)
    test.truthy(test.find { id = "capture-history-row-3", visible = true })
    test.falsy(test.find { id = "capture-history-row-4", visible = true })
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": fits a phone, a row to the finger", function()
    tool(style, { 412, 915 })
    history()
    local d = test.get("drawer-capture")
    test.truthy(d.width <= 412 - 20 and d.x >= 0)
    test.truthy(d.height <= 915)
    test.truthy(test.get("capture-history-row-1").height >= 44, "a row too small for a finger")
    test.truthy(test.find { id = "capture-history-delete", visible = true })
    local box = test.get("capture-history-delete")
    test.truthy(box.height >= 36)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("searches by name and by date", function()
  tool()
  history()
  test.ipc("search", "replay")
  test.eq(test.ipc("names"), { "Replay_2026-10-01.mp4" })
  test.ipc("search", "PNG")
  test.eq(#test.ipc("names"), 2)
  test.ipc("search", "recording")
  test.eq(#test.ipc("names"), 1)
  test.ipc("search", "nothing-like-this")
  test.eq(#test.ipc("names"), 0)
  test.truthy(test.find { id = "capture-history-empty", visible = true })
  test.ipc("search", "today")
  test.eq(#test.ipc("names"), 3)
  test.ipc("search", "")
  test.eq(#test.ipc("names"), 3)
end)

test.it("date words are found from when the file was made", function()
  tool()
  history()
  local said = test.ipc("words")
  test.eq(said.date, 1) test.eq(said.month, 1) test.eq(said.short, 1) test.eq(said.two, 1)
  test.eq(said.wrong, 0)
  test.contains(said.label, "Today ")
  test.eq(said.size, "2 KB") test.eq(said.big, "3.0 MB")
end)

test.it("a folder that is not there stays not there", function()
  tool()
  local missing = morf.env("XDG_CACHE_HOME") .. "/capture-history-missing/shots"
  test.ipc("folder_to", missing)
  history()
  test.eq(test.ipc("flow").total, 0)
  test.truthy(test.find { id = "capture-history-empty", visible = true })
  test.falsy(morf.fs.exists(missing), "opening the history made the folder")
  test.falsy(morf.fs.exists(morf.env("XDG_CACHE_HOME") .. "/capture-history-missing"))
end)

test.it("reopens a chosen shot in the editor, a press on a row twice the same", function()
  tool()
  history()
  test.ipc("search", "png")
  test.click("capture-history-row-1") test.advance(100)
  test.click("capture-history-edit") test.advance(500)
  test.truthy(test.ipc("flow").editing, "the editor did not open")
  test.key("Escape") test.advance(300)
  test.falsy(test.ipc("flow").editing)
  history()
  test.ipc("search", "png")
  test.click("capture-history-row-2") test.advance(100)
  test.falsy(test.ipc("flow").editing)
  test.click("capture-history-row-2") test.advance(500)
  test.truthy(test.ipc("flow").editing, "a second press did not open it")
  test.eq(#test.logs("error"), 0)
end)

test.it("copies a chosen shot", function()
  tool()
  history()
  test.ipc("search", "png")
  test.click("capture-history-row-1") test.advance(100)
  test.click("capture-history-copy") test.advance(100)
  local state = test.ipc("flow")
  test.eq(state.copies, 1)
  test.eq(state.note, "Copied")
end)

test.it("deletes on the second press only, the file and nothing else", function()
  tool()
  history()
  test.click("capture-history-row-1") test.advance(100)
  local name = test.ipc("names")[1]
  test.click("capture-history-delete") test.advance(100)
  test.truthy(test.ipc("exists", name), "a first press deleted it")
  test.contains(test.ipc("flow").note, "again")
  test.click("capture-history-delete") test.advance(100)
  test.falsy(test.ipc("exists", name), "a second press left it")
  local state = test.ipc("flow")
  test.eq(state.total, 2)
  test.truthy(test.ipc("exists", "notes.txt"))
end)

test.it("a delete asked for one row is not carried to another", function()
  tool()
  history()
  test.click("capture-history-row-1") test.advance(100)
  test.click("capture-history-delete") test.advance(100)
  test.click("capture-history-row-2") test.advance(100)
  test.click("capture-history-delete") test.advance(100)
  test.eq(test.ipc("flow").total, 3)
end)

test.it("shuts with the panel, and lets its pictures go", function()
  tool()
  history()
  test.truthy(test.ipc("flow").open)
  test.ipc("capture", "close") test.settle(1000)
  local state = test.ipc("flow")
  test.falsy(state.open)
  test.falsy(test.find { id = "capture-history" })
  test.ipc("capture", "open") test.settle(1000)
  test.truthy(test.find { id = "capture-screenshot", visible = true }, "it came back on the history")
end)
