-- The workspace rail, a frame at a time: Material's accent travels as a blob
-- in the pills' own field, Tsugumori's marker slides hard with a tick behind it.
local test = morf.test
local FRAME = 16

local HOST = [[
  local ui = require("morf.ui")
  local nodes = {}
  for _, kind in ipairs { "Rect", "Item", "SdfShape" } do
    local make = ui[kind]
    ui[kind] = function(props)
      local node = make(props)
      if props.id then nodes[props.id] = node end
      return node
    end
  end
  require("init")
  morf.ipc.blob = function()
    local blob, head = nodes["rail-blob"], nodes["rail-head"]
    return { blend = blob.blend, operation = blob.operation,
      tracks = blob.track ~= nil, stretch = head.stretch ~= nil and head.stretch ~= false }
  end
  morf.ipc.pill = function(i)
    local color = nodes["rail-pill-" .. i].color
    return { color = tostring(color), primary = tostring(require("theme").color.primary) }
  end
  morf.ipc.fields = function() return require("theme").blend end
]]

local function load(style, size)
  test.load("../shell/init.lua", { source = HOST, size = size or { 1920, 1080 }, env = {
    EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_WALLPAPER = "" } })
  test.advance(600)
end

local function positions(id, axis, frames)
  local out = {}
  for i = 1, frames do
    test.advance(FRAME)
    out[i] = test.get(id)[axis]
  end
  return out
end

test.describe("material rail", function()
  test.it("the blob sits apart at rest and in its own field", function()
    load("material")
    local blob = test.ipc("blob")
    test.eq(blob.operation, "smooth_union")
    test.truthy(blob.tracks, "the blob does not track its head")
    test.truthy(blob.stretch, "the blob does not stretch")
    test.near(blob.blend, 0, 0.001, "at rest the blob would fuse with its neighbours")
    test.near(test.get("rail-head").y, test.get("rail-pill-1").y, 0.01)
    local lit, dim = test.ipc("pill", 1), test.ipc("pill", 5)
    test.eq(lit.color, lit.primary, "the active pill is not lit")
    test.truthy(dim.color ~= dim.primary, "an idle pill is lit")
    test.truthy(test.find("rail-pills"), "the pills have no field of their own")
    test.eq(#test.logs("warn"), 0)
  end)

  test.it("the blob flows along a spring with an animated seam and comes to rest", function()
    load("material")
    local from, to = test.get("rail-pill-1").y, test.get("rail-pill-5").y
    test.ipc("workspace", 5)
    local path = positions("rail-head", "y", 1)
    local left = test.ipc("pill", 1)
    test.truthy(left.color ~= left.primary, "the accent faded off the old pill instead of leaving it")
    positions("rail-head", "y", 39)
    test.truthy(path[1] > from and path[1] < to, "the blob jumped")
    path[#path + 1] = test.get("rail-head").y
    local widest = 0
    test.ipc("workspace", 1)
    for _ = 1, 12 do
      test.advance(FRAME)
      widest = math.max(widest, test.ipc("blob").blend)
    end
    test.truthy(widest > 4, "the seam never opened")
    test.near(path[#path], to, 2, "the blob did not reach the fifth pill")
    test.settle(2000)
    test.near(test.ipc("blob").blend, 0, 0.01, "the seam stayed open at rest")
    test.near(test.get("rail-head").y, from, 0.01)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("runs along the bottom edge on a phone", function()
    load("material", { 868, 1932 })
    local from = test.get("rail-pill-1").x
    test.near(test.get("rail-head").x, from, 0.01)
    test.ipc("workspace", 3)
    local path = positions("rail-head", "x", 30)
    test.truthy(path[1] > from, "the blob did not leave along the edge")
    test.near(path[#path], test.get("rail-pill-3").x, 2)
    test.eq(#test.logs("error"), 0)
  end)
end)

test.describe("tsugumori rail", function()
  test.it("the marker slides hard and a tick lands after it", function()
    load("tsugumori")
    local start = test.get("rail-selector").y
    test.near(test.get("rail-tick").y, start, 0.01)
    test.ipc("workspace", 6)
    test.advance(5 * FRAME)
    local marker, tick = test.get("rail-selector").y, test.get("rail-tick").y
    test.truthy(marker > start, "the marker did not move")
    test.truthy(tick < marker, "the tick did not trail the marker")
    local goal = test.get("rail-pill-6").y
    test.advance(10 * FRAME)
    test.near(test.get("rail-selector").y, goal, 0.5, "the marker's tween is not short")
    test.truthy(test.get("rail-tick").y < goal, "the tick landed with the marker")
    test.advance(300)
    test.near(test.get("rail-tick").y, goal, 0.5)
    test.falsy(test.find("rail-blob"), "tsugumori has no blob")
    test.eq(#test.logs("error"), 0)
  end)
end)
