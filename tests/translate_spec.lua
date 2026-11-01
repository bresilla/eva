-- eva-translate: reading each engine's answer, the order and the chooser, that
-- text leaves only on a press and only ever on stdin, the window and the command
-- line. Every engine here is a stand-in, as in tools/see/translate.steps.
--
--     morf test --no-dbus tests/translate_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"

local function fresh(name)
  local state = morf.env("XDG_STATE_HOME") .. "/translate-" .. name .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(state)
  return state
end

-- A PATH holding only stand-ins named `programs`.
local function with_programs(state, programs)
  local dir = state .. "/bin"
  morf.fs.mkdir(dir)
  for _, name in ipairs(programs) do morf.fs.write(dir .. "/" .. name, "") end
  return dir
end

local function environment(state, style, programs, extra)
  local appearance = state .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style or "material", font = "" })
  local env = { XDG_STATE_HOME = state, EVA_SETTINGS = "/nonexistent/eva.json", LULE_A = "/nonexistent/lule",
    EVA_APPEARANCE = appearance, EVA_DRY_RUN = "0", PATH = with_programs(state, programs or {}), LANG = "fr_FR.UTF-8" }
  for key, value in pairs(extra or {}) do env[key] = value end
  return env
end

-- The tool with the web replaced: `web` is what MyMemory answers, and every url
-- asked for is kept, for `calls`.
local function host(web)
  return ([[
    local morf = require("morf")
    local engines = require("lib.services.translate")
    local answer = %q
    local asked = {}
    engines.http = {
      query = morf.http.query,
      get = function(url, options, done)
        asked[#asked + 1] = url
        done { ok = answer ~= "down", status = 200, error = "no route", json = function() return morf.json.decode(answer) end }
      end,
    }
    morf.ipc.calls = function() return asked end
    morf.ipc.read_trans = function(out, err, code)
      local words, why = engines.read_trans { ok = code == "0", stdout = out, stderr = err }
      return { words = words, why = why }
    end
    morf.ipc.mymemory = function(words) return engines.read_mymemory { responseStatus = 200, responseData = { translatedText = words } } end
    local frame = require("common.frame")
    local model = require("model")
    local view = require("view")
    model.load()
    frame.open { id = "translate", title = "Translate", width = 640, height = 760, build = function(w, h) return view.build(w, h) end }
    morf.ipc.state = function()
      local engine = model.current()
      return { input = model.input:get(), output = model.output:get(), source = model.source:get(), target = model.target:get(),
        engine = engine and engine.id or "", privacy = model.privacy(), message = model.message:get(),
        detected = model.detected:get() }
    end
    morf.ipc.input = function(...) model.input:set(table.concat({ ... }, " ")) return true end
    morf.ipc.engine = function(id) model.set_engine(id) return true end
    morf.ipc.source = function(code) model.set_source(code) return true end
    morf.ipc.target = function(code) model.set_target(code) return true end
    morf.ipc.go = function() return model.translate() end
    morf.ipc.swap = function() model.swap() return true end
  ]]):format(web)
end

local GOOD = '{"responseStatus":200,"responseData":{"translatedText":"guten Tag &amp; so","detectedLanguage":"en"},"quotaFinished":false}'

local function window(options)
  options = options or {}
  test.clear_stubs()
  if options.argos then test.stub_run("argos-translate", options.argos) end
  local state = fresh("host")
  test.load("../apps/translate/app.lua", { source = host(options.web or GOOD),
    env = environment(state, options.style, options.programs) })
  test.settle(200)
  return state
end

-- ------------------------------------------------------------- what they say --

test.it("takes translate-shell's words, and its quiet refusals as refusals", function()
  window()
  test.eq(test.ipc("read_trans", "Guten Morgen\n", "", "0").words, "Guten Morgen")
  local bad = test.ipc("read_trans", "hello\n", "\27[33m[WARNING] Unknown target language code: zzz\27[0m\n", "0")
  test.eq(bad.words, nil)
  test.contains(bad.why, "Unknown target language")
  test.contains(test.ipc("read_trans", "", "[ERROR] Null response.\n", "0").why, "Null response")
end)

test.it("gives Argos's reason, without its usage", function()
  window { programs = { "argos-translate" }, argos = { code = 2, stdout = "",
    stderr = "usage: argos-translate [-h] [TEXT]\nargos-translate: error: 'en' is not an installed language.\n" } }
  test.ipc("source", "en")
  test.ipc("input", "hello")
  test.ipc("go")
  test.settle(100)
  test.eq(test.ipc("state").message, "'en' is not an installed language.")
end)

test.it("turns the entities a web answer writes back into text", function()
  window()
  test.eq(test.ipc("mymemory", "it&#39;s &amp; &quot;so&quot; &lt;ok&gt; &unknown;"), [[it's & "so" <ok> &unknown;]])
end)

test.it("reads MyMemory's refusals, which arrive in the translation's own field", function()
  window { web = [[{"responseStatus":403,"responseDetails":"","responseData":{"translatedText":"'XX' IS AN INVALID TARGET LANGUAGE"}}]] }
  test.ipc("input", "hello")
  test.ipc("go")
  test.settle(100)
  test.eq(test.ipc("state").output, "")
  test.contains(test.ipc("state").message, "INVALID TARGET")
end)

test.it("says when MyMemory's free limit is spent", function()
  window { web = '{"responseStatus":200,"quotaFinished":true,"responseData":{"translatedText":"MYMEMORY WARNING"}}' }
  test.ipc("input", "hello")
  test.ipc("go")
  test.settle(100)
  test.eq(test.ipc("state").output, "")
  test.contains(test.ipc("state").message, "limit")
end)

test.it("says when the network does not answer", function()
  window { web = "down" }
  test.ipc("input", "hello")
  test.ipc("go")
  test.settle(100)
  test.eq(test.ipc("state").message, "no route")
end)

-- ---------------------------------------------------------------- the engines --

test.it("takes what is on this machine first, and names it offline", function()
  window { programs = { "argos-translate", "trans" } }
  local state = test.ipc("state")
  test.eq(state.engine, "argos")
  test.contains(state.privacy, "Offline: Argos Translate")
  test.contains(state.privacy, "stays on this machine")
end)

test.it("runs Argos with the splitter that needs no network, the text on stdin", function()
  local state = fresh("argos")
  test.clear_stubs()
  test.load("../apps/translate/app.lua", { env = environment(state, nil, { "argos-translate" }), source = [[
    local morf = require("morf")
    local fed = {}
    morf.process.run = function(argv, options, done)
      fed[#fed + 1] = { argv = argv, stdin = options.stdin, env = options.env }
      done { ok = true, stdout = "Hallo\n", stderr = "" }
    end
    require("morf.ui").Item { width = 1, height = 1 }
    local model = require("model")
    model.load()
    morf.ipc.go = function()
      model.input:set("private words")
      model.set_source("en")
      model.set_target("de")
      model.translate()
      return fed[1]
    end
  ]] })
  local call = test.ipc("go")
  test.eq(call.argv, { "argos-translate", "--from-lang", "en", "--to-lang", "de" })
  test.eq(call.stdin, "private words")
  test.eq(call.env.ARGOS_CHUNK_TYPE, "MINISBD")
end)

test.it("says what Argos needs when it has never had the network", function()
  window { programs = { "argos-translate" }, argos = { code = 1, stdout = "",
    stderr = "Traceback\nurllib.error.URLError: <urlopen error [Errno 101]>\n" } }
  test.ipc("source", "en")
  test.ipc("input", "hello")
  test.ipc("go")
  test.settle(100)
  test.contains(test.ipc("state").message, "needs the network once")
end)

test.it("falls to an online engine and says that it is one", function()
  window { programs = { "trans" } }
  test.eq(test.ipc("state").engine, "trans")
  test.contains(test.ipc("state").privacy, "Online: Send gives your text to translate-shell")
  window()
  test.eq(test.ipc("state").engine, "mymemory")
  test.contains(test.ipc("state").privacy, "Online: Send gives your text to MyMemory")
end)

test.it("keeps the engine chosen, and leaves it when it is gone", function()
  local state = window { programs = { "argos-translate", "trans" } }
  test.ipc("engine", "mymemory")
  test.load("../apps/translate/app.lua", { source = host(GOOD), env = environment(state, nil, { "argos-translate" }) })
  test.settle(100)
  test.eq(test.ipc("state").engine, "mymemory")
  test.ipc("engine", "trans")
  morf.fs.remove(state .. "/bin/trans")
  test.load("../apps/translate/app.lua", { source = host(GOOD), env = environment(state, nil, { "argos-translate" }) })
  test.settle(100)
  test.eq(test.ipc("state").engine, "argos", "translate-shell went: the first there is")
end)

test.it("takes the session's language for a first target", function()
  window()
  test.eq(test.ipc("state").target, "fr")
end)

-- ----------------------------------------------------------- what leaves here --

test.it("sends nothing until the press", function()
  window()
  test.click("translate-input")
  test.type("private words")
  test.settle(300)
  test.advance(5000)
  test.eq(test.ipc("calls"), {}, "typing sends nothing")
  test.click("translate-go")
  test.settle(200)
  test.eq(#test.ipc("calls"), 1, "the press sends it once")
  test.contains(test.ipc("calls")[1], "api.mymemory.translated.net")
  test.contains(test.ipc("state").output, "guten Tag & so")
end)

test.it("sends text to a program on stdin, never on its command line", function()
  local state = fresh("stdin")
  test.clear_stubs()
  test.load("../apps/translate/app.lua", { env = environment(state, nil, { "trans" }), source = [[
    local morf = require("morf")
    local fed = {}
    morf.process.run = function(argv, options, done)
      fed[#fed + 1] = { argv = argv, stdin = options and options.stdin }
      done { ok = true, stdout = "Hallo\n", stderr = "" }
    end
    require("morf.ui").Item { width = 1, height = 1 }
    local model = require("model")
    model.load()
    morf.ipc.go = function(text)
      model.input:set(text)
      model.set_target("de")
      model.translate()
      return fed
    end
  ]] })
  local fed = test.ipc("go", "private words")
  test.eq(fed[1].argv, { "trans", "-b", "-no-ansi", ":de" })
  test.eq(fed[1].stdin, "private words")
end)

test.it("keeps no text on disk", function()
  local state = window()
  test.ipc("input", "private words")
  test.ipc("target", "de")
  test.ipc("go")
  test.settle(100)
  test.falsy(morf.fs.read(state .. "/eva/translate/prefs.json"):find("private", 1, true))
end)

test.it("refuses what the engine cannot take, before it leaves", function()
  window()
  test.ipc("input", ("x"):rep(501))
  test.falsy(test.ipc("go"))
  test.contains(test.ipc("state").message, "500 bytes")
  test.ipc("input", "   ")
  test.falsy(test.ipc("go"))
  test.eq(test.ipc("calls"), {})
end)

test.it("asks for the source language where the engine cannot find it", function()
  test.clear_stubs()
  test.stub_run("argos-translate", { code = 0, stdout = "Hallo\n" })
  window { programs = { "argos-translate" } }
  test.ipc("source", "auto")
  test.ipc("input", "hello")
  test.falsy(test.ipc("go"))
  test.contains(test.ipc("state").message, "needs the source language")
end)

-- ---------------------------------------------------------------- the window --

test.it("swaps the languages and the texts", function()
  window()
  test.ipc("source", "en")
  test.ipc("target", "de")
  test.ipc("input", "hello")
  test.ipc("go")
  test.settle(100)
  test.ipc("swap")
  local state = test.ipc("state")
  test.eq(state.source, "de")
  test.eq(state.target, "en")
  test.contains(state.input, "guten Tag")
  test.eq(state.output, "")
end)

test.it("a swap from Detect takes the language that was found", function()
  window()
  test.ipc("source", "auto")
  test.ipc("target", "de")
  test.ipc("input", "hello")
  test.ipc("go")
  test.settle(100)
  test.eq(test.ipc("state").detected, "en")
  test.ipc("swap")
  test.eq(test.ipc("state").target, "en")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it("names the engine under its button, in " .. style, function()
    window { style = style }
    test.contains(test.get({ id = "translate-privacy" }).text, "MyMemory")
    test.eq(#test.logs("error"), 0)
    window { style = style, programs = { "argos-translate" } }
    test.contains(test.get({ id = "translate-privacy" }).text, "Offline")
    test.eq(#test.logs("error"), 0)
  end)
end

-- ---------------------------------------------------------- the command line --

local function job(args, programs, extra)
  local state = fresh("job")
  local out = state .. "/job.out"
  test.load("../apps/translate/app.lua", { args = args,
    env = environment(state, nil, programs, { EVA_JOB_OUT = out, table.unpack(extra or {}) }) })
  test.advance(300)
  return morf.fs.read(out) or ""
end

test.it("translates by an engine named on the command line", function()
  test.clear_stubs()
  test.stub_run("trans", { code = 0, stdout = "Hallo\n", stderr = "" })
  test.eq(job({ "-e", "trans", "-t", "de", "hello", "there" }, { "trans" }), "0\nHallo\n")
  local argv = test.runs()[#test.runs()]
  test.eq(argv, { "trans", "-b", "-no-ansi", ":de" })
end)

test.it("detects the language on the command line, whatever the window last chose", function()
  test.clear_stubs()
  test.stub_run("trans", { code = 0, stdout = "Hallo\n", stderr = "" })
  local state = fresh("saved-source")
  local out = state .. "/job.out"
  morf.fs.write(state .. "/eva/translate/prefs.json", morf.json.encode { source = "fr", target = "de" }, { parents = true })
  test.load("../apps/translate/app.lua", { args = { "-e", "trans", "hello" },
    env = environment(state, nil, { "trans" }, { EVA_JOB_OUT = out }) })
  test.advance(300)
  test.eq(test.runs()[#test.runs()], { "trans", "-b", "-no-ansi", ":de" })
end)

test.it("keeps the window's source where the engine cannot detect one", function()
  test.clear_stubs()
  test.stub_run("argos-translate", { code = 0, stdout = "Hallo\n", stderr = "" })
  local state = fresh("argos-source")
  local out = state .. "/job.out"
  morf.fs.write(state .. "/eva/translate/prefs.json", morf.json.encode { source = "en", target = "de" }, { parents = true })
  test.load("../apps/translate/app.lua", { args = { "hello" },
    env = environment(state, nil, { "argos-translate" }, { EVA_JOB_OUT = out }) })
  test.advance(300)
  test.eq(test.runs()[#test.runs()], { "argos-translate", "--from-lang", "en", "--to-lang", "de" })
end)

test.it("refuses an engine this machine has not", function()
  test.clear_stubs()
  test.contains(job({ "-e", "argos", "hello" }, {}), "1\nNo engine argos here")
end)

test.it("lists the engines here", function()
  test.clear_stubs()
  local answer = job({ "engines" }, { "argos-translate" })
  test.contains(answer, "Argos Translate (offline)")
  test.contains(answer, "MyMemory (online)")
  test.falsy(answer:find("translate-shell", 1, true))
end)

test.it("translates the clipboard", function()
  test.clear_stubs()
  test.stub_run("wl-paste", { code = 0, stdout = "from the clipboard" })
  test.stub_run("trans", { code = 0, stdout = "aus der Zwischenablage\n", stderr = "" })
  test.eq(job({ "-e", "trans", "--clipboard" }, { "trans" }), "0\naus der Zwischenablage\n")
end)

test.it("hands its words to the tool as a job", function()
  test.clear_stubs()
  local log = morf.env("XDG_STATE_HOME") .. "/translate-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. morf.env("XDG_STATE_HOME"), "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"),
    "sh", ROOT .. "apps/translate/cli", "-t", "de", "hello")
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  test.contains(morf.fs.read(log), "translate/app.lua -- -t de hello")
end)
