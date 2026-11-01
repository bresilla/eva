-- What the shell may cost, in the engine's own budgets. `morf check` runs each
-- scene in a process of its own with MORF_LIMITS set to what the scene measured
-- plus the margin, so a pass, a binding, a module or a built view that outgrows
-- that runs out of fuel here. The scene's nodes are counted the same way.
--
--     morf test --no-dbus tests/cost_spec.lua
--
-- MEASURED and NODES: the worst of both themes on a desk and a phone. MARGIN:
-- how far past them a scene may go.

local test = morf.test

local MARGIN = 1.25
local MEASURED = { frame = 1000000, handler = 151000, module = 1310000, delegate = 700000 }
local NODES = { tsugumori = { desk = 9002, phone = 10059 }, material = { desk = 6125, phone = 6814 } }

local FORMS = {
  desk = { size = "1920x1080" },
  phone = { size = "868x1932", devices = "tests/fixtures/input-devices-touch" },
}
local WALK = { "sidebar open notifications", "close", "leftbar open tasks", "close", "dashboard open", "close",
  "bottom open assistant", "close", "launcher open", "close", "utilities open", "settings panels", "close" }
-- Settings and Notifications in the left panel: the panels depend on each other.
local MOVED = [[{ "panels": { "right": [ "assistant" ], "left": [ "settings", "notifications", "tasks", "calendar" ],
  "bottom": [ "drop" ] } }]]

-- Runs a command for the spec, which has no loop of its own to wait on one.
local HOST = [[
  local answer
  morf.ipc.run = function(line)
    answer = nil
    local argv = morf.json.decode(line)
    for i, word in ipairs(argv) do if word == "@morf" then argv[i] = morf.executable end end
    morf.process.run(argv, { timeout_ms = 120000 }, function(result) answer = result end)
    return true
  end
  morf.ipc.answer = function() return answer end
]]

local function limits(scale)
  local out = {}
  for key, value in pairs(MEASURED) do out[#out + 1] = key .. "=" .. math.floor(value * scale) end
  return table.concat(out, ",")
end

--- `morf check` of the shell as `style` on `form`, with the budgets `caps`.
local function check(style, form, caps, ipcs, settings)
  local scratch = morf.env("XDG_CACHE_HOME")
  local argv = { "env", "MORF_LIMITS=" .. caps, "EVA_STYLE=" .. style, "EVA_DRY_RUN=1", "HOME=" .. scratch,
    "EVA_WALLPAPER=", "EVA_FONT_FILE=", "LULE_A=/nonexistent/lule" }
  if FORMS[form].devices then argv[#argv + 1] = "EVA_INPUT_DEVICES=" .. FORMS[form].devices end
  if settings then argv[#argv + 1] = "EVA_SETTINGS=" .. settings end
  for _, word in ipairs { "@morf", "check", "shell/init.lua", "--no-dbus", "--isolate",
    "--after", "3000", "--size", FORMS[form].size } do argv[#argv + 1] = word end
  for _, call in ipairs(ipcs or {}) do
    argv[#argv + 1] = "--ipc"
    argv[#argv + 1] = call
  end
  test.source(HOST)
  test.ipc("run", morf.json.encode(argv))
  local answer = test.wait(function() return test.ipc("answer") end, 120000, "morf check did not come back")
  return tostring(answer.stdout or "") .. tostring(answer.stderr or ""), answer.code
end

local function clean(text, code, what)
  test.falsy(text:find("exhausted", 1, true), what .. " ran out of fuel:\n" .. text:sub(-1200))
  test.eq(code, 0, what .. " did not check out:\n" .. text:sub(-1200))
end

test.it("a budget this small does run out, so the rest of this spec can fail", function()
  local text = check("material", "desk", "frame=2000,handler=2000", {})
  test.truthy(text:find("exhausted", 1, true), "nothing ran out of fuel:\n" .. text:sub(-800))
end)

for _, style in ipairs { "tsugumori", "material" } do
  for form in pairs(FORMS) do
    test.it(style .. " on a " .. form .. " comes up and walks its panels inside its budgets", function()
      local text, code = check(style, form, limits(MARGIN), WALK)
      clean(text, code, "the walk")
      local nodes = tonumber(text:match("surface primary.-(%d+) nodes"))
      test.truthy(nodes and nodes <= NODES[style][form] * MARGIN,
        ("%s nodes, past %d measured and the margin"):format(tostring(nodes), NODES[style][form]))
    end)
  end
  test.it(style .. " builds with the panels rearranged inside the same budgets", function()
    local file = morf.env("XDG_CACHE_HOME") .. "/moved-" .. style .. ".json"
    morf.fs.write(file, MOVED, { parents = true })
    local text, code = check(style, "desk", limits(MARGIN), { "utilities open" }, file)
    clean(text, code, "the rearranged shell")
  end)
end
