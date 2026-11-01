-- A Hyprland change said the Lua way first and the classic way where that is not
-- taken: the one helper, and every place that says one going through it.
--
--     morf test --no-dbus tests/hypr_fallback_spec.lua
local test = morf.test
local HOST = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local hypr = require("lib.util.hypr")
  morf.ipc.took = function(reply) return hypr.took(reply) end
  morf.ipc.took_nothing = function() return hypr.took(nil) end
  morf.ipc.run = function(answer)
    local said, classic, taken = {}, 0, 0
    hypr.eval_or({ eval = function(chunk, done) said[#said + 1] = chunk done(answer ~= "none" and answer or nil) end },
      "hl.config({})", function() classic = classic + 1 end, function() taken = taken + 1 end)
    return { said = said, classic = classic, taken = taken }
  end
  morf.ipc.bare = function(answer)
    local classic = 0
    hypr.eval_or({ eval = function(_, done) done(answer) end }, "chunk", function() classic = classic + 1 end)
    return classic
  end
  morf.ipc.onehanded = function(answer)
    local lib = require("lib.compositor.hyprland")
    local said = { evals = {}, keywords = {} }
    lib.eval = function(chunk, done) said.evals[#said.evals + 1] = chunk done(answer) end
    lib.keyword = function(name, value) said.keywords[#said.keywords + 1] = name .. " " .. value end
    require("quick_hardware").onehanded().set(true)
    return said
  end
]]

local function load(env)
  env = env or {}
  env.EVA_DRY_RUN = env.EVA_DRY_RUN or "1"
  test.load("../shell/init.lua", { size = { 412, 915 }, source = HOST, env = env })
  test.advance(50)
end

test.it("only a plain ok counts as taken", function()
  load()
  test.truthy(test.ipc("took", "ok"))
  test.truthy(test.ipc("took", " ok\n"))
  test.falsy(test.ipc("took", "unknown request"))
  test.falsy(test.ipc("took", "ok, but"))
  test.falsy(test.ipc("took_nothing"))
end)

test.it("a Lua answer ends it, and the classic way is never said", function()
  load()
  local got = test.ipc("run", "ok")
  test.eq(got.said, { "hl.config({})" })
  test.eq(got.classic, 0)
  test.eq(got.taken, 1)
end)

test.it("anything else falls back, a silence too", function()
  load()
  for _, answer in ipairs { "unknown request", "none" } do
    local got = test.ipc("run", answer)
    test.eq(got.classic, 1, answer)
    test.eq(got.taken, 0, answer)
  end
end)

test.it("what comes after is optional", function()
  load()
  test.eq(test.ipc("bare", "ok"), 0)
  test.eq(test.ipc("bare", "no"), 1)
end)

test.it("the one-handed margin falls back to the keyword", function()
  load { EVA_DRY_RUN = "" }
  local said = test.ipc("onehanded", "unknown request")
  test.contains(said.evals[1], "hl.monitor")
  test.contains(said.keywords[1], "monitor ")
  test.contains(said.keywords[1], ",addreserved,")
end)

test.it("nobody else reads Hyprland's answer or writes the fallback", function()
  for _, name in ipairs { "shell/auto_rotate.lua", "shell/quick_hardware.lua", "shell/windows_model.lua",
    "lib/services/screen_filter.lua", "lib/shell/capture/init.lua", "lib/shell/window_dispatch.lua",
    "apps/zoom/model.lua" } do
    test.falsy(morf.fs.read(name):find("%s*ok%s*$", 1, true), name .. " reads the answer itself")
  end
end)
