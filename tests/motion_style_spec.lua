-- How things move, chosen on the Eva page: a style that changes the bounce and
-- reloads in place, and a switch under which everything lands at once.
local test = morf.test
local FRAME = 16

local function source(motion, reduce)
  return ([[
    local reloads = 0
    morf.reload = function() reloads = reloads + 1 end
    local config = require("config")
    config.set("appearance.motion", %q)
    config.set("appearance.reduce_motion", %s)
    local ui = require("morf.ui")
    local nodes = {}
    local text = ui.Text
    ui.Text = function(props)
      local node = text(props)
      if props.id then nodes[props.id] = node end
      return node
    end
    require("init")
    morf.ipc.motion_state = function()
      local dashboard = require("dashboard").drawer
      return { reloads = reloads, style = config.get("appearance.motion"),
        reduced = config.get("appearance.reduce_motion"),
        y = dashboard.panel.translate_y, open = dashboard.open:get(), visible = dashboard.panel.visible,
        manual = dashboard.manual == true,
        stretch = dashboard.panel.stretch ~= nil and dashboard.panel.stretch ~= false }
    end
    morf.ipc.drag_test = function(phase, value)
      local dashboard = require("dashboard").drawer
      if phase == "begin" then dashboard.begin_drag()
      elseif phase == "move" then dashboard.drag_by(value)
      else dashboard.end_drag(value, false) end
    end
    morf.ipc.set_motion = function(style) config.set("appearance.motion", style) end
    morf.ipc.set_reduce = function(on) config.set("appearance.reduce_motion", on) end
  ]]):format(motion, reduce and "true" or "false")
end

local function load(style, motion, reduce)
  test.load("../shell/init.lua", { source = source(motion or "balanced", reduce), size = { 1600, 1000 },
    env = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_WALLPAPER = "",
      EVA_APPEARANCE = morf.env("XDG_CACHE_HOME") .. "/motion-style-appearance.json",
      EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/motion-style-settings-" .. style .. ".json" } })
  test.advance(200)
end

local function state() return test.ipc("motion_state") end

local function eva_page()
  test.ipc("utilities", "open") test.settle(900)
  test.click("utilities-toggle-eva") test.advance(2500)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " motion style", function()
    test.it("bounces more the more playful it is", function()
      -- How far the dashboard swings past where it rests, opening.
      local function overshoot(motion)
        load(style, motion)
        test.ipc("dashboard", "open")
        local peak = 0
        for _ = 1, 60 do
          test.advance(FRAME)
          peak = math.max(peak, state().y)
        end
        return peak
      end
      local calm, balanced, playful = overshoot("calm"), overshoot("balanced"), overshoot("playful")
      test.truthy(calm < balanced, ("calm %.1f is not calmer than balanced %.1f"):format(calm, balanced))
      test.truthy(balanced < playful, ("playful %.1f is not livelier than balanced %.1f"):format(playful, balanced))
    end)

    test.it("offers the styles on the Eva page and reloads in place once", function()
      load(style)
      eva_page()
      for _, name in ipairs { "calm", "balanced", "playful" } do
        test.truthy(test.find { id = "settings-motion-" .. name, visible = true }, "no " .. name .. " choice")
      end
      test.eq(state().reloads, 0, "opening the page reloaded the shell")
      test.click("settings-motion-playful")
      test.advance(400)
      test.eq(state().style, "playful")
      test.eq(state().reloads, 1, "a new style did not reload in place")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("settles quick changes into one reload", function()
      load(style)
      test.ipc("set_motion", "calm")
      test.advance(FRAME)
      test.ipc("set_motion", "playful")
      test.advance(FRAME)
      test.ipc("set_reduce", true)
      test.advance(400)
      test.eq(state().reloads, 1)
    end)

    test.it("keeps what is open through a real reload, in place at once", function()
      load(style)
      test.ipc("dashboard", "open")
      test.advance(1500)
      test.truthy(state().open)
      test.ipc("set_motion", "playful")
      test.advance(400)
      test.truthy(test.reload { source = source("playful") }, "the reload failed")
      test.advance(FRAME)
      local after = state()
      test.truthy(after.open, "the reload closed the drawer")
      test.truthy(after.visible, "the reloaded drawer is not shown")
      test.near(after.y, 0, 0.5, "the reloaded drawer did not come back in place")
      test.eq(after.style, "playful")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("keeps what is open when the scale changes", function()
      load(style)
      test.ipc("dashboard", "open")
      test.advance(1500)
      test.ipc("scale", "0.25")
      test.advance(400)
      test.truthy(test.reload { source = source("balanced") }, "the reload failed")
      test.advance(FRAME)
      test.truthy(state().open, "a new scale closed the drawer")
      test.ipc("scale", "0")
      test.advance(400)
    end)

    test.it("keeps what is open for one reload only", function()
      load(style)
      test.ipc("dashboard", "open")
      test.advance(1500)
      test.ipc("set_motion", "playful")
      test.advance(400)
      test.truthy(test.reload { source = source("playful") })
      test.advance(FRAME)
      test.truthy(state().open)
      test.truthy(test.reload { source = source("playful") })
      test.advance(FRAME)
      test.falsy(state().open, "a held drawer came back on a later, unrelated reload")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("reloads in place when Reduce motion changes", function()
      load(style)
      eva_page()
      local node, page = test.get("utilities-toggle-reduce-motion"), test.get("settings-eva-scroll")
      test.wheel(0, node.y - page.y - 40, { x = page.x + page.width - 2, y = page.y + 30 })
      test.advance(300)
      test.click("utilities-toggle-reduce-motion")
      test.advance(400)
      test.truthy(state().reduced)
      test.eq(state().reloads, 1)
    end)

    test.it("lands everything at once under Reduce motion", function()
      load(style, "balanced", true)
      local shut = state()
      test.truthy(shut.y < 0, "the shut drawer is not tucked")
      test.ipc("dashboard", "open")
      test.advance(3 * FRAME)
      local open = state()
      test.near(open.y, 0, 0.001, "the drawer travelled")
      test.truthy(open.visible)
      test.falsy(open.stretch, "a drawer stretched under Reduce motion")
      test.ipc("close")
      test.advance(3 * FRAME)
      local closed = state()
      test.near(closed.y, shut.y, 0.001, "the drawer travelled back")
      test.falsy(closed.visible, "a closed panel stayed visible")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("lands a drag's release at once under Reduce motion", function()
      load(style, "balanced", true)
      test.ipc("drag_test", "begin")
      test.ipc("drag_test", "move", 300)
      test.ipc("drag_test", "end", 900)
      test.advance(3 * FRAME)
      local landed = state()
      test.falsy(landed.manual, "the release is still travelling")
      test.near(landed.y, 0, 0.001, "the release did not land open")
      test.ipc("close")
      test.advance(3 * FRAME)
      test.falsy(state().visible)
      test.eq(#test.logs("warn"), 0)
    end)
  end)
end
