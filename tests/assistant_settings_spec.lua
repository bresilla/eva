-- The Assistant's settings page, typed into as a person does. The keyring is
-- the stand-in and the provider a local fake.
--     morf test --no-dbus tests/assistant_settings_spec.lua
local test = morf.test
local BIN = morf.env("PWD") .. "/tests/fixtures/bin-stand-in"
local KEY = "sk-eva-test"
local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  local secrets = require("lib.services.secrets")
  secrets.env = { SECRET_STAND_IN = morf.env("SECRET_DIR") }
  local config, model = require("config"), require("assistant_model")
  ui.Item { width = W, height = H, require("themes").view("assistant_settings").page(model, W, function() return H end) }
  local server = morf.process.spawn {
    command = { "python3", morf.env("FAKE_SERVER"), morf.env("FAKE_LOG") },
    on_stdout = function(line)
      config.set("assistant.anthropic.base", "http://127.0.0.1:" .. line)
      config.set("assistant.ollama.base", "http://127.0.0.1:" .. line)
      morf.ipc.port = function() return tonumber(line) end
    end, on_stderr = function() end }
  morf.ipc.port = function() return false end
  morf.ipc.state = function()
    return { kind = model.kind(), key = model.key_state:get(), summary = model.summary(), state = model.state(),
      model_id = config.get("assistant.openai.model"), base = config.get("assistant.openai.base"),
      anthropic_model = config.get("assistant.anthropic.model"), ollama_model = config.get("assistant.ollama.model"),
      system = config.get("assistant.system"), history = config.get("assistant.history") }
  end
  morf.ipc.lookup = function()
    local found
    secrets.lookup({ service = "eva-assistant", account = "anthropic" }, function(key) found = key or false end)
    morf.ipc.found = function() return found end
  end
  morf.ipc.found = function() return nil end
  morf.ipc.quit = function() server:kill("KILL") end
]]
local count = 0
local scratch
local function load(style)
  count = count + 1
  scratch = ("%s/assistant-settings-%d-%d"):format(morf.env("XDG_CACHE_HOME"), count, morf.process_id or 0)
  morf.fs.mkdir(scratch)
  morf.fs.write(scratch .. "/requests.log", "")
  test.load("../shell/init.lua", { source = HOST, size = { 408, 1000 }, env = { EVA_STYLE = style or "material",
    EVA_SETTINGS = scratch .. "/eva.json", SECRET_DIR = scratch .. "/keyring", FAKE_SERVER = "tests/fixtures/fake_llm.py",
    FAKE_LOG = scratch .. "/requests.log", PATH = BIN .. ":" .. morf.env("PATH"), TEST_WIDTH = "408", TEST_HEIGHT = "1000" } })
  test.wait(function() return test.ipc("port") end, 5000, "the fake server")
  test.advance(100)
end
local function state() return test.ipc("state") end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end

test.describe("assistant settings", function()
  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. " starts off, and hides what no provider needs", function()
      load(style)
      test.eq(state().kind, "")
      test.falsy(test.get("assistant-endpoint").visible)
      test.falsy(test.get("assistant-key-section").visible)
      test.click("assistant-kind-anthropic")
      test.advance(50)
      test.eq(state().kind, "anthropic")
      test.truthy(test.get("assistant-endpoint").visible)
      test.truthy(test.get("assistant-key-section").visible)
      test.eq(state().anthropic_model, "claude-sonnet-5-5")
      shot(style .. "-assistant-settings")
      test.eq(#test.logs("error"), 0)
      test.ipc("quit")
    end)
  end

  test.it("sends a typed key to the keyring and clears the field", function()
    load()
    test.click("assistant-kind-anthropic")
    test.wait(function() test.advance(20) return state().key == "none" end, 3000, "no key yet")
    test.click("assistant-key")
    test.type(KEY)
    test.eq(test.get("assistant-key").text, KEY)
    test.click("assistant-key-save")
    test.wait(function() test.advance(20) return state().key == "saved" end, 3000, "the key saved")
    test.eq(test.get("assistant-key").text, "", "the key stayed in the field")
    test.ipc("lookup")
    test.eq(test.wait(function() test.advance(20) return test.ipc("found") end, 3000, "the keyring"), KEY)
    for _, run in ipairs(test.runs()) do
      test.falsy(table.concat(run, " "):find(KEY, 1, true), "the key reached a command line")
    end
    test.falsy((morf.fs.exists(scratch .. "/eva.json") and morf.fs.read(scratch .. "/eva.json") or ""):find(KEY, 1, true))
    test.ipc("quit")
  end)

  test.it("refuses a key that could not be a key, and forgets one that is", function()
    load()
    test.click("assistant-kind-anthropic")
    test.wait(function() test.advance(20) return state().key == "none" end, 3000, "no key yet")
    test.click("assistant-key")
    test.type("two words")
    test.click("assistant-key-save")
    test.advance(100)
    test.eq(state().key, "none")
    test.truthy(test.find { text = "That does not look like a key." })
    test.click("assistant-key")
    test.type(KEY)
    test.click("assistant-key-save")
    test.wait(function() test.advance(20) return state().key == "saved" end, 3000, "the key saved")
    test.click("assistant-key-forget")
    test.wait(function() test.advance(20) return state().key == "none" end, 3000, "the key gone")
    test.ipc("quit")
  end)

  test.it("lists a local Ollama's models, and a press chooses one", function()
    load()
    test.click("assistant-kind-ollama")
    test.advance(50)
    test.falsy(test.get("assistant-key-section").visible, "Ollama needs no key")
    test.click("assistant-list-models")
    test.wait(function() test.advance(20) return test.find { id = "assistant-pick-fake-large" } end, 4000, "the models")
    test.click("assistant-pick-fake-large")
    test.eq(state().ollama_model, "fake-large")
    test.eq(state().state, "ready")
    test.ipc("quit")
  end)

  test.it("offers presets for OpenAI-compatible services", function()
    load()
    test.click("assistant-kind-openai")
    test.advance(600)
    test.truthy(test.get("assistant-presets").visible)
    test.click("assistant-preset-2")
    test.advance(50)
    test.eq(state().base, "https://openrouter.ai/api/v1")
    test.eq(test.get("assistant-base").text, "https://openrouter.ai/api/v1")
    test.ipc("quit")
  end)

  test.it("keeps the system prompt, and can keep no conversations", function()
    load()
    test.click("assistant-system")
    test.type("Answer in haiku.")
    test.eq(state().system, "Answer in haiku.")
    test.click("assistant-history-switch")
    test.advance(50)
    test.eq(state().history, false)
    test.ipc("quit")
  end)
end)
