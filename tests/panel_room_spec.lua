-- The panels of a desk, together: the bottom panel and the dashboard keep
-- clear of the side panels, are pushed along by them, give up width between
-- them and square off their corners where they join; past what the screen
-- holds the panel open longest shuts.
local test = morf.test
local SOURCE = [[
  require("init")
  local room = require("panel_room")
  morf.ipc.open_set = function()
    local open = {}
    for _, d in ipairs(require("drawer").all) do if d.is_open() then open[d.name] = true end end
    return open
  end
  morf.ipc.capture_panel = function() require("capture").panel:set(true) end
  morf.ipc.place = function(opening, left, right, want, least)
    local x, width = room.place(tonumber(opening), tonumber(left), tonumber(right), tonumber(want), tonumber(least))
    return { x = x, width = width }
  end
]]
local loads = 0
local function load(style, w, h)
  test.stub_run("task", { code = 0, stdout = "[]" })
  loads = loads + 1
  test.load("../shell/init.lua", { size = { w or 1920, h or 1080 }, source = SOURCE, env = { EVA_STYLE = style,
    EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1", LULE_A = "/nonexistent/lule",
    HOME = morf.env("XDG_CACHE_HOME"), EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/room-" .. loads .. ".json" } })
  test.settle(1200)
end
local function box(id) local n = test.get(id) return n.x, n.x + n.width, n end
local function apart(a, b)
  local a1, a2 = box(a)
  local b1, b2 = box(b)
  test.truthy(a2 <= b1 + 1 or b2 <= a1 + 1, ("%s (%g..%g) and %s (%g..%g) overlap"):format(a, a1, a2, b, b1, b2))
end

test.it("a panel stands in the middle, is pushed clear, and gives up width only between two", function()
  load("material")
  local function place(...) return test.ipc("place", ...) end
  test.eq(place(1900, 0, 0, 840, 430), { x = 530, width = 840 })
  test.eq(place(1900, 450, 0, 840, 430), { x = 530, width = 840 }, "clears the left panel already")
  test.eq(place(1500, 450, 0, 840, 430), { x = 450, width = 840 }, "pushed along by the left panel")
  test.eq(place(1500, 0, 450, 840, 430), { x = 210, width = 840 }, "pushed along by the right panel")
  test.eq(place(1500, 450, 450, 840, 430), { x = 450, width = 600 }, "shares what is left between two")
  test.eq(place(1000, 450, 450, 840, 430), { x = 450, width = 430 }, "never under its least")
end)

local function high(id) local n = test.get(id) return n.y, n.y + n.height end
for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " the launcher stands between the side panels, whole", function()
    load(style, 1280, 720)
    test.ipc("sidebar", "open", "settings") test.settle(1000)
    test.ipc("launcher", "open") test.settle(1200)
    test.truthy(test.ipc("open_set").sidebar, "it had room beside the panel")
    apart("drawer-launcher", "drawer-sidebar")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " with both side panels open the launcher shuts the older", function()
    load(style, 1280, 720)
    test.ipc("leftbar", "open", "tasks") test.settle(800)
    test.ipc("sidebar", "open", "settings") test.settle(800)
    test.ipc("launcher", "open") test.settle(1200)
    local open = test.ipc("open_set")
    test.truthy(open.launcher and open.sidebar, "what opened last stays")
    test.falsy(open.leftbar, "the older panel stayed open")
    apart("drawer-launcher", "drawer-sidebar")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " popups wait while the launcher stands where they would", function()
    load(style, 1280, 720)
    test.ipc("sidebar", "open", "settings") test.settle(1000)
    test.ipc("notify", "Backup finished", "All files are safe") test.settle(600)
    test.truthy(test.ipc("open_set").notifications, "the popup never came")
    test.ipc("launcher", "open") test.settle(1000)
    test.falsy(test.ipc("open_set").notifications, "the popup stayed over the launcher")
    test.ipc("launcher", "close") test.settle(1000)
    test.truthy(test.ipc("open_set").notifications, "the popup did not come back")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " on a wide desk popups stand beside the launcher", function()
    load(style, 1920, 1080)
    test.ipc("notify", "Backup finished", "All files are safe") test.settle(600)
    test.ipc("launcher", "open") test.settle(1000)
    test.truthy(test.ipc("open_set").notifications, "the popup left for no reason")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " the capture panel shuts a side panel it would stand in", function()
    load(style, 1280, 720)
    test.ipc("sidebar", "open", "settings") test.settle(1000)
    test.ipc("capture_panel") test.settle(800)
    test.falsy(test.ipc("open_set").sidebar, "the two overlap")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " on a wide desk the capture panel leaves the side panels", function()
    load(style, 1920, 1080)
    test.ipc("sidebar", "open", "settings") test.settle(1000)
    test.ipc("capture_panel") test.settle(800)
    test.truthy(test.ipc("open_set").sidebar, "it had room")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " the bottom panel stands under the dashboard, shorter", function()
    load(style, 1920, 1080)
    test.ipc("dashboard", "open") test.settle(1000)
    local _, top_end = high("drawer-dashboard")
    test.ipc("bottom", "open", "drop") test.settle(1500)
    test.truthy(test.ipc("open_set").dashboard, "there was room for both")
    local bottom_start = high("drawer-bottom")
    test.truthy(bottom_start >= top_end, ("the panels overlap: %g over %g"):format(bottom_start, top_end))
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " where the desk holds only one of them, what opened last stays", function()
    load(style, 1280, 720)
    test.ipc("dashboard", "open") test.settle(1000)
    test.ipc("bottom", "open", "assistant") test.settle(1500)
    local open = test.ipc("open_set")
    test.truthy(open.bottom, "the newer panel shut")
    test.falsy(open.dashboard, "the two overlap")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " a dashboard grown tall shuts the older bottom panel", function()
    load(style, 1920, 1080)
    test.ipc("bottom", "open", "drop") test.settle(1000)
    test.ipc("dashboard", "open", "performance") test.settle(1500)
    local open = test.ipc("open_set")
    test.truthy(open.dashboard, "the newer panel shut")
    test.falsy(open.bottom, "the two overlap")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " three panels open at once stand apart on a wide desk", function()
    load(style)
    test.ipc("sidebar", "open", "settings") test.settle(1000)
    test.ipc("bottom", "open", "assistant") test.settle(1000)
    test.ipc("leftbar", "open", "tasks") test.settle(1500)
    local open = test.ipc("open_set")
    test.truthy(open.sidebar and open.leftbar and open.bottom, "nothing needed to shut")
    apart("drawer-bottom", "drawer-leftbar")
    apart("drawer-bottom", "drawer-sidebar")
    test.eq(test.get("drawer-bottom").width, 840, "it had room to keep its width")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " between two panels on a smaller desk it eases its width and joins them", function()
    load(style, 1600, 900)
    test.ipc("bottom", "open", "assistant") test.settle(1200)
    test.eq(test.get("drawer-bottom").width, 840)
    test.truthy(test.get("drawer-bottom-background"))
    test.ipc("leftbar", "open", "tasks") test.settle(1500)
    test.ipc("sidebar", "open", "settings") test.settle(1500)
    local width = test.get("drawer-bottom").width
    test.near(width, 680, 1, "it did not ease into the gap")
    apart("drawer-bottom", "drawer-leftbar")
    apart("drawer-bottom", "drawer-sidebar")
    local _, left_end = box("drawer-leftbar")
    local bottom_start, bottom_end = box("drawer-bottom")
    local right_start = box("drawer-sidebar")
    test.near(bottom_start, left_end, 1, "it did not meet the left panel")
    test.near(bottom_end, right_start, 1, "it did not meet the right panel")
    test.advance(800)
    test.truthy(test.get("assistant-page").width <= width, "the page was left at its old width")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " past what the screen holds the panel open longest shuts", function()
    load(style, 1280, 800)
    test.ipc("sidebar", "open", "settings") test.settle(900)
    test.ipc("leftbar", "open", "tasks") test.settle(900)
    test.ipc("bottom", "open", "assistant") test.settle(1200)
    local open = test.ipc("open_set")
    test.falsy(open.sidebar, "the oldest stayed")
    test.truthy(open.leftbar and open.bottom, "the newer two should stay")
    apart("drawer-bottom", "drawer-leftbar")
    test.eq(#test.logs("error"), 0)
  end)

  test.it(style .. " the dashboard keeps clear of a side panel too", function()
    load(style, 1600, 900)
    test.ipc("leftbar", "open", "tasks") test.settle(900)
    test.ipc("dashboard", "open") test.settle(1400)
    apart("drawer-dashboard", "drawer-leftbar")
    test.ipc("sidebar", "open", "settings") test.settle(1400)
    apart("drawer-dashboard", "drawer-leftbar")
    apart("drawer-dashboard", "drawer-sidebar")
  end)
end
