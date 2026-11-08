-- A tool under a finger, in both themes: a page's tabs that page by swipe, as
-- the Tools window holds them, and a swipe in from an overlay's edge.

local test = morf.test

local SOURCE = [[
  local ui = require("morf.ui")
  local frame = require("apps.common.frame")
  local controls = require("apps.common.controls")
  local overlays = 0
  local node, tab = controls.pages { id = "probe", width = 608, height = 500, tabs = {
    { key = "one", name = "One", icon = "alarm", build = function() return ui.Item {} end },
    { key = "two", name = "Two", icon = "timer", build = function() return ui.Item {} end },
  } }
  ui.Item { x = 16, y = 16, width = 608, height = 500, node }
  morf.ipc.tool_state = function() return { tab = tab:get(), overlays = overlays } end
  frame.overlay { id = "probe-over", keyboard = "none", close = function() overlays = overlays + 1 end,
    root = ui.Item { id = "probe-over-root", anchors = { fill = true },
      ui.MouseArea { id = "probe-over-area", anchors = { fill = true } } } }
]]

local function load(style)
  local state = morf.env("XDG_STATE_HOME") .. "/touch-tool-" .. style
  morf.fs.mkdir(state)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style, font = "" })
  test.load("../shell/init.lua", { source = SOURCE, size = { 640, 560 }, env = { EVA_DRY_RUN = "1",
    XDG_STATE_HOME = state, EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule",
    EVA_APPEARANCE = appearance, EVA_STYLE = style } })
  test.settle(600)
end

local function drag(x, y, dx, dy)
  local on = { surface = "primary" }
  test.touch("down", 0, x, y, on) test.advance(16)
  for i = 1, 12 do test.touch("move", 0, x + dx * i / 12, y + dy * i / 12, on) test.advance(16) end
  test.touch("up", 0, x + dx, y + dy, on) test.advance(900)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " a tool's tabs turn under a finger and rubber band at the ends", function()
    load(style)
    local track = test.get("probe-pages")
    local x, y = track.x + 300, track.y + 200
    drag(x, y, -240, 0)
    test.eq(test.ipc("tool_state").tab, 2)
    drag(x, y, -240, 0)
    test.eq(test.ipc("tool_state").tab, 2, "past the last it stays")
    drag(x, y, 240, 0)
    test.eq(test.ipc("tool_state").tab, 1)
    test.eq(test.logs("error"), {})
  end)
  test.it(style .. " a swipe in from an overlay's edge is a finger's way out", function()
    load(style)
    local on = { surface = "layer:eva-probe-over" }
    test.touch("down", 0, 300, 4, on) test.advance(16)
    for i = 1, 12 do test.touch("move", 0, 300, 4 + 14 * i, on) test.advance(16) end
    test.touch("up", 0, 300, 172, on) test.advance(700)
    test.eq(test.ipc("tool_state").overlays, 1)
    test.eq(test.logs("error"), {})
  end)
end
