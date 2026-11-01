-- The first-run welcome: when it comes and when it stays away, its steps on each
-- form, that it leads to the real pages, and that the greeter and the lock
-- never reach it. The state folder is the runner's scratch one.
--     tools/test.sh tests/welcome_spec.lua
local test = morf.test

local KEYBOARD = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/input-devices")
local TOUCH = morf.fs.join(morf.env("PWD") or ".", "tests/fixtures/input-devices-touch")

-- The start alone, with the pages stubbed: what decides whether it comes.
local LOGIC = [[
  local ui = require("morf.ui")
  ui.Item { width = 10, height = 10 }
  local opened = false
  package.loaded.pages = { settings = function(route) opened = route return true end, close = function() opened = false end }
  local welcome = require("welcome_model")
  local guide = require("gesture_guide")
  local function state(name) return morf.paths.state(name) end
  morf.ipc.reset = function()
    for _, name in ipairs { "welcome-seen", "notifications/history.json", "calendar-reminders.json", "eva.json" } do morf.fs.remove(state(name)) end
    opened = false
  end
  morf.ipc.remember = function(name) morf.fs.write(state(name), "{}", { parents = true }) end
  morf.ipc.start = function() return welcome.start() end
  morf.ipc.opened = function() return opened end
  morf.ipc.seen = function() return morf.fs.exists(state("welcome-seen")) end
  morf.ipc.steps = function() return welcome.steps() end
  morf.ipc.gestures = function() return guide.gestures() end
  morf.ipc.keys = function() return guide.keys() end
]]

local serial = 0
local function shell(style, size, env)
  serial = serial + 1
  local vars = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1", EVA_FAKE_SYSTEM = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "",
    EVA_SETTINGS = ("%s/welcome-%d.json"):format(morf.env("XDG_CACHE_HOME"), serial), HOME = morf.env("XDG_CACHE_HOME") }
  for key, value in pairs(env or {}) do vars[key] = value end
  test.load("../shell/init.lua", { size = size or { 1920, 1080 }, env = vars })
  test.settle(1000)
end
local function logic(env, size)
  serial = serial + 1
  local vars = { EVA_DRY_RUN = "", EVA_SETTINGS = ("%s/welcome-%d.json"):format(morf.env("XDG_CACHE_HOME"), serial) }
  for key, value in pairs(env or {}) do vars[key] = value end
  test.load("../shell/init.lua", { source = LOGIC, size = size or { 1920, 1080 }, env = vars })
  test.ipc("reset")
end
local function shown() return test.find { id = "welcome", visible = true } end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end
local function open()
  test.ipc("welcome")
  test.settle(900)
end
local function next_step() test.click("welcome-next") test.settle(700) end

test.describe("when the welcome comes", function()
  test.it("the first login of a new person, once", function()
    logic { EVA_WELCOME = "1" }
    test.truthy(test.ipc("start"))
    test.eq(test.ipc("opened"), false, "it gives the shell a moment")
    test.advance(1600)
    test.eq(test.ipc("opened"), "welcome")
    test.truthy(test.ipc("seen"))
    test.falsy(test.ipc("start"), "a second start finds it seen")
  end)

  test.it("not to someone who already uses eva", function()
    for _, name in ipairs { "notifications/history.json", "calendar-reminders.json" } do
      logic { EVA_WELCOME = "1" }
      test.ipc("remember", name)
      test.falsy(test.ipc("start"), name)
      test.advance(1600)
      test.eq(test.ipc("opened"), false, name)
      test.truthy(test.ipc("seen"), "and it stays that way")
    end
  end)

  test.it("not where something asked it to stay away", function()
    logic { EVA_WELCOME = "0" }
    test.falsy(test.ipc("start"))
    test.falsy(test.ipc("seen"), "held back, it is still owed")
  end)

  test.it("not in a preview or a headless run", function()
    logic { EVA_DRY_RUN = "1" }
    test.falsy(test.ipc("start"))
    logic {}
    test.falsy(test.ipc("start"))
    test.falsy(test.ipc("seen"))
  end)

  test.it("never on the greeter or the lock: neither loads it", function()
    for _, file in ipairs { "greet/init.lua", "lock/init.lua" } do
      local text = morf.fs.read(file)
      test.falsy(text:find("welcome", 1, true), file)
      test.falsy(text:find("settings_model", 1, true), file)
    end
  end)
end)

test.describe("what it says on each device", function()
  test.it("a desk: the pointer and the keys, its touchpad where there is one", function()
    logic({ EVA_INPUT_DEVICES = KEYBOARD })
    test.eq(test.ipc("steps"), { "look", "network", "gestures", "keys" })
    local rows = test.ipc("gestures")
    test.eq(#rows, 4)
    test.truthy(rows[1][2]:find("pointer", 1, true), rows[1][2])
    test.truthy(test.ipc("keys")[1][3]:find("launcher", 1, true))
    test.eq(test.ipc("keys")[1][2], "Super + Space")
    local devices = morf.env("XDG_CACHE_HOME") .. "/devices-pad"
    morf.fs.write(devices, 'N: Name="ELAN Touchpad"\nH: Handlers=mouse0 event5\n')
    logic({ EVA_INPUT_DEVICES = devices })
    rows = test.ipc("gestures")
    test.eq(#rows, 5)
    test.truthy(rows[5][2]:find("4 fingers up", 1, true), rows[5][2])
  end)

  test.it("a phone: its edges, and no keys to learn", function()
    logic({ EVA_INPUT_DEVICES = TOUCH }, { 412, 915 })
    test.eq(test.ipc("steps"), { "look", "network", "gestures" })
    local rows = test.ipc("gestures")
    test.eq(#rows, 6)
    test.truthy(rows[1][2]:find("Swipe down from the top", 1, true), rows[1][2])
  end)

  test.it("a tablet with a keyboard keeps the keys step", function()
    logic({ EVA_INPUT_DEVICES = KEYBOARD }, { 1280, 800 })
    test.eq(test.ipc("steps")[4], "keys")
  end)

  test.it("the swipes it names are the ones bound", function()
    local script = morf.fs.read("nix/nixos/scripts/gestures.sh")
    for _, action in ipairs { "workspace-next", "workspace-previous", "dashboard", "top", "keyboard" } do
      test.truthy(script:find("PHONE_GESTURE_ACTION " .. action, 1, true), action)
    end
  end)
end)

test.describe("the welcome in the shell", function()
  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. ": walks its steps, there and back, and shuts", function()
      shell(style)
      open()
      test.truthy(shown())
      test.truthy(test.find { id = "welcome-mode-dark", visible = true })
      shot(style .. "-welcome-look")
      next_step()
      test.truthy(test.find { text = "Connected to Home", visible = true })
      next_step()
      test.truthy(test.find { id = "welcome-gesture-1", visible = true })
      test.click("welcome-back") test.settle(700)
      test.truthy(test.find { text = "Connected to Home", visible = true })
      next_step()
      next_step()
      test.truthy(test.find { id = "welcome-key-1", visible = true })
      test.truthy(test.find { id = "welcome-key-8", visible = true }, "every key of the list")
      test.truthy(test.find { id = "welcome-all-keys", visible = true } or test.find { id = "welcome-all-keys-press", visible = true })
      next_step()
      test.falsy(shown(), "Done shuts it")
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("Skip leaves it, and Settings has it back", function()
    shell()
    open()
    test.click("welcome-skip") test.settle(900)
    test.falsy(shown())
    test.ipc("settings", "home") test.settle(900)
    test.type("welcome") test.settle(300)
    test.truthy(test.find { text = "Welcome", visible = true })
    test.key("Return") test.settle(900)
    test.truthy(shown(), "reopened from Settings")
    test.ipc("settings", "eva") test.settle(900)
    test.truthy(test.find { id = "settings-eva-welcome", visible = true } or test.find { id = "settings-eva-welcome-press", visible = true })
  end)

  test.it("leads to the real page, and Back returns to the step", function()
    shell()
    open()
    next_step()
    test.click("welcome-wifi-press") test.settle(900)
    test.truthy(test.find { id = "network-scroll", visible = true }, "the Network page itself")
    test.click("settings-back") test.settle(900)
    test.truthy(shown())
    test.truthy(test.find { text = "Connected to Home", visible = true })
  end)

  test.it("a phone's sheet holds the longest step whole", function()
    shell("tsugumori", { 412, 915 }, { EVA_INPUT_DEVICES = TOUCH })
    open()
    next_step()
    next_step()
    shot("phone-welcome-gestures")
    test.truthy(test.find { id = "welcome-gesture-6", visible = true })
    local box = test.get("welcome")
    test.truthy(box.x >= 0 and box.x + box.width <= 412)
    local go = test.get("welcome-next")
    test.truthy(go.y + go.height <= 915, "Done stays on the screen")
    test.eq(#test.logs("error"), 0)
  end)
end)
