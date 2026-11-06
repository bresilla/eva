-- eva-disk over a folder tree made in the scratch state dir, walked by the real
-- `du`: the treemap's arithmetic, what a folder holds, drilling in and back up, the
-- boxes in one field, the file manager held back when dry, the mounts from a fake
-- machine, and the page on a phone. A real home is tools/see/disk.steps'.
--
--     morf test --no-dbus tests/disk_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local machine = load(morf.fs.read(ROOT .. "tests/fixtures/fake_machine.lua"))()
local serial = 0

local function folder()
  serial = serial + 1
  local path = morf.env("XDG_STATE_HOME") .. "/disk-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(path)
  return path
end

-- A file of `kib` KiB.
local function file(path, kib)
  morf.fs.write(path, string.rep("x", kib * 1024), { parents = true })
end

local function tree()
  local root = folder()
  file(root .. "/videos/one.bin", 400)
  file(root .. "/videos/two.bin", 300)
  file(root .. "/videos/old/three.bin", 200)
  file(root .. "/music/song.bin", 100)
  file(root .. "/big.iso", 500)
  file(root .. "/note.txt", 8)
  return root
end

local function env(extra)
  local out = { EVA_DRY_RUN = "1", EVA_SETTINGS = "/nonexistent/eva.json", EVA_TEST_TOOL = "disk",
    EVA_TEST_PAGE = "948x650" }
  for key, value in pairs(extra or {}) do out[key] = value end
  return out
end

local function scanned()
  test.wait(function()
    test.advance(250)
    return not test.ipc("state").scanning and test.ipc("state").total > 0
  end, 8000, "the scan ended")
  test.advance(700)
  test.settle(200)
end

-- The page alone, as the Tools window shows it, opened on `path` as
-- `eva-disk PATH` opens it.
local function page(path, extra, size)
  test.load("../shell/init.lua", { env = env(extra), args = { path }, size = size,
    source = morf.fs.read(ROOT .. "tests/fixtures/tool_page.lua") })
end

local function tool(path, extra, size)
  page(path, extra, size)
  scanned()
end

test.it("makes areas of its sizes, all inside the box", function()
  test.load("../shell/init.lua", { env = env(), source = [[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local treemap = require("apps.disk.treemap")
    morf.ipc.layout = function(w, h, ...)
      local sizes = {}
      for index, value in ipairs { ... } do sizes[index] = tonumber(value) end
      return treemap.layout(sizes, 0, 0, tonumber(w), tonumber(h))
    end
    morf.ipc.parent = function(path) return require("apps.disk.model").parent(path) or "" end
    morf.ipc.parse = function(line) return require("apps.disk.model").parse(line) end
    morf.ipc.crumbs = function(path) return require("apps.disk.model").crumbs(path) end
    morf.ipc.tail = function(path, width)
      local model = require("apps.disk.model")
      return model.tail(model.crumbs(path), tonumber(width))
    end
  ]] })
  local sizes = { 60, 30, 20, 10, 5, 1 }
  local rects = test.ipc("layout", 400, 300, 60, 30, 20, 10, 5, 1)
  test.eq(#rects, 6)
  local whole, sum = 400 * 300, 126
  for index, rect in ipairs(rects) do
    test.near(rect.w * rect.h, whole * sizes[index] / sum, 0.01)
    test.truthy(rect.x >= -0.01 and rect.x + rect.w <= 400.01, "off the side")
    test.truthy(rect.y >= -0.01 and rect.y + rect.h <= 300.01, "off the foot")
  end
  test.eq(#test.ipc("layout", 100, 100), 0)
  test.eq(test.ipc("layout", 0, 100, 5)[1].w, 0)
  test.eq(test.ipc("parent", "/home/ada/x"), "/home/ada")
  test.eq(test.ipc("parent", "/home"), "/")
  test.eq(test.ipc("parent", "/"), "")
  local entry = test.ipc("parse", "1024\t/home/ada/a folder")
  test.eq(entry.path, "/home/ada/a folder")
  test.eq(entry.size, 1048576)
  test.eq(#test.ipc("crumbs", "/home/ada"), 3)
  test.eq(#test.ipc("tail", "/home/ada", 900), 3)
  local cut = test.ipc("tail", "/home/ada/a-long-folder/deep/down", 260)
  test.eq(cut[1].label, "…")
  test.eq(cut[#cut].label, "down")
  test.eq(cut[1].path, "/home/ada/a-long-folder")
end)

test.it("says what a folder holds, the largest first", function()
  local root = tree()
  tool(root)
  local state = test.ipc("state")
  test.eq(state.path, root)
  test.eq(#state.entries, 4)
  test.eq(state.entries[1].name, "videos")
  test.truthy(state.entries[1].dir)
  test.eq(state.entries[2].name, "big.iso")
  test.falsy(state.entries[2].dir)
  test.truthy(state.total >= 1500 * 1024)
  test.eq(test.get({ id = "disk-name-1" }).text, "videos")
  test.falsy(test.find({ id = "disk-box-5" }).visible, "a box nobody needs stays hidden")
  test.eq(#test.logs("error"), 0)
end)

test.it("makes one box of what does not fit", function()
  local root = folder()
  for index = 1, 30 do file(root .. "/f" .. index, index) end
  tool(root)
  local boxes = test.ipc("state").boxes
  test.eq(#boxes, 16)
  test.truthy(boxes[16].others)
  test.eq(boxes[16].name, "15 others")
  test.falsy(test.ipc("press", 16), "the rest is no folder")
end)

test.it("drills into a folder and comes back up by the crumbs", function()
  local root = tree()
  tool(root)
  test.truthy(test.ipc("state").moving == false)
  test.truthy(test.ipc("press", 1))
  test.truthy(test.ipc("state").moving, "the boxes move on the way in")
  scanned()
  local state = test.ipc("state")
  test.eq(state.path, root .. "/videos")
  test.eq(state.entries[1].name, "one.bin")
  test.falsy(state.moving, "the field rests once settled")
  test.eq(state.crumbs[#state.crumbs].label, "videos")
  test.truthy(test.ipc("up"))
  test.settle(100)
  test.eq(test.ipc("state").path, root)
  test.eq(test.ipc("state").entries[1].name, "videos", "what was scanned is remembered")
end)

test.it("names a file rather than opening it", function()
  local root = tree()
  tool(root)
  test.truthy(test.ipc("press", 2))
  test.contains(test.ipc("state").message, "big.iso")
  test.eq(test.ipc("state").path, root)
end)

test.it("presses reach a box", function()
  local root = tree()
  tool(root)
  test.click { id = "disk-press-1" }
  test.settle(100)
  test.eq(test.ipc("state").path, root .. "/videos")
end)

test.it("scans anew when asked, and sees what changed", function()
  local root = tree()
  tool(root)
  local before = test.ipc("state").total
  file(root .. "/more.bin", 900)
  test.ipc("refresh")
  scanned()
  test.truthy(test.ipc("state").total > before)
end)

test.it("refuses a folder that is not there", function()
  local root = tree()
  tool(root)
  test.falsy(test.ipc("open", root .. "/nothing"))
  test.contains(test.ipc("state").message, "No such folder")
  test.eq(test.ipc("state").path, root)
end)

test.it("shows an empty folder as that", function()
  local root = folder()
  page(root)
  test.wait(function()
    test.advance(250)
    return not test.ipc("state").scanning
  end, 8000, "the scan ended")
  test.settle(100)
  test.truthy(test.find({ id = "disk-empty" }).visible)
end)

test.it("holds the file manager back when dry", function()
  local root = tree()
  tool(root)
  test.truthy(test.ipc("reveal"))
  test.contains(test.ipc("state").message, "dry run")
end)

test.it("says so when du cannot start", function()
  local root = tree()
  page(root, { EVA_DU = ROOT .. "tests/fixtures/bin/nothing-here" })
  test.settle(100)
  local state = test.ipc("state")
  test.falsy(state.scanning)
  test.ne(state.message, "")
end)

test.it("reads every mount from the sampler, only on its page", function()
  local root = tree()
  local fake = machine.build(root .. "/machine", {})
  tool(root, { EVA_DISK_ROOT = fake })
  test.eq(#test.ipc("state").mounts, 0)
  test.ipc("tab", "mounts")
  test.advance(600)
  test.settle(200)
  local mounts = test.ipc("state").mounts
  test.eq(mounts[1].mount, "/")
  test.eq(mounts[1].type, "ext4")
  test.eq(test.get({ id = "disk-mount-name-1" }).text, "/")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " keeps its boxes inside a phone", function()
    local root = tree()
    tool(root, { EVA_STYLE = style, EVA_TEST_PAGE = "380x800" }, { 380, 800 })
    test.advance(800)
    test.settle(300)
    for _, box in ipairs(test.ipc("state").boxes) do
      test.truthy(box.x + box.w <= 380, "a box runs off the side")
    end
    test.eq(#test.logs("error"), 0)
  end)
end
