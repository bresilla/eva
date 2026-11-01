-- The Phone page over a stand-in for kdeconnect-cli, with its real flags.
--     morf test --no-dbus tests/phone_page_spec.lua
local test = morf.test
local BIN = morf.env("PWD") .. "/tests/fixtures/bin-stand-in"
local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  local model = require("phone_model")
  local shown = morf.signal("phone.spec.shown", false)
  ui.Item { width = W, height = H, require("phone_page").build(function() return shown:get() end, W, function() return H end) }
  morf.ipc.show = function(on) shown:set(on == "yes") end
  morf.ipc.state = function()
    local devices, notes = {}, {}
    for i = 1, model.devices:len() do devices[i] = model.devices:get(i) end
    for i = 1, model.notifications:len() do notes[i] = model.notifications:get(i).text end
    return { present = model.present(), devices = devices, notes = notes, selected = model.selected:get(), loaded = model.loaded:get(),
      said = model.said:get(), battery = model.battery:get(), failed = model.failed:get() }
  end
  morf.ipc.ring = model.ring
  morf.ipc.ping = model.ping
  morf.ipc.clipboard = model.send_clipboard
  morf.ipc.share = model.share
  morf.ipc.select = model.select
]]
local function load(style, env, size)
  local w, h = (size or { 408, 900 })[1], (size or { 408, 900 })[2]
  local all = { EVA_STYLE = style or "material", PATH = BIN .. ":" .. morf.env("PATH"),
    TEST_WIDTH = tostring(w), TEST_HEIGHT = tostring(h), EVA_DRY_RUN = "0" }
  for name, value in pairs(env or {}) do all[name] = value end
  test.load("../shell/init.lua", { source = HOST, size = { w, h }, env = all })
end
local function state() return test.ipc("state") end
local function shown()
  test.ipc("show", "yes")
  return test.wait(function() test.advance(30) local s = state() return s.loaded and #s.notes > 0 and s.battery.percent and s end, 5000, "the phone")
end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end
local function argv_with(word)
  for _, run in ipairs(test.runs()) do
    for _, part in ipairs(run) do if part == word then return run end end
  end
end

test.describe("phone page", function()
  test.it("says when KDE Connect is not installed, and runs nothing", function()
    load(nil, { PATH = "/nonexistent" })
    test.ipc("show", "yes")
    test.advance(200)
    test.falsy(state().present)
    test.truthy(test.get("phone-missing").visible)
    test.eq(#test.runs(), 0)
  end)

  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. " shows the reachable phone, its battery and notifications", function()
      load(style)
      local s = shown()
      test.eq(#s.devices, 2)
      test.eq(s.selected, "a1b2c3d4", "the reachable one is chosen")
      test.eq(s.devices[1].reachable, true)
      test.eq(s.devices[2].reachable, false)
      test.eq(s.battery.percent, 77)
      test.eq(s.battery.charging, true)
      test.eq(s.notes, { "Messages: Dinner at seven?", "Calendar: Standup in ten minutes" })
      test.truthy(test.find { text = "Battery 77%, charging" })
      test.truthy(test.get("phone-drop").visible)
      shot(style .. "-phone")
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("rings, pings, sends the clipboard and shares a file", function()
    load()
    shown()
    test.ipc("ring")
    test.wait(function() test.advance(30) return state().said == "Ringing" end, 3000, "ringing")
    test.ipc("ping")
    test.ipc("clipboard")
    test.ipc("share", "/tmp/report.pdf")
    test.wait(function() test.advance(30) return state().said == "Sent report.pdf" end, 3000, "shared")
    test.eq(argv_with("--ring")[2], "--device")
    test.eq(argv_with("--ring")[3], "a1b2c3d4")
    test.truthy(argv_with("--ping"))
    test.truthy(argv_with("--send-clipboard"))
    test.truthy(argv_with("/tmp/report.pdf"))
  end)

  test.it("does nothing to a phone in a dry run", function()
    load(nil, { EVA_DRY_RUN = "1" })
    shown()
    test.ipc("ring")
    test.eq(state().said, "Ringing")
    test.eq(argv_with("--ring"), nil)
  end)

  test.it("says no phone is paired", function()
    load(nil, { PATH = "/nonexistent" })
    test.ipc("show", "yes")
    test.advance(100)
    test.falsy(test.get("phone-devices").visible)
  end)

  test.it("fits a phone", function()
    load("material", nil, { 390, 780 })
    shown()
    test.truthy(test.get("phone-actions").width <= 390)
    shot("phone-phone")
  end)
end)
