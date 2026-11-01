-- The ways of translating, each free and needing no key, in the order they are
-- tried: what runs on this machine before what sends text away. eva-translate and
-- the launcher's `tr` both go through here. An engine is `{ id, name, offline, auto,
-- program, limit, run(request, done) }`: `auto` says it can find the source language
-- itself, `program` what must be on PATH, `limit` the most bytes it takes. `run`
-- hears `{ text, source, target }` and answers `done(words, why, detected)`. Text
-- goes to a program on stdin, never in argv.
local morf = require("morf")
local host = require("lib.services.host")
local codec = require("lib.shell.launcher.codec")

local M = { http = morf.http, ORDER = { "argos", "trans", "mymemory" } }

M.URL = "https://api.mymemory.translated.net/get"
M.TIMEOUT_MS = 20000
-- How long a program on this machine may take.
M.LOCAL_TIMEOUT_MS = 60000
-- The sentence splitter Argos runs with.
M.ARGOS_ENV = { ARGOS_CHUNK_TYPE = "MINISBD" }

--- The languages on offer: `{ code, name }`.
M.LANGUAGES = {
  { "sq", "Albanian" }, { "ar", "Arabic" }, { "bg", "Bulgarian" }, { "zh", "Chinese" }, { "hr", "Croatian" },
  { "cs", "Czech" }, { "da", "Danish" }, { "nl", "Dutch" }, { "en", "English" }, { "et", "Estonian" },
  { "fi", "Finnish" }, { "fr", "French" }, { "de", "German" }, { "el", "Greek" }, { "he", "Hebrew" },
  { "hi", "Hindi" }, { "hu", "Hungarian" }, { "id", "Indonesian" }, { "ga", "Irish" }, { "it", "Italian" },
  { "ja", "Japanese" }, { "ko", "Korean" }, { "lv", "Latvian" }, { "lt", "Lithuanian" }, { "nb", "Norwegian" },
  { "fa", "Persian" }, { "pl", "Polish" }, { "pt", "Portuguese" }, { "ro", "Romanian" }, { "ru", "Russian" },
  { "sr", "Serbian" }, { "sk", "Slovak" }, { "sl", "Slovenian" }, { "es", "Spanish" }, { "sv", "Swedish" },
  { "th", "Thai" }, { "tr", "Turkish" }, { "uk", "Ukrainian" }, { "vi", "Vietnamese" },
}

local NAMES = {}
local CODES = { ["español"] = "es", ["français"] = "fr", deutsch = "de", shqip = "sq", no = "nb" }
for _, language in ipairs(M.LANGUAGES) do
  NAMES[language[1]] = language[2]
  CODES[language[2]:lower()] = language[1]
  CODES[language[1]] = language[1]
end

--- The name of the language `code`, or nil.
function M.name_of(code) return NAMES[code] end

--- The code of the language `word` names, by name or code, or nil.
function M.language(word) return CODES[tostring(word or ""):lower()] end

-- Languages the web engines spell another way.
local LONG = { zh = "zh-CN", nb = "no" }

local function long(code) return LONG[code] or code end

local function plain(text)
  return (tostring(text or ""):gsub("\27%[[%d;]*m", ""):match("^%s*(.-)%s*$"))
end

--- Why Argos failed: its last line, without the program's name for itself.
function M.read_argos(stderr)
  local says = tostring(stderr or "")
  if says:find("URLError", 1, true) or says:find("ConnectionError", 1, true) then
    return "Argos Translate needs the network once, for its sentence splitter"
  end
  local last = ""
  for line in says:gmatch("[^\r\n]+") do last = line end
  last = plain(last:gsub("^argos%-translate:%s*error:%s*", ""))
  return last ~= "" and last or "Argos Translate failed"
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
  return codec.html_decode(words), nil, reply.detectedLanguage
end

M.LIST = {
  argos = {
    id = "argos", name = "Argos Translate", offline = true, auto = false, program = "argos-translate",
    run = function(request, done)
      morf.process.run({ "argos-translate", "--from-lang", request.source, "--to-lang", request.target },
        { stdin = request.text, timeout_ms = M.LOCAL_TIMEOUT_MS, env = M.ARGOS_ENV }, function(result)
          if not result.ok then done(nil, M.read_argos(result.stderr)) return end
          done(plain(result.stdout))
        end)
    end,
  },
  trans = {
    id = "trans", name = "translate-shell", offline = false, auto = true, program = "trans",
    run = function(request, done)
      local pair = (request.source == "auto" and "" or long(request.source)) .. ":" .. long(request.target)
      morf.process.run({ "trans", "-b", "-no-ansi", pair }, { stdin = request.text, timeout_ms = M.TIMEOUT_MS }, function(result)
        done(M.read_trans(result))
      end)
    end,
  },
  mymemory = {
    id = "mymemory", name = "MyMemory", offline = false, auto = true, limit = 500,
    run = function(request, done)
      local from = request.source == "auto" and "Autodetect" or long(request.source)
      local url = M.URL .. "?" .. M.http.query { q = request.text, langpair = from .. "|" .. long(request.target) }
      M.http.get(url, { timeout_ms = M.TIMEOUT_MS }, function(response)
        if not response.ok then
          done(nil, response.error or (response.status and "MyMemory answered " .. response.status)
            or "MyMemory could not be reached")
          return
        end
        local ok, data = pcall(response.json)
        done(M.read_mymemory(ok and data or nil))
      end)
    end,
  },
}

local function row(engine)
  return { id = engine.id, name = engine.name, offline = engine.offline, auto = engine.auto, limit = engine.limit }
end

local function here(engine) return not engine.program or host.installed(engine.program) end

--- The engines this machine can use, in order, as plain rows: a row's `id`
--- finds its `run` in M.LIST.
function M.available()
  local out = {}
  for _, id in ipairs(M.ORDER) do
    if here(M.LIST[id]) then out[#out + 1] = row(M.LIST[id]) end
  end
  return out
end

--- The first engine this machine can use that finds the source language itself.
function M.detecting()
  for _, id in ipairs(M.ORDER) do
    if M.LIST[id].auto and here(M.LIST[id]) then return row(M.LIST[id]) end
  end
end

--- Why `engine`, a row, cannot take `request`, or nil.
function M.refusal(engine, request)
  if request.text:match("^%s*$") then return "Nothing to translate" end
  if not engine then return "No translator here" end
  if request.source == "auto" and not engine.auto then
    return engine.name .. " needs the source language named"
  end
  if engine.limit and #request.text > engine.limit then
    return ("%s takes %d bytes at a time"):format(engine.name, engine.limit)
  end
end

--- Sends `request` to `engine`, a row: `done(words, why, detected)`.
function M.send(engine, request, done) M.LIST[engine.id].run(request, done) end

return M
