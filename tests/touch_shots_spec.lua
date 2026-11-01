-- Gestures caught in flight, for looking at: nothing here asserts. Off unless
-- EVA_GESTURE_SNAPSHOTS=1, with `--snapshots DIR` saying where they land.

local test = morf.test
local touch = require("touch_forms")

local SOURCE = [[
  require("init")
  local sidebar = require("sidebar")
  morf.ipc.q_page = function(key)
    sidebar.select(key)
    sidebar.drawer.set(true)
  end
  morf.ipc.q_detail = function(key) require("utilities").request(key) end
  morf.ipc.q_tasks = function()
    local panel = require("pages").panel_name("tasks") == "leftbar" and require("leftbar") or sidebar
    local select = panel.select or panel.panel.select
    select("tasks")
    panel.drawer.set(true)
  end
  morf.ipc.q_dismiss = function()
    local notifs = require("notifs")
    for _, entry in ipairs(notifs.list:get()) do notifs.dismiss(entry.id) end
  end
  morf.ipc.q_push = function(summary, body)
    return require("notifs").push { summary = summary, body = body, urgency = 1, timeout_ms = 60000, app = summary }
  end
]]

local function shot(name)
  local ok, why = test.snapshot(name .. ".png")
  if not ok then error("no snapshot: " .. tostring(why)) end
end

if morf.env("EVA_GESTURE_SNAPSHOTS") ~= "1" then
  test.skip("gestures in flight", "EVA_GESTURE_SNAPSHOTS=1 takes them")
  return
end

for _, form in ipairs(touch.FORMS) do
  for _, style in ipairs { "material", "tsugumori" } do
    local tag = style .. "-" .. form.name:gsub(" .*", "")
    test.it(tag, function()
      touch.load(form, style, SOURCE)
      test.ipc("q_page", "settings") test.advance(1000)
      local box = test.get("drawer-sidebar")
      local tabs = test.get("sidebar-tabs")
      local way = form.sheet and { 0, -1 } or { 1, 0 }
      local x, y = tabs.x + tabs.width / 2, tabs.y + tabs.height / 2
      touch.drag(x, y, way[1] * box.width * .3, way[2] * box.height * .3, { hold = true })
      shot(tag .. "-panel-pulled")
      touch.lift(x, y, 900)

      test.ipc("q_page", "settings") test.advance(1000)
      local pages = test.get("sidebar-pages")
      touch.drag(pages.x + pages.width * .1, pages.y + pages.height * .6, pages.width * .5, 0, { hold = true })
      shot(tag .. "-tab-following")
      touch.lift(pages.x, pages.y, 900)

      test.ipc("q_page", "settings") test.advance(1000)
      test.ipc("q_detail", "theme") test.advance(1000)
      local detail = test.get("settings-detail")
      touch.drag(detail.x + 6, detail.y + detail.height / 2, detail.width * .45, 0, { hold = true })
      shot(tag .. "-back-peek")
      touch.lift(detail.x, detail.y, 900)

      test.ipc("close") test.advance(900)
      test.ipc("q_push", "A message", "Swiped partly, it shows what is under it") test.advance(2400)
      local card = test.get("notification-1")
      touch.drag(card.x + card.width * .7, card.y + card.height / 2, -100, 0, { slow = true })
      shot(tag .. "-snooze-latched")
      test.advance(5400)
      test.ipc("q_dismiss")

      test.ipc("q_tasks") test.advance(1100)
      local list = test.get("tasks-list")
      touch.drag(list.x + list.width / 2, list.y + list.height * .5, 0, 300, { hold = true })
      shot(tag .. "-pull-to-refresh")
      touch.lift(list.x, list.y, 2400)
    end)
  end
end
