-- eva-qr: the `WIFI:` string, where a password may and may not go, its page, and
-- the command line, all on the shared encoder (lib/util/qr.lua; tests/launcher_tools_spec.lua
-- reads its codes back). A code read back off the screen by a real decoder is
-- tools/see/qr.steps'.
--
--     morf test --no-dbus tests/qr_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local SECRET = "s3cret;pa:ss"

local PIECES = [[
  local morf = require("morf")
  require("morf.ui").Item { width = 1, height = 1 }
  local qr = require("lib.util.qr")
  local model = require("apps.qr.model")
  morf.ipc.wifi = function(ssid, security, password, hidden)
    return qr.wifi({ ssid = ssid, security = security, hidden = hidden == "yes" }, password)
  end
  morf.ipc.saved = function(lines) return model.parse_saved(lines) end
]]

local function fresh(name)
  local state = morf.env("XDG_STATE_HOME") .. "/qr-" .. name .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

local function environment(state, style, extra)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style or "material", font = "" })
  local env = { XDG_STATE_HOME = state, EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule",
    EVA_APPEARANCE = appearance, EVA_DRY_RUN = "1", EVA_TEST_TOOL = "qr", EVA_TEST_PAGE = "488x700" }
  for key, value in pairs(extra or {}) do env[key] = value end
  return env
end

local function pieces()
  test.load("../shell/init.lua", { source = PIECES, env = environment(fresh("pieces")) })
end

local function window(style, args, extra)
  test.clear_stubs()
  test.load("../shell/init.lua", { args = args, env = environment(fresh("window"), style, extra),
    source = morf.fs.read(ROOT .. "tests/fixtures/tool_page.lua") })
  test.settle(300)
end

-- Every argv since load, joined.
local function argv_text()
  local all = {}
  for _, run in ipairs(test.runs()) do all[#all + 1] = table.concat(run, " ") end
  return table.concat(all, "\n")
end

-- A host wrapping morf.process.run, to see every program it starts and what it
-- writes to them.
local function stdin_host()
  test.clear_stubs()
  test.load("../shell/init.lua", { env = environment(fresh("stdin"), nil, { EVA_DRY_RUN = "0" }), source = [[
    local morf = require("morf")
    local fed = {}
    morf.process.run = function(argv, options, done)
      fed[#fed + 1] = { argv = argv, stdin = options and options.stdin }
      done { ok = true, stdout = "####\n####\n" }
    end
  ]] .. morf.fs.read(ROOT .. "tests/fixtures/tool_page.lua") .. [[
    local model = require("apps.qr.model")
    morf.ipc.fed = function() return fed end
    morf.ipc.ssid = function(name) model.mode:set(2) model.ssid:set(name) return true end
    morf.ipc.password = function(value) model.set_password(value) return true end
    morf.ipc.save = function(path) model.save(path) return true end
  ]] })
  test.settle(100)
end

-- ------------------------------------------------------------------ strings --

test.it("writes the WIFI string, escaping what the format reserves", function()
  pieces()
  test.eq(test.ipc("wifi", "home", "WPA", "secret", "no"), "WIFI:T:WPA;S:home;P:secret;;")
  test.eq(test.ipc("wifi", "home", "WEP", "secret", "yes"), "WIFI:T:WEP;S:home;P:secret;H:true;;")
  test.eq(test.ipc("wifi", "cafe", "nopass", "ignored", "no"), "WIFI:T:nopass;S:cafe;;")
  test.eq(test.ipc("wifi", 'a;b,c:d\\e"f', "WPA", 'p;q,r:s\\t"u', "no"),
    'WIFI:T:WPA;S:a\\;b\\,c\\:d\\\\e\\"f;P:p\\;q\\,r\\:s\\\\t\\"u;;')
end)

test.it("reads the saved Wi-Fi networks and leaves the wired ones", function()
  pieces()
  test.eq(test.ipc("saved", "Cafe\\: guest:802-11-wireless\nhome:802-11-wireless\nWired:802-3-ethernet\n"),
    { "Cafe: guest", "home" })
end)

-- ------------------------------------------------------------------ secrets --

test.it("encodes the password in the tool, and no program hears it", function()
  stdin_host()
  test.ipc("ssid", "home")
  test.ipc("password", SECRET)
  test.advance(300)
  test.ne(test.ipc("state").size, 0)
  for _, call in ipairs(test.ipc("fed")) do
    test.falsy(table.concat(call.argv, " "):find("s3cret", 1, true), "never on a command line")
    test.falsy((call.stdin or ""):find("s3cret", 1, true), "never on a program's stdin")
  end
end)

test.it("keeps the password out of its state and off its signals", function()
  stdin_host()
  test.ipc("ssid", "home")
  test.ipc("password", SECRET)
  test.advance(300)
  local state = test.ipc("state")
  test.truthy(state.has_password)
  test.falsy(morf.json.encode(state):find("s3cret", 1, true))
end)

test.it("saves a network's PNG with no program", function()
  stdin_host()
  test.ipc("ssid", "home")
  test.ipc("password", SECRET)
  test.advance(300)
  local out = fresh("save") .. "/deep/out.png"
  local before = #test.ipc("fed")
  test.ipc("save", out)
  test.advance(300)
  test.eq(morf.fs.read(out):sub(2, 4), "PNG")
  test.eq(#test.ipc("fed"), before, "saving ran a program")
end)

test.it("takes a password piped in and lets its file go", function()
  local state = fresh("piped")
  local secret = state .. "/secret"
  morf.fs.write(secret, SECRET .. "\n", { mode = 384 })
  window(nil, { "wifi", "home", "--security", "WEP", "--hidden", "--input", secret })
  local seen = test.ipc("state")
  test.eq(seen.ssid, "home")
  test.eq(seen.security, "WEP")
  test.truthy(seen.hidden)
  test.truthy(seen.has_password)
  test.falsy(morf.fs.exists(secret), "the file is gone once read")
  test.falsy(argv_text():find("s3cret", 1, true))
end)

test.it("fills a saved network's secret into the input, never a signal", function()
  test.clear_stubs()
  test.stub_run("nmcli", { code = 0, stdout = "wpa-psk\n" .. SECRET .. "\nyes\n" })
  test.load("../shell/init.lua", { env = environment(fresh("nm")),
    source = morf.fs.read(ROOT .. "tests/fixtures/tool_page.lua") })
  test.settle(200)
  test.ipc("pick", "home")
  test.advance(300)
  local seen = test.ipc("state")
  test.eq(seen.ssid, "home")
  test.eq(seen.security, "WPA")
  test.truthy(seen.hidden)
  test.truthy(seen.has_password)
  test.falsy(morf.json.encode(seen):find("s3cret", 1, true))
end)

-- ---------------------------------------------------------------- the window --

for _, style in ipairs { "material", "tsugumori" } do
  test.it("makes a code as text is typed, in " .. style, function()
    window(style)
    test.falsy(test.get({ id = "qr-plate" }).visible)
    test.click("qr-text")
    test.type("hello")
    test.advance(300)
    test.settle(100)
    test.eq(test.ipc("state").size, 21)
    test.truthy(test.get({ id = "qr-plate" }).visible)
    test.eq(#test.logs("error"), 0)
  end)

  test.it("shows the code alone over the screen and lets it go, in " .. style, function()
    window(style, { "hello" })
    test.ipc("show", "on")
    test.settle(200)
    test.truthy(test.ipc("state").full)
    test.truthy(test.find { id = "qr-full-plate" })
    test.ipc("show", "off")
    test.settle(200)
    test.falsy(test.ipc("state").full)
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("keeps a whole number of pixels to a module", function()
  window(nil, { "hello" })
  local plate = test.get({ id = "qr-plate-modules" })
  test.eq(plate.width % 21, 0)
  test.truthy(plate.width >= 21)
end)

test.it("holds more at a lower level, and says when a level will not fit", function()
  local function until_state(check)
    return test.wait(function()
      test.advance(5)
      return check(test.ipc("state"))
    end, 8000, "the code did not come")
  end
  window(nil, { string.rep("x", 1500) })
  test.eq(test.ipc("state").level, "M")
  until_state(function(state) return state.size > 0 end)
  test.ipc("level", "4")
  until_state(function(state) return state.size == 0 end)
  test.contains(test.ipc("state").message, "too long")
  test.ipc("level", "1")
  until_state(function(state) return state.size > 0 end)
  test.eq(test.ipc("state").message, "")
end)

test.it("says what is wrong when no code can be made", function()
  window(nil, { string.rep("x", 3000) })
  test.contains(test.ipc("state").message, "too long")
  test.eq(test.ipc("state").size, 0)
end)

test.it("hides what needs no shown network tool", function()
  window()
  test.ipc("wifi", "home")
  test.ipc("security", "3")
  test.settle(300)
  test.eq(test.ipc("state").security, "nopass")
end)

-- ---------------------------------------------------------- the command line --

local function cli(args, env)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/qr-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/qr/cli"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.clear_stubs()
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or ""
end

test.it("opens Tools on text", function()
  test.contains(cli({ "hello", "world" }, { "STUB_UP=1" }), "ipc call tools qr hello world")
end)

test.it("keeps a network's password off the shell's command line", function()
  local calls = cli({ "wifi", "home", "--hidden" }, { "STUB_UP=1" })
  test.contains(calls, "ipc call tools qr wifi home --hidden --input ")
end)

test.it("writes a PNG as a job, and wants a file and a text", function()
  test.contains(cli { "--png", "/tmp/x.png", "hello" }, "qr/app.lua -- --png /tmp/x.png hello")
  test.eq(cli { "--png", "/tmp/x.png" }, "")
end)

test.it("really writes a PNG on a machine with no programs", function()
  test.clear_stubs()
  local state = fresh("real")
  local out = state .. "/code.png"
  local answer = state .. "/answer"
  test.load("../apps/qr/app.lua", { args = { "--png", out, "hello", "world" },
    env = environment(state, nil, { EVA_DRY_RUN = "0", EVA_JOB_OUT = answer, PATH = "/nonexistent" }) })
  test.wait(function()
    test.advance(5)
    return morf.fs.exists(answer)
  end, 5000, "the job answered")
  test.contains(morf.fs.read(answer), "0\n" .. out)
  test.eq((morf.fs.read(out) or ""):sub(2, 4), "PNG")
end)
