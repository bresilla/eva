-- The default keys: each calls a verb the shell has, in names Hyprland has, and
-- eva-keys shows the ones the compositor does not have bound.
local test = morf.test

local HOST = [[
  require("init")
  local keys = require("keybinds")
  morf.ipc.bound = function()
    local bound, gestures = {}, {}
    local hl = { dsp = { exec_cmd = function(command) return command end } }
    function hl.bind(chord, command, opts) bound[#bound + 1] = { chord = chord, command = command, opts = opts } end
    function hl.gesture(spec) gestures[#gestures + 1] = spec.fingers .. spec.direction end
    function hl.dispatch() end
    keys.apply(hl, "/bin/morf")
    return { bound = bound, gestures = gestures }
  end
]]

test.it("every key calls a verb the shell answers", function()
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = HOST, size = { 1920, 1080 }, env = { EVA_DRY_RUN = "1" } })
  test.advance(100)
  local verbs = {}
  for _, verb in ipairs(test.ipc_verbs()) do verbs[verb] = true end
  local all = test.ipc("bound")
  test.truthy(#all.bound > 20, "too few keys")
  local seen = {}
  for _, bind in ipairs(all.bound) do
    local verb = bind.command:match("^/bin/morf ipc call (%S+)")
    test.truthy(verbs[verb], bind.chord .. " calls `" .. tostring(verb) .. "`, which is no verb")
    test.truthy(bind.opts.description ~= "", bind.chord .. " has no description")
    local key = bind.chord .. (bind.opts.release and " up" or "")
    test.falsy(seen[key], bind.chord .. " is bound twice")
    seen[key] = true
  end
  test.eq(all.gestures, { "4up" })
end)

test.it("the session binds them only without a configuration of its own", function()
  local nix = morf.fs.read("nix/nixos/compositor.nix")
  test.contains(nix, 'config.programs.eva.hyprland.binds == "always" then "true" else "not own_config"')
  test.contains(nix, 'local own_config = file ~= nil')
end)

test.it("eva-keys lists what is not bound, and leaves out what is", function()
  test.load("../shell/init.lua", { source = [[
    local model = require("apps.keys.model")
    morf.ipc.rows = function(live)
      local binds = live == "yes" and { { modmask = 64, key = "Tab", description = "Overview" } } or {}
      return model.merge(binds)
    end
    return require("morf.ui").Item { width = 10, height = 10 }
  ]], size = { 400, 400 } })
  local groups = {}
  for _, row in ipairs(test.ipc("rows", "yes")) do
    groups[row.group] = (groups[row.group] or 0) + 1
    test.truthy(not (row.group == "Not bound" and row.keys == "SUPER + Tab"), "a bound key listed as not bound")
    if row.group == "Not bound" and row.keys == "SUPER + W" then
      test.contains(row.what, "morf ipc call window_menu toggle")
    end
  end
  test.truthy((groups["Not bound"] or 0) > 10)
  test.eq(groups.Compositor, 1)
  local plain = 0
  for _, row in ipairs(test.ipc("rows", "no")) do if row.group == "Windows" then plain = plain + 1 end end
  test.truthy(plain > 10, "with nothing to read the default keys are not shown")
end)
