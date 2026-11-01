-- What a page does under a finger, on a phone, a tablet and a desk with a
-- touchscreen, in both themes: boards arrange from a long press, the calendar
-- turns its months, a Settings detail goes back from its edge with the page
-- behind it peeking in, pictures zoom, text fields take a long press, and a pull
-- past the top of a page refreshes it.

local test = morf.test
local touch = require("touch_forms")

local SOURCE = [[
  local scroll = require("themes.kit.scroll")
  local make = scroll.make
  local views = {}
  scroll.make = function(widget, spec)
    local root, flick, state, ctl = make(widget, spec)
    if spec.id then views[spec.id] = { flick = flick, state = state } end
    return root, flick, state, ctl
  end
  require("init")
  local sidebar, utilities = require("sidebar"), require("utilities")
  local refreshes = 0
  morf.ipc.q_state = function()
    local open = {}
    for _, d in ipairs(require("drawer").all) do open[d.name] = d.open:get() end
    return { open = open, detail = utilities.detail:get(), editing = utilities.tiles.editing:get(),
      month = require("planner").month_offset:get(), haptic = require("haptics").last:get() }
  end
  morf.ipc.q_page = function(key)
    sidebar.select(key)
    sidebar.drawer.set(true)
  end
  morf.ipc.q_panel = function(name, key)
    local panel = require(name)
    local select = panel.select or panel.panel.select
    select(key)
    panel.drawer.set(true)
  end
  morf.ipc.q_detail = function(key) utilities.request(key) end
  morf.ipc.q_offset = function(id)
    local view = assert(views[id], id)
    return { offset = view.flick.content_y or 0,
      room = (view.state.content_height or 0) - (view.flick.layout_height or 0) }
  end
  morf.ipc.q_scroll = function(id, y) views[id].flick.content_y = tonumber(y) end
  morf.ipc.q_spy_refresh = function()
    local client = require("planner").client
    local refresh = client.refresh
    client.refresh = function(...) refreshes = refreshes + 1 return refresh(...) end
  end
  morf.ipc.q_refreshes = function() return refreshes end
  morf.ipc.q_active = function(key) return require("pages").active(key)() end
]]

local function open(key)
  test.ipc("q_page", key) test.advance(1000)
end

local function tiles_on_show()
  for _, id in ipairs { "wifi", "bluetooth", "dark", "nightlight", "dnd", "airplane" } do
    local node = test.find { id = "utilities-toggle-" .. id, visible = true }
    if node then return node, id end
  end
end

for _, form in ipairs(touch.FORMS) do
  for _, style in ipairs { "material", "tsugumori" } do
    local tag = style .. " " .. form.name

    test.it(tag .. ": a long press on a tile starts arranging the board", function()
      touch.load(form, style, SOURCE, { EVA_FAKE_HARDWARE = "1" })
      open("settings")
      local tile = tiles_on_show()
      test.truthy(tile, "a tile is on show")
      local x, y = tile.x + tile.width / 2, tile.y + tile.height / 2
      test.touch("down", 0, x, y) test.advance(700) test.touch("up", 0, x, y) test.advance(600)
      test.truthy(test.ipc("q_state").editing, "the board is being arranged")
      test.eq(test.ipc("q_state").haptic, "long")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": the calendar's month turns under a finger", function()
      touch.load(form, style, SOURCE)
      test.ipc("q_panel", form.sheet and "sidebar" or "leftbar", "calendar") test.advance(1100)
      local days = test.get("planner-months")
      local x, y = days.x + days.width * .7, days.y + days.height / 2
      local before = test.ipc("q_state").month
      touch.drag(x, y, -days.width * .4, 0, { hold = true })
      test.near(test.get("planner-months").x, days.x - days.width * .4, 3)
      touch.lift(x - days.width * .4, y)
      test.eq(test.ipc("q_state").month, before + 1, "the month")
      touch.drag(x, y, days.width * .4, 0)
      test.eq(test.ipc("q_state").month, before)
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a swipe in from a Settings detail's edge goes back with a peek", function()
      touch.load(form, style, SOURCE)
      open("settings")
      test.ipc("q_detail", "theme") test.advance(900)
      test.ne(test.ipc("q_state").detail, "")
      local box = test.get("settings-detail")
      local x, y = box.x + 6, box.y + box.height / 2
      local back_edge = test.get("settings-detail")
      touch.drag(x, y, box.width * .6, 0, { hold = true })
      test.truthy(test.get("settings-detail").x > back_edge.x + box.width * .4, "it follows the finger")
      test.truthy(test.get("utilities").visible, "the page behind peeks in")
      touch.lift(x + box.width * .6, y, 700)
      test.eq(test.ipc("q_state").detail, "", "it went back")
      test.truthy(test.ipc("q_state").open.sidebar, "the panel stays")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a short pull from the edge springs the detail back", function()
      touch.load(form, style, SOURCE)
      open("settings")
      test.ipc("q_detail", "theme") test.advance(900)
      local box = test.get("settings-detail")
      touch.drag(box.x + 6, box.y + box.height / 2, box.width * .2, 0, { slow = true })
      test.ne(test.ipc("q_state").detail, "", "it stayed")
      test.near(test.get("settings-detail").x, box.x, 1)
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a vertical scroll leaves a panel alone until the list is at its end", function()
      touch.load(form, style, SOURCE)
      open("settings")
      local list = test.ipc("q_offset", "settings-overview-scroll")
      if list.room <= 40 then return end
      test.ipc("q_scroll", "settings-overview-scroll", "20") test.advance(60)
      local box = test.get("drawer-sidebar")
      local x, y = box.x + box.width / 2, box.y + box.height * .6
      touch.drag(x, y, 0, -100)
      test.truthy(test.ipc("q_state").open.sidebar, "a scroll does not shut it")
      test.truthy(test.ipc("q_offset", "settings-overview-scroll").offset > 60, "it scrolled")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a pull past the top of the tasks page refreshes them", function()
      touch.load(form, style, SOURCE)
      test.ipc("q_panel", form.sheet and "sidebar" or "leftbar", "tasks") test.advance(1100)
      test.ipc("q_spy_refresh")
      local box = test.get("tasks-list")
      local x, y = box.x + box.width / 2, box.y + box.height * .5
      touch.drag(x, y, 0, 60, { slow = true })
      test.eq(test.ipc("q_refreshes"), 0, "a short pull does not")
      touch.drag(x, y, 0, 300, { hold = true })
      test.truthy(test.ipc("q_offset", "tasks-list").offset <= -64, "it reaches the refresh, got "
        .. tostring(test.ipc("q_offset", "tasks-list").offset))
      test.truthy(test.find { id = "tasks-list-pull", visible = true }, "the indicator comes down")
      touch.lift(x, y + 300, 200)
      test.eq(test.ipc("q_refreshes"), 1, "past it, it does")
      test.eq(test.ipc("q_state").haptic, "commit")
      test.truthy(test.ipc("q_offset", "tasks-list").offset < -30, "it holds while it refreshes")
      test.advance(1500)
      test.near(test.ipc("q_offset", "tasks-list").offset, 0, 1)
      test.eq(test.logs("error"), {})
    end)
  end
end
