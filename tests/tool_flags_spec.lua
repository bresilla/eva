-- The flags that make a tool run with no window. morf hands a flag to
-- `morf.options`, never to `morf.operands`, and a tool that reads the wrong one
-- quietly opens its window instead.
--
--     morf test --no-dbus tests/tool_flags_spec.lua

local test = morf.test

local ENV ={ EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule", EVA_DRY_RUN = "1" }

test.it("eva-clipboard opens its window with no flag", function()
  test.load("../apps/clipboard/app.lua", { env = ENV })
  test.settle(200)
  test.truthy(test.find { id = "clipboard-root" })
end)

test.it("eva-clipboard --watch keeps the history with no window", function()
  test.load("../apps/clipboard/app.lua", { args = { "--watch" }, env = ENV })
  test.settle(200)
  test.falsy(test.find { id = "clipboard-root" })
  test.ipc("text", "still kept")
  test.eq(test.ipc("state").items[1].text, "still kept")
end)

test.it("eva-colorpick opens its window with no flag", function()
  test.stub_run("grim", { code = 0 })
  test.load("../apps/colorpick/app.lua", { env = ENV })
  test.settle(200)
  test.truthy(test.find { id = "colorpick-page" })
end)

test.it("eva-colorpick --pick is the frozen screen alone", function()
  test.stub_run("grim", { code = 0 })
  test.load("../apps/colorpick/app.lua", { args = { "--pick" }, env = ENV })
  test.settle(200)
  test.falsy(test.find { id = "colorpick-page" })
end)

test.it("eva-displays --auto applies a profile with no window", function()
  test.stub_run("hyprctl", { code = 1 })
  local out = morf.env("XDG_STATE_HOME") .. "/displays-auto-" .. tostring(morf.time.now_ms())
  local env = { EVA_JOB_OUT = out }
  for key, value in pairs(ENV) do env[key] = value end
  test.load("../apps/common/job/app.lua", { args = { "displays", "--auto" }, env = env })
  test.settle(200)
  test.falsy(test.find { id = "displays-canvas" })
  test.eq((morf.fs.read(out) or ""):sub(1, 2), "0\n", "the flag did not reach the job")
end)
