-- Chat over HTTP: OpenAI-compatible endpoints, Anthropic's Messages API and a
-- local Ollama. A reply streams through `curl --config -`: the URL, the headers
-- and the key are on curl's stdin and the body in a private file, so nothing
-- of a request reaches a command line. Lists of models go through morf.http.
--
--   local stream = llm.stream {
--     provider = { kind = "anthropic", base = "https://api.anthropic.com", model = "claude-sonnet-5-5" },
--     key = key, system = "Be brief.", messages = { { role = "user", text = "Hello" } },
--     on_delta = function(text) end,
--     on_done = function(outcome) end,   -- { stopped, error, reason }
--   }
--   stream.stop()
local morf = require("morf")
local poll = require("lib.util.poll")
local M = { MAX_TOKENS = 8192, TIMEOUT_MS = 600000, STATUS = "__EVA_HTTP_" }

M.KINDS = {
  anthropic = { name = "Anthropic", base = "https://api.anthropic.com", model = "claude-sonnet-5-5", needs_key = true },
  openai = { name = "OpenAI-compatible", base = "https://api.openai.com/v1", model = "", needs_key = true },
  ollama = { name = "Ollama", base = "http://127.0.0.1:11434", model = "", needs_key = false },
}

--- Where an OpenAI-compatible provider lives, for the settings' presets.
M.PRESETS = {
  { name = "OpenAI", base = "https://api.openai.com/v1" },
  { name = "OpenRouter", base = "https://openrouter.ai/api/v1" },
  { name = "Groq", base = "https://api.groq.com/openai/v1" },
  { name = "LM Studio", base = "http://127.0.0.1:1234/v1" },
}

local function trimmed(url) return (tostring(url or ""):gsub("%s+", ""):gsub("/+$", "")) end

--- Whether `text` is safe as a URL in curl's config and worth asking.
function M.valid_base(text) return trimmed(text):match("^https?://[^%s\"\\]+$") ~= nil end

--- Whether `key` can travel in a header: no control characters, no spaces.
function M.valid_key(key) return type(key) == "string" and key ~= "" and not key:find("[%c%s\"\\]") end

-- ----------------------------------------------------------------- bodies --

-- A message's parts: its text, what was attached as text, its pictures.
local function parts(message)
  local text, pictures = { message.text or "" }, {}
  for _, item in ipairs(message.attachments or {}) do
    if item.kind == "text" then
      text[#text + 1] = ("\n\n[%s]\n%s"):format(item.name or "Attached", item.text or "")
    elseif item.kind == "image" and item.data then
      pictures[#pictures + 1] = item
    end
  end
  return table.concat(text), pictures
end

local function anthropic_messages(messages)
  local out = {}
  for _, message in ipairs(messages) do
    local text, pictures = parts(message)
    if #pictures == 0 then
      out[#out + 1] = { role = message.role, content = text }
    else
      local content = morf.json.array {}
      for _, picture in ipairs(pictures) do
        content[#content + 1] = { type = "image",
          source = { type = "base64", media_type = picture.mime or "image/png", data = picture.data } }
      end
      content[#content + 1] = { type = "text", text = text }
      out[#out + 1] = { role = message.role, content = content }
    end
  end
  return out
end

local function openai_messages(system, messages)
  local out = {}
  if system and system ~= "" then out[1] = { role = "system", content = system } end
  for _, message in ipairs(messages) do
    local text, pictures = parts(message)
    if #pictures == 0 then
      out[#out + 1] = { role = message.role, content = text }
    else
      local content = morf.json.array { { type = "text", text = text } }
      for _, picture in ipairs(pictures) do
        content[#content + 1] = { type = "image_url",
          image_url = { url = ("data:%s;base64,%s"):format(picture.mime or "image/png", picture.data) } }
      end
      out[#out + 1] = { role = message.role, content = content }
    end
  end
  return out
end

local function ollama_messages(system, messages)
  local out = {}
  if system and system ~= "" then out[1] = { role = "system", content = system } end
  for _, message in ipairs(messages) do
    local text, pictures = parts(message)
    local row = { role = message.role, content = text }
    if #pictures > 0 then
      row.images = morf.json.array {}
      for _, picture in ipairs(pictures) do row.images[#row.images + 1] = picture.data end
    end
    out[#out + 1] = row
  end
  return out
end

--- The request for one reply: `url`, `headers` (`{ name, value }`, with no
--- key), `key_header` (the header the key goes in, or nil) and `body`.
function M.request(spec)
  local provider, kind = spec.provider, spec.provider.kind
  local base = trimmed(provider.base)
  if kind == "anthropic" then
    local body = { model = provider.model, max_tokens = provider.max_tokens or M.MAX_TOKENS, stream = true,
      messages = anthropic_messages(spec.messages) }
    if spec.system and spec.system ~= "" then body.system = spec.system end
    return { url = base .. "/v1/messages", key_header = function(key) return "x-api-key: " .. key end, body = body,
      headers = { "anthropic-version: 2023-06-01", "content-type: application/json" } }
  elseif kind == "ollama" then
    return { url = base .. "/api/chat", headers = { "content-type: application/json" },
      body = { model = provider.model, stream = true, messages = ollama_messages(spec.system, spec.messages) } }
  end
  return { url = base .. "/chat/completions", key_header = function(key) return "authorization: Bearer " .. key end,
    headers = { "content-type: application/json" },
    body = { model = provider.model, stream = true, messages = openai_messages(spec.system, spec.messages) } }
end

-- ---------------------------------------------------------------- parsers --

local function decode(text)
  local ok, value = pcall(morf.json.decode, text)
  if ok and type(value) == "table" then return value end
end

local function string_of(value) return type(value) == "string" and value or nil end

--- Reads one line of a reply. Returns a table of what it said: `text`,
--- `finished`, `reason` (why it ended) or `error`; nil for a line that says
--- nothing.
function M.read_line(kind, line)
  if kind == "ollama" then
    local event = decode(line)
    if not event then return nil end
    if event.error then return { error = tostring(event.error) } end
    return { text = event.message and string_of(event.message.content), finished = event.done == true,
      reason = string_of(event.done_reason) }
  end
  local data = line:match("^data:%s?(.*)$")
  if not data or data == "" then return nil end
  if data == "[DONE]" then return { finished = true } end
  local event = decode(data)
  if not event then return nil end
  if kind == "anthropic" then
    if event.type == "content_block_delta" and event.delta then
      return { text = string_of(event.delta.text) }
    elseif event.type == "message_delta" and event.delta then
      return { reason = string_of(event.delta.stop_reason) }
    elseif event.type == "message_stop" then
      return { finished = true }
    elseif event.type == "error" then
      return { error = event.error and string_of(event.error.message) or "The provider reported an error." }
    end
    return nil
  end
  if event.error then
    return { error = type(event.error) == "table" and string_of(event.error.message) or tostring(event.error) }
  end
  local choice = type(event.choices) == "table" and event.choices[1]
  if choice then
    return { text = choice.delta and string_of(choice.delta.content), reason = string_of(choice.finish_reason) }
  end
end

-- What an error body says, in a person's words.
local function error_body(status, body)
  local event = decode(body)
  local said = event and (type(event.error) == "table" and event.error.message or event.error or event.message)
  said = type(said) == "string" and said or body:gsub("%s+", " "):sub(1, 200)
  if status == 401 or status == 403 then
    return ("The provider refused the key (%d)%s"):format(status, said ~= "" and (": " .. said) or ".")
  end
  if status == 404 then
    return ("Nothing there (404)%s"):format(said ~= "" and (": " .. said) or ": check the address and the model.")
  end
  return ("The provider answered %d%s"):format(status, said ~= "" and (": " .. said) or ".")
end
M.error_body = error_body

--- Why a reply ended, when that is news.
function M.reason_note(reason)
  if reason == "max_tokens" or reason == "length" then return "The reply was cut short at the length limit." end
  if reason == "refusal" or reason == "content_filter" then return "The provider declined to continue." end
end

-- --------------------------------------------------------------- transport --

-- A value quoted for a curl config line.
local function quoted(text) return '"' .. text:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end

--- The config curl reads from stdin: every option, the key among them.
function M.curl_config(request, key, body_path)
  local lines = {
    "silent", "show-error", "no-buffer", "location",
    "request = \"POST\"",
    ("max-time = %d"):format(M.TIMEOUT_MS // 1000),
    "url = " .. quoted(request.url),
    "data-binary = " .. quoted("@" .. body_path),
    "write-out = " .. quoted("\\n" .. M.STATUS .. "%{http_code}\\n"),
  }
  for _, header in ipairs(request.headers) do lines[#lines + 1] = "header = " .. quoted(header) end
  if request.key_header and key then lines[#lines + 1] = "header = " .. quoted(request.key_header(key)) end
  return table.concat(lines, "\n") .. "\n"
end

-- A private folder for request bodies.
local function spool()
  local runtime = morf.env and morf.env("XDG_RUNTIME_DIR")
  local dir = (runtime and runtime ~= "") and (runtime .. "/eva") or morf.paths.cache("assistant")
  pcall(morf.fs.mkdir, dir)
  return dir
end

local count = 0

--- Starts a reply; see the head of the file. Returns `{ stop() }`, or nil
--- after `on_done` was told why it could not start.
function M.stream(spec)
  local curl = poll.which("curl")
  if not curl then spec.on_done { error = "curl is not installed." } return nil end
  local request = M.request(spec)
  count = count + 1
  local body_path = ("%s/request-%d-%d.json"):format(spool(), morf.process_id or 0, count)
  local wrote, failure = morf.fs.write(body_path, morf.json.encode(request.body), { mode = 384 })
  if not wrote then spec.on_done { error = "The request could not be written: " .. tostring(failure) } return nil end

  local stopped, finished, reason, status, failed = false, false, nil, nil, nil
  local errors, unread = {}, {}
  local kind = spec.provider.kind
  local function read(line)
    local code = line:match("^" .. M.STATUS .. "(%d+)$")
    if code then status = tonumber(code) return end
    local said = M.read_line(kind, line)
    if said then
      if said.text and said.text ~= "" then spec.on_delta(said.text) end
      if said.error then failed = said.error end
      if said.reason then reason = said.reason end
      if said.finished then finished = true end
    elseif line ~= "" and not line:find("^event:") and not line:find("^:") and #unread < 40 then
      unread[#unread + 1] = line
    end
  end
  local function exited(code)
    pcall(morf.fs.remove, body_path)
    if stopped then spec.on_done { stopped = true } return end
    if status and (status < 200 or status >= 300) then
      spec.on_done { error = error_body(status, table.concat(unread, "\n")) }
    elseif failed then
      spec.on_done { error = failed }
    elseif code ~= 0 then
      local said = table.concat(errors, " "):gsub("^curl: %(%d+%)%s*", "")
      spec.on_done { error = said ~= "" and said or ("The request failed (" .. tostring(code) .. ").") }
    else
      spec.on_done { reason = reason, ended = finished }
    end
  end
  local child, why = morf.process.spawn {
    command = { curl, "--config", "-" },
    stdin = M.curl_config(request, spec.key, body_path),
    lines = true, max_line = 16 * 1024 * 1024,
    on_stdout = read,
    on_stderr = function(line) errors[#errors + 1] = line end,
    on_exit = exited,
  }
  if not child then
    pcall(morf.fs.remove, body_path)
    spec.on_done { error = tostring(why) }
    return nil
  end
  return { stop = function()
    stopped = true
    child:kill("TERM")
  end }
end

--- The models a provider offers: `done(list)` with ids, or `done(nil, why)`.
function M.models(provider, key, done)
  local base, kind = trimmed(provider.base), provider.kind
  local url = kind == "ollama" and (base .. "/api/tags") or kind == "anthropic" and (base .. "/v1/models")
    or (base .. "/models")
  local headers = {}
  if kind == "anthropic" then
    headers["anthropic-version"] = "2023-06-01"
    if key then headers["x-api-key"] = key end
  elseif kind == "openai" and key then
    headers.authorization = "Bearer " .. key
  end
  morf.http.get(url, { headers = headers, timeout_ms = 10000 }, function(response)
    if not response or response.status == 0 then
      done(nil, kind == "ollama" and "Ollama is not answering at that address."
        or ("No answer: " .. tostring(response and response.error or "the request failed")))
      return
    end
    if not response.ok then done(nil, error_body(response.status, response.body or "")) return end
    local data = decode(response.body or "")
    local out = {}
    for _, row in ipairs(data and (data.models or data.data) or {}) do
      local id = type(row) == "table" and (row.name or row.id or row.model)
      if type(id) == "string" then out[#out + 1] = id end
    end
    table.sort(out)
    done(out)
  end)
end

return M
