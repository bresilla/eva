-- The Assistant in the whole shell, on a phone and on a desk: the page in the
-- panel that really holds it, a stand-in keyring, a local fake provider.
--     morf test --no-dbus tests/assistant_shell_spec.lua
local test = morf.test
local ROOT = morf.env("PWD")
local BIN = ROOT .. "/tests/fixtures/bin-stand-in"
local HOST = [[
  require("lib.services.secrets").env = { SECRET_STAND_IN = morf.env("SECRET_DIR") }
  require("init")
  local config, model = require("config"), require("assistant_model")
  config.set("assistant.folder", morf.env("HISTORY_DIR"))
  local server = morf.process.spawn {
    command = { "python3", morf.env("FAKE_SERVER"), morf.env("FAKE_LOG") },
    on_stdout = function(line)
      config.set("assistant.anthropic.base", "http://127.0.0.1:" .. line)
      config.set("assistant.anthropic.model", "fake-small")
      morf.ipc.shell_port = function() return tonumber(line) end
    end, on_stderr = function() end }
  morf.ipc.shell_port = function() return false end
  morf.ipc.shell_ready = function(key)
    config.set("assistant.provider", "anthropic")
    model.save_key(key, function() end)
  end
  morf.ipc.shell_state = function()
    local last = model.messages:len() > 0 and model.messages:get(model.messages:len()) or {}
    return { state = model.state(), streaming = model.streaming:get(), count = model.messages:len(), text = last.text or "",
      busy = last.busy == true, sheets = require("responsive").sheets(), compact = require("responsive").compact() }
  end
  morf.ipc.shell_quit = function() server:kill("KILL") end
]]
local count = 0
local function load(size, touch)
  count = count + 1
  local scratch = ("%s/assistant-shell-%d-%d"):format(morf.env("XDG_CACHE_HOME"), count, morf.process_id or 0)
  morf.fs.mkdir(scratch)
  morf.fs.write(scratch .. "/requests.log", "")
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { source = HOST, size = size, env = { EVA_STYLE = "material", EVA_DRY_RUN = "1",
    EVA_SETTINGS = scratch .. "/eva.json", SECRET_DIR = scratch .. "/keyring", HISTORY_DIR = scratch .. "/history",
    FAKE_SERVER = "tests/fixtures/fake_llm.py", FAKE_LOG = scratch .. "/requests.log", PATH = BIN .. ":" .. morf.env("PATH"),
    EVA_INPUT_DEVICES = ROOT .. "/tests/fixtures/input-devices" .. (touch and "-touch" or ""),
    LULE_A = "/nonexistent/lule", EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") } })
  test.wait(function() return test.ipc("shell_port") end, 5000, "the fake server")
  test.ipc("shell_ready", "sk-eva-test")
  test.settle(600)
end
local function state() return test.ipc("shell_state") end
local function asked_and_answered()
  test.ipc("page", "assistant")
  test.settle(1000)
  test.wait(function() test.advance(30) return state().state == "ready" end, 4000, "the keyring")
  test.ipc("ask", "hello from the whole shell")
  test.wait(function() test.advance(30) local s = state() return s.count == 2 and not s.streaming end, 8000, "a reply")
  test.settle(400)
end

test.describe("assistant in the shell", function()
  test.it("shows a reply on a phone, in the sheet that holds the page", function()
    load({ 868, 1932 }, true)
    asked_and_answered()
    local s = state()
    test.truthy(s.text:find("stand-in", 1, true))
    test.eq(s.busy, false)
    test.truthy(s.sheets)
    test.settle(2000)
    local waits = test.find_all { id = "assistant-message-2-waiting" }
    local codes = test.find_all { id = "assistant-message-2-4-code" }
    test.eq(#codes, #test.find_all { id = "assistant-input" }, "a copy of the page never got the reply")
    test.truthy(#codes >= 1, "the reply never reached the page")
    for _, waiting in ipairs(waits) do test.falsy(waiting.visible, "a copy still says it is thinking") end
    test.ipc("shell_quit")
  end)

  test.it("shows a reply on a desk, in the bottom panel", function()
    load({ 1920, 1080 }, false)
    asked_and_answered()
    local waiting = test.find { id = "assistant-message-2-waiting" }
    test.truthy(waiting == nil or not waiting.visible, "the desk still says it is thinking")
    test.truthy(test.find { id = "assistant-message-2-4-code" }, "the reply never reached the page")
    test.ipc("shell_quit")
  end)
end)
