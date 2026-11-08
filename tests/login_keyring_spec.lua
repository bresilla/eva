-- The login keyring a pattern login leaves locked: asked for once a session,
-- through the Secret Service, so its prompt comes to eva's dialog. A stand-in
-- bus answers; no keyring is touched.
local test = morf.test
local dir = morf.env("XDG_CACHE_HOME") .. "/login-keyring"

local SOURCE = [[
  local calls, locked = {}, true
  local bus = { call_async = function(name, path, interface, method, arguments, _, done)
    calls[#calls + 1] = method .. " " .. path
    morf.time.timer(1, function()
      if method == "ReadAlias" then done({ "/org/freedesktop/secrets/collection/login" })
      elseif method == "Get" then done({ locked })
      elseif method == "Unlock" then
        calls[#calls] = calls[#calls] .. " " .. arguments[1].signature .. " " .. arguments[1].value[1]
        done({ {}, "/org/freedesktop/secrets/prompt/u1" })
      elseif method == "Prompt" then done(true) end
    end, false)
    return true
  end }
  local said
  morf.ipc.ask = function(user, open)
    locked = open ~= "open"
    return require("lib.services.login_keyring").ask_once { user = user, bus = bus,
      marker = morf.env("SPEC_MARKER"), done = function(what, why) said = what or why end }
  end
  morf.ipc.calls = function() return { calls = calls, said = said } end
]]

local function load()
  pcall(morf.fs.remove, dir .. "/asked")
  test.load("../shell/init.lua", { size = { 40, 40 }, source = SOURCE,
    env = { EVA_PATTY_DIR = dir, SPEC_MARKER = dir .. "/asked" } })
end

test.it("asks gnome-keyring once to unlock a locked keyring, where there is a pattern", function()
  morf.fs.write(dir .. "/ada.kind", "grid\n", { parents = true })
  load()
  test.truthy(test.ipc("ask", "ada"))
  test.advance(50)
  local got = test.ipc("calls")
  test.eq(got.calls, {
    "ReadAlias /org/freedesktop/secrets",
    "Get /org/freedesktop/secrets/collection/login",
    "Unlock /org/freedesktop/secrets ao /org/freedesktop/secrets/collection/login",
    "Prompt /org/freedesktop/secrets/prompt/u1",
  })
  test.eq(got.said, "asked")
  test.falsy(test.ipc("ask", "ada"), "asked a second time in one session")
end)

test.it("leaves an open keyring alone", function()
  morf.fs.write(dir .. "/ada.kind", "grid\n", { parents = true })
  load()
  test.ipc("ask", "ada", "open")
  test.advance(50)
  local got = test.ipc("calls")
  test.eq(#got.calls, 2)
  test.eq(got.said, "open")
end)

test.it("asks nothing for an account with no pattern", function()
  pcall(morf.fs.remove, dir .. "/bob.kind")
  load()
  test.falsy(test.ipc("ask", "bob"))
  test.advance(50)
  test.eq(test.ipc("calls").calls, {})
end)
