-- patty as the screens read it: the kind and the wrong tries from its folder,
-- which digits go on the grid, a stroke over the dots, and the sheet's choice
-- between pattern and password. Stand-in files only; nothing runs patty or PAM.
local test = morf.test
local dir = morf.env("XDG_CACHE_HOME") .. "/patty-spec"

local function put(name, text) morf.fs.write(dir .. "/" .. name, text, { parents = true }) end
local function drop(name) pcall(morf.fs.remove, dir .. "/" .. name) end
local function clean() for _, name in ipairs { "ada", "ada.kind", "ada.fails" } do drop(name) end end

local SOURCE = [[
  local patty = require("lib.shell.auth.patty")
  local trace_model = require("models.pattern_trace")
  morf.ipc.dir = function() return patty.dir() end
  morf.ipc.kind = function(user, only) return patty.kind(user, { kind_only = only == "only" }) or "none" end
  morf.ipc.fails = function(user) return patty.fails(user) or "none" end
  morf.ipc.standing = function(count, until_at, now)
    return patty.standing({ count = count, until_at = until_at }, now)
  end
  morf.ipc.drawable = function(digits)
    local ok, why = patty.drawable(digits)
    return { ok = ok, why = why or "", kind = patty.kind_of(digits), valid = patty.valid(digits) }
  end
  morf.ipc.neighbours = function(a, b) return patty.neighbours(a, b) end
  -- A stroke through the given dot centres on a 300 px grid, as a finger draws it.
  morf.ipc.stroke = function(points)
    local trace = trace_model.new("spec")
    local last
    for _, p in ipairs(points) do
      local x, y = trace_model.centre(p[1], 300)
      x, y = x + (p[2] or 0), y + (p[3] or 0)
      for _, n in ipairs(trace_model.passed(last or { x, y }, { x, y }, 300, 36)) do trace.join(n) end
      last = { x, y }
    end
    return trace.digits()
  end
  local now, armed = 1000, nil
  local entry = require("models.pattern_entry").new { name = "spec", fails = true,
    user = function() return "ada" end, clock = function() return now end,
    timer = function(ms, fn) armed = { ms = ms, fn = fn } return { cancel = function() armed = nil end } end }
  morf.ipc.entry = function(how, value)
    if how == "open" then entry.open()
    elseif how == "use" then entry.use(value)
    elseif how == "failed" then entry.failed()
    elseif how == "clock" then now = value
    elseif how == "fire" and armed then local fn = armed.fn armed = nil fn() end
    return { method = entry.method:get(), kind = entry.kind:get(), shown = entry.shown() or "",
      left = entry.left:get(), locked = entry.locked:get(), armed = armed and armed.ms or 0 }
  end
]]

local function load(env)
  test.load("../lock/init.lua", { size = { 40, 40 }, source = SOURCE, env = env or { EVA_PATTY_DIR = dir } })
end

test.describe("patty's folder", function()
  test.it("is /var/lib/patty unless EVA_PATTY_DIR names another", function()
    load({ EVA_PATTY_DIR = false })
    test.eq(test.ipc("dir"), "/var/lib/patty")
    load()
    test.eq(test.ipc("dir"), dir)
  end)

  test.it("gives the kind from <user>.kind first, then the main file's first word", function()
    clean()
    load()
    test.eq(test.ipc("kind", "ada"), "none", "no files, no pattern")
    put("ada", "keypad $y$j9T$salt$hash\n")
    test.eq(test.ipc("kind", "ada"), "keypad", "the main file alone")
    put("ada.kind", "grid\n")
    test.eq(test.ipc("kind", "ada"), "grid", ".kind is read before the main file")
    put("ada.kind", "nonsense\n")
    test.eq(test.ipc("kind", "ada"), "keypad", "a .kind that says nothing falls back")
  end)

  test.it("a greeter reads only <user>.kind", function()
    clean()
    load()
    put("ada", "grid $y$j9T$salt$hash\n")
    test.eq(test.ipc("kind", "ada", "only"), "none", "the main file is not the greeter's to read")
    put("ada.kind", "keypad\n")
    test.eq(test.ipc("kind", "ada", "only"), "keypad")
  end)

  test.it("refuses names patty would refuse", function()
    clean()
    load()
    put("ada.kind", "grid\n")
    test.eq(test.ipc("kind", "../patty-spec/ada"), "none")
    test.eq(test.ipc("kind", "Ada"), "none")
    test.eq(test.ipc("kind", ""), "none")
  end)

  test.it("reads wrong tries and a lockout, and what is left of them", function()
    clean()
    load()
    test.eq(test.ipc("fails", "ada"), "none")
    put("ada.fails", "2 0\n")
    test.eq(test.ipc("fails", "ada"), { count = 2, until_at = 0 })
    test.eq(test.ipc("standing", 2, 0, 1000), { locked = 0, left = 3, used = 2 })
    test.eq(test.ipc("standing", 0, 1300, 1000), { locked = 300, left = 0, used = 5 }, "a lockout leaves no tries")
    test.eq(test.ipc("standing", 0, 900, 1000), { locked = 0, left = 5, used = 0 }, "a lockout that ended")
  end)
end)

test.describe("the grid", function()
  test.it("takes neighbours, diagonals too, and nothing further", function()
    load()
    test.truthy(test.ipc("neighbours", 1, 2))
    test.truthy(test.ipc("neighbours", 1, 5), "a diagonal")
    test.truthy(test.ipc("neighbours", 6, 8), "the other diagonal")
    test.falsy(test.ipc("neighbours", 1, 3), "a skip")
    test.falsy(test.ipc("neighbours", 1, 6), "a knight's move")
    test.falsy(test.ipc("neighbours", 5, 5), "itself")
    test.falsy(test.ipc("neighbours", 8, 0), "0 is not on the grid")
  end)

  test.it("files digits as patty does", function()
    load()
    for _, digits in ipairs { "12369", "14789", "75321", "1595" } do
      local said = test.ipc("drawable", digits)
      test.eq(said.kind, digits == "1595" and "keypad" or "grid", digits)
    end
    test.eq(test.ipc("drawable", "1593").why, "9 to 3 is not a neighbour")
    test.eq(test.ipc("drawable", "2580").why, "0 is not on the grid")
    test.eq(test.ipc("drawable", "1231").why, "1 is used twice")
    test.falsy(test.ipc("drawable", "125").valid, "three digits are too few")
    test.truthy(test.ipc("drawable", "1254").valid)
    test.falsy(test.ipc("drawable", "12345678901234567").valid, "seventeen are too many")
  end)

  test.it("joins the dots a stroke passes, in order, once each", function()
    load()
    test.eq(test.ipc("stroke", { { 1 }, { 3 } }), "123", "a straight line takes the dot between")
    test.eq(test.ipc("stroke", { { 1 }, { 9 } }), "159", "a diagonal takes the centre")
    test.eq(test.ipc("stroke", { { 1 }, { 3 }, { 6 }, { 5 }, { 4 } }), "123654")
    test.eq(test.ipc("stroke", { { 1 }, { 3 }, { 1 } }), "123", "a dot is never taken twice")
    test.eq(test.ipc("stroke", { { 1 }, { 6, 0, 0 } }), "1", "a dot that is not a neighbour is passed by")
    test.eq(test.ipc("stroke", { { 5, 50, -50 }, { 5, 50, 50 } }), "", "between the dots joins nothing")
  end)
end)

test.describe("the sheet's choice", function()
  test.it("shows the pattern where there is one, and the password at the person's word", function()
    clean()
    load()
    test.eq(test.ipc("entry", "open").shown, "", "no pattern: the password, as before")
    put("ada.kind", "grid\n")
    put("ada.fails", "1 0\n")
    local now = test.ipc("entry", "open")
    test.eq(now.shown, "grid")
    test.eq(now.left, 4)
    test.eq(test.ipc("entry", "use", "password").shown, "")
    test.eq(test.ipc("entry", "use", "pattern").shown, "grid")
  end)

  test.it("moves to the password while locked out, and back once it ends", function()
    clean()
    load()
    put("ada.kind", "keypad\n")
    put("ada.fails", "4 0\n")
    test.eq(test.ipc("entry", "open").shown, "keypad")
    put("ada.fails", "0 1090\n")
    local locked = test.ipc("entry", "failed")
    test.eq(locked.method, "password")
    test.eq(locked.locked, 90)
    test.eq(locked.armed, 30000, "woken when the minute it shows turns over")
    test.ipc("entry", "clock", 1060)
    test.eq(test.ipc("entry", "fire").method, "password", "still locked")
    test.ipc("entry", "clock", 1091)
    local back = test.ipc("entry", "fire")
    test.eq(back.locked, 0)
    test.eq(back.shown, "keypad", "the pattern comes back by itself")
  end)

  test.it("keeps the password when the person chose it, through the lockout's end", function()
    clean()
    load()
    put("ada.kind", "grid\n")
    put("ada.fails", "0 1010\n")
    test.ipc("entry", "open")
    test.ipc("entry", "use", "password")
    test.ipc("entry", "clock", 1011)
    test.eq(test.ipc("entry", "fire").shown, "")
  end)
end)
