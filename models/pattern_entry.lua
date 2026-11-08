-- What a login sheet takes for its account: patty's kind, the pattern or the
-- password, and on the lock patty's tries left and lockout, followed to its end.
local morf = require("morf")
local patty = require("lib.shell.auth.patty")

local M = {}

function M.new(options)
  local name = options.name
  local clock = options.clock or morf.time.now
  local timer = options.timer or morf.time.timer
  local self = {
    kind = morf.signal(name .. ".pattern.kind", ""),
    method = morf.signal(name .. ".pattern.method", "password"),
    left = morf.signal(name .. ".pattern.left", patty.TRIES),
    locked = morf.signal(name .. ".pattern.locked", 0),
    trace = require("models.pattern_trace").new(name .. ".pattern"),
  }
  local chose, waiting = false, nil

  local function user() return options.user() or "" end
  local function follow()
    if waiting then waiting:cancel() waiting = nil end
    local left = self.locked:get()
    if left <= 0 then return end
    waiting = timer(1000 * math.min(left, (left - 1) % 60 + 1), function()
      waiting = nil
      self.read()
      if self.locked:get() == 0 and self.kind:get() ~= "" and not chose then self.method:set("pattern") end
    end, false)
  end

  --- Kind and tries, read again.
  function self.read()
    self.kind:set(patty.kind(user(), { kind_only = options.kind_only }) or "")
    if options.fails then
      local fails = patty.fails(user())
      local standing = patty.standing(fails, clock())
      self.left:set(fails and standing.left or -1)
      self.locked:set(standing.locked)
      follow()
    end
  end
  function self.taken() return self.kind:get() ~= "" and self.locked:get() == 0 end
  function self.shown()
    if self.method:get() ~= "pattern" or not self.taken() then return nil end
    return self.kind:get()
  end
  function self.open()
    chose = false
    self.trace.clear()
    self.read()
    self.method:set(self.taken() and "pattern" or "password")
  end
  --- The person's choice: "pattern" or "password".
  function self.use(method)
    chose = method == "password"
    self.trace.clear()
    self.method:set(method == "pattern" and self.taken() and "pattern" or "password")
  end
  --- After a wrong answer: the lockout moves the sheet to the password.
  function self.failed()
    self.read()
    if self.locked:get() > 0 then self.method:set("password") end
  end
  return self
end

return M
