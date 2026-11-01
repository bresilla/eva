-- The small things under a finger, in both themes: a picture zooms and pans
-- under two fingers and leaves a page's swipe alone while it is not zoomed, a
-- text field walks its caret and selects on a long press, and a tool's overlay
-- has a finger's way out.

local test = morf.test

local PICTURE = [[
  local ui = require("morf.ui")
  require("kit")
  local node = ui.Rect { id = "picture", anchors = { fill = true }, color = "#336699" }
  local frame = ui.Item { id = "frame", x = 40, y = 40, width = 320, height = 240, clip = true, node }
  local view = require("pinch_zoom").attach { node = node, area = frame }
  local pans = 0
  ui.Item { width = 400, height = 400, frame,
    on_panned = function(phase) if phase == "begin" then pans = pans + 1 end end }
  morf.ipc.q_view = function()
    return { scale = node.scale, x = node.translate_x, y = node.translate_y, pans = pans, view = view.scale() }
  end
]]

local FIELD = [[
  local ui = require("morf.ui")
  local kit = require("kit")
  local box, input = kit.text_field("entry", { id = "field", width = 300, height = 44, text = "hello brave world" })
  ui.Item { width = 400, height = 200, ui.Item { x = 20, y = 20, width = 300, height = 44, box } }
  morf.ipc.q_field = function()
    return { from = input.selection_start, to = input.selection_end, at = input.cursor_position,
      picked = input:selected_text() }
  end
]]

local function load(style, source, size)
  test.load("../shell/init.lua", { source = source, size = size or { 400, 400 }, env = { EVA_STYLE = style,
    EVA_DRY_RUN = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "", LULE_A = "/nonexistent/lule",
    HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(300)
end

local function pinch(x, y, from, to, keep)
  test.touch("down", 0, x - from, y) test.touch("down", 1, x + from, y) test.advance(16)
  for i = 1, 8 do
    local at = from + (to - from) * i / 8
    test.touch("move", 0, x - at, y) test.touch("move", 1, x + at, y) test.advance(16)
  end
  if keep then return end
  test.touch("up", 0, x - to, y) test.touch("up", 1, x + to, y) test.advance(900)
end

local function drag(x, y, dx, dy)
  test.touch("down", 0, x, y) test.advance(16)
  for i = 1, 10 do test.touch("move", 0, x + dx * i / 10, y + dy * i / 10) test.advance(16) end
  test.advance(120)
  test.touch("up", 0, x + dx, y + dy) test.advance(900)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " a picture zooms under two fingers and springs back past its limits", function()
    load(style, PICTURE)
    pinch(200, 160, 30, 90, true)
    test.near(test.ipc("q_view").scale, 3, .1)
    test.touch("up", 0, 110, 160) test.touch("up", 1, 290, 160) test.advance(900)
    test.near(test.ipc("q_view").scale, 3, .1)
    pinch(200, 160, 100, 20)
    test.near(test.ipc("q_view").view, 1, .01, "closed past its smallest it springs back")
    test.near(test.ipc("q_view").scale, 1, .01)
    test.eq(test.logs("error"), {})
  end)

  test.it(style .. " one finger pans a zoomed picture and leaves a page's swipe alone otherwise", function()
    load(style, PICTURE)
    drag(200, 160, -100, 0)
    test.eq(test.ipc("q_view").pans, 1, "at rest the drag is the page's")
    pinch(200, 160, 30, 90)
    drag(200, 160, -60, 0)
    test.eq(test.ipc("q_view").pans, 1, "zoomed the drag is the picture's")
    test.truthy(test.ipc("q_view").x < -30, "it panned")
    test.eq(test.logs("error"), {})
  end)

  test.it(style .. " a double tap zooms in and back out", function()
    load(style, PICTURE)
    test.click(200, 160) test.advance(60) test.click(200, 160) test.advance(900)
    test.truthy(test.ipc("q_view").scale > 2)
    test.click(200, 160) test.advance(60) test.click(200, 160) test.advance(900)
    test.near(test.ipc("q_view").scale, 1, .01)
    test.eq(test.logs("error"), {})
  end)

  test.it(style .. " a finger on a text field walks the caret, a long press selects the word", function()
    load(style, FIELD)
    test.touch("down", 0, 40, 42) test.advance(16)
    for i = 1, 6 do test.touch("move", 0, 40 + 12 * i, 42) test.advance(16) end
    test.touch("up", 0, 112, 42) test.advance(100)
    local state = test.ipc("q_field")
    test.eq(state.from, state.to, "a drag leaves no selection")
    test.touch("down", 0, 100, 42) test.advance(700) test.touch("up", 0, 100, 42) test.advance(100)
    state = test.ipc("q_field")
    test.truthy(state.to > state.from, "a long press selected")
    test.truthy(state.picked == "hello" or state.picked == "brave" or state.picked == "world", state.picked)
    test.eq(test.logs("error"), {})
  end)
end
