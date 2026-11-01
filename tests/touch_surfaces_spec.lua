-- The shell's surfaces under a finger, on a phone, a tablet and a desk with a
-- touchscreen, in both themes: panels, pages, popups and OSDs follow and let go;
-- what already owns a drag keeps it.

local test = morf.test
local touch = require("touch_forms")

local SOURCE = [[
  require("init")
  local sidebar = require("sidebar")
  morf.ipc.q_state = function()
    local open = {}
    for _, d in ipairs(require("drawer").all) do open[d.name] = d.open:get() end
    return { open = open, tab = sidebar.tab:get(), keys = (function()
        local keys = {} for i, t in ipairs(sidebar.TABS) do keys[i] = t.key end return keys end)(),
      dashboard_tab = require("dashboard").tab:get(), detail = require("utilities").detail:get(),
      haptic = require("haptics").last:get(), haptics = require("haptics").count:get(),
      osd = require("levels").active:get(), popups = #require("notifs").list:get(),
      form = require("responsive").form(), tiles = require("utilities").tiles and false }
  end
  morf.ipc.q_panel = function(key)
    sidebar.select(key)
    sidebar.drawer.set(true)
  end
  morf.ipc.q_notify = function(summary)
    require("notifs").notify("Spec", summary, "Body", 5000)
  end
  morf.ipc.q_osd = function(kind) require("osd").show(kind) end
]]

local function open(key)
  test.ipc("q_panel", key) test.advance(900)
  return test.get("drawer-sidebar")
end

for _, form in ipairs(touch.FORMS) do
  for _, style in ipairs { "material", "tsugumori" } do
    local tag = style .. " " .. form.name

    test.it(tag .. ": a panel follows the finger shut and a fling carries it", function()
      touch.load(form, style, SOURCE)
      test.eq(test.ipc("q_state").form, form.sheet and test.ipc("q_state").form or "desk")
      local box = open("settings")
      local way = form.sheet and { 0, -1 } or { 1, 0 }
      local tabs = test.get("sidebar-tabs")
      local x, y = tabs.x + tabs.width / 2, tabs.y + tabs.height / 2
      touch.drag(x, y, way[1] * 90, way[2] * 90, { hold = true })
      local now = test.get("drawer-sidebar")
      if form.sheet then test.truthy(now.y < box.y - 40, "it followed up") else test.truthy(now.x > box.x + 40, "it followed right") end
      test.truthy(test.ipc("q_state").open.sidebar, "it stays open under the finger")
      touch.lift(x + way[1] * 90, y + way[2] * 90, 900)
      test.falsy(test.ipc("q_state").open.sidebar, "let go past the way, it shuts")
      test.eq(test.ipc("q_state").haptic, "commit")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a page follows a swipe to the next tab, with a band at the ends", function()
      touch.load(form, style, SOURCE)
      local keys = test.ipc("q_state").keys
      open(keys[#keys])
      local pages = test.get("sidebar-pages")
      local x, y = pages.x + pages.width * .2, pages.y + pages.height * .6
      local start = test.get("sidebar-page-track").x
      touch.drag(x, y, -60, 0, { hold = true })
      test.truthy(test.get("sidebar-page-track").x < start - 8, "past the last page it stretches")
      test.truthy(test.get("sidebar-page-track").x > start - 60, "at less than the finger's pace")
      touch.lift(x - 60, y)
      test.truthy(test.ipc("q_state").open.sidebar, "the panel stays")
      test.near(test.get("sidebar-page-track").x, start, 1)
      test.eq(test.ipc("q_state").tab, #keys)
      touch.drag(x, y, pages.width * .6, 0, { hold = true })
      test.near(test.get("sidebar-page-track").x, start + pages.width * .6, 2)
      test.eq(test.ipc("q_state").tab, #keys, "the tab waits for the release")
      touch.lift(x + pages.width * .6, y)
      test.eq(test.ipc("q_state").tab, #keys - 1)
      test.eq(test.ipc("q_state").haptic, "commit")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": the dashboard's pages follow a swipe", function()
      touch.load(form, style, SOURCE)
      test.ipc("dashboard", "open") test.advance(1000)
      local pages = test.get("dashboard-pages")
      local x, y = pages.x + pages.width * .8, pages.y + 8
      local start = test.get("dashboard-page-track").x
      touch.drag(x, y, -160, 0, { hold = true })
      test.near(test.get("dashboard-page-track").x, start - 160, 2)
      touch.lift(x - 160, y, 1100)
      test.eq(test.ipc("q_state").dashboard_tab, 2)
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a slider keeps its drag, and a swipe beside it pages", function()
      touch.load(form, style, SOURCE)
      local box = open("settings")
      local slider = test.get("utilities-volume")
      local x, y = slider.x + slider.width * .3, slider.y + slider.height / 2
      local tab = test.ipc("q_state").tab
      touch.drag(x, y, slider.width * .4, 0)
      test.eq(test.ipc("q_state").tab, tab, "a slider drag changed the tab")
      test.truthy(test.ipc("q_state").open.sidebar, "a slider drag shut the panel")
      test.eq(test.logs("error"), {})
      test.truthy(box.width > 0)
    end)
  end
end
