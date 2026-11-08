-- The greeter with patty's pattern: it reads only `<user>.kind` (the greeter
-- user cannot read the rest), shows the grid or keypad for the chosen account,
-- and hands what is drawn to greetd as the password. The door is a fixture.
local test = morf.test
local dir = morf.env("XDG_CACHE_HOME") .. "/greet-pattern"

local function files(list)
  for _, name in ipairs { "ada", "ada.kind", "bob.kind" } do pcall(morf.fs.remove, dir .. "/" .. name) end
  for name, text in pairs(list) do morf.fs.write(dir .. "/" .. name, text .. "\n", { parents = true }) end
end

local SOURCE = [[
  package.loaded["lib.services.accounts"] = { list = function()
    return { { name = "ada", label = "Ada", initial = "A" }, { name = "bob", label = "Bob", initial = "B" } }
  end }
  package.loaded["lib.services.sessions"] = { list = function() return { { name = "Desktop", command = { "false" } } } end,
    default_index = function() return 1 end }
  local given, handlers = {}, nil
  package.loaded["lib.shell.auth"] = { greeter = function(on)
    handlers = on
    local door = { available = true }
    function door.submit(_, token)
      given[#given + 1] = token
      on.on_busy(true)
      morf.time.timer(50, function() on.on_failed("Authentication failure") end, false)
    end
    function door.switch() end
    function door.stop() end
    return door
  end }
  require("init")
  morf.ipc.given = function() return given end
  morf.ipc.info = function(text) handlers.on_info(text, false) return true end
]]

local function load(style)
  pcall(morf.fs.remove, dir .. "/memory.json")
  test.load("../greet/init.lua", { source = SOURCE, size = { 1368, 912 },
    env = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_PATTY_DIR = dir, GREETD_SOCK = false,
      EVA_GREETER_MEMORY = dir .. "/memory.json" } })
  test.settle(1200)
  test.ipc("stage", "sheet")
  test.settle(900)
end
local function shown(id) return test.find { id = id, visible = true } end
local function centre(id)
  local node = test.get(id)
  return node.x + node.width / 2, node.y + node.height / 2
end

for _, style in ipairs { "tsugumori", "material" } do
  test.describe(style .. " greeter with a pattern", function()
    test.it("shows the grid from <user>.kind and hands the stroke over as the password", function()
      files { ["ada.kind"] = "grid" }
      load(style)
      test.truthy(shown("greet-pattern"), "no grid")
      test.falsy(shown("greet-field"))
      local x, y = centre("greet-pattern-ring-9")
      test.press(x, y)
      for _, n in ipairs { 8, 7, 4 } do test.move(centre("greet-pattern-ring-" .. n)) end
      test.release(centre("greet-pattern-ring-4"))
      test.advance(100)
      test.eq(test.ipc("given"), { "9874" })
      test.eq(test.get("greet-message").text, "Authentication failure", "a wrong pattern says what a wrong password says")
      test.truthy(shown("greet-pattern"), "a wrong pattern leaves the grid")
    end)

    test.it("keeps the password field where only the main file is there", function()
      files { ada = "grid $y$j9T$salt$hash" }
      load(style)
      test.truthy(shown("greet-field"))
      test.falsy(shown("greet-pattern"))
      test.falsy(shown("greet-method"))
      test.type("1236")
      test.key("Return")
      test.advance(100)
      test.eq(test.ipc("given"), { "1236" }, "digits in the password field go as they are")
    end)

    test.it("follows the chosen account", function()
      files { ["ada.kind"] = "grid", ["bob.kind"] = "keypad" }
      load(style)
      test.truthy(shown("greet-pattern"))
      test.key("Escape")
      test.settle(400)
      test.key("Right")
      test.settle(300)
      test.key("Return")
      test.settle(900)
      test.truthy(shown("greet-keypad"), "bob's keypad")
      for _, place in ipairs { 2, 5, 8, 11, 12 } do test.click("greet-pattern-key-" .. place) end
      test.advance(100)
      test.eq(test.ipc("given"), { "2580" })
    end)

    test.it("shows a cue from the stack as a hint", function()
      files { ["ada.kind"] = "grid" }
      load(style)
      test.ipc("info", "Please touch the device.")
      test.eq(test.get("greet-message").text, "Please touch the device.")
    end)
  end)
end
