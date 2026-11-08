-- What the login stacks say on the way to a verdict: the lock's password
-- conversation and the greeter's, against stand-ins for morf.pam and
-- morf.greetd. A cue such as pam_u2f's is a hint, and a second question goes
-- to the person instead of getting the password again.
local test = morf.test

local LOCK = [[
  local sessions = {}
  morf.pam = {
    session = function(service, user)
      local s = { service = service, user = user, answers = {}, cancelled = false }
      function s.on_message(self, fn) self.hear = fn end
      function s.respond(self, answer) self.answers[#self.answers + 1] = answer return true end
      function s.cancel(self) self.cancelled = true end
      sessions[#sessions + 1] = s
      return s
    end,
    authenticate = function() error("the lock asked without a conversation") end,
  }
  local said = {}
  local door = require("lib.shell.auth").lock { user = "ada", listen = false, reader = false,
    on_busy = function(b) said[#said + 1] = "busy " .. tostring(b) end,
    on_hint = function(text, bad) said[#said + 1] = (bad and "error " or "hint ") .. text end,
    on_info = function(text) said[#said + 1] = "reader " .. text end,
    on_prompt = function(text) said[#said + 1] = "asks " .. text end,
    on_failed = function(why) said[#said + 1] = "failed " .. why end,
    on_open = function() said[#said + 1] = "open" end }
  morf.ipc.submit = function(token) door:submit(token) return true end
  morf.ipc.cancel = function() door:cancel() return true end
  morf.ipc.stack = function(kind, text, ok)
    sessions[#sessions].hear({ kind = kind, text = text or "", echo = false,
      ok = ok == "ok", error = ok == "ok" and nil or "Authentication failure" })
    return true
  end
  morf.ipc.state = function()
    local s = sessions[#sessions] or {}
    return { said = said, answers = s.answers or {}, cancelled = s.cancelled == true, sessions = #sessions }
  end
]]

local GREETER = [[
  local logins = {}
  morf.greetd = { converse = function(user)
    local l = { user = user, answers = {} }
    function l.on_message(self, fn) self.hear = fn end
    function l.respond(self, answer) self.answers[#self.answers + 1] = answer == nil and "(nothing)" or answer end
    function l.cancel() end
    function l.start() end
    logins[#logins + 1] = l
    return l
  end }
  local said = {}
  local door = require("lib.shell.auth").greeter { user = "ada", session = { command = { "true" } },
    on_busy = function(b) said[#said + 1] = "busy " .. tostring(b) end,
    on_info = function(text, bad) said[#said + 1] = (bad and "error " or "hint ") .. text end,
    on_prompt = function(text) said[#said + 1] = "asks " .. text end,
    on_failed = function(why) said[#said + 1] = "failed " .. why end }
  door.available = true
  morf.ipc.submit = function(token) door:submit(token) return true end
  morf.ipc.stack = function(kind, text)
    logins[#logins].hear({ kind = "auth", auth_type = kind, text = text or "" })
    return true
  end
  morf.ipc.state = function() return { said = said, answers = (logins[#logins] or {}).answers or {} } end
]]

local function lock()
  test.load("../lock/init.lua", { size = { 40, 40 }, source = LOCK, env = { EVA_DRY_RUN = "1" } })
end

test.describe("the lock's password stack", function()
  test.it("gets the password at its first question, and its cue is a hint", function()
    lock()
    test.ipc("submit", "1236")
    test.ipc("stack", "prompt", "Password: ")
    test.ipc("stack", "info", "Please touch the device.")
    test.ipc("stack", "finished", "", "ok")
    local state = test.ipc("state")
    test.eq(state.answers, { "1236" })
    test.eq(state.said, { "busy true", "hint Please touch the device.", "busy false", "open" })
  end)

  test.it("says what a module's error is, marked as one", function()
    lock()
    test.ipc("submit", "hunter2")
    test.ipc("stack", "prompt", "Password: ")
    test.ipc("stack", "error", "Wrong PIN")
    test.ipc("stack", "finished", "", "no")
    test.eq(test.ipc("state").said, { "busy true", "error Wrong PIN", "busy false", "failed Authentication failure" })
  end)

  test.it("asks the person a second question, and their next submit answers it", function()
    lock()
    test.ipc("submit", "hunter2")
    test.ipc("stack", "prompt", "Password: ")
    test.ipc("stack", "prompt", "Please enter the PIN:")
    local asked = test.ipc("state")
    test.eq(asked.answers, { "hunter2" }, "the password went to the second question too")
    test.eq(asked.said, { "busy true", "busy false", "asks Please enter the PIN:" })
    test.ipc("submit", "4321")
    test.ipc("stack", "finished", "", "ok")
    local state = test.ipc("state")
    test.eq(state.answers, { "hunter2", "4321" })
    test.eq(state.sessions, 1, "the answer started another conversation")
    test.eq(state.said[#state.said], "open")
  end)

  test.it("gives up a question nobody answers", function()
    lock()
    test.ipc("submit", "hunter2")
    test.ipc("stack", "prompt", "Password: ")
    test.ipc("stack", "prompt", "Please enter the PIN:")
    test.ipc("cancel")
    test.truthy(test.ipc("state").cancelled)
    test.ipc("submit", "again")
    test.eq(test.ipc("state").sessions, 2, "after giving up, a submit starts over")
  end)
end)

test.describe("the greeter's stack", function()
  test.it("shows a cue as a hint and answers it with nothing", function()
    test.load("../greet/init.lua", { size = { 40, 40 }, source = GREETER, env = { EVA_DRY_RUN = "1" } })
    test.ipc("submit", "1236")
    test.ipc("stack", "secret", "Password:")
    test.ipc("stack", "info", "Please touch the device.")
    test.ipc("stack", "secret", "Please enter the PIN:")
    local state = test.ipc("state")
    test.eq(state.answers, { "1236", "(nothing)" })
    test.eq(state.said, { "busy true", "hint Please touch the device.", "busy false", "asks Please enter the PIN:" })
  end)
end)
