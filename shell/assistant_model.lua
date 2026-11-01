-- The assistant's state: which provider, the conversations, the reply that is
-- arriving, and what is attached. One model, whichever panel shows the page.
-- No nodes. A key is fetched for each request into a local and never kept: no
-- signal, no setting and no log line ever holds it.
local morf = require("morf")
local config = require("config")
local llm = require("lib.integrations.llm")
local secrets = require("lib.services.secrets")
local markup = require("lib.shell.markup")
local store = require("assistant_store")
local M = {
  messages = morf.list_model({}),
  conversations = morf.list_model({}),
  attachments = morf.list_model({}),
  current = morf.signal("eva.assistant.current", ""),
  streaming = morf.signal("eva.assistant.streaming", false),
  notice = morf.signal("eva.assistant.notice", ""),
  draft = morf.signal("eva.assistant.draft", ""),
  key_state = morf.signal("eva.assistant.key", "unknown"),
  copied = morf.signal("eva.assistant.copied", ""),
  private = morf.signal("eva.assistant.private", false),
  browsing = morf.signal("eva.assistant.browsing", false),
  tick = morf.signal("eva.assistant.tick", 0),
  KINDS = llm.KINDS,
  PRESETS = llm.PRESETS,
  ORDER = { "anthropic", "openai", "ollama" },
  MAX_ATTACHED_TEXT = 64 * 1024,
  MAX_PICTURE = 5 * 1024 * 1024,
}

local conversation, reply, draining, loaded = nil, nil, false, false
local buffered = {}

local function dry_run()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

-- ---------------------------------------------------------------- provider --

--- The kind chosen in the settings, or "".
function M.kind() return config.get("assistant.provider") or "" end

--- The chosen provider's settings: `kind`, `base`, `model`.
function M.provider(kind)
  kind = kind or M.kind()
  if not llm.KINDS[kind] then return nil end
  return { kind = kind, base = config.get("assistant." .. kind .. ".base"), model = config.get("assistant." .. kind .. ".model") }
end

local function attributes(provider)
  local account = provider.kind == "openai" and ("openai:" .. tostring(provider.base)) or provider.kind
  return { service = "eva-assistant", account = account }
end

--- Whether a provider needs a key at all.
function M.needs_key(kind) local spec = llm.KINDS[kind or M.kind()] return spec ~= nil and spec.needs_key end

--- Asks the keyring whether a key is there; the key itself is dropped.
--- `done()` runs once the answer is in.
function M.check_key(done)
  done = done or function() end
  local provider = M.provider()
  if not provider or not M.needs_key() then M.key_state:set("unneeded") done() return end
  if not secrets.available() then M.key_state:set("no-tool") done() return end
  secrets.lookup(attributes(provider), function(key, why)
    if key then M.key_state:set("saved")
    elseif why == "" then M.key_state:set("none")
    else M.key_state:set("failed") end
    done()
  end)
end

--- Where things stand: `none`, `needs-model`, `no-tool`, `needs-key`, `failed`
--- (the keyring would not answer), `checking` or `ready`.
function M.state()
  local provider = M.provider()
  if not provider then return "none" end
  if provider.model == "" then return "needs-model" end
  if not M.needs_key() then return "ready" end
  local key = M.key_state:get()
  if key == "no-tool" then return "no-tool" end
  if key == "none" then return "needs-key" end
  if key == "failed" then return "failed" end
  if key == "saved" then return "ready" end
  return "checking"
end

--- What a person is told about the state, as `{ title, text }`.
function M.explain()
  local state, provider = M.state(), M.provider()
  local name = provider and llm.KINDS[provider.kind].name or ""
  if state == "none" then
    return "No assistant connected", "Nothing is answering yet. Choose Anthropic, an OpenAI-compatible service or a local Ollama in the settings."
  elseif state == "needs-model" then
    return "No model chosen", name .. " is selected, but no model is. Pick one in the settings."
  elseif state == "no-tool" then
    return "Keys cannot be stored", secrets.MISSING
  elseif state == "needs-key" then
    return "No key saved", name .. " needs an API key. Add one in the settings: it goes to the keyring, never to a file."
  elseif state == "failed" then
    return "The keyring did not answer", "Unlock the keyring, or start a Secret Service, then try again."
  elseif state == "checking" then
    return "Checking the keyring", "Looking for your " .. name .. " key."
  end
  return "", ""
end

--- A line for the page: the provider and model on show.
function M.summary()
  local provider = M.provider()
  if not provider then return "Not connected" end
  return llm.KINDS[provider.kind].name .. (provider.model ~= "" and (" · " .. provider.model) or "")
end

--- Opens the settings page for all of this.
function M.open_settings() require("pages").settings("assistant") end

--- Selects a provider and asks about its key.
function M.choose(kind)
  config.set("assistant.provider", kind)
  M.key_state:set("unknown")
  M.check_key()
end

function M.set_field(kind, field, value)
  config.set("assistant." .. kind .. "." .. field, value)
  if field == "base" then M.key_state:set("unknown") M.check_key() end
end

--- Sends `key` to the keyring, on stdin, and forgets it. `done(ok, why)`.
function M.save_key(key, done)
  local provider = M.provider()
  key = tostring(key or ""):match("^%s*(.-)%s*$")
  if not provider then done(false, "Choose a provider first.") return end
  if not llm.valid_key(key) then done(false, "That does not look like a key.") return end
  secrets.store("Eva assistant: " .. llm.KINDS[provider.kind].name, attributes(provider), key, function(ok, why)
    if ok then M.key_state:set("saved") end
    done(ok, why)
  end)
end

--- Removes the chosen provider's key from the keyring.
function M.forget_key(done)
  local provider = M.provider()
  if not provider then return end
  secrets.clear(attributes(provider), function(ok, why)
    if ok then M.key_state:set("none") end
    if done then done(ok, why) end
  end)
end

-- Hands `use` the chosen provider's key, or nil and a reason not to go on.
local function with_key(provider, use)
  if not M.needs_key(provider.kind) then use(nil) return end
  secrets.lookup(attributes(provider), function(key, why)
    if key then use(key) else use(nil, why ~= "" and why or "No key is saved for this provider.") end
  end)
end

--- The models on offer: `done(list)` or `done(nil, why)`.
function M.models(done)
  local provider = M.provider()
  if not provider then done(nil, "Choose a provider first.") return end
  if not llm.valid_base(provider.base) then done(nil, "That address does not look right.") return end
  with_key(provider, function(key, why)
    if why then done(nil, why) return end
    llm.models(provider, key, done)
  end)
end

-- ------------------------------------------------------------ conversation --

local function row_of(message, id)
  return { id = id, role = message.role, text = message.text or "", blocks = markup.blocks(message.text or ""),
    busy = message.busy == true, failed = message.failed or "", note = message.note or "",
    attached = message.attached or "" }
end

local function attached_names(attachments)
  local names = {}
  for _, item in ipairs(attachments or {}) do names[#names + 1] = item.name end
  return table.concat(names, " · ")
end

local function show()
  local rows = {}
  for i, message in ipairs(conversation and conversation.messages or {}) do
    message.attached = attached_names(message.attachments)
    rows[i] = row_of(message, tostring(i))
  end
  M.messages:replace(rows, "id")
end

local function list()
  local rows = {}
  for _, row in ipairs(store.list()) do
    rows[#rows + 1] = { id = row.id, title = row.title or "Untitled",
      when = row.updated and morf.time.format("%-d %b %H:%M", row.updated) or "" }
  end
  M.conversations:replace(rows, "id")
end

local function fresh()
  conversation = { id = morf.encoding.uuid(), title = "New conversation", messages = {} }
  M.current:set(conversation.id)
  M.private:set(false)
  show()
end

local function title_from(text)
  local line = tostring(text):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if utf8.len(line) and utf8.len(line) > 48 then line = line:sub(1, utf8.offset(line, 48) - 1) .. "…" end
  return line ~= "" and line or "Attached context"
end

local function save()
  if not conversation or M.private:get() or config.get("assistant.history") == false then return end
  local ok, why = store.save(conversation)
  if not ok then M.notice:set("This conversation could not be saved: " .. tostring(why)) end
  list()
end

--- Loads what is on disk; called when the page first shows. `done()` runs
--- once the keyring has answered.
function M.begin(done)
  if not loaded then
    loaded = true
    list()
    fresh()
  end
  M.check_key(done)
end

--- Starts an empty conversation.
function M.new_conversation()
  if M.streaming:get() then return end
  fresh()
  M.browsing:set(false)
  M.notice:set("")
end

--- Opens a saved conversation.
function M.open(id)
  if M.streaming:get() then return end
  local found = store.load(id)
  if not found then M.notice:set("That conversation could not be read.") return end
  found.messages = found.messages or {}
  conversation = found
  M.current:set(found.id)
  M.private:set(false)
  M.browsing:set(false)
  M.notice:set("")
  show()
  M.tick:set(M.tick:get() + 1)
end

--- Deletes a saved conversation.
function M.delete(id)
  if M.streaming:get() then return end
  store.remove(id)
  list()
  if M.current:get() == id then fresh() end
end

--- Keeps this conversation off the disk, or back on it.
function M.set_private(on)
  M.private:set(on == true)
  if on and conversation then store.remove(conversation.id) list() end
  if not on then save() end
end

-- --------------------------------------------------------------- attaching --

local function attach(item)
  item.id = morf.encoding.uuid()
  buffered[item.id] = item
  M.attachments:insert(M.attachments:len() + 1, { id = item.id, kind = item.kind, name = item.name })
end

--- Takes an attachment off again.
function M.detach(id)
  buffered[id] = nil
  for i = 1, M.attachments:len() do
    if M.attachments:get(i).id == id then M.attachments:remove(i) return end
  end
end

--- Attaches the clipboard's text.
function M.attach_clipboard()
  local paste = require("lib.util.poll").which("wl-paste") or "wl-paste"
  morf.process.run({ paste, "--no-newline", "--type", "text" }, { timeout_ms = 3000, max_output = M.MAX_ATTACHED_TEXT * 4 }, function(result)
    local text = result and result.ok and result.stdout or ""
    if text == "" then M.notice:set("The clipboard holds no text.") return end
    if #text > M.MAX_ATTACHED_TEXT then
      text = text:sub(1, M.MAX_ATTACHED_TEXT)
      M.notice:set("Only the first 64 KB of the clipboard were attached.")
    end
    attach { kind = "text", name = "Clipboard", text = text }
  end)
end

--- Attaches the focused window's title.
function M.attach_window()
  local title = require("services").window.title()
  if title == "" or title == "Desktop" then M.notice:set("No window has the focus.") return end
  attach { kind = "text", name = "Focused window", text = title }
end

local function screenshot_tool()
  local installed = require("lib.util.poll").which("eva-screenshot")
  if installed then return { installed } end
  local dev = morf.paths.shell() .. "/../apps/screenshot/cli"
  if morf.fs.exists(dev) then return { "sh", dev } end
end

--- Attaches a picture of the focused window, through eva-screenshot.
function M.attach_screenshot()
  local words = screenshot_tool()
  if not words then M.notice:set("eva-screenshot is not installed.") return end
  words[#words + 1] = "window"
  words[#words + 1] = "--save"
  morf.process.run(words, { timeout_ms = 15000 }, function(result)
    local path = result and result.ok and (result.stdout or ""):match("(/[^\n]+%.png)")
    if not path then
      local dry = dry_run() and "Dry run: no screenshot was taken."
      M.notice:set(dry or "The screenshot failed: " .. tostring(result and result.stderr or ""):sub(1, 160))
      return
    end
    attach { kind = "image", name = "Screenshot", path = path, mime = "image/png" }
  end)
end

-- What a stored attachment is on the wire: pictures are read at send time.
local function wire(message)
  local out = { role = message.role, text = message.text, attachments = {} }
  for _, item in ipairs(message.attachments or {}) do
    if item.kind == "image" then
      local ok, bytes = pcall(morf.fs.read, item.path)
      if ok and type(bytes) == "string" and #bytes <= M.MAX_PICTURE then
        out.attachments[#out.attachments + 1] = { kind = "image", mime = item.mime, data = morf.encoding.base64_encode(bytes) }
      end
    else
      out.attachments[#out.attachments + 1] = item
    end
  end
  return out
end

-- ---------------------------------------------------------------- replying --

local FLUSH_MS = 40

-- The last row, redrawn from the reply so far.
local function redraw()
  local count = M.messages:len()
  if count == 0 or not conversation then return end
  local message = conversation.messages[#conversation.messages]
  M.messages:set(count, row_of(message, tostring(count)))
  M.tick:set(M.tick:get() + 1)
end

local function schedule()
  if draining then return end
  draining = true
  morf.time.timer(FLUSH_MS, function()
    draining = false
    redraw()
  end, false)
end

local function finish(message, outcome)
  message.busy = false
  reply = nil
  M.streaming:set(false)
  if outcome.stopped then
    message.note = "Stopped."
  elseif outcome.error then
    message.failed = outcome.error
  else
    message.note = llm.reason_note(outcome.reason)
  end
  redraw()
  save()
end

-- A reply to the conversation as it stands, into a new row.
local function start_reply()
  local provider = M.provider()
  local history = {}
  for _, message in ipairs(conversation.messages) do
    if (message.text or "") ~= "" or #(message.attachments or {}) > 0 then history[#history + 1] = wire(message) end
  end
  local message = { role = "assistant", text = "", busy = true }
  conversation.messages[#conversation.messages + 1] = message
  show()
  M.streaming:set(true)
  M.tick:set(M.tick:get() + 1)
  with_key(provider, function(key, why)
    if why then finish(message, { error = why }) return end
    if not M.streaming:get() then finish(message, { stopped = true }) return end
    reply = llm.stream {
      provider = provider, key = key, system = config.get("assistant.system"), messages = history,
      on_delta = function(piece)
        message.text = message.text .. piece
        schedule()
      end,
      on_done = function(outcome) finish(message, outcome) end,
    }
  end)
end

--- Sends `text`, with what is attached, and starts the reply.
function M.send(text)
  text = tostring(text or M.draft:get() or ""):match("^%s*(.-)%s*$")
  if M.streaming:get() then return false end
  if text == "" and M.attachments:len() == 0 then return false end
  if M.state() ~= "ready" then
    M.draft:set(text)
    M.notice:set(select(2, M.explain()))
    return false
  end
  if not conversation then M.begin() end
  local attachments = {}
  for i = 1, M.attachments:len() do
    local id = M.attachments:get(i).id
    if buffered[id] then attachments[#attachments + 1] = buffered[id] end
  end
  if #conversation.messages == 0 then conversation.title = title_from(text) end
  conversation.messages[#conversation.messages + 1] = { role = "user", text = text, attachments = attachments }
  M.attachments:replace({}, "id")
  buffered = {}
  M.draft:set("")
  M.notice:set("")
  save()
  start_reply()
  return true
end

--- Stops the reply that is arriving, keeping what came.
function M.stop()
  if reply then reply.stop()
  elseif M.streaming:get() then M.streaming:set(false) end
end

--- Whether the row `id` can be asked again.
function M.can_regenerate(id)
  return not M.streaming:get() and tonumber(id) == M.messages:len() and M.messages:len() > 0
    and M.messages:get(M.messages:len()).role == "assistant"
end

--- Drops the last reply and asks again.
function M.regenerate()
  if M.streaming:get() or not conversation or M.state() ~= "ready" then return false end
  local last = conversation.messages[#conversation.messages]
  if not last or last.role ~= "assistant" then return false end
  conversation.messages[#conversation.messages] = nil
  start_reply()
  return true
end

--- Copies `text`, marking `id` as copied for a moment.
function M.copy(id, text)
  pcall(morf.clipboard.set, tostring(text or ""))
  M.copied:set(id)
  morf.time.timer(1400, function() if M.copied:get() == id then M.copied:set("") end end, false)
end

--- A row's whole text, by id.
function M.text_of(id)
  local message = conversation and conversation.messages[tonumber(id)]
  return message and message.text or ""
end

--- Opens the page and asks `question`: the launcher's `ai`.
function M.ask(question)
  require("pages").reach("assistant")
  M.begin(function()
    if M.state() == "ready" and not M.streaming:get() then
      M.new_conversation()
      M.send(question)
    else
      M.draft:set(question)
    end
  end)
end

return M
