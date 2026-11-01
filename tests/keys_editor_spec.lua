-- The keybind editor: a chord pressed on a row, what it collides with, the plan
-- sent to Hyprland, and going back to the default. hyprctl and the compositor
-- are stand-ins here; nix/tests/windows.py presses the same chords on a real one.
--
--     morf test --no-dbus tests/keys_editor_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")

local HOST = [[
  local model = require("model")
  morf.ipc.rows_of = function() return model.rows:get() end
  morf.ipc.offer = function(id, chord) return model.offer(id, chord) end
  morf.ipc.overrides = function() return require("keys_model").overrides() end
  morf.ipc.cancel = function() model.cancel() return true end
  morf.ipc.sent = function()
    local out = {}
    for _, line in ipairs(require("lib.services.host_fake").last_hyprland.sent) do out[#out + 1] = line end
    return out
  end
  require("app")
]]

local function env(name)
  local settings = morf.env("XDG_CACHE_HOME") .. "/keys-editor-" .. name .. ".json"
  morf.fs.remove(settings)
  return { EVA_SETTINGS = settings, EVA_FAKE_SYSTEM = "1", LULE_A = "/nonexistent/lule" }
end

local function tool(name, size)
  test.stub_run("hyprctl", { code = 0, stdout = morf.fs.read(ROOT .. "tests/fixtures/binds.json") })
  test.load("../apps/keys/app.lua", { source = HOST, env = env(name), size = size })
  test.settle(300)
end

local function pure(body)
  test.load("../shell/init.lua", { source = [[
    local rows, keys = require("key_rows"), require("keys_model")
    morf.ipc.run = function() ]] .. body .. [[ end
    return require("morf.ui").Item { width = 10, height = 10 }
  ]], size = { 400, 400 }, env = { EVA_DRY_RUN = "1" } })
  return test.ipc("run")
end

test.it("a press names its chord as Hyprland binds it", function()
  local out = pure([[
    return { rows.recorded("q", "q", "super"), rows.recorded("Tab", "", "super+shift"),
      rows.recorded("Super_L", "", "super") or "none", rows.recorded("!", "!", "super+shift"),
      rows.recorded(",", ",", "ctrl+super"), rows.recorded("F5", "", ""), rows.recorded(" ", " ", "alt") }
  ]])
  test.eq(out, { "SUPER + Q", "SUPER + SHIFT + Tab", "none", "SUPER + SHIFT + 1", "SUPER + CTRL + comma", "F5", "ALT + space" })
end)

test.it("a chord is the same chord however it is spelled", function()
  local out = pure([[
    return { rows.normal("SUPER + SHIFT + q") == rows.normal("shift+SUPER+Q"),
      rows.normal("CTRL + a") == rows.normal("CONTROL + A"), rows.normal("SUPER + Q") == rows.normal("ALT + Q") }
  ]])
  test.eq(out, { true, true, false })
end)

test.it("plain letters are refused, a modified key is not", function()
  local out = pure([[ return { rows.refused("A") ~= nil, rows.refused("Return") ~= nil, rows.refused("F5") == nil,
    rows.refused("SUPER + A") == nil, rows.refused("SUPER") ~= nil } ]])
  test.eq(out, { true, true, true, true, true })
end)

test.it("a key of eva's goes back to its verb under the new chord", function()
  local plan = pure([[ return keys.plan({ ["verb:overview toggle"] = "SUPER + SHIFT + O" }, {}, {}, "lua") ]])
  test.contains(plan[1].eval, 'hl.unbind("SUPER + Tab")')
  test.contains(plan[1].eval, 'hl.bind("SUPER + SHIFT + O", hl.dsp.exec_cmd("morf ipc call overview toggle")')
  test.contains(plan[1].eval, 'description = "Show every workspace and window"')
end)

test.it("any other key is moved by its registry reference, every spelling let go", function()
  local plan = pure([[
    local binds = { { modmask = 72, key = "W", dispatcher = "__lua", arg = "9", locked = true, submap = "" } }
    return keys.plan({ ["bind:ALT + SUPER + W"] = "SUPER + E" }, {}, binds, "lua")
  ]])
  test.contains(plan[1].eval, 'hl.unbind("SUPER + ALT + W")')
  test.contains(plan[1].eval, 'hl.unbind("ALT + SUPER + W")')
  test.contains(plan[1].eval, 'hl.bind("SUPER + E", registry[9], { locked = true })')
end)

test.it("two chords can swap: every old one lets go before a new one binds", function()
  local plan = pure([[
    local binds = { { modmask = 64, key = "A", dispatcher = "__lua", arg = "1", submap = "" },
      { modmask = 64, key = "B", dispatcher = "__lua", arg = "2", submap = "" } }
    return keys.plan({ ["bind:SUPER + A"] = "SUPER + B", ["bind:SUPER + B"] = "SUPER + A" }, {}, binds, "lua")
  ]])
  local chunk = plan[1].eval
  test.truthy(chunk:find('hl.unbind("SUPER + B")', 1, true) < chunk:find('hl.bind("SUPER + B"', 1, true), chunk)
  test.truthy(chunk:find('hl.unbind("SUPER + A")', 1, true) < chunk:find('hl.bind("SUPER + B"', 1, true), chunk)
end)

test.it("an empty chord only lets go, and a classic Hyprland takes keywords", function()
  local plan = pure([[ return keys.plan({ ["verb:kill_mode"] = "" }, {}, {}, "lua") ]])
  test.contains(plan[1].eval, 'hl.unbind("SUPER + X")')
  test.falsy(plan[1].eval:find("hl.bind", 1, true))
  local conf = pure([[ return keys.plan({ ["verb:kill_mode"] = "SUPER + K" }, {}, {}, "hyprlang") ]])
  test.eq(conf[1], { keyword = "unbind", value = "SUPER,X" })
  test.eq(conf[2], { keyword = "bind", value = "SUPER,K,exec,morf ipc call kill_mode" })
end)

test.it("a plan refuses what a settings file should not be able to send", function()
  local out = pure([[
    local plan, why = keys.plan({ ['verb:kill_mode'] = 'SUPER + K") os.execute("x' }, {}, {}, "lua")
    local none = keys.plan({ ["verb:no such"] = "SUPER + K" }, {}, {}, "lua")
    return { plan == nil, why, none == nil }
  ]])
  test.eq(out, { true, "bad chord", true })
end)

test.it("recording holds the compositor's keys back and lets them go", function()
  local steps = pure([[ return { keys.record_steps(true, "lua")[1].eval, keys.record_steps(false, "lua")[1].eval } ]])
  test.contains(steps[1], 'hl.define_submap("eva-keys-record"')
  test.contains(steps[1], 'hl.timer(')
  test.contains(steps[2], 'hl.dsp.submap("reset")')
end)

test.it("eva's rows carry their verb, and a moved one shows it is", function()
  local out = pure([[
    local plain = rows.merge({ { modmask = 64, key = "Tab", description = "Show every workspace and window", submap = "" },
      { modmask = 64, key = "Q", dispatcher = "__lua", arg = "5", submap = "" },
      { modmask = 64, key = "mouse:272", dispatcher = "__lua", arg = "7", mouse = true, submap = "" },
      { modmask = 0, key = "escape", dispatcher = "__lua", arg = "8", submap = "eva-keys-record" } }, {}, "Print")
    local moved = rows.merge({ { modmask = 65, key = "O", description = "Show every workspace and window", submap = "" } },
      { ["verb:overview toggle"] = "SUPER + SHIFT + O" }, "Print")
    local function pick(list, keys) for _, row in ipairs(list) do if row.keys == keys then return row end end end
    return { pick(plain, "SUPER + Tab").id, pick(plain, "SUPER + Q").id, pick(plain, "SUPER + Q").what,
      pick(plain, "SUPER + mouse:272").editable, pick(plain, "escape") == nil,
      pick(moved, "SUPER + SHIFT + O").custom, pick(moved, "SUPER + SHIFT + O").default }
  ]])
  test.eq(out, { "verb:overview toggle", "bind:SUPER + Q", "A key of your Hyprland configuration", false, true, true, "SUPER + Tab" })
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": a row listens, a free chord is taken at once, and it can go back", function()
    tool("free-" .. style)
    test.ipc("search", "close the window") test.settle(100)
    test.click("keys-row-1-press") test.settle(100)
    test.contains(test.ipc("state").recording, "bind:")
    test.eq(test.get({ id = "keys-row-1-keys" }).text, "Press the keys")
    test.truthy(test.find { id = "keys-notice", visible = true })
    local sent = table.concat(test.ipc("sent"), "\n")
    test.contains(sent, "hl.define_submap")
    test.key("Super_L", "super")
    test.eq(test.ipc("state").recording ~= "", true, "a modifier alone is not a chord")
    test.key("y", "super") test.settle(100)
    test.eq(test.ipc("state").recording, "")
    test.contains(table.concat(test.ipc("sent"), "\n"), 'hl.dsp.submap("reset")')
    local kept = test.ipc("overrides")
    test.eq(kept["bind:SUPER + SHIFT + Q"], "SUPER + Y")
    test.ipc("reset", "bind:SUPER + SHIFT + Q") test.settle(100)
    test.eq(next(test.ipc("overrides")), nil)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("Escape gives up, leaving the row as it was", function()
  tool("escape")
  test.ipc("search", "close the window") test.settle(100)
  test.click("keys-row-1-press") test.settle(100)
  test.key("Escape") test.settle(100)
  test.eq(test.ipc("state").recording, "")
  test.eq(next(test.ipc("overrides")), nil)
  test.contains(table.concat(test.ipc("sent"), "\n"), 'hl.dsp.submap("reset")')
end)

test.it("a taken chord waits, says who has it, and Use it moves it over", function()
  tool("clash")
  test.ipc("search", "close the window") test.settle(100)
  test.click("keys-row-1-press") test.settle(100)
  test.key("Return", "super") test.settle(100)
  local state = test.ipc("state")
  test.contains(state.pending, "SUPER + Return already does: exec kitty")
  test.eq(next(test.ipc("overrides")), nil, "nothing was changed yet")
  test.truthy(test.find { id = "keys-confirm", visible = true })
  test.click("keys-confirm") test.settle(100)
  local kept = test.ipc("overrides")
  test.eq(kept["bind:SUPER + SHIFT + Q"], "SUPER + Return")
  test.eq(kept["bind:SUPER + Return"], "")
end)

test.it("Cancel leaves both rows alone", function()
  tool("cancel")
  test.ipc("search", "close the window") test.settle(100)
  test.click("keys-row-1-press") test.settle(100)
  test.key("Return", "super") test.settle(100)
  test.click("keys-cancel") test.settle(100)
  test.eq(test.ipc("state").pending, "")
  test.eq(next(test.ipc("overrides")), nil)
end)

test.it("a plain letter is refused and says why", function()
  tool("plain")
  test.falsy(test.ipc("offer", "verb:kill_mode", "K"))
  test.contains(test.ipc("state").message, "typed")
end)

test.it("the shell's own shortcuts are shown, not changed", function()
  tool("shell")
  test.falsy(test.ipc("record", "shell:ctrl+d"))
  test.eq(test.ipc("state").recording, "")
end)

test.it("a phone lists the keys and offers no recording: it has no keyboard to press them on", function()
  tool("phone", { 412, 915 })
  test.falsy(test.ipc("record", "bind:SUPER + SHIFT + Q"))
  test.truthy(test.ipc("state").rows > 5)
end)

test.it("the shell sends a kept chord now, after a reload, and reloads to take one back", function()
  local settings = morf.env("XDG_CACHE_HOME") .. "/keys-editor-push.json"
  morf.fs.remove(settings)
  test.load("../shell/init.lua", { source = [[
    require("init")
    local keys = require("keys_model")
    morf.ipc.set = function(id, chord) keys.set(id, chord) return true end
    morf.ipc.reset = function(id) keys.reset(id) return true end
    morf.ipc.sent = function() return require("lib.services.host_fake").last_hyprland.sent end
    morf.ipc.fire = function() require("lib.services.host_fake").last_hyprland.fire("configreloaded") return true end
    morf.ipc.count = function(word)
      local n = 0
      for _, line in ipairs(require("lib.services.host_fake").last_hyprland.sent) do
        if line:find(word, 1, true) then n = n + 1 end
      end
      return n
    end
  ]], size = { 1920, 1080 }, env = { EVA_SETTINGS = settings, EVA_FAKE_SYSTEM = "1", EVA_DRY_RUN = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "" } })
  test.settle(500)
  test.ipc("set", "verb:kill_mode", "SUPER + K") test.settle(300)
  test.eq(test.ipc("count", 'hl.bind("SUPER + K"'), 1)
  test.ipc("fire") test.settle(300)
  test.eq(test.ipc("count", 'hl.bind("SUPER + K"'), 2)
  test.ipc("reset", "verb:kill_mode") test.settle(300)
  test.eq(test.ipc("count", "/reload"), 1)
end)

test.it("Settings search finds the keyboard shortcuts", function()
  local found = pure([[
    local out = {}
    for _, entry in ipairs(require("settings_registry").search("rebind")) do out[#out + 1] = entry.name end
    return out
  ]])
  test.contains(table.concat(found, ","), "Keyboard shortcuts")
end)
