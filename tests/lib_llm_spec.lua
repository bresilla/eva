-- The assistant's transport against a local fake HTTP server: real curl, real
-- sockets, a stand-in provider. No real API is called.
--     morf test --no-dbus tests/lib_llm_spec.lua
local test = morf.test
local HOST = [[
  local llm = require("lib.integrations.llm")
  local secrets = require("lib.services.secrets")
  local port, log = nil, morf.env("FAKE_LOG")
  local server = morf.process.spawn {
    command = { "python3", morf.env("FAKE_SERVER"), log },
    on_stdout = function(line) port = tonumber(line) end, on_stderr = function() end,
  }
  local run = {}
  morf.ipc.port = function() return port end
  morf.ipc.start = function(kind, key, text, model)
    local base = "http://127.0.0.1:" .. port .. (kind == "openai" and "/v1" or "")
    run = { text = "", done = false }
    run.stream = llm.stream {
      provider = { kind = kind, base = base, model = model or "fake-small" },
      key = key ~= "" and key or nil, system = "Be brief.",
      messages = { { role = "user", text = text } },
      on_delta = function(piece) run.text = run.text .. piece end,
      on_done = function(outcome) run.done = true run.outcome = outcome end,
    }
  end
  morf.ipc.state = function() return { text = run.text, done = run.done, outcome = run.outcome or {} } end
  morf.ipc.stop = function() run.stream.stop() end
  -- What the live curl shows the rest of the machine.
  morf.ipc.exposed = function()
    local pid = run.stream.pid()
    local stat = morf.fs.stat(run.stream.body_path)
    return { pid = pid, cmdline = morf.fs.read("/proc/" .. pid .. "/cmdline"), environ = morf.fs.read("/proc/" .. pid .. "/environ"),
      body = morf.fs.read(run.stream.body_path), mode = stat.mode, path = run.stream.body_path }
  end
  morf.ipc.exists = function(path) return morf.fs.exists(path) end
  morf.ipc.models = function(kind, key)
    run = { done = false }
    llm.models({ kind = kind, base = "http://127.0.0.1:" .. port .. (kind == "openai" and "/v1" or "") },
      key ~= "" and key or nil, function(list, why) run.done = true run.list = list run.why = why end)
  end
  morf.ipc.listed = function() return { done = run.done, list = run.list or {}, why = run.why or "" } end
  morf.ipc.config = function(key) return llm.curl_config(llm.request {
    provider = { kind = "anthropic", base = "https://x.test", model = "m" }, messages = {} }, key, "/tmp/body") end
  morf.ipc.line = function(kind, line) return llm.read_line(kind, line) or false end
  morf.ipc.bodies = function(kind)
    local spec = { provider = { kind = kind, base = "http://x.test", model = "m" }, system = "S",
      messages = { { role = "user", text = "see", attachments = { { kind = "text", name = "Clip", text = "words" },
        { kind = "image", mime = "image/png", data = "QUJD" } } } } }
    return morf.json.encode(llm.request(spec).body)
  end
  morf.ipc.valid_base = llm.valid_base
  morf.ipc.valid_key = llm.valid_key
  morf.ipc.quit_server = function() server:kill("KILL") end
]]

local spec_count = 0
local function start()
  spec_count = spec_count + 1
  local log = ("%s/fake-llm-%d.log"):format(morf.env("XDG_CACHE_HOME"), spec_count)
  morf.fs.write(log, "")
  test.load { source = HOST, env = { FAKE_LOG = log, FAKE_SERVER = "tests/fixtures/fake_llm.py" } }
  test.wait(function() return test.ipc("port") end, 5000, "the fake server's port")
  return log
end
local function finished() return test.wait(function() local s = test.ipc("state") return s.done and s end, 8000, "a reply") end
local function requests(log)
  local out = {}
  for line in morf.fs.read(log):gmatch("[^\n]+") do out[#out + 1] = morf.json.decode(line) end
  return out
end

test.describe("assistant transport", function()
  for _, case in ipairs { { "anthropic", "sk-eva-test", "/v1/messages" },
    { "openai", "sk-eva-test", "/v1/chat/completions" }, { "ollama", "", "/api/chat" } } do
    local kind, key, path = case[1], case[2], case[3]
    test.it(kind .. " streams a reply through curl", function()
      local log = start()
      test.ipc("start", kind, key, "hello there")
      local state = finished()
      test.truthy(state.text:find("stand-in", 1, true))
      test.truthy(state.text:find("print('streamed')", 1, true))
      test.truthy(state.text:find("hello there", 1, true))
      test.eq(state.outcome.error, nil)
      local sent = requests(log)[1]
      test.eq(sent.path, path)
      test.eq(sent.body.stream, true)
      test.ipc("quit_server")
    end)
  end

  test.it("sends the key as a header and never on a command line", function()
    local log = start()
    test.ipc("start", "anthropic", "sk-eva-test", "keys")
    finished()
    local sent = requests(log)[1]
    test.eq(sent.headers["x-api-key"], "sk-eva-test")
    test.eq(sent.headers["anthropic-version"], "2023-06-01")
    test.eq(sent.body.model, "fake-small")
    test.eq(sent.body.system, "Be brief.")
    test.truthy(sent.body.max_tokens > 0)
    local config = test.ipc("config", "sk-secret")
    test.truthy(config:find('header = "x-api-key: sk-secret"', 1, true))
    test.truthy(config:find('data-binary = "@/tmp/body"', 1, true))
    test.ipc("quit_server")
  end)

  test.it("shows the rest of the machine no key while curl runs", function()
    start()
    test.ipc("start", "anthropic", "sk-eva-test", "slow")
    test.wait(function() return test.ipc("state").text:find("tick", 1, true) end, 5000, "the first words")
    local seen = test.ipc("exposed")
    test.truthy(seen.cmdline:find("curl", 1, true), "that was not curl")
    test.falsy(seen.cmdline:find("sk-eva-test", 1, true), "the key is on curl's command line")
    test.falsy(seen.cmdline:find("127.0.0.1", 1, true), "the address is on curl's command line")
    test.falsy(seen.environ:find("sk-eva-test", 1, true), "the key is in curl's environment")
    test.falsy(seen.body:find("sk-eva-test", 1, true), "the key is in the request file")
    test.eq(seen.mode & 511, 384, "the request file is readable by others")
    test.ipc("stop")
    finished()
    test.falsy(test.ipc("exists", seen.path), "the request file stayed behind")
    test.ipc("quit_server")
  end)

  test.it("says what a refused key and a failing server said", function()
    start()
    test.ipc("start", "anthropic", "wrong", "hello")
    local state = finished()
    test.truthy(state.outcome.error:find("refused the key", 1, true), state.outcome.error)
    test.truthy(state.outcome.error:find("invalid key", 1, true))
    test.ipc("start", "openai", "sk-eva-test", "boom")
    state = finished()
    test.truthy(state.outcome.error:find("500", 1, true), state.outcome.error)
    test.truthy(state.outcome.error:find("fell over", 1, true))
    test.ipc("quit_server")
  end)

  test.it("reports a server that is not there", function()
    start()
    test.ipc("quit_server")
    test.wait(function() return true end, 100)
    test.ipc("start", "ollama", "", "hello")
    local state = finished()
    test.truthy(state.outcome.error ~= nil and state.outcome.error ~= "")
  end)

  test.it("stops a reply part way and keeps what came", function()
    start()
    test.ipc("start", "anthropic", "sk-eva-test", "slow")
    test.wait(function() return test.ipc("state").text:find("tick", 1, true) end, 5000, "the first words")
    test.ipc("stop")
    local state = finished()
    test.eq(state.outcome.stopped, true)
    test.truthy(state.text:find("tick", 1, true))
    test.ipc("quit_server")
  end)

  test.it("hears a reply cut short at the length limit", function()
    start()
    test.ipc("start", "anthropic", "sk-eva-test", "long")
    test.eq(finished().outcome.reason, "max_tokens")
    test.ipc("start", "openai", "sk-eva-test", "long")
    test.eq(finished().outcome.reason, "length")
    test.ipc("quit_server")
  end)

  test.it("lists models with the key in a header", function()
    local log = start()
    test.ipc("models", "ollama", "")
    local listed = test.wait(function() local l = test.ipc("listed") return l.done and l end, 5000, "models")
    test.eq(listed.list, { "fake-large", "fake-small" })
    test.ipc("models", "anthropic", "sk-eva-test")
    listed = test.wait(function() local l = test.ipc("listed") return l.done and l end, 5000, "models")
    test.eq(#listed.list, 2)
    test.ipc("models", "openai", "wrong")
    listed = test.wait(function() local l = test.ipc("listed") return l.done and l end, 5000, "models")
    test.truthy(listed.why:find("refused", 1, true))
    test.eq(requests(log)[2].headers["x-api-key"], "sk-eva-test")
    test.ipc("quit_server")
  end)

  test.it("builds each provider's body with its attachments", function()
    start()
    local anthropic = morf.json.decode(test.ipc("bodies", "anthropic"))
    test.eq(anthropic.system, "S")
    local content = anthropic.messages[1].content
    test.eq(content[1].type, "image")
    test.eq(content[1].source.data, "QUJD")
    test.truthy(content[2].text:find("[Clip]", 1, true))
    local openai = morf.json.decode(test.ipc("bodies", "openai"))
    test.eq(openai.messages[1].role, "system")
    test.truthy(openai.messages[2].content[2].image_url.url:find("^data:image/png;base64,QUJD"))
    local ollama = morf.json.decode(test.ipc("bodies", "ollama"))
    test.eq(ollama.messages[2].images, { "QUJD" })
    test.ipc("quit_server")
  end)

  test.it("reads each protocol's lines", function()
    start()
    test.eq(test.ipc("line", "anthropic", "event: ping"), false)
    test.eq(test.ipc("line", "anthropic", 'data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"a"}}').text, "a")
    test.eq(test.ipc("line", "anthropic", 'data: {"type":"error","error":{"message":"overloaded"}}').error, "overloaded")
    test.eq(test.ipc("line", "openai", "data: [DONE]").finished, true)
    test.eq(test.ipc("line", "ollama", '{"error":"no model"}').error, "no model")
    test.ipc("quit_server")
  end)

  test.it("refuses what could break out of curl's config", function()
    start()
    test.falsy(test.ipc("valid_key", 'abc"\nurl = "http://evil.test'))
    test.falsy(test.ipc("valid_key", "two words"))
    test.truthy(test.ipc("valid_key", "sk-ant-api03_abc-DEF"))
    test.falsy(test.ipc("valid_base", 'http://x"y'))
    test.falsy(test.ipc("valid_base", "ftp://x.test"))
    test.truthy(test.ipc("valid_base", "https://openrouter.ai/api/v1"))
    test.ipc("quit_server")
  end)
end)
