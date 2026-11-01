-- The overview on the window stand-in: it runs the real shell, and everything
-- sent to the compositor is read back from the stand-in's list.
local test = morf.test

local function load(style, size, scene)
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = size or { 1920, 1080 },
    env = { EVA_STYLE = style or "material", EVA_FAKE_WINDOWS = scene or "1", EVA_DRY_RUN = "1" } })
  test.advance(200)
end

local function by_title(title)
  for _, w in ipairs(test.ipc("windows")) do if w.title == title then return w end end
end

test.it("a second monitor's workspaces, with sparse ids, join the strip", function()
  load("material", nil, '{"second_monitor":true,"clients":[{"class":"kitty","title":"one","workspace":1}]}')
  test.eq(test.ipc("overview", "open"), true)
  test.settle(3000)
  test.truthy(test.get("overview-desk-1").visible)
  test.truthy(test.get("overview-desk-11").visible, "the second monitor's workspace is missing")
  test.eq(#test.logs("warn"), 0)
end)

test.it("it opens and shuts, each card flying from its window to a slot", function()
  load()
  test.eq(test.ipc("overview", "open"), true)
  test.advance(16)
  local card = test.get("overview-card-1")
  test.settle(3000)
  card = test.get("overview-card-1")
  test.truthy(card.visible, "no card")
  test.truthy(card.y > 200, "the card did not land under the strip")
  test.truthy(test.get("overview-desk-1").visible, "no strip")
  test.eq(test.ipc("overview", "state"), true)
  test.key("Escape")
  test.settle(3000)
  test.eq(test.ipc("overview", "state"), false)
  test.falsy(test.find({ id = "overview", visible = true }), "it stayed on the screen")
end)
