-- Lists under a finger, on a phone and a desk with a touchscreen, in both
-- themes: a pull past an end is a rubber band that springs back, a pull
-- past the top refreshes where the page has that, and a scroll leaves the
-- panel alone until the list is at its end.

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
  morf.ipc.list_state = function(id)
    local view = views[id] if not view then local k = {} for n in pairs(views) do k[#k + 1] = n end error(table.concat(k, " ")) end
    return { offset = view.flick.content_y or 0, content = view.state.content_height,
      room = (view.state.content_height or 0) - (view.flick.layout_height or 0),
      sidebar = require("sidebar").drawer.open:get() }
  end
  morf.ipc.list_end = function(id)
    local view = views[id]
    view.flick.content_y = math.max(0, (view.state.content_height or 0) - (view.flick.layout_height or 0))
  end
  morf.ipc.show_view = function(panel, key)
    local target = require(panel)
    target.select(key)
    target.drawer.set(true)
  end
]]

for _, form in ipairs(touch.FORMS) do
  for _, style in ipairs { "material", "tsugumori" } do
    local tag = style .. " " .. form.name
    test.it(tag .. ": a pull past the top is a rubber band that springs back", function()
      touch.load(form, style, SOURCE)
      test.ipc("show_view", "sidebar", "settings") test.advance(900)
      local box = test.get("drawer-sidebar")
      local x, y = box.x + box.width / 2, box.y + box.height * .5
      touch.drag(x, y, 0, 240, { hold = true })
      local past = test.ipc("list_state", "settings-overview-scroll").offset
      test.truthy(past < -8, "it follows the finger, got " .. tostring(past))
      test.truthy(past > -120, "at less than the finger's pace, got " .. tostring(past))
      touch.lift(x, y + 240)
      test.near(test.ipc("list_state", "settings-overview-scroll").offset, 0, 1)
      test.truthy(test.ipc("list_state", "settings-overview-scroll").sidebar, "the panel stays")
      test.eq(test.logs("error"), {})
    end)

    test.it(tag .. ": a pull past the bottom stretches a side panel's list and shuts a top sheet", function()
      touch.load(form, style, SOURCE)
      test.ipc("show_view", "sidebar", "settings") test.advance(900)
      local box = test.get("drawer-sidebar")
      local x, y = box.x + box.width / 2, box.y + box.height * .7
      local room = test.ipc("list_state", "settings-overview-scroll").room
      test.ipc("list_end", "settings-overview-scroll") test.advance(60)
      touch.drag(x, y, 0, -200, { hold = true })
      if form.sheet then
        test.near(test.ipc("list_state", "settings-overview-scroll").offset, math.max(0, room), 2, "the list stays put")
        touch.lift(x, y - 200)
        test.falsy(test.ipc("list_state", "settings-overview-scroll").sidebar, "the sheet shuts")
      else
        local past = test.ipc("list_state", "settings-overview-scroll").offset
        test.truthy(past > math.max(0, room) + 8, "it stretches past its end, got " .. tostring(past))
        touch.lift(x, y - 200)
        test.near(test.ipc("list_state", "settings-overview-scroll").offset, math.max(0, room), 1)
        test.truthy(test.ipc("list_state", "settings-overview-scroll").sidebar, "the panel stays")
      end
      test.eq(test.logs("error"), {})
    end)
  end
end
