-- eva-keys: the compositor's bindings and the shell's as one list, spelled and
-- searched. hyprctl is stubbed.
--
--     morf test --no-dbus tests/keys_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local ENV = { EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule" }

local function tool(result)
  test.stub_run("hyprctl", result)
  test.load("../apps/keys/app.lua", { env = ENV })
  test.settle(300)
end

local function live() return { code = 0, stdout = morf.fs.read(ROOT .. "tests/fixtures/binds.json") } end

test.it("merges the live bindings with the shell's", function()
  tool(live())
  local state = test.ipc("state")
  test.truthy(state.rows > 10)
  test.eq(#test.logs("error"), 0)
end)

test.it("spells a chord and says what it does", function()
  tool(live())
  test.ipc("search", "killactive")
  test.eq(test.ipc("state").found, 0)
  test.ipc("search", "close the window")
  test.settle(100)
  test.eq(test.get({ id = "keys-row-1-keys" }).text, "SUPER + SHIFT + Q")
  test.eq(test.get({ id = "keys-row-1-what" }).text, "Close the window")
  test.ipc("search", "workspace 1")
  test.settle(100)
  test.eq(test.get({ id = "keys-row-1-what" }).text, "workspace 1")
end)

test.it("searches every word, in either column", function()
  tool(live())
  test.eq(test.ipc("search", "alt fullscreen"), 1)
  test.eq(test.ipc("search", "print capture"), 1)
  test.eq(test.ipc("search", "no such thing"), 0)
end)

test.it("spells the shell's own shortcuts alike", function()
  tool(live())
  test.ipc("search", "calendar")
  test.settle(100)
  test.eq(test.get({ id = "keys-row-1-keys" }).text, "CTRL + SHIFT + C")
end)

test.it("still lists the shell's own where the compositor cannot answer", function()
  tool { code = 1 }
  local state = test.ipc("state")
  test.truthy(state.rows > 5)
  test.contains(state.message, "cannot be read")
end)
