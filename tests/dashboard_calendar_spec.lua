-- The dashboard's month is the kit's calendar, read only: the days of the months
-- beside it, the weekends, the day that is today, the wheel and the arrows, in
-- both themes, on a desk and a phone. A finger that starts on a day still pages
-- the dashboard.
--
--     morf test --no-dbus tests/dashboard_calendar_spec.lua
local test = morf.test

local PICKER = [[
  local ui = require("morf.ui")
  local kit = require("kit")
  local composites = require("themes.kit.composites")
  local calendar = require("themes.kit.composites.calendar")
  local changed = { glance = 0, picker = 0 }
  local glance_node, glance = composites.calendar { id = "glance", width = 280, month = "2026-11", read_only = true, spill = true,
    weekends = true, on_changed = function() changed.glance = changed.glance + 1 end }
  local picker_node, picker = composites.calendar { id = "picker", width = 280, month = "2026-11",
    on_changed = function() changed.picker = changed.picker + 1 end }
  local fitted_node = composites.calendar { id = "fitted", width = 280, month = "2026-11", height = 220 }
  kit.card { width = 1000, height = 500, ui.Item { x = 20, y = 20, glance_node }, ui.Item { x = 340, y = 20, picker_node },
    ui.Item { x = 660, y = 20, fitted_node } }
  morf.ipc.cells = function(first, spill)
    local month = calendar.month_cells(calendar.month_index(2026, 11), tonumber(first), spill == "spill")
    return month
  end
  morf.ipc.changed = function() return changed end
  morf.ipc.selected = function() return { glance = glance.selected(), picker = picker.selected() } end
]]

local SHELL = [[
  require("init")
  morf.ipc.tab = function() return require("dashboard_state").tab:get() end
  morf.ipc.offset = function() return require("dashboard_model").month_offset:get() end
  morf.ipc.today = function() return morf.time.format("%Y-%m-%d") end
]]

local function picker(style)
  test.load("../shell/init.lua", { size = { 1000, 500 }, env = { EVA_STYLE = style }, source = PICKER })
  test.settle(600)
end

local function shell(style, size, touch)
  test.stub_run("task", { code = 0, stdout = "[]" })
  local devices = morf.env("EVA_INPUT_DEVICES")
  test.load("../shell/init.lua", { size = size, source = SHELL, env = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_WALLPAPER = "",
    EVA_FONT_FILE = "", LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"),
    EVA_INPUT_DEVICES = devices and touch and devices .. "-touch" or devices } })
  test.settle(2000)
  test.ipc("dashboard", "open") test.settle(2400)
end

test.it("a month runs on into its neighbours, six full weeks", function()
  picker("material")
  local month = test.ipc("cells", "1", "spill")
  test.eq(#month.list, 42)
  test.eq(month.list[1].label, "26")
  test.truthy(month.list[1].outside)
  test.eq(month.list[7].label, "1")
  test.eq(month.list[7].date, "2026-11-01")
  test.falsy(month.list[7].outside)
  test.eq(month.list[37].label, "1")
  test.truthy(month.list[37].outside)
  test.eq(month.list[42].label, "6")
  test.eq(#month.blanks, 12)
end)

test.it("without spill the padding stays blank", function()
  picker("material")
  local month = test.ipc("cells", "1", "plain")
  test.eq(#month.list, 36)
  test.eq(month.list[1].label, "")
  test.falsy(month.list[1].outside)
  test.eq(#month.blanks, 6)
end)

test.it("the first weekday moves the padding, and weekends are the days'", function()
  picker("material")
  local sunday = test.ipc("cells", "7", "plain")
  test.eq(sunday.list[1].date, "2026-11-01")
  test.truthy(sunday.list[1].weekend, "a Sunday")
  test.falsy(sunday.list[2].weekend, "a Monday")
  test.truthy(sunday.list[7].weekend, "a Saturday")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": read only, a press selects nothing; a picker's still does", function()
    picker(style)
    test.click("glance-day-2026-11-11") test.settle(200)
    test.click("picker-day-2026-11-11") test.settle(200)
    test.eq(test.ipc("changed"), { glance = 0, picker = 1 })
    test.eq(test.ipc("selected"), { glance = "", picker = "2026-11-11" })
  end)

  test.it(style .. ": given a height it fits it, six weeks always", function()
    picker(style)
    test.eq(test.get("fitted").height, 220)
    test.truthy(test.get("fitted-day-2026-11-11").height <= 27)
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": the desk's card is the calendar, and the wheel and arrows turn it", function()
    shell(style, { 1920, 1080 })
    local today = test.ipc("today")
    local day = test.get("calendar-day-" .. today)
    test.truthy(day.visible, "today is not on the card")
    test.truthy(test.get(style == "material" and "calendar-title" or "calendar-title-text").visible)
    test.click("calendar-next") test.settle(600)
    test.eq(test.ipc("offset"), 1)
    test.click("calendar-previous") test.settle(600)
    test.eq(test.ipc("offset"), 0)
    test.wheel(0, 120, { x = day.x + day.width / 2, y = day.y + day.height / 2 }) test.settle(600)
    test.eq(test.ipc("offset"), 1, "the wheel over a day did not turn the month")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. ": on a phone a pan that starts on a day still pages the dashboard", function()
    shell(style, { 868, 1932 }, true)
    test.eq(test.ipc("tab"), 1)
    local day = test.get("calendar-day-" .. test.ipc("today"))
    local x, y = day.x + day.width / 2, day.y + day.height / 2
    test.touch("down", 0, x, y) test.advance(16)
    for i = 1, 14 do test.touch("move", 0, x - i * 24, y) test.advance(16) end
    test.touch("up", 0, x - 336, y) test.settle(1200)
    test.eq(test.ipc("tab"), 2, "the calendar took the pan")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("the card holds no calendar of its own, and the model no month of its own", function()
  local card = morf.fs.read("themes/layouts/views/dashboard_overview_cards.lua")
  test.falsy(card:find('"Sun"', 1, true), "the card still spells the week out")
  test.falsy(card:find("ui.Grid", 1, true), "the card still lays out days")
  test.truthy(card:find("composites", 1, true), "the card does not use the composite")
  test.falsy(morf.fs.read("shell/dashboard_model.lua"):find("morf.time.month", 1, true), "the model still builds a month")
end)
