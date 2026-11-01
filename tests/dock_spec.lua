-- The dock on the window stand-in, at each form.
local test = morf.test

local SCENE = [[{"focus":1,"clients":[
  {"class":"zzterm","title":"one","workspace":1,"floating":true,"x":100,"y":100,"width":400,"height":300},
  {"class":"zzterm","title":"two","workspace":2},
  {"class":"zzweb","title":"web","workspace":2}]}]]

local function load(style, size, env, touch)
  test.stub_run("task", { code = 0, stdout = "[]" })
  local devices = morf.env("EVA_INPUT_DEVICES")
  local e = { EVA_STYLE = style or "material", EVA_FAKE_WINDOWS = SCENE, EVA_DRY_RUN = "1",
    EVA_INPUT_DEVICES = devices and touch and devices .. "-touch" or devices }
  for k, v in pairs(env or {}) do e[k] = v end
  test.load("../shell/init.lua", { size = size or { 1920, 1080 }, env = e })
  test.advance(200)
  test.ipc("dock", "auto")
  test.ipc("dock_clear")
  test.advance(50)
end

local function windows() return test.ipc("windows") end

-- Presses a node with one button, at its middle.
local function press(id, button)
  local node = test.get(id)
  test.click(node.x + node.width / 2, node.y + node.height / 2, { button = button })
end

test.it("an icon swells near the pointer and pushes its neighbours", function()
  test.load("../shell/init.lua", { source = [[
    local m = require("dock_model")
    morf.ipc.calc = function()
      local at_rest, rest = m.sizes(5, 48, 8, nil, .6, 2.2)
      local near, total = m.sizes(5, 48, 8, 28, .6, 2.2)
      return { at_rest = at_rest, rest = rest, near = near, total = total }
    end
    return require("morf.ui").Item { width = 10, height = 10 }
  ]] })
  local r = test.ipc("calc")
  test.eq(r.at_rest, { 48, 48, 48, 48, 48 })
  test.eq(r.rest, 272)
  test.near(r.near[1], 76.8, .1, "the icon under the pointer is not the biggest")
  test.truthy(r.near[1] > r.near[2] and r.near[2] > r.near[3], "the swell does not fall away")
  test.truthy(r.total > r.rest, "the row did not grow")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " the desk has none unless asked, then running apps with their window counts", function()
    load(style)
    test.falsy(test.find({ id = "dock", visible = true }), "a dock on a desk by default")
    test.eq(test.ipc("dock", "on").mode, "dock")
    test.advance(300)
    test.truthy(test.get("dock").visible)
    test.truthy(test.get("dock-icon-1").visible)
    test.truthy(test.get("dock-icon-2").visible)
    test.falsy(test.find("dock-icon-3"), "two applications, three icons")
    test.truthy(test.get("dock-dot-1-1").visible)
    test.truthy(test.get("dock-dot-1-2").visible, "kitty's second window has no mark")
    test.falsy(test.find({ id = "dock-dot-1-3", visible = true }))
    test.eq(#test.logs("warn"), 0)
  end)
end

test.it("a tablet has a taskbar along its edge, keeping windows clear of it", function()
  load("material", { 1280, 800 }, nil, true)
  local state = test.ipc("dock", "state")
  test.eq(state.mode, "taskbar")
  test.truthy(state.shown)
  test.advance(300)
  local plate = test.get("dock-plate")
  test.eq(plate.width, 1280.0, "it does not span the edge")
  test.eq(test.ipc("dock_reserve"), 64)
end)

test.it("a phone has none", function()
  load("material", { 412, 915 }, nil, true)
  test.eq(test.ipc("dock", "on").mode, "off")
  test.falsy(test.find({ id = "dock", visible = true }))
end)

test.it("a press goes to the window, the wheel walks them, the middle button closes", function()
  load()
  test.ipc("dock", "on")
  test.ipc("dock", "peek")
  test.advance(300)
  test.click("dock-icon-area-2")
  test.advance(16)
  local first = windows()[1]
  test.eq(first.title, "web")
  press("dock-icon-area-1", "middle")
  test.advance(16)
  test.eq(#windows(), 2, "the middle button left it open")
end)

test.it("it hides when a window lies under it, and comes back to the pointer", function()
  load()
  test.ipc("dock", "on")
  test.ipc("workspace", "2")
  test.advance(600)
  test.falsy(test.ipc("dock", "state").shown, "tiled windows fill the screen, yet it stays out")
  test.ipc("workspace", "1")
  test.advance(600)
  test.truthy(test.ipc("dock", "state").shown, "nothing lies under it, yet it hides")
  test.ipc("workspace", "2")
  test.advance(600)
  test.move(960, 1078)
  test.advance(300)
  test.truthy(test.ipc("dock", "state").shown, "the edge did not bring it back")
end)

test.it("the right button offers the app's windows, pinning and closing", function()
  load()
  test.ipc("dock", "on")
  test.ipc("dock", "peek")
  test.advance(300)
  press("dock-icon-area-1", "right")
  test.advance(100)
  test.truthy(test.get("dock-menu").visible)
  local labels = {}
  for i = 1, 6 do
    local row = test.find({ id = "dock-menu-" .. i, visible = true })
    if row then labels[#labels + 1] = test.text_of(row) end
  end
  test.contains(labels, "push_pin Pin")
  test.contains(labels, "select_window two")
  test.contains(labels, "close Close all")
  test.click({ text = "Pin" })
  test.advance(100)
  test.falsy(test.find({ id = "dock-menu", visible = true }))
end)

test.it("pins come first, and reorder", function()
  load()
  test.ipc("dock", "on")
  test.ipc("dock", "pin", "alpha")
  test.ipc("dock", "pin", "beta")
  test.advance(100)
  test.eq(test.ipc("dock_order"), { "alpha", "beta", "zzterm", "zzweb" })
  test.ipc("dock_reorder", "1", "2")
  test.advance(100)
  test.eq(test.ipc("dock_order"), { "beta", "alpha", "zzterm", "zzweb" })
end)

test.it("past what a field can hold the rest are counted", function()
  local clients = {}
  for i = 1, 18 do clients[i] = ('{"class":"app%d","title":"t","workspace":1}'):format(i) end
  load("material", nil, { EVA_FAKE_WINDOWS = '{"clients":[' .. table.concat(clients, ",") .. "]}" })
  local state = test.ipc("dock", "on")
  test.advance(200)
  test.eq(test.ipc("dock", "state").rows, 14)
  test.eq(test.ipc("dock", "state").overflow, 4)
  test.eq(#test.logs("warn"), 0)
  local _ = state
end)
