-- A list's rows come in after the drawer has revealed them, on every opening,
-- in both themes: none moves under a cover, the top one first, shutting lands
-- them at rest, Reduce motion has them stand at once, and nothing moves once
-- they have arrived.
local test = morf.test
local FRAME = 16
local HOST = [[
  local ui = require("morf.ui")
  local W, H = 1280, 800
  morf.surface.height = H
  package.loaded.bar = { desk = function() return 0, 0, W, H end }
  package.loaded.providers = { PREFIXES = {} }
  package.loaded.menus = { source = morf.signal("test.menu", ""), back = function() return false end,
    open = function() end, search = function() return {}, "apps" end }
  package.loaded.wallpaper = { current = morf.signal("test.wallpaper", "not-current") }
  package.loaded.apps = { refresh = function() end, icon = function() return nil end,
    activate = function() return "keep" end,
    search = function()
      local out = {}
      for i = 1, 6 do out[i] = { id = "app" .. i, kind = "app", name = "Application " .. i, description = "A result" } end
      return out, "apps"
    end }
  local launcher = require("launcher")
  ui.Item { width = W, height = H,
    ui.Sdf { anchors = { fill = true }, launcher.drawer.shape }, launcher.drawer.panel }
  morf.ipc.open = function(on) launcher.drawer.set(on == "yes") end
  morf.ipc.revealed = function() return require("presentation").active("launcher.revealed")() end
]]

local serial = 0
local function load(style, values)
  serial = serial + 1
  local appearance = morf.env("XDG_CACHE_HOME") .. "/reveal-rows-" .. serial .. ".json"
  morf.fs.write(appearance, morf.json.encode(values or {}))
  test.load("../shell/init.lua", { source = HOST, size = { 1280, 800 }, env = { EVA_STYLE = style,
    EVA_APPEARANCE = appearance,
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/reveal-rows-settings-" .. serial .. ".json" } })
end
local function row(i) return test.get("launcher-row-app:app" .. i) end
-- Frames until the drawer says its rows are in sight.
local function until_revealed()
  for _ = 1, 120 do
    if test.ipc("revealed") then return true end
    test.advance(FRAME)
  end
  return false
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " rows after the reveal", function()
    test.it("enter once revealed, the top one first, on every opening", function()
      load(style)
      for pass = 1, 2 do
        test.ipc("open", "yes")
        test.truthy(until_revealed(), "the drawer never revealed its rows")
        test.advance(2 * FRAME)
        local first, last = row(1).opacity, row(6).opacity
        test.truthy(first < 1 or last < 1, "no row came in on opening " .. pass)
        test.truthy(first >= last, "the rows did not come in top first")
        test.advance(1500)
        for i = 1, 6 do test.near(row(i).opacity, 1, 0.001, "row " .. i .. " did not arrive") end
        test.ipc("open", "no")
        test.advance(1500)
      end
      test.eq(#test.logs("error"), 0)
    end)

    test.it("lands at rest when shut while coming in", function()
      load(style)
      test.ipc("open", "yes")
      until_revealed()
      test.advance(FRAME)
      test.ipc("open", "no")
      test.advance(FRAME)
      for i = 1, 6 do test.near(row(i).opacity, 1, 0.001, "row " .. i .. " was left half in") end
      test.falsy(test.ipc("revealed"), "a shutting drawer still says it shows its rows")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("stands at once under Reduce motion", function()
      load(style, { reduce_motion = true })
      test.ipc("open", "yes")
      test.truthy(until_revealed(), "the drawer never revealed its rows")
      test.advance(2 * FRAME)
      for i = 1, 6 do test.near(row(i).opacity, 1, 0.001, "row " .. i .. " travelled") end
      test.eq(#test.logs("error"), 0)
    end)

    test.it("holds still once the rows have arrived", function()
      load(style)
      test.ipc("open", "yes")
      test.settle(4000)
      -- A settle takes two frames to see that nothing moved.
      test.truthy(test.settle(2000) <= 2 * FRAME, "something still moves at rest")
    end)
  end)
end
