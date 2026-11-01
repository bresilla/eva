-- What comes in, a frame at a time: panels' contents in turn on the spatial
-- spring, a list's rows after one another, a tab's indicator between tabs.
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
  local kit = require("kit")
  local theme = require("theme")
  local cards = {}
  for i = 1, 3 do cards[i] = ui.Rect { id = "card-" .. i, x = (i - 1) * 110, width = 100, height = 60,
    color = function() return theme.color.primary end } end
  local tab = morf.signal("entrance.tab", 1)
  local shown = morf.signal("entrance.rows", false)
  morf.surface.width, morf.surface.height = 640, 320
  ui.Item { width = 640, height = 320, ui.Item { width = 640, height = 80, table.unpack(cards) },
    ui.Item { y = 100, width = 640, height = 64,
      kit.tabs { id = "sample", width = 600, height = 64, tab = tab,
        tabs = { { key = "a", name = "One", icon = "home" }, { key = "b", name = "Two", icon = "home" },
          { key = "c", name = "Three", icon = "home" }, { key = "d", name = "Four", icon = "home" } } } },
    ui.Loader { y = 180, width = 640, height = 120, active = function() return shown:get() end,
      source = function()
        local list = { width = 640, height = 120 }
        for i = 1, 3 do
          list[i] = ui.Rect { id = "row-" .. i, x = (i - 1) * 110, width = 100, height = 40, enter = kit.enter(i),
            color = function() return theme.color.primary end }
        end
        return ui.Item(list)
      end },
  }
  morf.ipc.bud = function()
    for _, card in ipairs(cards) do card.opacity = 0 end
    kit.bud(cards, true)
  end
  morf.ipc.tab = function(i) tab:set(i) end
  morf.ipc.rows = function() shown:set(true) end
  morf.ipc.tokens = function() return { spatial = theme.bounce.spatial.duration, stagger = theme.stagger } end
  morf.ipc.indicator = function()
    local node = nodes["sample-tab-indicator"]
    return { stretch = node ~= nil and node.stretch ~= nil and node.stretch ~= false, x = node and node.x }
  end
]]

local function load(style)
  test.load("../shell/init.lua", { source = HOST, size = { 640, 320 }, env = {
    EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_WALLPAPER = "",
    EVA_APPEARANCE = morf.env("XDG_CACHE_HOME") .. "/entrance-appearance.json",
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/entrance-settings.json",
  } })
  test.advance(600)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " entrances", function()
    test.it("buds a panel's contents in turn", function()
      load(style)
      local stagger = test.ipc("tokens").stagger
      test.ipc("bud")
      test.advance(stagger.delay + FRAME * 2)
      local first, second = test.get("card-1").opacity, test.get("card-3").opacity
      test.truthy(first > second, "they all came in together")
      test.advance(1500)
      for i = 1, 3 do test.near(test.get("card-" .. i).opacity, 1, 0.001) end
      test.eq(#test.logs("error"), 0)
    end)

    test.it("brings a list's rows in after one another", function()
      load(style)
      local stagger = test.ipc("tokens").stagger
      test.ipc("rows")
      test.advance(FRAME * 2)
      local early, late = test.get("row-1").opacity, test.get("row-3").opacity
      test.truthy(early > 0, "the first row did not start")
      test.truthy(late < early or stagger.step == 0, "the rows did not stagger")
      test.advance(1500)
      for i = 1, 3 do test.near(test.get("row-" .. i).opacity, 1, 0.001) end
      test.eq(#test.logs("error"), 0)
    end)
  end)
end

test.describe("material tabs", function()
  test.it("stretches its indicator between tabs and carries its speed through a change", function()
    load("material")
    local start = test.ipc("indicator")
    test.truthy(start.stretch, "the indicator does not stretch")
    test.ipc("tab", 4)
    test.advance(FRAME * 3)
    local going = test.ipc("indicator").x
    test.truthy(going > start.x, "the indicator did not leave")
    test.ipc("tab", 1)
    test.near(test.ipc("indicator").x, going, 0.5, "a change of mind jumped")
    test.advance(FRAME)
    test.truthy(test.ipc("indicator").x > going, "the speed was lost at the turn")
    test.advance(1000)
    test.near(test.ipc("indicator").x, start.x, 0.5)
    test.eq(#test.logs("error"), 0)
  end)
end)
