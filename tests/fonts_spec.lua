-- The fonts: the family filter and weights shell/fonts_model.lua adds to
-- themes/fonts.lua, setting the font on both paths, Settings' Fonts page and
-- `eva-fonts` as a job. The shell's verb taking it for real is
-- tools/see/fonts.steps'.
--
--     morf test --no-dbus tests/fonts_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local FAMILIES = "Rubik\nNoto Sans\nIBM Plex Mono\nJetBrains Mono\nNoto Serif\n"
local JOB = "../apps/common/job/app.lua"

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

local function saved(state) return morf.json.decode(morf.fs.read(state .. "/appearance.json")) end

-- The model in a tool's place, setting through common/sys.lua as eva-fonts does.
local TOOL = [[
  local morf = require("morf")
  require("morf.ui").Item { width = 1, height = 1 }
  local model = require("fonts_model")
  model.via = require("common.sys")
  morf.ipc.parse = function(lines) return model.parse_weights(lines) end
  morf.ipc.pattern = function(family) return model.pattern(family) end
  morf.ipc.state = function()
    return { shown = model.shown(), chosen = model.chosen:get(), weights = model.weights:get(),
      weight = model.weight:get(), message = model.message:get() }
  end
  morf.ipc.load = function() model.load() return true end
  morf.ipc.mono = function(how) model.set_mono(how == "on") return true end
  morf.ipc.search = function(query) model.search(query) return true end
  morf.ipc.choose = function(family) model.choose(family) return true end
  morf.ipc.apply = function(family)
    local answer
    model.apply(family, function(ok, words) answer = { ok = ok, words = words } end)
    return answer
  end
]]

local function tool(name, source)
  local state = fresh(name)
  test.load(JOB, { source = (source or "") .. TOOL, env = environment(state) })
  test.settle(100)
  return state
end

local function verbs()
  local out = {}
  for _, run in ipairs(test.runs()) do
    if run[1] == "env" then out[#out + 1] = table.concat(run, " "):match("ipc call (.*)$") end
  end
  return out
end

-- ------------------------------------------------------------------- pieces --

test.it("reads weights from fontconfig, a variable font's range too", function()
  tool("pieces")
  test.eq(test.ipc("parse", "80\n200\n80\n"), { 400, 700 })
  test.eq(test.ipc("parse", "50\n180\n"), { 300, 600 })
  test.eq(test.ipc("parse", "[0 200]\n"), { 100, 200, 300, 400, 500, 600, 700 })
  test.eq(test.ipc("parse", ""), {})
  test.eq(test.ipc("pattern", "Plain Name"), ":family=Plain Name")
  test.eq(test.ipc("pattern", "A-B:C,D"), ":family=A\\-B\\:C\\,D")
end)

test.it("lists what themes/fonts.lua lists, and filters to the monospace ones", function()
  stubs { code = 1 }
  tool("list")
  test.ipc("load") test.settle(100)
  test.eq(#test.ipc("state").shown, 5)
  test.clear_stubs()
  test.stub_run("fc-list", { code = 0, stdout = "IBM Plex Mono\nJetBrains Mono\n" })
  test.ipc("mono", "on") test.settle(100)
  test.eq(test.ipc("state").shown, { "IBM Plex Mono", "JetBrains Mono" })
  test.ipc("mono", "off") test.settle(100)
  test.eq(#test.ipc("state").shown, 5)
  test.ipc("search", "noto") test.settle(100)
  test.eq(#test.ipc("state").shown, 2)
end)

test.it("previews a family at its own weights", function()
  stubs { code = 1 }
  tool("weights")
  test.clear_stubs()
  test.stub_run("fc-list", { code = 0, stdout = "50\n200\n" })
  test.ipc("choose", "Rubik") test.settle(100)
  local state = test.ipc("state")
  test.eq(state.chosen, "Rubik")
  test.eq(state.weights, { 300, 700 })
  test.eq(state.weight, 300, "the weight moved to one the family has")
end)

-- ---------------------------------------------------------------- the paths --

test.it("with no shell, writes the file the shell starts from", function()
  stubs { code = 1 }
  local state = tool("down")
  test.ipc("apply", "Rubik") test.settle(200)
  test.eq(saved(state).font, "Rubik")
  test.contains(test.ipc("state").message, "when it starts")
  test.eq(verbs(), { "appearance state" })
end)

-- A shell that answers state and then the font verb, each with its own reply.
local SHELL = [[
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
  morf.ipc.calls = function() return calls end
]]

test.it("asks the running shell through font:NAME and leaves the file to it", function()
  local state = tool("shell", SHELL)
  local answer = test.ipc("apply", "Goku")
  test.truthy(answer.ok)
  test.contains(answer.words, "changing to Goku")
  test.eq(test.ipc("calls"), { "appearance state", "appearance font:Goku" })
  test.eq(saved(state).font, "")
end)

test.it("says why the shell refused", function()
  tool("refused", SHELL)
  local answer = test.ipc("apply", "Refused")
  test.falsy(answer.ok)
  test.contains(answer.words, "Finish the capture")
end)

test.it("does not trouble the shell for the font it already has", function()
  tool("same", SHELL)
  local answer = test.ipc("apply", "Rubik")
  test.contains(answer.words, "already uses")
  test.eq(test.ipc("calls"), { "appearance state" })
end)

test.it("refuses what cannot be a family's name", function()
  tool("bad", SHELL)
  test.falsy(test.ipc("apply", "bad\nname").ok)
  test.eq(test.ipc("calls"), nil)
end)

-- ------------------------------------------------------------ the Fonts page --

local function page(style, size)
  stubs()
  test.stub_run("task", { code = 0, stdout = "[]" })
  local state = fresh("page-" .. style)
  local env = environment(state, style, { EVA_DRY_RUN = "1", EVA_STYLE = style, HOME = morf.env("XDG_CACHE_HOME") })
  test.load("../shell/init.lua", { size = size or { 1600, 1000 }, env = env })
  test.settle(1000)
  test.ipc("settings", "theme/fonts") test.settle(1500)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("picks a family from the kit's picker and previews it, in " .. style, function()
    page(style)
    test.truthy(test.find { id = "fonts-search", visible = true })
    test.clear_stubs()
    test.stub_run("fc-list", { code = 0, stdout = "50\n200\n" })
    test.click("fonts-option-2") test.settle(300)
    local family = test.get({ id = "fonts-family" }).text
    test.falsy(family == "Pick a family", "nothing was picked")
    test.truthy(test.find { id = "fonts-weight-700-box", visible = true })
    test.falsy(test.find { id = "fonts-weight-500-box", visible = true })
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("Theme leads to Fonts, and the Lule picker stays shut", function()
  page("material")
  test.ipc("settings", "theme") test.settle(900)
  test.click("settings-theme-fonts") test.settle(900)
  test.eq(test.ipc("settings", "state").page, "theme/fonts")
  test.falsy(test.find { id = "lule-font-picker", visible = true })
end)

test.it("fits a phone", function()
  page("tsugumori", { 412, 915 })
  local search, pane = test.get("fonts-search"), test.get("settings-detail")
  test.truthy(search.x >= pane.x and search.x + search.width <= pane.x + pane.width)
  test.eq(#test.logs("error"), 0)
end)

-- ---------------------------------------------------------- the command line --

local function job(args, shell)
  local state = fresh("job")
  local out = state .. "/job.out"
  stubs(shell or { code = 1 })
  local words = { "fonts" }
  for _, word in ipairs(args) do words[#words + 1] = word end
  test.load(JOB, { args = words, env = environment(state, nil, { EVA_JOB_OUT = out }) })
  test.advance(400)
  return morf.fs.read(out) or "", state
end

test.it("lists the families", function()
  test.contains(job { "list" }, "0\nIBM Plex Mono\nJetBrains Mono\nNoto Sans\nNoto Serif\nRubik")
end)

test.it("lists the monospace ones alone, the flag reaching the job", function()
  local state = fresh("mono")
  local out = state .. "/job.out"
  test.clear_stubs()
  test.load(JOB, { env = environment(state, nil, { EVA_JOB_OUT = out }), source = [[
      local real = morf.process.run
      morf.process.run = function(argv, options, done)
        if argv[1] ~= "fc-list" then return real(argv, options, done) end
        local mono = argv[2] == ":spacing=mono"
        done { ok = true, stdout = mono and "IBM Plex Mono\n" or "Rubik\nIBM Plex Mono\n" }
      end
      local job = require("lib.util.job")
      job.quiet()
      require("fonts_model").job({ "list", "--mono" }, job.finish, require("common.sys"))
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

local function cli(args, env)
  test.clear_stubs()
  local log = morf.env("XDG_STATE_HOME") .. "/fonts-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. morf.env("XDG_STATE_HOME"), "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR") }
  for _, word in ipairs(env or {}) do argv[#argv + 1] = word end
  argv[#argv + 1] = "sh"
  argv[#argv + 1] = ROOT .. "apps/bin/eva-fonts"
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log)
end

test.it("hands its words to the shell's code as a job", function()
  test.contains(cli { "set", "IBM Plex Mono" }, "apps/common/job/app.lua -- fonts set IBM Plex Mono")
end)

test.it("alone it opens Fonts in the Settings window", function()
  test.contains(cli({}, { "STUB_UP=1" }), "ipc call settings theme/fonts")
end)
