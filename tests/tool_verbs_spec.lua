-- The shell's verbs the tools of apps/ stand on: keep awake with a time on it,
-- and the focus seam.
--
--     morf test --no-dbus tests/tool_verbs_spec.lua

local test = morf.test

local function shell()
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = { 1280, 800 }, env = { EVA_DRY_RUN = "1", EVA_STYLE = "material",
    LULE_A = "/nonexistent/lule", HYPRLAND_INSTANCE_SIGNATURE = false, EVA_FONT_FILE = "" }, source = [[
    require("services").here = function() return true end
    require("services").weather = function() return { available = false } end
    require("services").media = nil
    require("init")
  ]] })
  test.settle(600)
end

test.it("keeps awake until told otherwise", function()
  shell()
  test.falsy(test.ipc("awake", "state").on)
  test.truthy(test.ipc("awake", "on").on)
  test.eq(test.ipc("awake", "state")["until"], 0)
  test.falsy(test.ipc("awake", "toggle").on)
end)

test.it("lets go by itself after the time given", function()
  shell()
  local state = test.ipc("awake", "on", "1")
  test.truthy(state.on)
  test.truthy(state["until"] > 0)
  test.advance(59000)
  test.truthy(test.ipc("awake", "state").on)
  test.advance(2000)
  test.falsy(test.ipc("awake", "state").on)
  test.eq(test.ipc("awake", "state")["until"], 0)
end)

test.it("turning it off forgets the time", function()
  shell()
  test.ipc("awake", "on", "1")
  test.falsy(test.ipc("awake", "off").on)
  test.ipc("awake", "on")
  test.advance(61000)
  test.truthy(test.ipc("awake", "state").on)
end)

test.it("refuses what it does not know", function()
  shell()
  test.falsy(pcall(test.ipc, "awake", "sideways"))
  test.falsy(pcall(test.ipc, "focus", "sideways"))
end)

test.it("focus is do not disturb", function()
  shell()
  test.falsy(test.ipc("focus", "state"))
  test.truthy(test.ipc("focus", "on"))
  test.falsy(test.ipc("focus", "toggle"))
end)
