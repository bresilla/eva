-- The Assistant page against a local fake server and a stand-in keyring: real
-- curl, real streaming, no real API.
--     morf test --no-dbus tests/assistant_page_spec.lua
local test = morf.test
local ROOT = morf.env("PWD")
local BIN = ROOT .. "/tests/fixtures/bin-stand-in"
local KEY = "sk-eva-test"
local HOST = [[
  local ui = require("morf.ui")
  local W, H = tonumber(morf.env("TEST_WIDTH")), tonumber(morf.env("TEST_HEIGHT"))
  morf.surface.height = H
  require("lib.services.secrets").env = { SECRET_STAND_IN = morf.env("SECRET_DIR") }
  local config, model = require("config"), require("assistant_model")
  local opened
  package.loaded.pages = { settings = function(route) opened = route end, open = function(key) opened = key end,
    all = {}, tabs = function() return {} end }
  package.loaded.services = { window = { title = function() return morf.env("WINDOW_TITLE") or "Desktop" end } }
  config.set("assistant.folder", morf.env("HISTORY_DIR"))
  local shown = morf.signal("assistant.spec.shown", true)
  local active = function() return shown:get() end
  ui.Item { width = W, height = H,
    require("themes.layouts.page").frame { id = "page-assistant", width = W, height = function() return H end,
      title = "Assistant", title_id = "assistant-title", titled = true, active = active,
      build = function(bw, bh) return require("assistant").build({ active = active }, bw, bh) end } }
  local server = morf.process.spawn {
    command = { "python3", morf.env("FAKE_SERVER"), morf.env("FAKE_LOG") },
    on_stdout = function(line)
      config.set("assistant.anthropic.base", "http://127.0.0.1:" .. line)
      config.set("assistant.ollama.base", "http://127.0.0.1:" .. line)
      morf.ipc.port = function() return tonumber(line) end
    end, on_stderr = function() end }
  morf.ipc.port = function() return false end
  morf.ipc.provider = function(kind, model_id)
    config.set("assistant." .. kind .. ".model", model_id or "fake-small")
    model.choose(kind)
  end
  morf.ipc.save_key = function(key)
    model.save_key(key, function(ok, why) morf.ipc.saved = function() return { ok = ok, why = why or "" } end end)
  end
  morf.ipc.saved = function() return false end
  morf.ipc.state = function()
    local last = model.messages:len() > 0 and model.messages:get(model.messages:len()) or {}
    return { state = model.state(), streaming = model.streaming:get(), notice = model.notice:get(), key = model.key_state:get(),
      count = model.messages:len(), text = last.text or "", busy = last.busy or false, failed = last.failed or "",
      note = last.note or "", role = last.role or "", opened = opened, draft = model.draft:get(),
      attachments = model.attachments:len(), conversations = model.conversations:len(), current = model.current:get(),
      private = model.private:get() }
  end
  morf.ipc.send = function(text) return model.send(text) end
  morf.ipc.stop = model.stop
  morf.ipc.regenerate = model.regenerate
  morf.ipc.new = model.new_conversation
  morf.ipc.reopen = function(index) model.open(model.conversations:get(tonumber(index)).id) end
  morf.ipc.delete = function(index) model.delete(model.conversations:get(tonumber(index)).id) end
  morf.ipc.attach = function(kind) model["attach_" .. kind]() end
  morf.ipc.detach_first = function() model.detach(model.attachments:get(1).id) end
  morf.ipc.private = function(on) model.set_private(on == "yes") end
  morf.ipc.ask = model.ask
  morf.ipc.copied = function() return model.copied:get() end
  morf.ipc.message_text = function(index) return model.text_of(index) end
  morf.ipc.can_regenerate = function(index) return model.can_regenerate(index) end
  morf.ipc.quit = function() server:kill("KILL") end
]]

local count = 0
local scratch, log
local function load(style, env, size)
  count = count + 1
  scratch = ("%s/assistant-spec-%d-%d"):format(morf.env("XDG_CACHE_HOME"), count, morf.process_id or 0)
  morf.fs.mkdir(scratch .. "/state")
  log = scratch .. "/requests.log"
  morf.fs.write(log, "")
  local w, h = (size or { 1500, 610 })[1], (size or { 1500, 610 })[2]
  local all = { EVA_STYLE = style or "material", EVA_SETTINGS = scratch .. "/eva.json", SECRET_DIR = scratch .. "/keyring",
    HISTORY_DIR = scratch .. "/history",
    FAKE_SERVER = "tests/fixtures/fake_llm.py", FAKE_LOG = log, PATH = BIN .. ":" .. morf.env("PATH"),
    TEST_WIDTH = tostring(w), TEST_HEIGHT = tostring(h), EVA_DRY_RUN = "0", XDG_RUNTIME_DIR = scratch }
  for name, value in pairs(env or {}) do all[name] = value end
  test.load("../shell/init.lua", { source = HOST, size = { w, h }, env = all })
  test.wait(function() return test.ipc("port") end, 5000, "the fake server")
  test.advance(100)
end
local function state() return test.ipc("state") end
local function ready()
  test.ipc("provider", "anthropic")
  test.ipc("save_key", KEY)
  test.wait(function() test.advance(20) return test.ipc("saved") end, 3000, "the key saved")
  test.wait(function() test.advance(20) return state().state == "ready" end, 3000, "ready")
end
local function replied()
  return test.wait(function() test.advance(50) local s = state() return not s.streaming and s end, 8000, "a reply")
end
local function requests()
  local out = {}
  for line in morf.fs.read(log):gmatch("[^\n]+") do out[#out + 1] = morf.json.decode(line) end
  return out
end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end

test.describe("assistant page", function()
  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. " says plainly that nothing is connected, and offers the settings", function()
      load(style)
      test.settle(600)
      test.truthy(test.get("assistant-setup").visible)
      test.falsy(test.get("assistant-chat").visible)
      test.truthy(test.find { text = "No assistant connected" })
      test.click("assistant-open-settings")
      test.eq(state().opened, "assistant")
      test.eq(#test.runs(), 0, "nothing ran before a provider was chosen")
      test.ipc("quit")
    end)

    test.it(style .. " streams a reply with markup and a code block", function()
      load(style)
      ready()
      test.falsy(test.get("assistant-setup").visible)
      test.truthy(test.get("assistant-chat").visible)
      test.ipc("send", "hello there")
      local s = replied()
      test.eq(s.count, 2)
      test.eq(s.failed, "")
      test.truthy(s.text:find("stand-in", 1, true))
      test.truthy(test.find { id = "assistant-message-2-4-code" }, "the reply's fence is a code block")
      test.truthy(test.find { id = "assistant-message-2-copy" })
      test.eq(requests()[#requests()].headers["x-api-key"], KEY)
      shot(style .. "-assistant-reply")
      test.eq(#test.logs("error"), 0)
      test.ipc("quit")
    end)
  end

  test.it("keeps conversations on disk and opens them again", function()
    load()
    ready()
    test.ipc("send", "first question")
    replied()
    test.eq(state().conversations, 1)
    test.ipc("new")
    test.eq(state().count, 0)
    test.ipc("send", "second question")
    replied()
    test.eq(state().conversations, 2)
    test.ipc("reopen", 2)
    test.eq(state().count, 2)
    test.eq(test.ipc("message_text", 1), "first question")
    test.ipc("delete", 2)
    test.eq(state().conversations, 1)
    test.eq(state().count, 0, "deleting the one on show leaves an empty one")
    test.ipc("quit")
  end)

  test.it("stops a reply and keeps what came, then regenerates", function()
    load()
    ready()
    test.ipc("send", "slow one")
    test.wait(function() test.advance(50) return state().text:find("tick", 1, true) end, 5000, "first words")
    test.ipc("stop")
    local s = replied()
    test.eq(s.note, "Stopped.")
    test.truthy(s.text:find("tick", 1, true))
    test.truthy(test.ipc("can_regenerate", "2"))
    test.falsy(test.ipc("can_regenerate", "1"))
    local before = #requests()
    test.ipc("regenerate")
    test.ipc("stop")
    replied()
    test.eq(state().count, 2, "regenerate replaces the reply")
    test.truthy(#requests() >= before)
    test.ipc("quit")
  end)

  test.it("shows what a failed request said, in the conversation", function()
    load()
    ready()
    test.ipc("send", "boom")
    local s = replied()
    test.truthy(s.failed:find("500", 1, true), s.failed)
    test.ipc("quit")
  end)

  test.it("says when a reply was cut short", function()
    load()
    ready()
    test.ipc("send", "long one")
    test.truthy(replied().note:find("cut short", 1, true))
    test.ipc("quit")
  end)

  test.it("sends the system prompt and the whole conversation", function()
    load()
    ready()
    test.ipc("send", "one")
    replied()
    test.ipc("send", "two")
    replied()
    local body = requests()[#requests()].body
    test.eq(#body.messages, 3)
    test.eq(body.messages[1].content, "one")
    test.eq(body.messages[2].role, "assistant")
    test.eq(body.messages[3].content, "two")
    test.eq(body.model, "fake-small")
    test.ipc("quit")
  end)

  test.it("attaches the clipboard, the focused window and a screenshot", function()
    load(nil, { WINDOW_TITLE = "report.pdf - Zathura" })
    ready()
    test.ipc("attach", "clipboard")
    test.wait(function() test.advance(20) return state().attachments == 1 end, 3000, "the clipboard")
    test.ipc("attach", "window")
    test.eq(state().attachments, 2)
    test.ipc("attach", "screenshot")
    test.wait(function() test.advance(20) return state().attachments == 3 end, 3000, "the screenshot")
    test.ipc("send", "look at this")
    replied()
    local content = requests()[#requests()].body.messages[1].content
    test.eq(content[1].type, "image")
    test.eq(content[1].source.media_type, "image/png")
    test.truthy(content[2].text:find("words from the clipboard", 1, true))
    test.truthy(content[2].text:find("report.pdf - Zathura", 1, true))
    test.eq(state().attachments, 0, "attachments go with the message")
    test.ipc("quit")
  end)

  test.it("says when there is nothing to attach", function()
    load(nil, { WINDOW_TITLE = "Desktop" })
    test.ipc("attach", "window")
    test.truthy(state().notice:find("No window", 1, true))
    test.ipc("quit")
  end)

  test.it("keeps a private conversation off the disk", function()
    load()
    ready()
    test.ipc("private", "yes")
    test.ipc("send", "a secret plan")
    replied()
    test.eq(state().conversations, 0)
    test.ipc("quit")
  end)

  test.it("keeps a key out of signals, settings, logs, arguments and history", function()
    load()
    ready()
    test.ipc("send", "anything")
    replied()
    local settings = morf.fs.read(scratch .. "/eva.json")
    test.falsy(settings:find(KEY, 1, true), "the key reached eva.json")
    for _, run in ipairs(test.runs()) do
      test.falsy(table.concat(run, " "):find(KEY, 1, true), "the key reached a command line")
    end
    for _, line in ipairs(test.logs("debug")) do
      test.falsy(tostring(line.message):find(KEY, 1, true), "the key reached a log")
    end
    local s = state()
    for _, value in pairs(s) do test.falsy(tostring(value):find(KEY, 1, true), "the key reached the model's state") end
    test.truthy(requests()[#requests()].headers["x-api-key"] == KEY, "the key did reach the server, in a header")
    test.ipc("quit")
  end)

  test.it("needs no key for a local Ollama", function()
    load()
    test.ipc("provider", "ollama")
    test.advance(50)
    test.eq(state().state, "ready")
    test.ipc("send", "hello ollama")
    local s = replied()
    test.truthy(s.text:find("stand-in", 1, true))
    test.eq(requests()[#requests()].path, "/api/chat")
    test.ipc("quit")
  end)

  test.it("sends the launcher's question once the keyring has answered", function()
    load()
    ready()
    test.ipc("ask", "from the launcher")
    test.wait(function() test.advance(50) return state().count == 2 and not state().streaming end, 8000, "the asked question")
    test.eq(state().opened, "assistant")
    test.ipc("quit")
  end)

  test.it("keeps a launcher question as a draft when nothing can answer", function()
    load()
    test.ipc("ask", "from the launcher")
    test.advance(50)
    test.eq(state().draft, "from the launcher")
    test.eq(state().count, 0)
    test.ipc("quit")
  end)

  test.it("fits a phone, its conversations a press away", function()
    load("material", nil, { 390, 780 })
    ready()
    test.ipc("send", "hello")
    replied()
    test.truthy(test.get("assistant-chat").visible)
    test.falsy(test.get("assistant-list").visible)
    test.eq(test.get("assistant-input").width <= 390, true)
    shot("phone-assistant")
    test.ipc("quit")
  end)
end)
