-- eva-fonts: the family filter and weights it adds to themes/fonts.lua, setting
-- the font on both paths, the window and the command line. The shell's verb
-- taking it for real is tools/see/fonts.steps'.
--
--     morf test --no-dbus tests/fonts_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local FAMILIES = "Rubik\nNoto Sans\nIBM Plex Mono\nJetBrains Mono\nNoto Serif\n"

local function fresh(name)
  local state = morf.env("XDG_STATE_HOME") .. "/fonts-" .. name .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

-- Answers fc-list as a machine with these families would.
local function stubs(shell)
  test.clear_stubs()
  test.stub_run("fc-list", { code = 0, stdout = FAMILIES })
  if shell then test.stub_run("env", shell) end
end

local function environment(state, style, extra)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style or "material", font = "" })
  local env = { XDG_STATE_HOME = state, EVA_DRY_RUN = "0", EVA_SETTINGS = "/nonexistent/eva.json",
    LULE_A = "/nonexistent/lule", EVA_APPEARANCE = appearance }
  for key, value in pairs(extra or {}) do env[key] = value end
  return env
end

local function window(name, style, shell)
  local state = fresh(name)
  stubs(shell or { code = 1 })
  test.load("../apps/fonts/app.lua", { env = environment(state, style) })
  test.settle(400)
  return state
end

local function saved(state) return morf.json.decode(morf.fs.read(state .. "/appearance.json")) end

local function verbs()
  local out = {}
  for _, run in ipairs(test.runs()) do
    if run[1] == "env" then out[#out + 1] = table.concat(run, " "):match("ipc call (.*)$") end
  end
  return out
end

-- ------------------------------------------------------------------- pieces --

test.it("reads weights from fontconfig, a variable font's range too", function()
  test.load("../apps/fonts/app.lua", { source = [[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local model = require("model")
    morf.ipc.parse = function(lines) return model.parse_weights(lines) end
    morf.ipc.pattern = function(family) return model.pattern(family) end
    morf.ipc.nearest = function(...) return model.nearest({ ... }) end
  ]], env = environment(fresh("pieces")) })
  test.eq(test.ipc("parse", "80\n200\n80\n"), { 400, 700 })
  test.eq(test.ipc("parse", "50\n180\n"), { 300, 600 })
  test.eq(test.ipc("parse", "[0 200]\n"), { 100, 200, 300, 400, 500, 600, 700 })
  test.eq(test.ipc("parse", ""), {})
  test.eq(test.ipc("pattern", "Plain Name"), ":family=Plain Name")
  test.eq(test.ipc("pattern", "A-B:C,D"), ":family=A\\-B\\:C\\,D")
end)

-- ---------------------------------------------------------------- browsing --

test.it("lists what themes/fonts.lua lists, and filters to the monospace ones", function()
  window("list")
  local state = test.ipc("state")
  test.eq(#state.shown, 5)
  test.clear_stubs()
  test.stub_run("fc-list", { code = 0, stdout = "IBM Plex Mono\nJetBrains Mono\n" })
  test.ipc("mono", "on")
  test.settle(100)
  test.eq(test.ipc("state").shown, { "IBM Plex Mono", "JetBrains Mono" })
  test.ipc("mono", "off")
  test.settle(100)
  test.eq(#test.ipc("state").shown, 5)
  test.ipc("search", "noto")
  test.settle(100)
  test.eq(#test.ipc("state").shown, 2)
end)

test.it("previews a family at its own weights", function()
  window("preview")
  test.clear_stubs()
  test.stub_run("fc-list", { code = 0, stdout = "50\n200\n" })
  test.ipc("choose", "Rubik")
  test.settle(100)
  local state = test.ipc("state")
  test.eq(state.chosen, "Rubik")
  test.eq(state.weights, { 300, 700 })
  test.eq(state.weight, 300, "the weight moved to one the family has")
  test.contains(test.get({ id = "fonts-family" }).text, "Rubik")
  test.truthy(test.get({ id = "fonts-weight-700-box" }).visible)
  test.falsy(test.get({ id = "fonts-weight-500-box" }).visible)
  test.ipc("size", "6")
  test.ipc("weight", "700")
  test.settle(100)
  test.eq(test.ipc("state").size, 72)
  test.contains(test.get({ id = "fonts-family" }).text, "72 px · weight 700")
end)

test.it("a restored family comes back with its weights", function()
  test.clear_stubs()
  test.stub_run("fc-list", { code = 0, stdout = "80\n200\n" })
  test.load("../apps/fonts/app.lua", { env = environment(fresh("restore")), source = [[
    local morf = require("morf")
    require("morf.ui").Item { width = 1, height = 1 }
    local model = require("model")
    model.choose("Rubik")
    morf.ipc.again = function()
      model.chosen:set("")
      model.weights:set({})
      model.restore()
      return true
    end
    morf.ipc.seen = function() return { chosen = model.chosen:get(), weights = model.weights:get() } end
  ]] })
  test.settle(100)
  test.ipc("again")
  test.settle(100)
  test.eq(test.ipc("seen"), { chosen = "Rubik", weights = { 400, 700 } })
end)

-- ---------------------------------------------------------------- the paths --

test.it("with no shell, writes the file the shell starts from", function()
  local state = window("down")
  test.ipc("apply", "Rubik")
  test.settle(200)
  test.eq(saved(state).font, "Rubik")
  test.contains(test.ipc("state").message, "when it starts")
  test.eq(verbs(), { "appearance state" })
end)

-- A shell that answers state and then the font verb, each with its own reply.
local SHELL = [[
  local morf = require("morf")
  local real = morf.process.run
  morf.process.run = function(argv, options, done)
    local line = table.concat(argv, " ")
    if line:find("ipc call", 1, true) then
      local reply = '{"n":1,"ok":true,"result":["{\\"font\\":\\"Rubik\\",\\"message\\":\\"Finish the capture before changing theme.\\"}"]}'
      if line:find("font:Goku", 1, true) then reply = '{"n":1,"ok":true,"result":[true]}' end
      if line:find("font:Refused", 1, true) then reply = '{"n":1,"ok":true,"result":[false]}' end
      calls = calls or {}
      calls[#calls + 1] = line:match("ipc call (.*)$")
      done { ok = true, stdout = reply }
      return
    end
    return real(argv, options, done)
  end
  require("morf.ui").Item { width = 1, height = 1 }
  local model = require("model")
  morf.ipc.apply = function(family)
    local answer
    model.apply(family, function(ok, words) answer = { ok = ok, words = words } end)
    return answer
  end
  morf.ipc.calls = function() return calls end
]]

local function shell_host()
  local state = fresh("shell")
  test.load("../apps/fonts/app.lua", { source = SHELL, env = environment(state) })
  return state
end

test.it("asks the running shell through font:NAME and leaves the file to it", function()
  local state = shell_host()
  local answer = test.ipc("apply", "Goku")
  test.truthy(answer.ok)
  test.contains(answer.words, "changing to Goku")
  test.eq(test.ipc("calls"), { "appearance state", "appearance font:Goku" })
  test.eq(saved(state).font, "")
end)

test.it("says why the shell refused", function()
  shell_host()
  local answer = test.ipc("apply", "Refused")
  test.falsy(answer.ok)
  test.contains(answer.words, "Finish the capture")
end)

test.it("does not trouble the shell for the font it already has", function()
  shell_host()
  local answer = test.ipc("apply", "Rubik")
  test.contains(answer.words, "already uses")
  test.eq(test.ipc("calls"), { "appearance state" })
end)

test.it("refuses what cannot be a family's name", function()
  shell_host()
  test.falsy(test.ipc("apply", "bad\nname").ok)
  test.eq(test.ipc("calls"), nil)
end)

-- ---------------------------------------------------------------- the window --

for _, style in ipairs { "material", "tsugumori" } do
  test.it("picks a family from the kit's picker, in " .. style, function()
    window("pick-" .. style, style)
    test.truthy(test.find { id = "fonts-search" })
    test.click("fonts-option-2")
    test.settle(300)
    test.ne(test.ipc("state").chosen, "")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("makes the picker again at a new size", function()
  window("resize")
  local before = test.get({ id = "fonts-search" }).width
  test.resize_window("Fonts", 420, 700)
  test.advance(300)
  test.settle(200)
  test.ne(test.get({ id = "fonts-search" }).width, before, "the search follows the window's new layout")
  test.eq(#test.logs("error"), 0)
end)

-- ---------------------------------------------------------- the command line --

local function job(args, shell)
  local state = fresh("job")
  local out = state .. "/job.out"
  stubs(shell or { code = 1 })
  test.load("../apps/fonts/app.lua", { args = args, env = environment(state, nil, { EVA_JOB_OUT = out }) })
  test.advance(400)
  return morf.fs.read(out) or "", state
end

test.it("lists the families", function()
  test.contains(job { "list" }, "0\nIBM Plex Mono\nJetBrains Mono\nNoto Sans\nNoto Serif\nRubik")
end)

test.it("lists the monospace ones alone, the flag reaching the tool", function()
  local state = fresh("mono")
  local out = state .. "/job.out"
  test.clear_stubs()
  test.load("../apps/fonts/app.lua", { env = environment(state, nil, { EVA_JOB_OUT = out }), args = { "list", "--mono" },
    source = [[
      local morf = require("morf")
      local real = morf.process.run
      morf.process.run = function(argv, options, done)
        if argv[1] ~= "fc-list" then return real(argv, options, done) end
        local mono = argv[2] == ":spacing=mono"
        done { ok = true, stdout = mono and "IBM Plex Mono\n" or "Rubik\nIBM Plex Mono\n" }
      end
      require("common.frame").quiet()
      require("model").job(morf.args, require("lib.shell.tool_job").finish)
    ]] })
  test.advance(400)
  test.eq(morf.fs.read(out), "0\nIBM Plex Mono\n")
end)

test.it("sets a family it has, and refuses one it has not", function()
  local answer, state = job { "set", "IBM", "Plex", "Mono" }
  test.contains(answer, "Saved IBM Plex Mono")
  test.eq(saved(state).font, "IBM Plex Mono")
  test.contains(job { "set", "Atlantis" }, "1\nNo family called Atlantis")
end)

test.it("says the font in use, and goes back to the theme's", function()
  test.contains(job { "current" }, "the theme's own font")
  test.contains(job { "reset" }, "Saved the theme's own font")
end)

test.it("hands its words to the tool as a job", function()
  test.clear_stubs()
  local log = morf.env("XDG_STATE_HOME") .. "/fonts-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. morf.env("XDG_STATE_HOME"), "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"),
    "sh", ROOT .. "apps/fonts/cli", "set", "IBM Plex Mono")
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  test.contains(morf.fs.read(log), "fonts/app.lua -- set IBM Plex Mono")
end)
