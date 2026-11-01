-- The seam: the stand-in answers as the real Hyprland answered in
-- nix/tests/windows.py, refusals included; and the picture queue.
local test = morf.test

local HOST = [[
  require("windows_stand_in").install()
  local hypr = require("lib.compositor.hyprland")
  local shots = require("window_shots")
  local seen = {}
  morf.screencopy.capture_window = function(id, callback, options)
    seen[#seen + 1] = { id = id, gpu = options.gpu }
    callback({ source = "memory:" .. id })
  end
  morf.ipc.eval = function(chunk)
    local answer
    hypr.eval(chunk, function(reply) answer = reply end)
    return answer
  end
  morf.ipc.wire = function() return hypr.wire end
  morf.ipc.clients = function()
    local out = {}
    for _, c in ipairs(hypr.snapshot().clients) do out[#out + 1] = c end
    return out
  end
  morf.ipc.layout = function(id)
    local answer
    hypr.json("j/workspaces", function(rows)
      for _, row in ipairs(rows) do if row.id == tonumber(id) then answer = row.tiledLayout end end
    end)
    return answer
  end
  morf.ipc.shots = function()
    shots.refresh({ { address = "0xa", class = "c", title = "t", toplevel = "one" } })
    return { seen = seen, source = shots.source("0xa"), refused = shots.refused }
  end
  return require("morf.ui").Item { width = 10, height = 10 }
]]

local function load(env)
  local e = { EVA_FAKE_WINDOWS = "1" }
  for k, v in pairs(env or {}) do e[k] = v end
  test.load("../shell/init.lua", { source = HOST, size = { 1920, 1080 }, env = e })
  test.advance(50)
end

test.it("it refuses what Hyprland refused, in Hyprland's words", function()
  load()
  local a = test.ipc("clients")[1].address
  local w = ('"address:%s"'):format(a)
  test.contains(test.ipc("eval", ("hl.dispatch(hl.dsp.window.alter_zorder({ action = %q, window = %s }))"):format("top", w)),
    "'mode' is required")
  test.contains(test.ipc("eval", 'hl.dispatch(hl.dsp.layout("splitratio exact 0.6"))'), "as a delta")
  test.contains(test.ipc("eval", ('hl.dispatch(hl.dsp.window.set_prop({ prop = "alpha", value = "0.7", window = %s }))'):format(w)),
    "Invalid prop name")
  test.contains(test.ipc("eval", 'hl.dispatch(hl.dsp.workspace.rename({ id = 1, name = "x" }))'), "'workspace' is required")
  test.contains(test.ipc("eval", "hl.dispatch(hl.dsp.window.no_such_thing())"), "error")
  test.clear_logs()
end)

test.it("what it accepts changes its list, as the compositor's would", function()
  load()
  local c = test.ipc("clients")[1]
  local w = ('"address:%s"'):format(c.address)
  test.eq(test.ipc("eval", ('hl.dispatch(hl.dsp.window.float({ action = "on", window = %s }))'):format(w)), "ok")
  test.eq(test.ipc("eval", ("hl.dispatch(hl.dsp.window.resize({ x = 640, y = 400, window = %s }))"):format(w)), "ok")
  test.eq(test.ipc("eval", ("hl.dispatch(hl.dsp.window.move({ x = 100, y = 120, window = %s }))"):format(w)), "ok")
  local now
  for _, row in ipairs(test.ipc("clients")) do if row.address == c.address then now = row end end
  test.truthy(now.floating)
  test.eq({ now.x, now.y, now.width, now.height }, { 100.0, 120.0, 640.0, 400.0 })
  test.eq(test.ipc("eval", 'hl.workspace_rule({ workspace = "1", layout = "monocle" })'), "ok")
  test.eq(test.ipc("layout", "1"), "monocle")
  test.truthy(#test.ipc("wire") >= 4, "the wire was not recorded")
end)

test.it("the focus order follows the event, before the list is asked for again", function()
  test.load("../shell/init.lua", { source = [[
    require("windows_stand_in").install()
    local hypr = require("lib.compositor.hyprland")
    local windows = require("windows_model")
    morf.ipc.order = function(address)
      if address then hypr.emit("activewindowv2", address) end
      local out = {}
      for i, c in ipairs(windows.recent()) do out[i] = c.address end
      return out
    end
    return require("morf.ui").Item { width = 10, height = 10 }
  ]], size = { 1920, 1080 }, env = { EVA_FAKE_WINDOWS = "1" } })
  test.advance(50)
  local before = test.ipc("order")
  local last = before[#before]
  test.eq(test.ipc("order", last)[1], last, "the window just focused is not first")
  test.eq(test.ipc("order", before[2])[2], last, "the one before it is not second")
end)

test.it("pictures stay on the GPU, unless the renderer is a software one", function()
  load()
  local r = test.ipc("shots")
  test.eq(r.seen[1], { id = "one", gpu = true })
  test.eq(r.source, "memory:one")
  load { LIBGL_ALWAYS_SOFTWARE = "1" }
  test.eq(test.ipc("shots").seen[1], { id = "one", gpu = false })
end)
