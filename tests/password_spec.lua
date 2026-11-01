-- What the login screens hold while a password is typed, and the lock itself
-- typed into: a Backspace takes back one character whatever its size.
--
--     morf test tests/password_spec.lua

local test = morf.test

local HOST = [[
  local password = require("models.password")
  local p = password.new("spec", 18)
  morf.ipc.add = function(text) return p.add(text) end
  morf.ipc.erase = function() p.erase() end
  morf.ipc.clear = function() p.clear() end
  morf.ipc.empty = function() return p.empty() end
  morf.ipc.take = function() return p.take() end
  morf.ipc.dots = function() return p.typed:get() end
]]

test.it("counts characters, not bytes", function()
  test.load("../lock/init.lua", { source = HOST })
  test.ipc("add", "w") test.ipc("add", "ë")
  test.eq(test.ipc("dots"), 2)
end)

test.it("erases a whole character", function()
  test.load("../lock/init.lua", { source = HOST })
  test.ipc("add", "w") test.ipc("add", "ë")
  test.ipc("erase")
  test.eq(test.ipc("dots"), 1)
  test.eq(test.ipc("take"), "w")
end)

test.it("erases a four-byte character and stops at empty", function()
  test.load("../lock/init.lua", { source = HOST })
  test.ipc("add", "😀")
  test.ipc("erase")
  test.truthy(test.ipc("empty"))
  test.ipc("erase")
  test.eq(test.ipc("dots"), 0)
end)

test.it("caps the dots, not the text", function()
  test.load("../lock/init.lua", { source = HOST })
  for _ = 1, 30 do test.ipc("add", "a") end
  test.eq(test.ipc("dots"), 18)
  test.eq(#test.ipc("take"), 30)
end)

test.it("gives the text once and keeps its dots until cleared", function()
  test.load("../lock/init.lua", { source = HOST })
  test.ipc("add", "a")
  test.eq(test.ipc("take"), "a")
  test.truthy(test.ipc("empty"))
  test.eq(test.ipc("dots"), 1)
  test.ipc("clear")
  test.eq(test.ipc("dots"), 0)
end)

test.it("refuses what would run past the limit", function()
  test.load("../lock/init.lua", { source = HOST })
  for _ = 1, 256 do test.truthy(test.ipc("add", "a")) end
  test.eq(test.ipc("add", "a"), false)
end)

-- Preview refuses only the exact word "wrong", so a stray byte left by the
-- Backspace would open it.
test.it("the lock refuses a word retyped after a corrected accent", function()
  test.load("../lock/init.lua", { args = { "window", "preview" }, env = { EVA_DRY_RUN = "1" } })
  test.advance(600)
  test.ipc("stage", "sheet")
  test.advance(600)
  test.type("wrongë")
  test.key("BackSpace")
  test.key("Return")
  test.advance(900)
  test.eq(test.find("lock-output") ~= nil, true)
  test.eq(test.ipc("stage"), "sheet")
end)
