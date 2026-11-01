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
  require("init")
  local bar = require("bar")
  morf.ipc.bar_state = function()
    local open = {}
    for _, d in ipairs(require("drawer").all) do open[d.name] = d.open:get() end
    return { level = level, adjusted = #adjusted, open = open, side = bar.side and bar.side() or "",
      menu = require("kit") and nil, haptics = require("haptics").last:get() }
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
  end
end
