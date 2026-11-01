-- The bar under a finger, on a phone, a tablet and a desk with a touchscreen:
-- a slide along a module turns it, a pull off the bar brings out what hangs
-- there, and a long press gives each module its menu.

local test = morf.test
local touch = require("touch_forms")

local SOURCE = [[
  local osd = require("osd")
  local level, adjusted = .5, {}
  osd.volume = function() return level, false end
  osd.brightness = function() return level end
  osd.adjust = function(kind, value) level = value adjusted[#adjusted + 1] = kind end
  local rail_went = {}
  local workspace = require("services").workspace
  local go = workspace.go
  workspace.go = function(id) rail_went[#rail_went + 1] = id go(id) end
  require("init")
  local bar = require("bar")
  morf.ipc.bar_state = function()
    local open = {}
    for _, d in ipairs(require("drawer").all) do open[d.name] = d.open:get() end
    return { level = level, adjusted = #adjusted, open = open, side = bar.side and bar.side() or "",
      haptics = require("haptics").last:get(), rail_went = rail_went, scrubbed = rail_went }
  end
  morf.ipc.bar_show = function(side)
    bar.set_on(true)
    if side ~= "" then bar.set_side(side) end
  end
]]

for _, form in ipairs(touch.FORMS) do
  for _, style in ipairs { "material", "tsugumori" } do
    local tag = style .. " " .. form.name
    test.it(tag .. ": a slide along the volume module turns it, a pull off the bar opens the panel", function()
      touch.load(form, style, SOURCE)
      test.ipc("bar_show", "top") test.settle(1200)
      test.ipc("bar", "add", "volume", "end") test.settle(900)
      local chip = test.get("bar-module-volume")
      test.truthy(chip, "the module is on the bar")
      local x, y = chip.x + chip.width / 2, chip.y + chip.height / 2
      touch.drag(x, y, 64, 0)
      local state = test.ipc("bar_state")
      test.truthy(state.adjusted > 0, "a slide turned it")
      test.truthy(state.level > .6, "up toward the right, got " .. tostring(state.level))
      test.eq(state.open.dashboard or state.open.sidebar, false)
      touch.drag(x, y, 0, 320)
      state = test.ipc("bar_state")
      test.truthy(state.open.dashboard or state.open.sidebar, "a pull down brought one out")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a long press on a module opens its menu", function()
      touch.load(form, style, SOURCE)
      test.ipc("bar_show", "top") test.settle(1200)
      test.ipc("bar", "add", "volume", "end") test.settle(900)
      local chip = test.get("bar-module-volume")
      local x, y = chip.x + chip.width / 2, chip.y + chip.height / 2
      test.touch("down", 0, x, y) test.advance(700) test.touch("up", 0, x, y) test.advance(300)
      test.truthy(test.find { text = "Sound settings", visible = true } or test.find { text = "SOUND SETTINGS", visible = true }, "the menu is out")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a finger along the workspaces scrubs through them", function()
      touch.load(form, style, SOURCE)
      test.ipc("bar_show", "top") test.settle(1200)
      test.ipc("bar", "add", "workspaces", "start") test.settle(900)
      local one, two = test.get("bar-workspace-1"), test.get("bar-workspace-2")
      local y = one.y + one.height / 2
      touch.drag(one.x + 4, y, two.x + two.width - one.x, 0)
      local went = 0
      for _, line in ipairs(test.logs("info")) do
        if tostring(line.message or line):find("eva: workspace", 1, true) then went = went + 1 end
      end
      test.truthy(went >= 1, "the finger went to another")
      test.eq(test.logs("error"), {})
    end)
  end
end

test.it("a finger along the rail scrubs through the workspaces", function()
  local form = touch.FORMS[3]
  touch.load(form, "material", SOURCE)
  local hit = test.get("rail-hit-2")
  local x, y = hit.x + hit.width / 2, hit.y + hit.height / 2
  touch.drag(x, y, 0, hit.height * 4)
  test.truthy(#test.ipc("bar_state").rail_went >= 2, "it went through more than one")
  test.eq(test.logs("error"), {})
end)
