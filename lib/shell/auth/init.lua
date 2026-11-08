-- The two doors a login screen has, behind one interface: a lock's, asked
-- through PAM, and a greeter's, asked through greetd.
--
--   local auth = require("lib.shell.auth")
--   local door = auth.lock {                -- or auth.greeter { ... }
--     user = "trim",
--     on_busy = function(busy) end,         -- a verdict is being waited on
--     on_info = function(text, bad) end,    -- what the stack says ("touch the reader")
--     on_hint = function(text, bad) end,    -- the lock: what the password's stack says
--     on_prompt = function(text) end,       -- a second question; the next submit answers it
--     on_failed = function(why) end,        -- a wrong answer
--     on_verified = function(start) end,    -- the greeter: the password was right;
--                                           -- call `start` to start the session
--     on_open = function() end,             -- in: lift the lock, or the session starts
--   }
--   door:submit(password)
--   door.session = sessions.list()[1]      -- the greeter: what to start
--   door:switch("someone")                 -- the greeter: another account
--   door:stop()
--
-- The password is an argument, never a signal: signals are named, observable
-- and kept, and a secret wants none of that.
--
-- A lock has two stacks. The password goes to the password stack --
-- `eva-lock` when the machine has one, else `system-auth`, else `login` --
-- and gets its verdict in the time a hash takes. The interactive stack,
-- `login`, is where a machine puts a fingerprint reader or a face: that one is
-- listened to the whole time the lock is up, in a conversation of its own, and
-- whatever it says is passed on. One stack for both would put the reader
-- ahead of the password and wait for a finger before hearing a word.

local morf = require("morf")

local auth = {}

local function noop() end

local function handlers(options)
  return {
    busy = options.on_busy or noop,
    info = options.on_info or noop,
    hint = options.on_hint or options.on_info or noop,
    prompt = options.on_prompt or noop,
    failed = options.on_failed or noop,
    open = options.on_open or noop,
    verified = options.on_verified or function(start) start() end,
  }
end

--- The PAM services a lock uses: the password's, and the reader's (or nil).
---
--- The reader -- a fingerprint, a face -- is listened to on a stack of its
--- own, `/etc/pam.d/eva-lock-reader`, and only when there is one. A stack
--- that goes on to a password after the reader (`login`, `system-auth`)
--- cannot be listened to: when the reader gives up it asks for the password,
--- the listener has none to give, and pam_faillock counts that as a failed
--- login -- a lock listening in a loop locked its own person out in
--- seconds. The reader's stack is the module and nothing to fall through
--- to, e.g.
---
---     auth  sufficient  pam_fprintd.so      (or pam_gaze.so, pam_howdy.so)
---     auth  required    pam_deny.so
---     account include   system-auth
--- The readers a lock can listen to, those this machine has a stack for,
--- in order: `eva-lock-finger` (pam_fprintd), `eva-lock-face` (pam_gaze,
--- pam_howdy) and `eva-lock-reader` (anything else). Each is the module
--- and `pam_deny` after it, as above, so a miss is never a failed login.
function auth.lock_readers()
  local out = {}
  for _, service in ipairs { "eva-lock-finger", "eva-lock-face", "eva-lock-reader" } do
    if morf.fs.exists("/etc/pam.d/" .. service) then out[#out + 1] = service end
  end
  return out
end

function auth.lock_services()
  local password = "login"
  for _, service in ipairs { "eva-lock", "system-auth" } do
    if morf.fs.exists("/etc/pam.d/" .. service) then
      password = service
      break
    end
  end
  local reader = morf.fs.exists("/etc/pam.d/eva-lock-reader") and "eva-lock-reader" or nil
  return password, reader
end

-- ------------------------------------------------------------------ lock --

local Lock = {}
Lock.__index = Lock

--- A lock's door: PAM, for `options.user`. The reader is listened to from
--- the start unless `options.listen` is false; then `door:listen()` and
--- `door:stop()` say when (a lock listens while its way in is open, and a
--- camera is not kept on while the clock is looked at).
function auth.lock(options)
  local password_service = auth.lock_services()
  local readers = options.reader == false and {} or (options.readers or auth.lock_readers())
  local door = setmetatable({
    user = options.user,
    password_service = options.service or password_service,
    readers = readers,
    listening = {}, wanted = {},
    on = handlers(options),
    working = false,
    done = false,
    tries = options.tries or 0, misses = {},
  }, Lock)
  if options.listen ~= false then door:listen() end
  return door
end

-- The password stack, in a conversation: its first question gets the password,
-- what it says on the way ("Please touch the device.") goes to `on_hint`, and a
-- later question goes to the person, whose next submit answers it.
function Lock:submit(password)
  if self.done or not self.user then return end
  if self.asking then
    local session = self.asking
    self.asking, self.working = nil, true
    self.on.busy(true)
    if not session:respond(password or "") then self:verdict(session, false, "No question to answer") end
    return
  end
  if self.working then return end
  self.working = true
  self.on.busy(true)
  local ok, session = pcall(morf.pam.session, self.password_service, self.user)
  if not ok or not session then
    morf.pam.authenticate(self.password_service, self.user, password or "", function(right, why)
      self.working = false
      self.on.busy(false)
      if self.done then return end
      if right then self:finish() else self.on.failed(why or "Wrong password") end
    end)
    return
  end
  local answer = password or ""
  self.talking = session
  session:on_message(function(m)
    if self.talking ~= session then return end
    if m.kind == "prompt" and answer then
      local given = answer
      answer = nil
      session:respond(given)
    elseif m.kind == "prompt" then
      self.asking, self.working = session, false
      self.on.busy(false)
      self.on.prompt(m.text ~= "" and m.text or "Answer needed")
    elseif m.kind == "info" or m.kind == "error" then
      self.on.hint(m.text, m.kind == "error")
    elseif m.kind == "finished" then
      answer = nil
      self:verdict(session, m.ok, m.error)
    end
  end)
end

function Lock:verdict(session, ok, why)
  if self.talking == session then self.talking = nil end
  if self.asking == session then self.asking = nil end
  self.working = false
  self.on.busy(false)
  if self.done then return end
  if ok then self:finish() else self.on.failed(why or "Wrong password") end
end

--- Gives up a question the stack is waiting on.
function Lock:cancel()
  local session = self.asking or self.talking
  if not session or self.working then return end
  self.asking, self.talking = nil, nil
  pcall(function() session:cancel() end)
end

-- The readers' stacks, each heard for as long as it is wanted and the door
-- is shut, all at once: a finger and a face race, and the first yes opens
-- the door. A no starts that reader listening again, since a reader that
-- gave up is not a reader that refused -- after a moment, or after a while
-- when it gave up at once (a reader it cannot reach, a camera in use).
--
-- `door:listen(service)` and `door:stop(service)`; without one, all of them.
local function wants(self, service, fn)
  for _, name in ipairs(self.readers) do
    if service == nil or service == name then fn(name) end
  end
end

function Lock:listen(service)
  wants(self, service, function(name)
    self.wanted[name] = true
    self:hear(name)
  end)
end

function Lock:hear(name)
  if self.listening[name] or self.done or not self.user or not self.wanted[name] then return end
  local ok, session = pcall(morf.pam.session, name, self.user)
  if not ok or not session then return end
  local started = morf.time.now_ms()
  self.listening[name] = session
  session:on_message(function(m)
    if self.listening[name] ~= session then return end
    if m.kind == "info" or m.kind == "error" then
      self.on.info(m.text, m.kind == "error")
    elseif m.kind == "prompt" then
      -- It fell through to asking for a password: that has its own stack.
      session:cancel()
    elseif m.kind == "finished" then
      self.listening[name] = nil
      if m.ok then
        self:finish()
      elseif not self.done and self.wanted[name] then
        local quick = (morf.time.now_ms() - started) < 1000
        -- A reader that answered no, however often it is allowed to.
        if not quick and self.tries > 0 then
          self.misses[name] = (self.misses[name] or 0) + 1
          if self.misses[name] >= self.tries then
            self.wanted[name] = false
            self.on.info("Too many tries. Use your password.", false)
            return
          end
        end
        morf.time.timer(quick and 10000 or 1500, function()
          if self.wanted[name] then self:hear(name) end
        end, false)
      end
    end
  end)
end

function Lock:finish()
  if self.done then return end
  self.done = true
  self:stop()
  self.on.open()
end

function Lock:stop(service)
  wants(self, service, function(name)
    self.wanted[name] = false
    local listening = self.listening[name]
    self.listening[name] = nil
    if listening then pcall(function() listening:cancel() end) end
  end)
end

-- --------------------------------------------------------------- greeter --

local Greeter = {}
Greeter.__index = Greeter

--- A greeter's door: greetd, for `options.user`; `options.session` (from
--- lib.sessions) is what a yes starts. Nested, with no greetd to ask,
--- `door.available` is false and a submit says so.
function auth.greeter(options)
  local door = setmetatable({
    user = options.user,
    session = options.session,
    on = handlers(options),
    available = options.enabled ~= false and (morf.env("GREETD_SOCK") or "") ~= "",
    working = false,
  }, Greeter)
  return door
end

-- Start only for an explicit submission. Opening a greeter, selecting an
-- account or receiving an error must never consume another PAM attempt.
function Greeter:begin()
  if self.login or not self.user or not self.available then return end
  local ok, login = pcall(morf.greetd.converse, self.user)
  if not ok or not login then return end
  self.login, self.wanting, self.held, self.started = login, false, nil, false
  login:on_message(function(m)
    if self.login ~= login then return end
    if m.kind == "auth" then
      if m.auth_type == "secret" or m.auth_type == "visible" then
        if self.held then
          local answer = self.held
          self.held = nil
          login:respond(answer)
        else
          -- A second question: the person answers it, not the password.
          self.wanting, self.working = true, false
          self.on.busy(false)
          self.on.prompt(m.text ~= "" and m.text or "Answer needed")
        end
      else
        self.on.info(m.text, m.auth_type == "error")
        login:respond(nil)
      end
    elseif m.kind == "success" then
      if self.started then
        self.on.open()
        return
      end
      local session = self.session
      if not session then
        self:fail("No session to start")
        return
      end
      self.started = true
      self.on.verified(function()
        if self.login == login then login:start(session.command, session.environment) end
      end)
    elseif m.kind == "error" or m.kind == "failed" then
      self:fail(m.text ~= "" and m.text or "Authentication connection failed")
    end
  end)
end

function Greeter:fail(why)
  self:stop()
  self.on.failed(why)
end

function Greeter:submit(password)
  if self.working or not self.user or not password or password == "" then return end
  if not self.available then
    self.on.failed("No greetd to ask (not started by greetd)")
    return
  end
  if not self.login then self:begin() end
  if not self.login then
    self.on.failed("Cannot reach the login service")
    return
  end
  self.working = true
  self.on.busy(true)
  if self.wanting then
    self.wanting = false
    self.login:respond(password or "")
  else
    self.held = password or ""
  end
end

--- Another account: cancel the old conversation; wait for a submission.
function Greeter:switch(user)
  if user == self.user then return end
  self:stop()
  self.user = user
end

function Greeter:stop()
  local login = self.login
  -- Detach first: late callbacks from cancellation cannot start a session.
  self.login, self.wanting, self.held, self.started = nil, false, nil, false
  self.working = false
  if login then pcall(function() login:cancel() end) end
  self.on.busy(false)
end

-- ------------------------------------------------------------------ power --

--- Asks logind to "Suspend", "Reboot" or "PowerOff". Not interactive: a
--- login screen has nobody to answer a polkit prompt. True, or nil and why.
function auth.power(method)
  local dbus = morf.dbus
  if not dbus then return nil, "cannot reach logind" end
  local ok, manager = pcall(dbus.proxy, "system", "org.freedesktop.login1",
    "/org/freedesktop/login1", "org.freedesktop.login1.Manager")
  if not (ok and manager) then return nil, "cannot reach logind" end
  local called, err = pcall(manager.call_with, manager, method, false)
  if not called then return nil, tostring(err) end
  return true
end

return auth
