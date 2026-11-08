-- A dialog in the middle of the screen (the window switcher) comes and goes in
-- place in both themes: it is drawn while it leaves, a reversal goes on from
-- the pose it had, Reduce motion lands it at once, and at rest nothing moves.
local test = morf.test
local FRAME = 16

local SCENE = [[{"focus":1,"clients":[
  {"class":"kitty","title":"one","workspace":1},
  {"class":"firefox","title":"web","workspace":1},
  {"class":"code","title":"edit","workspace":2}]}]]

local serial = 0
local function load(style, values)
  serial = serial + 1
  local appearance = morf.env("XDG_CACHE_HOME") .. "/appear-" .. serial .. ".json"
  morf.fs.write(appearance, morf.json.encode(values or {}))
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1920, 1080 }, env = { EVA_FAKE_WINDOWS = SCENE, EVA_DRY_RUN = "1",
    EVA_STYLE = style, EVA_APPEARANCE = appearance,
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/appear-settings-" .. serial .. ".json" } })
  test.advance(200)
end
local function plate() return test.get("window-switcher") end
local function shown()
  test.ipc("switcher", "next")
  test.advance(300)
  test.truthy(test.ipc("switcher", "state").shown, "the switcher never showed")
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " a dialog in place", function()
    test.it("is drawn while it leaves, and then not at all", function()
      load(style)
      shown()
      test.settle(1500)
      test.near(plate().opacity, 1, 0.001)
      test.ipc("switcher", "cancel")
      test.advance(FRAME)
      test.truthy(plate().visible, "it vanished at once")
      local leaving = plate().opacity
      test.truthy(leaving > 0 and leaving < 1, "it did not fade on the way out")
      test.advance(1000)
      test.falsy(plate().visible, "it stayed on screen after leaving")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("turns back from where it stood", function()
      load(style)
      test.ipc("switcher", "next")
      for _ = 1, 40 do
        if test.ipc("switcher", "state").shown then break end
        test.advance(FRAME)
      end
      test.advance(FRAME)
      local coming = plate().opacity
      test.truthy(coming > 0 and coming < 1, "it was not coming in")
      test.ipc("switcher", "cancel")
      test.advance(FRAME)
      local going = plate().opacity
      test.truthy(going > 0 and math.abs(going - coming) < 0.4, "the reversal jumped from " .. coming .. " to " .. going)
      test.eq(#test.logs("error"), 0)
    end)

    test.it("lands at once under Reduce motion", function()
      load(style, { reduce_motion = true })
      shown()
      test.near(plate().opacity, 1, 0.001, "it travelled")
      test.ipc("switcher", "cancel")
      test.advance(2 * FRAME)
      test.falsy(plate().visible, "it lingered")
    end)

    test.it("holds still once it has arrived", function()
      load(style)
      shown()
      test.settle(3000)
      test.truthy(test.settle(2000) <= 2 * FRAME, "something still moves at rest")
    end)
  end)
end
