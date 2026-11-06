-- The Fingerprints page over fprintd, against the stand-in reader on the fake
-- bus: the real service code runs, and no daemon, reader or PAM stack is touched.
--
--     morf test --no-dbus tests/fingerprint_spec.lua
local test = morf.test
local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"

local HOST = [==[
  require("init")
  morf.ipc.fp = function() return require("fingerprint_model").state() end
  morf.ipc.fp_join = function() return require("fingerprint_model").join() end
  morf.ipc.fp_calls = function()
    local out, fake = {}, require("lib.testing.dbus")
    for _, call in ipairs(fake.calls) do
      if call.dest == "net.reactivated.Fprint" then out[#out + 1] = call.method end
    end
    return out
  end
  morf.ipc.fp_cancel = function() require("fingerprint_model").cancel() return true end
  morf.ipc.fp_setting = function(key) return require("config").get(key) end
]==]

local serial = 0
local function load(style, env, settings)
  serial = serial + 1
  local path = morf.env("XDG_CACHE_HOME") .. "/fingerprint-" .. serial .. ".json"
  morf.fs.write(path, morf.json.encode(settings or {}))
  env = env or {}
  env.EVA_STYLE, env.EVA_DRY_RUN, env.EVA_SETTINGS, env.EVA_WALLPAPER = style, "1", path, ""
  env.EVA_INPUT_DEVICES, env.EVA_FAKE_SYSTEM = TOUCH, env.EVA_FAKE_SYSTEM or "1"
  env.EVA_FAKE_FINGER_STACK = env.EVA_FAKE_FINGER_STACK or "1"
  env.HOME = morf.env("XDG_CACHE_HOME")
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = HOST, size = { 412, 915 }, env = env })
  test.settle(900)
  test.ipc("settings", "lock/fingerprint")
  test.settle(900)
end

-- Presses `id`, the page scrolled to bring it into view first.
local function press(id)
  for _ = 1, 40 do
    local node, sheet = test.get(id), test.get("settings-detail")
    if node.y > sheet.y and node.y + node.height < sheet.y + sheet.height - 4 then
      test.settle(300)
      node = test.get(id)
      test.click(node.x + node.width / 2, node.y + node.height / 2)
      return
    end
    test.wheel(0, node.y > 400 and 200 or -200, { x = 206, y = 400 })
    test.settle(150)
  end
  error("never came into view: " .. id)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " the page", function()
    test.it("lists what the reader holds, and what can be added", function()
      load(style)
      local state = test.ipc("fp")
      test.eq(state.status, "ready")
      test.eq(state.name, "Stand-in reader")
      test.eq(state.fingers, { "right-index-finger" })
      test.matches(test.get("fingerprint-finger-1-title").text, "Right index")
      test.falsy(test.find { id = "fingerprint-add-10", visible = true }, "an enrolled finger is offered again")
      test.truthy(test.find { id = "fingerprint-add-9", visible = true })
      test.eq(#test.logs("error"), 0)
    end)

    test.it("adds a finger, reading by reading, and hands the reader back", function()
      load(style)
      test.click("fingerprint-add-1-press") test.advance(60)
      test.truthy(test.find { id = "fingerprint-adding", visible = true }, "no sign of it starting")
      test.eq(test.ipc("fp").enrolling.finger, "left-index-finger")
      test.wait(function()
        test.advance(16)
        return tostring(test.ipc("fp").note):find("Centre your finger", 1, true) ~= nil
      end, 3000, "a reading that failed said nothing")
      test.eq(test.ipc("fp").enrolling.read, 1, "a reading that failed counted")
      test.wait(function()
        test.advance(16)
        return not test.ipc("fp").enrolling
      end, 3000, "it never finished")
      test.settle(300)
      local state = test.ipc("fp")
      test.falsy(state.enrolling, "it is still adding")
      test.eq(state.note, "Done")
      test.eq(state.fingers, { "right-index-finger", "left-index-finger" })
      local calls = table.concat(test.ipc("fp_calls"), " ")
      test.matches(calls, "Claim EnrollStart")
      test.matches(calls, "EnrollStop Release")
      test.falsy(test.find { id = "fingerprint-adding", visible = true })
    end)

    test.it("stops when told, and when the page is left", function()
      load(style)
      test.click("fingerprint-add-1-press") test.settle(60)
      test.click("fingerprint-cancel") test.settle(300)
      test.falsy(test.ipc("fp").enrolling, "it kept going")
      test.matches(table.concat(test.ipc("fp_calls"), " "), "EnrollStop Release")
      test.click("fingerprint-add-1-press") test.settle(60)
      test.ipc("close") test.settle(600)
      test.falsy(test.ipc("fp").enrolling, "leaving the page left the reader claimed")
    end)

    test.it("takes a finger away on a second press", function()
      load(style)
      test.click("fingerprint-remove-1") test.settle(200)
      test.eq(#test.ipc("fp").fingers, 1, "one press took it")
      test.click("fingerprint-remove-1") test.settle(400)
      test.eq(#test.ipc("fp").fingers, 0)
      test.matches(table.concat(test.ipc("fp_calls"), " "), "Claim DeleteEnrolledFinger Release")
    end)

    test.it("says so when someone else holds the reader", function()
      load(style, { EVA_FAKE_FPRINT = "busy" })
      test.click("fingerprint-add-1-press") test.settle(300)
      test.falsy(test.ipc("fp").enrolling)
      test.matches(test.ipc("fp").note, "busy")
    end)
  end)

  test.describe(style .. " what the machine has", function()
    test.it("says plainly where there is no reader", function()
      load(style, { EVA_FAKE_FPRINT = "noreader" })
      test.eq(test.ipc("fp").status, "absent")
      test.matches(test.get("fingerprint-status-title").text, "No reader")
      test.falsy(test.find { id = "fingerprint-add", visible = true }, "offered what cannot work")
    end)

    test.it("says how to get fprintd where it is missing", function()
      load(style, { EVA_FAKE_FPRINT = "none" })
      test.eq(test.ipc("fp").status, "none")
      test.matches(test.get("fingerprint-status-subtitle").text, "services.fprintd.enable")
      test.eq(test.ipc("fp_calls"), {}, "it asked a bus with nothing on it")
    end)
  end)

  test.describe(style .. " the lock", function()
    test.it("says what is missing for a finger to open it, on NixOS and elsewhere", function()
      load(style, { EVA_FAKE_FINGER_STACK = "0", EVA_FAKE_SYSTEM = "nixos" })
      test.matches(test.ipc("fp_join").text, "services.fprintd.enable")
      load(style, { EVA_FAKE_FINGER_STACK = "0" })
      test.matches(test.ipc("fp_join").text, "helpers/pam/readers.sh")
    end)

    test.it("shares its switch with the lock's own", function()
      load(style)
      test.matches(test.ipc("fp_join").title, "A finger opens the lock")
      press("fingerprint-readers-switch") test.settle(300)
      test.eq(test.ipc("fp_setting", "lock.readers"), false)
      test.matches(test.ipc("fp_join").title, "readers are off")
    end)
  end)
end

test.it("is reached from the Lock screen page, and by search", function()
  load("material")
  test.ipc("settings", "lock") test.settle(900)
  test.truthy(test.find { id = "lock-set-fingerprints" }, "no way there")
  local keys = {}
  for _, hit in ipairs(test.ipc("settings-search", "enrol")) do keys[#keys + 1] = hit.key end
  test.truthy(table.concat(keys, " "):find("lock/fingerprint", 1, true), "search does not find it")
end)

test.it("never calls the bus in a dry run with no stand-in", function()
  local path = morf.env("XDG_CACHE_HOME") .. "/fingerprint-dry.json"
  morf.fs.write(path, "{}")
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = [==[
    require("init")
    morf.ipc.fp = function() return require("fingerprint_model").state() end
  ]==], size = { 412, 915 }, env = { EVA_DRY_RUN = "1", EVA_SETTINGS = path, EVA_WALLPAPER = "", HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(600)
  test.ipc("settings", "lock/fingerprint") test.settle(600)
  test.eq(test.ipc("fp").status, "none", "a dry run reached for fprintd")
end)
