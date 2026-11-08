-- The lock with patty's pattern: the grid drawn, the keypad pressed, the
-- keyboard typing either, the way to the password and back, wrong tries and a
-- lockout. The door is a fixture and the folder a stand-in: nothing reaches PAM.
local test = morf.test
local dir = morf.env("XDG_CACHE_HOME") .. "/lock-pattern"

local function put(name, text) morf.fs.write(dir .. "/" .. name, text, { parents = true }) end
local function files(kind, fails)
  for _, name in ipairs { "ada.kind", "ada.fails" } do pcall(morf.fs.remove, dir .. "/" .. name) end
  if kind then put("ada.kind", kind .. "\n") end
  if fails then put("ada.fails", fails .. "\n") end
end

local SOURCE = [[
  pcall(function()
    morf.pam = setmetatable({}, { __index = function(_, name) error("the spec reached PAM: " .. name) end })
  end)
  package.loaded["lib.services.accounts"] = { me = function() return { name = "ada", label = "Ada", initial = "A" } end }
  package.loaded["lib.services.keyboards"] = { attached = function() return morf.env("SPEC_KEYBOARD") ~= "0" end }
  package.loaded["lib.services.mpris"] = { connect = function() return { state = { active = {} } } end }
  local auth = require("lib.shell.auth")
  local handlers, given, verdict = nil, {}, "wrong"
  package.loaded["lib.shell.auth"] = setmetatable({ lock = function(on)
    handlers = on
    local door = { done = false }
    function door.submit(self, token)
      given[#given + 1] = token
      on.on_busy(true)
      morf.time.timer(50, function()
        on.on_busy(false)
        if verdict == "right" then self.done = true on.on_open() else on.on_failed("Authentication failure") end
      end, false)
    end
    function door.listen() end
    function door.stop() end
    return door
  end }, { __index = auth })
  local ctx
  local theme = require("themes").current.lock
  local build = require(theme)
  package.loaded[theme] = function(context) ctx = ctx or context return build(context) end
  require("init")
  morf.ipc.door = function(what, value)
    if what == "verdict" then verdict = value
    elseif what == "hint" then handlers.on_hint(value, false)
    elseif what == "busy" then handlers.on_busy(value == "on") end
    return { given = given, message = ctx.message:get(), bad = ctx.bad:get(), busy = ctx.busy:get() }
  end
]]

local function load(style, options)
  options = options or {}
  local env = { EVA_STYLE = style, EVA_SCALE_MODE = "compositor", EVA_DRY_RUN = "1", EVA_PATTY_DIR = dir,
    EVA_SETTINGS = dir .. "/none.json", EVA_WALLPAPER = "", SPEC_KEYBOARD = options.keyboard or "1" }
  test.load("../lock/init.lua", { source = SOURCE, size = options.size or { 1368, 912 }, args = { "window" }, env = env })
  test.settle(1200)
  test.ipc("stage", "sheet")
  test.settle(900)
end

local function shown(id) return test.find { id = id, visible = true } end
local function centre(id)
  local node = test.get(id)
  return node.x + node.width / 2, node.y + node.height / 2
end
-- A stroke through the dots, pressed at the first and let go at the last.
local function draw(dots)
  local x, y = centre("lock-pattern-ring-" .. dots[1])
  test.press(x, y)
  for i = 2, #dots do
    local tx, ty = centre("lock-pattern-ring-" .. dots[i])
    for step = 1, 6 do test.move(x + (tx - x) * step / 6, y + (ty - y) * step / 6) end
    x, y = tx, ty
  end
  test.release(x, y)
  test.settle(200)
end
local function message() return test.get("lock-message").text end

for _, style in ipairs { "tsugumori", "material" } do
  test.describe(style .. " lock with a pattern", function()
    test.it("is as it was where there is no pattern", function()
      files(nil, nil)
      load(style)
      test.truthy(shown("lock-field"), "no password field")
      test.falsy(shown("lock-pattern"), "a grid with no pattern")
      test.falsy(shown("lock-method"), "a way to a pattern there is not")
    end)

    test.it("hands a drawn grid pattern to the door as its digits", function()
      files("grid", "0 0")
      load(style)
      test.truthy(shown("lock-pattern"), "no grid")
      test.falsy(shown("lock-field"), "the password field under the grid")
      test.eq(test.get("lock-method-label").text, "Use password")
      test.ipc("door", "verdict", "right")
      draw { 1, 2, 3, 6 }
      test.eq(test.ipc("door").given, { "1236" })
    end)

    test.it("skips a dot that is no neighbour and never takes one twice", function()
      files("grid", "0 0")
      load(style)
      draw { 7, 5, 3, 6, 5, 4 }
      test.eq(test.ipc("door").given, { "7536" }, "6 to 4 over the used 5 is no step patty draws")
    end)

    test.it("does not send fewer than four dots", function()
      files("grid", "0 0")
      load(style)
      draw { 1, 2, 3 }
      test.eq(test.ipc("door").given, {})
      test.eq(message(), "Connect at least 4 dots")
      test.eq(test.ipc("pattern").drawn, 0)
    end)

    test.it("says how many tries are left after a wrong one, red a moment", function()
      files("grid", "0 0")
      load(style)
      put("ada.fails", "3 0\n")
      test.press(centre("lock-pattern-ring-1"))
      for _, n in ipairs { 4, 7, 8 } do test.move(centre("lock-pattern-ring-" .. n)) end
      test.release(centre("lock-pattern-ring-8"))
      test.advance(100)
      test.eq(message(), "Wrong pattern. 2 tries left")
      test.truthy(test.ipc("door").bad)
      test.eq(test.ipc("pattern").drawn, 4, "the wrong pattern stays drawn a moment")
      test.advance(1000)
      test.eq(test.ipc("pattern").drawn, 0)
      test.key("1")
      test.settle(100)
      test.eq(message(), "2 tries left", "the count stays once the person goes on")
    end)

    test.it("moves to the password when patty locks the pattern, and back when it ends", function()
      files("grid", "4 0")
      load(style)
      local now = math.floor(morf.time.now())
      put("ada.fails", ("0 %d\n"):format(now + 150))
      draw { 1, 2, 3, 6 }
      test.advance(100)
      test.eq(message(), "Pattern locked for 3 min — use your password")
      test.truthy(shown("lock-field"), "still on the grid while locked")
      test.falsy(shown("lock-method"), "a way back to a locked pattern")
      put("ada.fails", ("0 %d\n"):format(now - 1))
      test.advance(31000)
      test.eq(test.ipc("pattern").shown, "grid", "the pattern did not come back")
    end)

    test.it("opens on the password while patty is locked, and says so", function()
      files("grid", ("0 %d"):format(math.floor(morf.time.now()) + 100))
      load(style)
      test.truthy(shown("lock-field"))
      test.eq(message(), "Pattern locked for 2 min — use your password")
    end)

    test.it("goes to the password and back, which takes digits too", function()
      files("grid", "0 0")
      load(style)
      test.click("lock-method")
      test.settle(200)
      test.truthy(shown("lock-field"))
      test.eq(test.get("lock-method-label").text, "Use pattern")
      test.type("1236")
      test.key("Return")
      test.advance(100)
      test.type("hunter2")
      test.key("Return")
      test.advance(100)
      test.eq(test.ipc("door").given, { "1236", "hunter2" })
      test.click("lock-method")
      test.settle(200)
      test.truthy(shown("lock-pattern"))
    end)

    test.it("takes typed digits on the grid, and moves to the password at the first that does not fit", function()
      files("grid", "0 0")
      load(style)
      test.type("1236")
      test.eq(test.ipc("pattern").drawn, 4, "typed digits are drawn")
      test.key("BackSpace")
      test.type("5")
      test.key("Return")
      test.advance(100)
      test.type("19x")
      test.eq(test.ipc("pattern").method, "password")
      test.key("Return")
      test.advance(100)
      test.eq(test.ipc("door").given, { "1235", "19x" })
    end)

    test.it("hands keypad digits to the door, pressed or typed", function()
      files("keypad", "0 0")
      load(style)
      test.truthy(shown("lock-keypad"), "no keypad")
      for _, place in ipairs { 1, 10, 2, 5, 8, 11 } do test.click("lock-pattern-key-" .. place) end
      test.click("lock-pattern-key-12")
      test.advance(100)
      test.type("1593")
      test.key("Return")
      test.advance(100)
      test.eq(test.ipc("door").given, { "2580", "1593" })
    end)

    test.it("shows what the stack says while it checks, as a hint", function()
      files("grid", "0 0")
      load(style)
      test.ipc("door", "busy", "on")
      local said = test.ipc("door", "hint", "Please touch the device.")
      test.eq(said.message, "Please touch the device.")
      test.falsy(said.bad, "a cue is not an error")
      test.eq(message(), "Please touch the device.")
    end)
  end)
end

test.it("gives a finger room on a phone, with the keyboard down", function()
  files("grid", "0 0")
  load("tsugumori", { size = { 868, 1932 }, keyboard = "0" })
  test.truthy(shown("lock-pattern"))
  test.falsy(shown("lock-keyboard"), "the on-screen keyboard over the grid")
  test.truthy(test.get("lock-pattern-ring-1").width >= 96, "dots too small for a finger")
  local _, y1 = centre("lock-pattern-ring-1")
  local _, y7 = centre("lock-pattern-ring-7")
  test.truthy(y7 - y1 >= 300, "a grid too small for a finger")
  local x, y = centre("lock-pattern-ring-3")
  test.touch("down", 1, x, y)
  for _, n in ipairs { 5, 7, 8 } do
    local tx, ty = centre("lock-pattern-ring-" .. n)
    for step = 1, 8 do test.touch("move", 1, x + (tx - x) * step / 8, y + (ty - y) * step / 8) end
    x, y = tx, ty
  end
  test.touch("up", 1, x, y)
  test.advance(200)
  test.eq(test.ipc("door").given, { "3578" }, "a finger's stroke")
  test.click("lock-method")
  test.settle(300)
  test.truthy(shown("lock-keyboard"), "the keyboard with the password")
end)
