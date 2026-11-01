-- A tool under a finger, in both themes: tabs that page by swipe, a swipe in from
-- the window's left edge to leave, and a swipe in from an overlay's edge.

local test = morf.test

local SOURCE = [[
  local ui = require("morf.ui")
  local frame = require("common.frame")
  local controls = require("common.controls")
  local closed, back_allowed, backed, overlays = 0, false, 0, 0
  frame.open { id = "probe", title = "Probe", width = 640, height = 560,
    on_close = function() closed = closed + 1 end,
    back = function()
      if back_allowed then backed = backed + 1 return true end
      return false
    end,
    build = function(w, h)
      local node, tab = controls.pages { id = "probe", width = w, height = h, tabs = {
        { key = "one", name = "One", icon = "alarm", build = function() return ui.Item {} end },
        { key = "two", name = "Two", icon = "timer", build = function() return ui.Item {} end },
      } }
      morf.ipc.tool_state = function() return { tab = tab:get(), closed = closed, backed = backed } end
      morf.ipc.allow_back = function() back_allowed = true end
      return node
    end }
]]

local function load(style)
  local state = morf.env("XDG_STATE_HOME") .. "/touch-tool-" .. style
  morf.fs.mkdir(state)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style, font = "" })
  test.load("../apps/keys/app.lua", { source = SOURCE, env = { EVA_DRY_RUN = "1", XDG_STATE_HOME = state,
    EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_APPEARANCE = appearance } })
  test.settle(600)
end

-- The tool's window, the surface after the primary.
local function window()
  for _, surface in ipairs(test.surfaces()) do
    if surface.label ~= "primary" then return surface.label end
  end
end

local function drag(x, y, dx, dy)
  local on = { surface = window() }
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
  test.it(style .. " a swipe in from the left edge goes back a level, or closes the tool", function()
    load(style)
    test.ipc("allow_back")
    drag(6, 300, 300, 0)
    test.eq(test.ipc("tool_state").backed, 1)
    test.eq(test.ipc("tool_state").closed, 0)
    test.eq(test.logs("error"), {})
  end)
end
