-- The ways of translating, each free and needing no key, in the order they are
-- tried: what runs on this machine before what sends text away. An engine is
-- `{ id, name, offline, auto, program, limit, run(request, done) }`: `auto` says
-- it can find the source language itself, `program` what must be on PATH, `limit`
-- the most bytes it takes. `run` hears `{ text, source, target }` and answers
-- `done(words, why, detected)`. Text goes to a program on stdin, never in argv.
local morf = require("morf")
local sys = require("common.sys")

local M = { http = morf.http, ORDER = { "argos", "trans", "mymemory" } }

M.URL = "https://api.mymemory.translated.net/get"
M.TIMEOUT_MS = 20000
-- Argos loads its models for each call.
M.LOCAL_TIMEOUT_MS = 60000

-- Languages some engines spell longer.
local LONG = { zh = "zh-CN" }

local function long(code) return LONG[code] or code end

local ENTITIES = { ["&amp;"] = "&", ["&lt;"] = "<", ["&gt;"] = ">", ["&quot;"] = '"', ["&#39;"] = "'", ["&#x27;"] = "'" }

--- `text` with the entities a web service writes turned back.
function M.unescape(text)
  return (tostring(text):gsub("&#?%w+;", function(entity) return ENTITIES[entity] end))
end

local function plain(text)
  return (tostring(text or ""):gsub("\27%[[%d;]*m", ""):match("^%s*(.-)%s*$"))
end

--- What translate-shell said: words, or nil and why. An unknown language
--- leaves its status at 0 and the text as it was, and says so on stderr.
function M.read_trans(result)
  local says = plain(result.stderr)
  if says:find("Unknown", 1, true) or says:find("[ERROR]", 1, true) or not result.ok then
    return nil, says ~= "" and says or "translate-shell did not answer"
  end
  local words = plain(result.stdout)
  if words == "" then return nil, "translate-shell had no answer" end
  return words
end

--- What MyMemory answered: words, or nil and why, then the language it found.
--- It reports a refusal inside the field a translation comes in.
function M.read_mymemory(data)
  if type(data) ~= "table" then return nil, "MyMemory did not answer" end
  if data.quotaFinished == true then return nil, "MyMemory's free daily limit is used up" end
  local reply = type(data.responseData) == "table" and data.responseData or {}
  if tonumber(data.responseStatus) ~= 200 then
    return nil, plain(data.responseDetails ~= "" and data.responseDetails or reply.translatedText or "MyMemory refused")
  end
  local words = plain(reply.translatedText)
  if words == "" then return nil, "MyMemory had no answer" end
  return M.unescape(words), nil, reply.detectedLanguage
end

M.LIST = {
  argos = {
    id = "argos", name = "Argos Translate", offline = true, auto = false, program = "argos-translate",
    run = function(request, done)
      sys.run({ "argos-translate", "--from-lang", request.source, "--to-lang", request.target },
        { stdin = request.text, read = true, timeout_ms = M.LOCAL_TIMEOUT_MS }, function(result)
          if not result.ok then done(nil, plain(result.stderr) ~= "" and plain(result.stderr) or "Argos Translate failed") return end
          done(plain(result.stdout))
        end)
    end,
  },
  trans = {
    id = "trans", name = "translate-shell", offline = false, auto = true, program = "trans",
    run = function(request, done)
      local pair = (request.source == "auto" and "" or long(request.source)) .. ":" .. long(request.target)
      sys.run({ "trans", "-b", "-no-ansi", pair }, { stdin = request.text, timeout_ms = M.TIMEOUT_MS }, function(result)
        if result.dry then done(nil, "dry run") return end
        done(M.read_trans(result))
      end)
    end,
  },
  mymemory = {
    id = "mymemory", name = "MyMemory", offline = false, auto = true, limit = 500,
    run = function(request, done)
      if sys.dry() then done(nil, "dry run") return end
      local from = request.source == "auto" and "Autodetect" or long(request.source)
      local url = M.URL .. "?" .. M.http.query { q = request.text, langpair = from .. "|" .. long(request.target) }
      M.http.get(url, { timeout_ms = M.TIMEOUT_MS }, function(response)
        if not response.ok then
          done(nil, response.error or ("MyMemory answered " .. tostring(response.status)))
          return
        end
        local ok, data = pcall(response.json)
        done(M.read_mymemory(ok and data or nil))
      end)
    end,
  },
}

--- The engines this machine can use, in order, as plain rows: a row's `id`
--- finds its `run` in M.LIST.
function M.available()
  local out = {}
  for _, id in ipairs(M.ORDER) do
    local engine = M.LIST[id]
    if not engine.program or sys.has(engine.program) then
      out[#out + 1] = { id = id, name = engine.name, offline = engine.offline, auto = engine.auto, limit = engine.limit }
    end
  end
  return out
end

return M
