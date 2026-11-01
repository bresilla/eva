-- The launcher under a finger, in both themes: a swipe down shuts it, a hold
-- opens an app's actions, and an app dragged from a hold onto the place over the
-- grid is pinned, while a drag that never held scrolls.

local test = morf.test
local host = assert(load(morf.fs.read(morf.env("PWD") .. "/tests/fixtures/launcher_host.lua")))()

local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"
local COVER = morf.env("PWD") .. "/tests/fixtures/input-devices-cover"
local PHONE, DESK = { 620, 1380 }, { 1440, 900 }

local function at(node) return node.x + node.width / 2, node.y + node.height / 2 end

local function drag(x, y, dx, dy, keep)
  test.touch("down", 0, x, y) test.advance(16)
  for i = 1, 12 do test.touch("move", 0, x + dx * i / 12, y + dy * i / 12) test.advance(16) end
  if keep then return end
  test.touch("up", 0, x + dx, y + dy) test.advance(800)
end

local function open(style, devices, size, settings)
  host.load { style = style, size = size, settings = settings, env = { EVA_INPUT_DEVICES = devices } }
  test.ipc("launcher", "open") test.settle(700)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " a swipe down shuts the launcher, following the finger", function()
    for _, case in ipairs { { TOUCH, PHONE }, { COVER, DESK } } do
      open(style, case[1], case[2])
      local panel = test.get("drawer-launcher")
      local x, y = at(panel)
      drag(x, y, 0, 120, true)
      test.truthy(test.get("drawer-launcher").y > panel.y + 60, "it followed the finger")
      test.touch("up", 0, x, y + 120) test.advance(800)
      test.falsy(test.find { id = "drawer-launcher", visible = true }, "it shut")
    end
    test.eq(test.logs("error"), {})
  end)

  test.it(style .. " a hold opens an app's actions, and a drag from a hold pins it", function()
    open(style, TOUCH, PHONE)
    local tile = test.get { text = "Fixture Browser", visible = true }
    local x, y = tile.x + tile.width / 2, tile.y
    test.touch("down", 0, x, y) test.advance(700)
    test.truthy(test.find { id = "launcher-pin-target", visible = true }, "the place to drop on shows")
    local place = test.get("launcher-pin-target")
    local tx, ty = at(place)
    for i = 1, 10 do test.touch("move", 0, x + (tx - x) * i / 10, y + (ty - y) * i / 10) test.advance(16) end
    test.touch("up", 0, tx, ty) test.advance(400)
    test.falsy(test.find { id = "launcher-pin-target", visible = true }, "it goes with the finger")
    test.eq(test.ipc("state").acting, "", "a drag away from where it was opens no menu")
    tile = test.get { text = "Fixture Browser", visible = true }
    x, y = tile.x + tile.width / 2, tile.y
    test.touch("down", 0, x, y) test.advance(700)
    test.touch("up", 0, x, y) test.advance(300)
    test.truthy(host.row("Unpin from favourites"), "it was pinned")
    test.eq(test.logs("error"), {})
  end)
end
