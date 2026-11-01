-- A drawer's travel, sampled frame by frame: momentum through a reversal, a
-- release at the finger's speed, and a change of size while it moves.
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  local drawer = require("drawer")
  local edge = morf.env("TEST_EDGE")
  local size = morf.signal("test.size", 300)
  local content = ui.Item { id = "sample-content", anchors = { fill = true } }
  local d = drawer.new { name = "sample", edge = edge, content = content,
    width = 320, height = function() return size:get() end }
  ui.Item { width = 1280, height = 720, ui.Sdf { width = 1280, height = 720, d.shape }, d.panel }
  local axis = (edge == "left" or edge == "right") and "translate_x" or "translate_y"
  morf.ipc.open = d.set
  morf.ipc.at = function() return d.panel[axis] end
  morf.ipc.spring = function() return require("theme").springs.drawer end
  morf.ipc.stretch = function()
    local s = d.panel.stretch
    return { set = s ~= nil and s ~= false, token = require("theme").stretch }
  end
  morf.ipc.size = function(v) size:set(v) end
  morf.ipc.grab = function() return d.begin_drag() end
  morf.ipc.drag = function(delta) d.drag_by(delta) end
  morf.ipc.release = function(velocity, canceled) d.end_drag(velocity, canceled) end
  morf.ipc.interrupt = function() d.interrupt_drag() end
  morf.ipc.state = function()
    return { visible = d.panel.visible, manual = d.manual == true, open = d.open:get(),
      content = content.opacity, background = d.shape.opacity }
  end
]]
local FRAME = 16

local function load(style, edge)
  test.load("../shell/init.lua", { source = HOST, size = { 1280, 720 }, env = {
    EVA_STYLE = style, TEST_EDGE = edge or "top",
    EVA_APPEARANCE = morf.env("XDG_CACHE_HOME") .. "/drawer-motion-appearance.json",
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/drawer-motion-settings.json",
  } })
end

-- Positions, one a frame, from the frame after now.
local function sample(frames, into)
  local out = into or {}
  for _ = 1, frames do
    test.advance(FRAME)
    out[#out + 1] = test.ipc("at")
  end
  return out
end

-- Where a spring from `position` at `speed` px/s towards `target` is, a frame
-- at a time, stepped as the engine steps one: two semi-implicit steps a frame.
local function spring_path(spring, position, speed, target, frames)
  local damping = 2 * spring.ratio * math.sqrt(spring.stiffness)
  local step = FRAME / 2000
  local out = {}
  for frame = 1, frames do
    for _ = 1, 2 do
      speed = speed + (spring.stiffness * (target - position) - damping * speed) * step
      position = position + speed * step
    end
    out[frame] = position
  end
  return out
end

local SHELL = [[
  require("init")
  morf.ipc.seams = function()
    local out, count = {}, 0
    for _, d in ipairs(require("drawer").all) do
      count = count + 1
      out[d.name] = d.shape.blend_group
    end
    out.count = count
    return out
  end
]]

test.describe("drawer seams", function()
  local NEIGHBOURS = { "dashboard", "sidebar", "leftbar", "bottom", "session", "capture" }
  local APART = { "launcher", "polkit", "keyring", "authsteps", "headphones" }

  test.it("material's working panels melt together and dialogs stand apart", function()
    test.load("../shell/init.lua", { source = SHELL, size = { 1920, 1080 },
      env = { EVA_STYLE = "material", EVA_DRY_RUN = "1", EVA_WALLPAPER = "" } })
    local seams = test.ipc("seams")
    for _, name in ipairs(NEIGHBOURS) do test.eq(seams[name], seams.dashboard, name) end
    test.truthy(seams.dashboard ~= 0, "group 0 would melt into everything, the rail included")
    for _, name in ipairs(APART) do test.truthy(seams[name] ~= seams.dashboard, name .. " melted") end
  end)

  test.it("tsugumori keeps every panel's edge its own", function()
    test.load("../shell/init.lua", { source = SHELL, size = { 1920, 1080 },
      env = { EVA_STYLE = "tsugumori", EVA_DRY_RUN = "1", EVA_WALLPAPER = "" } })
    local seams, seen = test.ipc("seams"), {}
    seams.count = nil
    for name, group in pairs(seams) do
      test.falsy(seen[group], name .. " shares a seam")
      seen[group] = true
    end
  end)
end)

test.describe("drawer travel", function()
  for _, edge in ipairs { "top", "right", "bottom", "left" } do
    test.it("material " .. edge .. " keeps its momentum through a reversal", function()
      load("material", edge)
      local spring = test.ipc("spring")
      local home = test.ipc("at")
      test.ipc("open", true)
      local path = sample(5)
      local turn = #path
      test.ipc("open", false)
      test.near(test.ipc("at"), path[turn], 0.01, "a reversal moved the panel at once")
      sample(8, path)
      local seconds = FRAME / 1000
      local speed = (3 * path[turn] - 4 * path[turn - 1] + path[turn - 2]) / (2 * seconds)
      test.truthy(math.abs(speed) > 400, "the panel was not moving when it reversed")
      local kept = spring_path(spring, path[turn], speed, home, 8)
      local dropped = spring_path(spring, path[turn], 0, home, 8)
      test.truthy(math.abs(kept[3] - dropped[3]) > 10, "this reversal cannot tell the two apart")
      for i = 1, 8 do
        test.near(path[turn + i], kept[i], 3,
          ("frame %d after the reversal left the spring's path"):format(i))
      end
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("tsugumori keeps its momentum on its own stiffer spring", function()
    load("tsugumori")
    local spring = test.ipc("spring")
    test.truthy(spring.stiffness > 400, "tsugumori's drawer spring is not its own")
    local home = test.ipc("at")
    test.ipc("open", true)
    local path = sample(4)
    local turn = #path
    test.truthy(test.get("drawer-sample-curtain").visible, "the curtain did not cover the travel")
    test.ipc("open", false)
    -- It covers again before it withdraws, so the panel holds its course
    -- until the curtain has closed, and the pose carries on from where it was.
    test.near(test.ipc("at"), path[turn], 0.01, "a reversal moved the panel at once")
    test.truthy(test.get("drawer-sample-curtain").visible)
    test.advance(1200)
    test.near(test.ipc("at"), home, 0.01)
    test.falsy(test.ipc("state").visible)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("tsugumori reverses its withdrawal without stopping dead", function()
    load("tsugumori")
    local spring = test.ipc("spring")
    test.ipc("open", true) test.advance(1200)
    test.ipc("open", false)
    local path = { test.ipc("at") }
    while math.abs(path[#path]) < 40 and #path < 60 do sample(1, path) end
    sample(2, path)
    local turn = #path
    test.truthy(turn < 60, "the panel never withdrew")
    test.ipc("open", true)
    sample(6, path)
    local seconds = FRAME / 1000
    local speed = (3 * path[turn] - 4 * path[turn - 1] + path[turn - 2]) / (2 * seconds)
    test.truthy(math.abs(speed) > 200, "the panel was not moving when it reversed")
    local kept = spring_path(spring, path[turn], speed, 0, 6)
    for i = 1, 6 do test.near(path[turn + i], kept[i], 3) end
    test.advance(1000)
    test.near(test.ipc("at"), 0, 0.01)
    test.falsy(test.get("drawer-sample-curtain").visible)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("tsugumori hands a release to its spring and keeps its curtain out of a drag", function()
    load("tsugumori")
    test.ipc("open", true) test.advance(1200)
    test.truthy(test.ipc("grab"))
    test.ipc("drag", -100) test.advance(FRAME)
    test.near(test.ipc("at"), -100, 0.01)
    test.falsy(test.get("drawer-sample-curtain").visible, "a drag raised the curtain")
    test.ipc("release", -900, false)
    local path = sample(3)
    test.near((path[1] + 100) / (FRAME / 1000), -900, 40, "the release lost its speed")
    test.advance(1000)
    local state = test.ipc("state")
    test.falsy(state.open) test.falsy(state.visible) test.falsy(state.manual)
  end)

  test.it("material keeps the release velocity in the first frames after a drag", function()
    load("material")
    test.ipc("open", true) test.advance(900)
    test.truthy(test.ipc("grab"))
    test.ipc("drag", -100) test.advance(FRAME)
    test.near(test.ipc("at"), -100, 0.01)
    test.ipc("release", -900, false)
    local path = sample(4)
    local first = path[1] - -100
    test.near(first / (FRAME / 1000), -900, 40, "the release lost its speed")
    test.truthy(path[2] < path[1], "the spring did not carry the release on")
    test.falsy(test.ipc("state").open, "a fling shut did not shut")
    test.advance(1000)
    local state = test.ipc("state")
    test.falsy(state.visible, "a closed panel stayed visible")
    test.falsy(state.manual, "the drag never finished")
  end)

  test.it("material stays manual until it lands and a set interrupts it", function()
    load("material")
    test.ipc("open", true) test.advance(900)
    test.truthy(test.ipc("grab"))
    test.truthy(test.ipc("state").manual)
    test.ipc("drag", -40) test.advance(FRAME)
    test.ipc("release", 0, false)
    test.advance(FRAME)
    test.truthy(test.ipc("state").manual, "released, it is still landing")
    test.advance(1000)
    test.falsy(test.ipc("state").manual)
    test.near(test.ipc("at"), 0, 0.01)
    test.truthy(test.ipc("grab"))
    test.ipc("drag", -60) test.advance(FRAME)
    test.ipc("open", false)
    test.falsy(test.ipc("state").manual, "a set did not interrupt the drag")
    test.advance(1000)
    test.falsy(test.ipc("state").visible)
  end)

  test.it("material lands a canceled drag where it began", function()
    load("material")
    test.ipc("open", true) test.advance(900)
    test.truthy(test.ipc("grab"))
    test.ipc("drag", -280) test.advance(FRAME)
    test.ipc("release", 0, true)
    test.advance(1000)
    test.near(test.ipc("at"), 0, 0.01)
    test.truthy(test.ipc("state").open)
    test.near(test.ipc("state").content, 1, 0.001)
  end)

  test.it("material re-aims by itself when its size changes", function()
    load("material")
    local away = test.ipc("at")
    test.ipc("size", 500) test.advance(1000)
    local further = test.ipc("at")
    test.near(further - away, -200, 0.01, "a closed drawer did not tuck to its new size")
    test.ipc("open", true) test.advance(90)
    test.ipc("open", false) test.advance(FRAME)
    test.ipc("size", 200) test.advance(1000)
    test.near(test.ipc("at"), further + 300, 0.01, "a closing drawer aimed at its old size")
    test.falsy(test.ipc("state").visible)
  end)

  test.it("material stretches along its travel as a liquid, tsugumori not at all", function()
    load("material")
    local stretch = test.ipc("stretch")
    test.truthy(stretch.set, "a material drawer does not stretch")
    local drawer = stretch.token.drawer
    test.truthy(drawer.max <= 0.06, "a whole panel stretching this far reads as jelly")
    test.truthy(drawer.damping >= 1.7 * math.sqrt(drawer.stiffness), "a whole panel must not wobble")
    load("tsugumori")
    test.falsy(test.ipc("stretch").set, "tsugumori is crisp")
  end)

  test.it("material ties its contents and seam to who owns the axis", function()
    load("material")
    local shut = test.ipc("state")
    test.near(shut.content, 0, 0.001)
    test.near(shut.background, 0, 0.001)
    test.ipc("open", true) test.advance(48)
    local coming = test.ipc("state")
    test.truthy(coming.content > 0 and coming.content < 1, "the contents did not fade in")
    test.near(coming.background, coming.content, 0.001)
    test.advance(900)
    local open = test.ipc("state")
    test.near(open.content, 1, 0.001)
    test.near(open.background, 1, 0.001)
    test.truthy(test.ipc("grab"))
    test.near(test.ipc("state").content, 1, 0.001, "a held drawer faded")
    test.eq(#test.logs("warn"), 0)
  end)
end)
