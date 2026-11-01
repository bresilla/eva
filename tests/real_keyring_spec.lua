-- lib/services/secrets.lua against a real secret-tool and a real keyring, on a
-- throwaway session bus: tools/real-keyring.sh. Skipped anywhere else, so it
-- can never reach a person's own keyring.
--     tools/real-keyring.sh
local test = morf.test
local NAME = "keeps a key in a real keyring, on stdin"
if morf.env("EVA_REAL_KEYRING") ~= "1" then
  test.skip(NAME, "runs under tools/real-keyring.sh")
  return
end
local KEY = "sk-real-keyring-spec-0123456789"
local HOST = [[
  local secrets = require("lib.services.secrets")
  local answer
  local WHERE = { service = "eva-assistant", account = "real-keyring-spec" }
  morf.ipc.available = secrets.available
  morf.ipc.store = function(key) answer = nil
    secrets.store("Eva spec", WHERE, key, function(ok, why) answer = { ok = ok, why = why or "" } end) end
  morf.ipc.lookup = function() answer = nil
    secrets.lookup(WHERE, function(key, why) answer = { key = key or false, why = why or "" } end) end
  morf.ipc.clear = function() answer = nil
    secrets.clear(WHERE, function(ok, why) answer = { ok = ok, why = why or "" } end) end
  morf.ipc.answer = function() return answer or false end
]]
local function answered() return test.wait(function() return test.ipc("answer") end, 8000, "the keyring") end

test.it(NAME, function()
  test.load { source = HOST }
  test.truthy(test.ipc("available"))
  test.ipc("lookup")
  local absent = answered()
  test.eq(absent.key, false)
  test.eq(absent.why, "", "an absent key is not a failed keyring")
  test.ipc("store", KEY)
  test.eq(answered().ok, true)
  test.ipc("lookup")
  test.eq(answered().key, KEY)
  for _, run in ipairs(test.runs()) do
    test.falsy(table.concat(run, " "):find(KEY, 1, true), "the key reached a command line")
  end
  test.ipc("clear")
  test.eq(answered().ok, true)
  test.ipc("lookup")
  test.eq(answered().key, false)
end)
