-- What comes and goes under a finger, on a phone, a tablet and a desk with a
-- touchscreen, in both themes: popups swipe away, latch open on their snooze and
-- expand under two fingers, OSDs swipe away, and a meter keeps its own drag.

local test = morf.test
local touch = require("touch_forms")

local SOURCE = [[
  local notifs
  require("init")
  notifs = require("notifs")
  local levels, osd = require("levels"), require("osd")
  morf.ipc.q_push = function(summary, body)
    return notifs.push { summary = summary, body = body, urgency = 1, timeout_ms = 60000, app = summary }
  end
  morf.ipc.q_state = function()
    local ids, snoozed = {}, #notifs.snoozed:get()
    for i, entry in ipairs(notifs.list:get()) do ids[i] = entry.id end
    return { ids = ids, snoozed = snoozed, shown = levels.shown:get(), active = levels.active:get(),
      volume = osd.volume(), tools = notifs.tools:get(), haptic = require("haptics").last:get(),
      open = ids[1] ~= nil and notifs.expanded(ids[1]) or false }
  end
  morf.ipc.q_pop = levels.pop
  morf.ipc.q_spot = function(kind) return { edge = levels.spot(kind).edge } end
]]

local function card()
  test.ipc("q_push", "Swipe me", "Some long body text that wraps past a line for sure and then some more") test.advance(2400)
  local node = test.get("notification-1")
  return node.x + node.width / 2, node.y + node.height / 2, node
end

local function pinch(x, y, from, to)
  test.touch("down", 0, x - from, y) test.touch("down", 1, x + from, y) test.advance(16)
  for i = 1, 8 do
    local at = from + (to - from) * i / 8
    test.touch("move", 0, x - at, y) test.touch("move", 1, x + at, y) test.advance(16)
  end
  test.touch("up", 0, x - to, y) test.touch("up", 1, x + to, y) test.advance(500)
end

for _, form in ipairs(touch.FORMS) do
  for _, style in ipairs { "material", "tsugumori" } do
    local tag = style .. " " .. form.name

    test.it(tag .. ": a popup follows a swipe and goes, and a short pull springs back", function()
      touch.load(form, style, SOURCE)
      local x, y, node = card()
      local start = node.x
      touch.drag(x, y, 40, 0, { hold = true })
      test.near(test.get("notification-1").x, start + 40, 2)
      touch.lift(x + 40, y, 700)
      test.near(test.get("notification-1").x, start, 2)
      test.eq(#test.ipc("q_state").ids, 1)
      touch.drag(x, y, 160, 0)
      test.eq(#test.ipc("q_state").ids, 0, "past its distance it goes")
      test.eq(test.ipc("q_state").haptic, "commit")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a partial swipe latches a popup open on its snooze", function()
      touch.load(form, style, SOURCE)
      local x, y, node = card()
      local start = node.x
      touch.drag(x, y, -100, 0, { slow = true })
      test.truthy(test.get("notification-1").x < start - 50, "it stays uncovered")
      test.truthy(test.find { id = "notification-reveal-1", visible = true }, "the snooze shows")
      test.eq(#test.ipc("q_state").ids, 1)
      test.click("notification-snooze-1") test.advance(800)
      test.eq(test.ipc("q_state").snoozed, 1, "it snoozed")
      test.eq(#test.ipc("q_state").ids, 0)
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a long press opens a popup's tools, two fingers spread it", function()
      touch.load(form, style, SOURCE)
      local x, y = card()
      pinch(x, y, 40, 120)
      test.truthy(test.ipc("q_state").open, "spread, it opens")
      pinch(x, y, 120, 40)
      test.falsy(test.ipc("q_state").open, "closed, it shuts")
      test.touch("down", 0, x, y) test.advance(700) test.touch("up", 0, x, y) test.advance(300)
      test.truthy(test.ipc("q_state").tools, "the tools are out")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": an OSD swipes away toward its edge, and a meter keeps a drag along it", function()
      touch.load(form, style, SOURCE)
      test.ipc("q_pop", "brightness") test.advance(700)
      test.truthy(test.ipc("q_state").active, "it is out")
      local spot = test.ipc("q_spot", "brightness")
      local way = ({ left = { -1, 0 }, right = { 1, 0 }, top = { 0, -1 }, bottom = { 0, 1 } })[spot.edge or "right"]
      local bud = test.get("levels-swell")
      local x, y = bud.x + bud.width / 2, bud.y + bud.height / 2
      touch.drag(x, y, way[1] * 110, way[2] * 110, { hold = true })
      local moved = test.get("levels-swell")
      test.truthy(math.abs(moved.x - bud.x) + math.abs(moved.y - bud.y) > 40, "it follows the finger")
      touch.lift(x + way[1] * 110, y + way[2] * 110, 500)
      test.falsy(test.ipc("q_state").active, "let go past its distance, it goes")
      test.eq(test.ipc("q_state").haptic, "commit")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a status pill swipes away along its edge too", function()
      touch.load(form, style, SOURCE)
      test.ipc("q_pop", "caps") test.advance(700)
      local bud = test.get("levels-swell")
      local x, y = bud.x + bud.width / 2, bud.y + bud.height / 2
      touch.drag(x, y, 120, 0)
      test.falsy(test.ipc("q_state").active, "it went")
      test.eq(test.logs("error"), {})
    end)
  end
end
