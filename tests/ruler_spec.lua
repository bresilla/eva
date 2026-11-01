-- eva-ruler: the walk, edges read off a real picture through the strips, a
-- picture over the limit a file's pixel takes, the modes, the units, the copy,
-- and how it ends. The real clipboard over a real freeze is tools/see/ruler.steps'.
--
--     morf test --no-dbus tests/ruler_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local SURFACE = "layer:eva-ruler"

-- A white screen with a black box from 100,50 up to 300,200 and a grey one
-- beside it, a colour apart from the white that a tolerance can walk through.
local SVG = [[<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d">
  <rect width="%d" height="%d" fill="#ffffff"/>
  <rect x="100" y="50" width="200" height="150" fill="#000000"/>
  <rect x="300" y="50" width="100" height="150" fill="#f0f0f0"/>
</svg>]]

local function make(path, width, height)
  test.load { source = ([[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local done = false
    morf.image.process { source = %q, output = %q, on_done = function() done = true end, ops = {} }
    morf.ipc.done = function() return done end
  ]]):format(SVG:format(width, height, width, height), path) }
  test.wait(function() test.advance(16) return test.ipc("done") end, 8000)
end

local PICTURE = morf.env("XDG_STATE_HOME") .. "/ruler-picture.png"
local BIG = morf.env("XDG_STATE_HOME") .. "/ruler-big.png"

local function env(extra)
  local full = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" }
  for key, value in pairs(extra or {}) do full[key] = value end
  return full
end

local function tool(extra, picture, size)
  test.stub_run("grim", { code = 1 })
  test.load("../apps/ruler/app.lua", { env = env(extra), size = size or { 1280, 800 }, source = ([[
    local model = require("model")
    model.freeze = function() model.picture:set { path = %q, width = %d, height = %d } end
  ]]):format(picture or PICTURE, (size or { 1280, 800 })[1], (size or { 1280, 800 })[2])
    .. morf.fs.read(ROOT .. "apps/ruler/app.lua") })
  test.advance(32)
end

local function state() return test.ipc("state") end

local function measured()
  return test.wait(function()
    test.advance(16)
    local s = state()
    return s.reading ~= "" and s.edges and s or nil
  end, 5000, "no edges came back")
end

test.it("makes its pictures", function()
  make(PICTURE, 1280, 800)
  make(BIG, 3840, 2160)
  test.truthy(morf.fs.exists(PICTURE))
end)

test.it("walks to the last pixel in tolerance", function()
  test.load { source = [[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local scan = require("scan")
    morf.ipc.walk = function(from, step, last, tolerance)
      local line = { 10, 10, 11, 10, 90, 90, 90 }
      local function read(i) return line[i + 1], line[i + 1], line[i + 1] end
      return scan.walk(read, tonumber(from), tonumber(step), tonumber(last), tonumber(tolerance))
    end
  ]], runtime_path = { ROOT .. "apps/ruler" } }
  test.eq(test.ipc("walk", "1", "1", "6", "2"), 3)
  test.eq(test.ipc("walk", "5", "-1", "0", "2"), 4)
  test.eq(test.ipc("walk", "1", "1", "6", "100"), 6, "it stopped short of the end")
  test.eq(test.ipc("walk", "0", "-1", "0", "2"), 0)
end)

test.it("finds the edges round the pointer", function()
  tool()
  test.ipc("point", "200", "120")
  local s = measured()
  test.eq(s.edges, { left = 100, right = 299, top = 50, bottom = 199 })
  test.eq(s.reading, "200 × 150 px")
end)

test.it("walks through a near colour until the tolerance is tightened", function()
  tool()
  test.ipc("point", "600", "120")
  local wide = measured()
  test.eq(wide.edges.left, 300, "white did not run into the near grey")
  test.ipc("tune", "-4")
  local tight = state()
  test.eq(tight.tolerance, 10)
  test.eq(tight.edges.left, 400, "the grey box is not an edge at a tight tolerance")
end)

test.it("reads a picture over the limit a file's pixel takes", function()
  tool(nil, BIG, { 3840, 2160 })
  test.ipc("point", "200", "120")
  local s = measured()
  test.eq(s.edges, { left = 100, right = 299, top = 50, bottom = 199 })
end)

test.it("keeps a run of moves to the newest", function()
  tool()
  test.ipc("point", "10", "10")
  test.ipc("point", "20", "20")
  test.ipc("point", "200", "120")
  test.wait(function()
    test.advance(16)
    local s = state()
    return s.edges and s.edges.left == 100
  end, 5000, "the newest point was dropped")
end)

test.it("reads one axis in the one-axis modes", function()
  tool()
  test.ipc("point", "200", "120")
  measured()
  test.ipc("mode", "horizontal")
  test.eq(state().reading, "200 px")
  test.ipc("mode", "vertical")
  test.eq(state().reading, "150 px")
end)

test.it("reads a dragged box", function()
  tool()
  test.ipc("mode", "bounds")
  test.drag({ 100, 100 }, { 500, 400 }, { steps = 6, surface = SURFACE })
  test.eq(state().reading, "400 × 300 px")
  test.eq(state().copied, "400 × 300 px", "the drag's end copies it")
  test.settle(1000)
  local box = test.get("ruler-box")
  test.near(box.width, 400, 2)
end)

test.it("adds millimetres and inches where the screen says its size", function()
  tool { EVA_FAKE_SCREEN_MM = "320x200" }
  test.ipc("point", "200", "120")
  local s = measured()
  test.eq(s.physical, "50.0 × 37.5 mm · 1.97 × 1.48 in")
  tool()
  test.ipc("point", "200", "120")
  test.eq(measured().physical, "")
end)

test.it("a click copies the measure, and the keys pick the mode", function()
  tool()
  test.ipc("point", "200", "120")
  measured()
  test.click(200, 120, { surface = SURFACE })
  test.eq(state().copied, "200 × 150 px")
  test.contains(state().message, "Copied")
  test.key("h")
  test.eq(state().mode, "horizontal")
  test.key("4")
  test.eq(state().mode, "bounds")
  test.click { id = "ruler-mode-spacing" }
  test.eq(state().mode, "spacing")
end)

test.it("the wheel changes the tolerance", function()
  tool()
  test.wheel(0, -40, { x = 300, y = 300, surface = SURFACE })
  test.eq(state().tolerance, 35)
  test.wheel(0, 40, { x = 300, y = 300, surface = SURFACE })
  test.wheel(0, 40, { x = 300, y = 300, surface = SURFACE })
  test.eq(state().tolerance, 25)
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it("draws the measure as one field on springs in " .. style, function()
    tool { EVA_STYLE = style }
    test.ipc("point", "200", "120")
    measured()
    test.settle(1500)
    test.eq(test.get("ruler-field").element, "Sdf")
    test.eq(test.get("ruler-shape-2").parent, test.get("ruler-field").handle)
    local across = test.get("ruler-across")
    test.near(across.x, 100, 2)
    test.near(across.width, 200, 2)
    test.truthy(test.get("ruler-reading").visible)
    test.eq(test.get("ruler-px").text, "200 × 150 px")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("takes a finger on a phone, the pill on the screen", function()
  tool(nil, nil, { 412, 915 })
  local bar = test.get("ruler-modes")
  test.truthy(bar.x >= 0 and bar.x + bar.width <= 412)
  test.touch("down", 1, 200, 120, { surface = SURFACE })
  test.touch("up", 1, 200, 120, { surface = SURFACE })
  test.wait(function() test.advance(16) return state().reading ~= "" end, 5000)
  test.click { id = "ruler-mode-bounds" }
  test.eq(state().mode, "bounds")
end)

test.it("ends on Escape and a second launch", function()
  tool()
  test.click(5, 5, { surface = SURFACE, button = "right" })
  test.key("Escape")
  test.falsy(state().frozen)
  tool()
  test.ipc("eva-raise")
  test.falsy(state().frozen)
end)
