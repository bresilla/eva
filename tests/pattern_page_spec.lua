-- The Pattern page: what patty holds for the account, a pattern drawn or typed
-- twice and handed to `pkexec patty set` on its stdin only, and clearing it.
-- pkexec is the stand-in machine's, or a stand-in script; never the real one.
local test = morf.test
local ROOT = morf.env("PWD") .. "/"
local dir = morf.env("EVA_PATTY_DIR") or (morf.env("XDG_CACHE_HOME") .. "/pattern-page")
local NAMES = { "ada", "ada.kind", "ada.fails", "pkexec.argv", "pkexec.stdin", "pkexec.code" }

local function put(name, text) morf.fs.write(dir .. "/" .. name, text, { parents = true }) end
local function read(name)
  local ok, text = pcall(morf.fs.read, dir .. "/" .. name)
  return ok and text or nil
end
local function clean() for _, name in ipairs(NAMES) do pcall(morf.fs.remove, dir .. "/" .. name) end end

local HOST = [==[
  require("init")
  morf.ipc.pat = function()
    local model, fake = require("pattern_model"), require("lib.services.host_fake")
    local ran = {}
    for _, argv in ipairs(fake.ran) do if argv[2] == "patty" then ran[#ran + 1] = argv end end
    return { ran = ran, stdin = fake.stdin, state = model.state:get(), said = model.said:get().text,
      step = model.step:get() }
  end
]==]

local serial = 0
local function load(style, env)
  serial = serial + 1
  local settings = morf.env("XDG_CACHE_HOME") .. "/pattern-page-" .. serial .. ".json"
  morf.fs.write(settings, "{}")
  local vars = { EVA_STYLE = style, EVA_DRY_RUN = "", EVA_FAKE_SYSTEM = "1", EVA_SETTINGS = settings,
    EVA_WALLPAPER = "", EVA_PATTY_DIR = dir, USER = "ada", HOME = morf.env("XDG_CACHE_HOME") }
  for key, value in pairs(env or {}) do vars[key] = value end
  test.load("../shell/init.lua", { source = HOST, size = { 1920, 1080 }, env = vars })
  test.settle(900)
  test.ipc("settings", "lock/pattern")
  test.settle(900)
end

-- Scrolls the page until `id` stands whole in it.
local function into_view(id)
  for _ = 1, 40 do
    local node, sheet = test.get(id), test.get("settings-detail")
    if node.y > sheet.y and node.y + node.height < sheet.y + sheet.height - 4 then
      test.settle(200)
      return test.get(id)
    end
    test.wheel(0, node.y > sheet.y + sheet.height / 2 and 120 or -120,
      { x = sheet.x + sheet.width / 2, y = sheet.y + sheet.height / 2 })
    test.settle(150)
  end
  error("never came into view: " .. id)
end
local function centre(id)
  local node = test.get(id)
  return node.x + node.width / 2, node.y + node.height / 2
end
local function draw(dots)
  into_view("pattern-page-grid-box")
  test.press(centre("pattern-page-grid-ring-" .. dots[1]))
  for i = 2, #dots do test.move(centre("pattern-page-grid-ring-" .. dots[i])) end
  test.release(centre("pattern-page-grid-ring-" .. dots[#dots]))
  test.settle(200)
end
local function type_in(digits)
  local node = into_view("pattern-page-digits")
  test.click(node.x + node.width / 2, node.y + node.height / 2)
  test.type(digits)
  test.key("Return")
  test.settle(200)
end
local function no_digits_on(ran, digits)
  for _, argv in ipairs(ran) do
    for _, word in ipairs(argv) do test.falsy(tostring(word):find(digits, 1, true), "a pattern on a command line") end
  end
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " Pattern page", function()
    test.it("draws a pattern twice and hands both to pkexec patty on its stdin", function()
      clean()
      load(style)
      test.eq(test.get("pattern-kind-title").text, "No pattern")
      draw { 1, 2, 3, 6 }
      test.eq(test.ipc("pat").step, "again")
      test.eq(test.ipc("pat").ran, {}, "it ran after one entry")
      draw { 1, 2, 3, 6 }
      local state = test.ipc("pat")
      test.eq(state.ran, { { "pkexec", "patty", "set", "ada" } })
      test.eq(state.stdin, "1236\n1236\n")
      no_digits_on(state.ran, "1236")
      test.eq(state.said, "Saved. The screens show a grid")
      test.eq(state.state.kind, "grid")
      test.eq(test.get("pattern-kind-title").text, "A grid pattern")
    end)

    test.it("takes typed digits for a keypad pattern", function()
      clean()
      load(style)
      type_in("2580")
      type_in("2580")
      local state = test.ipc("pat")
      test.eq(state.stdin, "2580\n2580\n")
      test.eq(state.state.kind, "keypad")
      test.eq(test.get("pattern-page-digits").text, "", "the field kept the digits")
    end)

    test.it("starts over when the two differ, and runs nothing", function()
      clean()
      load(style)
      draw { 1, 2, 3, 6 }
      draw { 1, 4, 7, 8 }
      local state = test.ipc("pat")
      test.eq(state.ran, {})
      test.eq(state.said, "The two differ. Start again")
      test.eq(state.step, "first")
    end)

    test.it("refuses fewer than four", function()
      clean()
      load(style)
      draw { 1, 2, 3 }
      test.eq(test.ipc("pat").step, "first")
      test.eq(test.ipc("pat").said, "At least 4 digits, or 4 dots")
    end)

    test.it("clears the pattern on a second press", function()
      clean()
      put("ada", "grid $y$fake\n")
      put("ada.kind", "grid\n")
      put("ada.fails", "2 0\n")
      load(style)
      test.eq(test.get("pattern-tries-title").text, "2 of 5 wrong tries")
      into_view("pattern-clear")
      test.click("pattern-clear")
      test.settle(200)
      test.eq(test.ipc("pat").ran, {}, "one press cleared it")
      test.click("pattern-clear")
      test.settle(300)
      local state = test.ipc("pat")
      test.eq(state.ran, { { "pkexec", "patty", "clear", "ada" } })
      test.eq(state.state.kind, "")
      test.eq(test.get("pattern-kind-title").text, "No pattern")
    end)

    test.it("shows a lockout", function()
      clean()
      put("ada.kind", "grid\n")
      put("ada.fails", ("0 %d\n"):format(math.floor(morf.time.now()) + 200))
      load(style)
      test.truthy(test.find { id = "pattern-locked", visible = true }, "no lockout shown")
      test.falsy(test.find { id = "pattern-tries", visible = true })
    end)

    test.it("says when patty is not installed", function()
      clean()
      load(style, { EVA_FAKE_PATTY = "none" })
      test.truthy(test.find { id = "pattern-missing", visible = true })
      test.eq(test.get("pattern-missing-row-title").text, "patty is not installed on this machine")
      test.falsy(test.find { id = "pattern-set", visible = true })
    end)
  end)
end

test.it("a stand-in pkexec gets the pattern on stdin and nowhere else", function()
  clean()
  load("material", { EVA_FAKE_SYSTEM = "", EVA_PKEXEC = ROOT .. "tests/fixtures/bin/pkexec-patty",
    EVA_PATTY = "/run/current-system/sw/bin/patty" })
  draw { 9, 5, 1, 2 }
  draw { 9, 5, 1, 2 }
  test.wait(function() return test.ipc("pat").said:find("Saved", 1, true) end, 5000, "pkexec never answered")
  test.eq(read("pkexec.stdin"), "9512\n9512\n")
  test.eq(read("pkexec.argv"), "/run/current-system/sw/bin/patty set ada\n")
  test.eq(test.ipc("pat").said, "Saved. The screens show a grid")
  put("pkexec.code", "1\n")
  draw { 9, 5, 1, 2 }
  draw { 9, 5, 1, 2 }
  test.wait(function() return test.ipc("pat").said:find("Not changed", 1, true) end, 5000, "the failure went unsaid")
  test.eq(test.ipc("pat").said, "Not changed: the two patterns differ; nothing saved")
  clean()
end)
