-- eva-find: the start position's seam, the three modes, how each ends, and the
-- spotlight's field as one box with a circle out of it, in both themes. The
-- overlay on a real compositor is tools/see/find.steps'.
--
--     morf test --no-dbus tests/find_spec.lua

local test = morf.test

local SURFACE = "layer:eva-find"

local function tool(env)
  local full = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" }
  for key, value in pairs(env or {}) do full[key] = value end
  test.load("../apps/find/app.lua", { env = full, size = { 1280, 800 } })
  test.advance(16)
end

local function state() return test.ipc("state") end

test.it("starts at the fake pointer", function()
  tool { EVA_FAKE_POINTER = "300,200" }
  local s = state()
  test.eq(s.mode, "spotlight")
  test.eq({ s.x, s.y, s.known }, { 300, 200, true })
end)

test.it("reads the pointer from hyprctl where it can", function()
  test.stub_run("hyprctl", { code = 0, stdout = "640, 360\n" })
  tool { HYPRLAND_INSTANCE_SIGNATURE = "stub" }
  test.advance(50)
  local s = state()
  test.eq({ s.x, s.y, s.known }, { 640, 360, true })
  test.eq(test.runs()[1], { "hyprctl", "cursorpos" })
  test.clear_stubs()
end)

test.it("takes the middle of the screen until the first motion", function()
  tool()
  local s = state()
  test.eq({ s.x, s.y, s.known }, { 640, 400, false })
  test.move(100, 120)
  test.eq(state().known, false, "a move on the primary surface is not the overlay's")
  test.ipc("point", "100", "120")
  s = state()
  test.eq({ s.x, s.y, s.known }, { 100, 120, true })
end)

test.it("follows motion over the overlay", function()
  tool()
  test.click(10, 10, { surface = SURFACE, button = "right" })
  test.truthy(state().leaving, "a press ends the spotlight")
  tool { EVA_FIND_MODE = "crosshairs" }
  test.ipc("point", "500", "300")
  test.eq(state().mode, "crosshairs")
  test.truthy(test.find { id = "find-line-gap" })
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it("has one field for the dim and the circle in " .. style, function()
    tool { EVA_FAKE_POINTER = "300,200", EVA_STYLE = style }
    local field = test.get("find-field")
    test.eq(field.element, "Sdf")
    test.eq(test.get("find-circle").parent, field.handle)
    test.eq(test.get("find-screen").parent, field.handle)
    test.settle(2000 - 400)
    local hole = test.get("find-hole")
    test.near(hole.x + hole.width / 2, 300, 1, "the circle is not on the pointer")
    test.near(hole.width, 220, 2, "the circle did not spring in")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("springs in from wide", function()
  tool { EVA_FAKE_POINTER = "300,200" }
  test.truthy(test.get("find-hole").width > 1000, "the circle starts wide")
end)

test.it("goes after a moment, and a move holds it off", function()
  tool()
  test.advance(1500)
  test.ipc("point", "20", "20")
  test.advance(1500)
  test.falsy(state().leaving, "a move restarts the moment")
  test.advance(400)
  test.truthy(state().leaving)
end)

test.it("ends on a key, a press, the wheel and a second launch", function()
  tool()
  test.click(5, 5, { surface = SURFACE })
  test.truthy(state().leaving, "press")
  tool()
  test.wheel(0, 40, { x = 5, y = 5, surface = SURFACE })
  test.truthy(state().leaving, "wheel")
  tool()
  test.click(5, 5, { surface = SURFACE, button = "middle" })
  test.truthy(state().leaving, "another button")
  tool()
  test.ipc("eva-raise")
  test.truthy(state().leaving, "second launch")
end)

test.it("ends on a key: any key for the rest, Escape for the rings", function()
  tool { EVA_FIND_MODE = "ripple" }
  test.click(5, 5, { surface = SURFACE })
  test.key("a")
  test.falsy(state().leaving, "a key ended the rings")
  test.key("Escape")
  test.truthy(state().leaving)
  tool { EVA_FIND_MODE = "spotlight" }
  test.ipc("point", "5", "5")
  test.move(5, 5, { surface = SURFACE })
  test.key("a", nil, { surface = SURFACE })
end)

test.it("keeps the crosshairs until it is told", function()
  tool { EVA_FIND_MODE = "crosshairs" }
  test.advance(5000)
  test.falsy(state().leaving)
  local across = test.get("find-across")
  test.truthy(across.width > 1280, "the line does not cross the screen")
  test.eq(test.get("find-lines").element, "Sdf")
end)

test.it("draws a ring on each press and leaves none behind", function()
  tool { EVA_FIND_MODE = "ripple" }
  test.press(200, 200, { surface = SURFACE })
  test.release(200, 200, { surface = SURFACE })
  test.press(400, 300, { surface = SURFACE })
  test.release(400, 300, { surface = SURFACE })
  test.eq(state().rings, 2)
  test.falsy(state().leaving, "a press ends the rings")
  test.truthy(test.find { id = "find-ring-1" })
  test.advance(1000)
  test.eq(state().rings, 0)
end)

test.it("answers a touch on a phone", function()
  test.load("../apps/find/app.lua", { size = { 412, 915 }, env = { EVA_DRY_RUN = "1", EVA_FIND_MODE = "ripple",
    EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule" } })
  test.advance(16)
  test.touch("down", 1, 100, 300, { surface = SURFACE })
  test.touch("up", 1, 100, 300, { surface = SURFACE })
  test.eq(state().rings, 1)
end)

test.it("takes the modes as flags too", function()
  for _, flag in ipairs { "crosshairs", "ripple" } do
    test.load("../apps/find/app.lua", { args = { "--" .. flag }, size = { 1280, 800 },
      env = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" } })
    test.advance(16)
    test.eq(state().mode, flag)
  end
end)

test.it("falls back to the spotlight for a word it does not know", function()
  tool { EVA_FIND_MODE = "nonsense" }
  test.eq(state().mode, "spotlight")
end)
