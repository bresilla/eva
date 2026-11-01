-- eva-draw: a stroke from the mouse and from a finger, the pen and width keys,
-- undo and clear, words, the toolbar, and how it ends. Seeing it over a real
-- screen is tools/see/draw.steps'.
--
--     morf test --no-dbus tests/draw_spec.lua

local test = morf.test

local SURFACE = "layer:eva-draw"

local function tool(extra, size)
  local env = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" }
  for key, value in pairs(extra or {}) do env[key] = value end
  test.load("../apps/draw/app.lua", { env = env, size = size or { 1280, 800 } })
  test.advance(32)
end

local function state() return test.ipc("state") end

local function drag(from, to)
  test.drag(from, to, { steps = 12, surface = SURFACE })
end

test.it("a drag leaves one path, in the box it reached", function()
  tool()
  drag({ 100, 100 }, { 400, 300 })
  test.eq(state().marks, 1)
  local path = test.get("draw-mark-1")
  test.eq(path.element, "Path")
  test.near(path.x, 100 - 8, 6)
  test.truthy(path.width > 280 and path.width < 340, "the box is " .. path.width .. " wide")
  test.falsy(test.get("draw-draft").visible, "the draft stayed up")
end)

test.it("draws with a finger too", function()
  tool()
  test.touch("down", 1, 100, 100, { surface = SURFACE })
  test.truthy(state().drawing)
  test.touch("move", 1, 160, 130, { surface = SURFACE })
  test.touch("move", 1, 220, 180, { surface = SURFACE })
  test.touch("up", 1, 220, 180, { surface = SURFACE })
  test.eq(state().marks, 1)
  test.truthy(test.get("draw-mark-1").width > 100)
end)

test.it("a tap leaves a dot", function()
  tool()
  test.click(300, 300, { surface = SURFACE })
  test.eq(state().marks, 1)
  test.truthy(test.get("draw-mark-1").width > 0)
end)

test.it("shows the stroke under way", function()
  tool()
  test.press(100, 100, { surface = SURFACE })
  test.move(200, 200, { surface = SURFACE })
  test.truthy(test.get("draw-draft").visible)
  test.truthy(state().drawing)
  test.release(200, 200, { surface = SURFACE })
end)

test.it("keeps a long stroke in pieces and loses none of it", function()
  tool()
  local words = {}
  for index = 0, 700 do
    words[#words + 1] = tostring(10 + (index * 3) % 1200)
    words[#words + 1] = tostring(10 + index // 10)
  end
  test.ipc("stroke", table.concat(words, " "))
  test.eq(state().marks, 2)
end)

test.it("picks the pen and width from keys, the wheel and the toolbar", function()
  tool()
  test.click(5, 5, { surface = SURFACE })
  test.key("g")
  test.eq(state().pen, "g")
  test.key("p")
  test.eq(state().pen, "p")
  test.key("+")
  test.eq(state().width, 3)
  test.key("-")
  test.key("-")
  test.eq(state().width, 1)
  test.key("-")
  test.eq(state().width, 1, "the width ran under the first")
  test.wheel(0, -40, { x = 200, y = 200, surface = SURFACE })
  test.eq(state().width, 2)
  test.click { id = "draw-pen-c" }
  test.eq(state().pen, "c")
  test.click { id = "draw-width" }
  test.eq(state().width, 3)
end)

test.it("rides a mark onto the chosen pen on a spring", function()
  tool()
  local at = test.get("draw-chosen").x
  test.click { id = "draw-pen-p" }
  test.advance(32)
  local moving = test.get("draw-chosen").x
  test.truthy(moving > at, "the mark did not move")
  test.settle(1500)
  test.truthy(test.get("draw-chosen").x > moving, "the mark jumped")
  test.near(test.get("draw-chosen").x + 20, test.get("draw-pen-p").x + 20, 2)
end)

test.it("takes marks back, one by one and all at once", function()
  tool()
  drag({ 100, 100 }, { 200, 100 })
  drag({ 100, 200 }, { 200, 200 })
  drag({ 100, 300 }, { 200, 300 })
  test.key("u")
  test.eq(state().marks, 2)
  test.key("z", "ctrl")
  test.eq(state().marks, 1)
  test.key("e")
  test.eq(state().marks, 0)
  test.settle(1000)
  test.falsy(test.find { id = "draw-mark-1" }, "a mark stayed after its fade")
end)

test.it("takes words where they are pressed", function()
  tool()
  test.click { id = "draw-text" }
  test.truthy(state().writing)
  test.click(300, 200, { surface = SURFACE })
  test.truthy(state().typing)
  test.type("hey")
  test.eq(test.get("draw-typing-text").text, "hey")
  test.key("BackSpace")
  test.eq(test.get("draw-typing-text").text, "he")
  test.key("Return")
  test.falsy(state().typing)
  test.eq(state().marks, 1)
  local words = test.get("draw-mark-1")
  test.eq(words.text, "he")
  test.near(words.x, 300, 1)
end)

test.it("Escape leaves the words, and a typed letter picks no pen", function()
  tool()
  test.click { id = "draw-text" }
  test.click(300, 200, { surface = SURFACE })
  test.type("g")
  test.eq(state().pen, "r", "a typed letter picked a pen")
  test.key("Escape")
  test.falsy(state().typing)
  test.eq(state().marks, 0)
end)

test.it("keeps the toolbar on a phone's screen", function()
  tool(nil, { 412, 915 })
  local bar = test.get("draw-toolbar")
  test.truthy(bar.x >= 0 and bar.x + bar.width <= 412, "the toolbar runs off the screen")
  test.truthy(bar.height > 60, "it did not take a second row")
  local last = test.get("draw-end")
  test.truthy(last.x + last.width <= 412)
  test.click { id = "draw-pen-g" }
  test.eq(state().pen, "g")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it("builds in " .. style, function()
    tool { EVA_STYLE = style }
    drag({ 100, 100 }, { 200, 200 })
    test.eq(state().marks, 1)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("a press on the toolbar draws nothing", function()
  tool()
  test.click { id = "draw-undo" }
  test.eq(state().marks, 0)
  test.falsy(state().drawing)
end)
