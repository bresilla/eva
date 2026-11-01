-- The Secret Service through `secret-tool`. A secret travels on the child's
-- stdin and comes back on its stdout; it is never an argument, never kept
-- here, and never reaches a signal, a log or the settings. Callers hold it in
-- a local for as long as one request takes.
--
--   secrets.store("Eva assistant: anthropic", { service = "eva", account = "anthropic" }, key, function(ok, why) end)
--   secrets.lookup({ service = "eva", account = "anthropic" }, function(key, why) end)
--   secrets.clear({ service = "eva", account = "anthropic" }, function(ok, why) end)
local morf = require("morf")
local poll = require("lib.util.poll")
local M = { TIMEOUT_MS = 8000, MISSING = "secret-tool is not installed: add libsecret to keep keys in the keyring.",
  -- Added to what `secret-tool` inherits.
  env = nil }

local function program() return poll.which("secret-tool") end

--- Whether `secret-tool` is on PATH.
function M.available() return program() ~= nil end

-- Attribute pairs in a stable order, as `secret-tool` takes them.
local function pairs_of(attributes)
  local names = {}
  for name in pairs(attributes) do names[#names + 1] = name end
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    out[#out + 1] = name
    out[#out + 1] = tostring(attributes[name])
  end
  return out
end

local function argv(verb, attributes, extra)
  local words = { program(), verb }
  for _, word in ipairs(extra or {}) do words[#words + 1] = word end
  for _, word in ipairs(pairs_of(attributes)) do words[#words + 1] = word end
  return words
end

-- What a failed run says, trimmed; stdout may hold a secret and is not read.
local function why(result)
  local said = result and (result.error or result.stderr) or ""
  said = tostring(said or ""):gsub("%s+$", "")
  if result and result.timed_out then return "The keyring did not answer." end
  if said == "" then return "The keyring refused." end
  return said:sub(1, 200)
end

local function run(words, options, done)
  options.env = M.env
  local ok, failure = pcall(morf.process.run, words, options, done)
  if not ok then done { ok = false, error = tostring(failure) } end
end

--- Writes `value` under `attributes`, labelled `label`.
function M.store(label, attributes, value, done)
  if not program() then done(false, M.MISSING) return end
  run(argv("store", attributes, { "--label=" .. label }), { stdin = value, timeout_ms = M.TIMEOUT_MS }, function(result)
    if result.ok then done(true) else done(false, why(result)) end
  end)
end

--- Hands `value` to `done`, or nil and why. An absent secret is nil and "".
function M.lookup(attributes, done)
  if not program() then done(nil, M.MISSING) return end
  run(argv("lookup", attributes), { timeout_ms = M.TIMEOUT_MS }, function(result)
    if result.ok and (result.stdout or "") ~= "" then
      done((result.stdout:gsub("[\r\n]+$", "")))
    elseif result.error or result.timed_out then
      done(nil, why(result))
    else
      done(nil, "")
    end
  end)
end

--- Removes what is stored under `attributes`.
function M.clear(attributes, done)
  if not program() then done(false, M.MISSING) return end
  run(argv("clear", attributes), { timeout_ms = M.TIMEOUT_MS }, function(result)
    if result.ok then done(true) else done(false, why(result)) end
  end)
end

return M
