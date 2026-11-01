-- The launcher's panel, a frame at a time: it never closes between modes, it
-- changes size on a spring, and its highlight glides from row to row.
local test = morf.test
local FRAME = 16
local HOST = [[
  local ui = require("morf.ui")
  local nodes = {}
  local item = ui.Item
  ui.Item = function(props)
    local node = item(props)
    if props.id then nodes[props.id] = node end
    return node
  end
  local W, H = 1280, 800
  morf.surface.height = H
  package.loaded.bar = { desk = function() return 0, 0, W, H end }
  package.loaded.providers = { PREFIXES = {} }
  package.loaded.menus = { source = morf.signal("test.menu", ""), back = function() return false end,
    open = function() end, search = function() return {}, "apps" end }
  package.loaded.wallpaper = { current = morf.signal("test.wallpaper", "not-current") }
  package.loaded.apps = { refresh = function() end, icon = function() return nil end,
    activate = function() return "keep" end,
    search = function(q)
      if q == "none" then return {}, "apps" end
      if q == "wall" then
        local out = {}
        for i = 1, 12 do out[i] = { kind = "wallpaper", id = tostring(i), path = "", name = "Wallpaper " .. i } end
        return out, "wallpapers"
      end
      if q == "calc" then
        return { { id = "answer", kind = "calc", question = "2 + 2", name = "4", description = "Result" } }, "calculator"
      end
      local out = {}
      for i = 1, 6 do out[i] = { id = "app" .. i, kind = "app", name = "Application " .. i, description = "A result" } end
      return out, "apps"
    end }
  local launcher = require("launcher")
  ui.Item { width = W, height = H,
    ui.Sdf { anchors = { fill = true }, launcher.drawer.shape }, launcher.drawer.panel }
  morf.ipc.open = function(on) launcher.drawer.set(on == "yes") end
  morf.ipc.query = launcher.set_query
  morf.ipc.move = function(delta) launcher.move(tonumber(delta)) end
  morf.ipc.stretch = function()
    local node = nodes["launcher-highlight"]
    return node.stretch ~= nil and node.stretch ~= false
  end
  morf.ipc.open_now = function() return launcher.drawer.open:get() end
]]

local function load(style)
  test.load("../shell/init.lua", { source = HOST, size = { 1280, 800 }, env = { EVA_STYLE = style,
    EVA_APPEARANCE = morf.env("XDG_CACHE_HOME") .. "/launcher-motion-appearance.json",
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/launcher-motion-settings.json" } })
  test.ipc("open", "yes")
  test.advance(2200)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " launcher motion", function()
    test.it("stays open through every change of mode", function()
      load(style)
      for _, query in ipairs { "calc", "wall", "none", "", "calc", "" } do
        test.ipc("query", query)
        for _ = 1, 12 do
          test.advance(FRAME)
          test.truthy(test.ipc("open_now"), "the launcher closed for " .. query)
          test.truthy(test.get("drawer-launcher").visible, "the panel left for " .. query)
          test.near(test.get("drawer-launcher").opacity, 1, 0.001, "the panel faded for " .. query)
        end
      end
      test.eq(#test.logs("error"), 0)
    end)

    test.it("changes height on a spring and reverses without a jump", function()
      load(style)
      local tall = test.get("drawer-launcher").height
      test.ipc("query", "none")
      test.near(test.get("drawer-launcher").height, tall, 0.5, "the height jumped")
      test.advance(4 * FRAME)
      local turning = test.get("drawer-launcher").height
      test.truthy(turning < tall - 1, "the height did not move")
      test.ipc("query", "")
      test.near(test.get("drawer-launcher").height, turning, 0.5, "a reversal jumped")
      local path, lowest = {}, turning
      for i = 1, 40 do
        test.advance(FRAME)
        path[i] = test.get("drawer-launcher").height
        lowest = math.min(lowest, path[i])
      end
      test.truthy(lowest < turning, "the height stopped dead on the reversal")
      test.near(path[#path], tall, 1)
      test.eq(#test.logs("error"), 0)
    end)

    test.it("widens on a spring for the wallpapers", function()
      load(style)
      local narrow = test.get("drawer-launcher").width
      test.ipc("query", "wall")
      test.advance(3 * FRAME)
      local moving = test.get("drawer-launcher").width
      test.truthy(moving > narrow + 1, "the width did not move")
      test.advance(1000)
      test.truthy(test.get("drawer-launcher").width > moving, "the width did not arrive")
    end)

    test.it("glides its highlight between rows", function()
      load(style)
      local from = test.get("launcher-highlight").y
      test.ipc("move", 1)
      test.advance(3 * FRAME)
      local moving = test.get("launcher-highlight").y
      test.truthy(moving > from, "the highlight did not leave")
      test.advance(600)
      local to = test.get("launcher-highlight").y
      test.truthy(moving < to, "the highlight jumped to its row")
      test.eq(test.ipc("stretch"), style == "material", "stretch belongs to material's highlight")
    end)
  end)
end
