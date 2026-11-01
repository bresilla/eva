-- How a press feels, sampled a frame at a time: Material's surfaces morph and
-- sink on the press spring and overshoot as they let go, its handles widen and
-- its thumbs stretch; Tsugumori's offset crisply and keep their square corners.
local test = morf.test
local FRAME = 16

local HOST = [[
  local ui = require("morf.ui")
  local nodes = {}
  for _, kind in ipairs { "Rect", "Item" } do
    local make = ui[kind]
    ui[kind] = function(props)
      local node = make(props)
      if props.id then nodes[props.id] = node end
      return node
    end
  end
  local widgets = require("kit").widgets
  local value = morf.signal("press.value", .5)
  morf.surface.width, morf.surface.height = 720, 360
  ui.Item { width = 720, height = 360,
    widgets.push { id = "button", x = 20, y = 20, width = 180, height = 48, label = "Apply" },
    widgets.pill { id = "pill", x = 220, y = 20, width = 180, height = 40, label = "Pill" },
    widgets.tile { id = "tile", x = 20, y = 90, width = 220, height = 72, label = "Wi-Fi", icon = "wifi" },
    widgets.chip_assist { id = "chip", x = 260, y = 90, width = 120, height = 32, label = "Chip" },
    widgets.row_activation { id = "row", x = 20, y = 180, width = 300, height = 56, label = "Row" },
    widgets.switch { id = "switch", x = 420, y = 20 },
    widgets.slider { id = "slider", x = 420, y = 90, width = 260, height = 52, bar_height = 44,
      value = function() return value:get() end, on_moved = function(v) value:set(v) end },
  }
  morf.ipc.pose = function(id)
    local node = nodes[id]
    local rounded, radius = pcall(function() return node.radius end)
    return { scale = node.scale, radius = rounded and radius or nil, scale_x = node.scale_x, x = node.x,
      translate_x = node.translate_x, translate_y = node.translate_y,
      stretch = node.stretch ~= nil and node.stretch ~= false }
  end
]]

local function load(style)
  test.load("../shell/init.lua", { source = HOST, size = { 720, 360 }, env = {
    EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_WALLPAPER = "",
    EVA_APPEARANCE = morf.env("XDG_CACHE_HOME") .. "/press-appearance.json",
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/press-settings.json",
  } })
  test.advance(300)
end

local function pose(id) return test.ipc("pose", id) end

-- One property of a node, a frame at a time.
local function trace(id, property, frames)
  local out = {}
  for i = 1, frames do
    test.advance(FRAME)
    out[i] = pose(id)[property]
  end
  return out
end

local function peak(values)
  local top = values[1]
  for _, value in ipairs(values) do top = math.max(top, value) end
  return top
end

local function centre(id)
  local node = test.get(id)
  return node.x + node.width / 2, node.y + node.height / 2
end

test.describe("material presses", function()
  for _, id in ipairs { "button", "pill", "tile", "chip", "row" } do
    test.it(id .. " sinks and tightens under the finger and overshoots on release", function()
      load("material")
      local plate = id .. "-plate"
      local rest = pose(plate)
      test.near(rest.scale, 1, 0.001)
      local x, y = centre(id)
      test.move(x, y)
      test.press(x, y)
      local going = trace(plate, "scale", 16)
      test.truthy(going[1] > 0.97, "the press landed at once, not on a spring")
      local held = pose(plate)
      test.near(held.scale, 0.97, 0.004, "the surface did not sink")
      test.truthy(math.abs(held.radius - rest.radius) > 1, "the corners did not morph")
      test.release(x, y)
      local back = trace(plate, "scale", 30)
      local top = peak(back)
      test.truthy(top > 1.0005, "the release did not overshoot")
      test.truthy(top < 1.012, "the release overshot like jelly: " .. top)
      test.near(back[#back], 1, 0.001)
      test.near(pose(plate).radius, rest.radius, 0.05)
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("the slider's handle widens under the finger and settles on a spring", function()
    load("material")
    test.near(pose("slider-handle").scale_x, 1, 0.001)
    local x, y = centre("slider-track")
    test.move(x, y)
    test.press(x, y)
    local going = trace("slider-handle", "scale_x", 16)
    test.truthy(going[1] < 1.8, "the handle jumped wide")
    test.near(going[#going], 1.8, 0.02, "the handle did not widen")
    test.release(x, y)
    local back = trace("slider-handle", "scale_x", 30)
    test.truthy(back[1] > 1, "the handle jumped back")
    test.near(back[#back], 1, 0.01)
  end)

  test.it("the switch's thumb stretches as it travels", function()
    load("material")
    local thumb = pose("switch-thumb")
    test.truthy(thumb.stretch, "the thumb has no stretch")
    test.click("switch")
    local path = trace("switch-thumb", "x", 24)
    test.truthy(path[1] > thumb.x and path[1] < thumb.x + 20, "the thumb did not travel")
    test.near(path[#path], thumb.x + 20, 0.05)
  end)
end)

test.describe("tsugumori presses", function()
  for _, id in ipairs { "button", "tile", "chip", "row" } do
    test.it(id .. " offsets crisply and keeps its square corners", function()
      load("tsugumori")
      local plate = id .. "-plate"
      local rest = pose(plate)
      test.near(rest.translate_x, 0, 0.001)
      test.near(rest.scale, 1, 0.001)
      local x, y = centre(id)
      test.move(x, y)
      test.press(x, y)
      local going = trace(plate, "translate_y", 12)
      local held = pose(plate)
      test.truthy(held.translate_y >= 1 and held.translate_y <= 3, "no short offset: " .. held.translate_y)
      test.near(held.translate_x, held.translate_y, 0.001)
      test.near(held.scale, 1, 0.001, "tsugumori does not squash")
      test.eq(held.radius, 0, "a press rounded a corner")
      test.truthy(going[1] > 0, "the offset took more than a frame to begin")
      test.release(x, y)
      test.advance(300)
      test.near(pose(plate).translate_y, 0, 0.01)
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("the switch's thumb travels on its own spring and does not stretch", function()
    load("tsugumori")
    local thumb = pose("switch-thumb")
    test.falsy(thumb.stretch, "tsugumori is crisp")
    test.click("switch")
    test.advance(FRAME)
    local moving = pose("switch-thumb").x
    test.truthy(moving > thumb.x and moving < thumb.x + 23, "the thumb jumped")
    test.advance(400)
    test.near(pose("switch-thumb").x, thumb.x + 23, 0.05)
  end)
end)
