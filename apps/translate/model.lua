-- eva-translate's state. Text leaves this machine only from `translate`, which
-- only a press or a command line reaches; what is typed or pasted stays here. No
-- text is kept on disk: the file holds the choices. No nodes.
local morf = require("morf")
local sys = require("common.sys")
local engines = require("engines")

local M = {
  input = morf.signal("translate.input", ""),
  output = morf.signal("translate.output", ""),
  source = morf.signal("translate.source", "auto"),
  target = morf.signal("translate.target", "de"),
  engine = morf.signal("translate.engine", ""),
  detected = morf.signal("translate.detected", ""),
  busy = morf.signal("translate.busy", false),
  message = morf.signal("translate.message", ""),
  found = morf.signal("translate.found", {}),
}

M.LANGUAGES = {
  { "ar", "Arabic" }, { "sq", "Albanian" }, { "zh", "Chinese" }, { "cs", "Czech" }, { "da", "Danish" }, { "nl", "Dutch" },
  { "en", "English" }, { "fi", "Finnish" }, { "fr", "French" }, { "de", "German" }, { "el", "Greek" }, { "he", "Hebrew" },
  { "hi", "Hindi" }, { "hu", "Hungarian" }, { "it", "Italian" }, { "ja", "Japanese" }, { "ko", "Korean" },
  { "nb", "Norwegian" }, { "pl", "Polish" }, { "pt", "Portuguese" }, { "ro", "Romanian" }, { "ru", "Russian" },
  { "sr", "Serbian" }, { "es", "Spanish" }, { "sv", "Swedish" }, { "tr", "Turkish" }, { "uk", "Ukrainian" },
}

local function prefs() return sys.state("translate", "prefs.json") end

local function keep()
  sys.save(prefs(), { source = M.source:get(), target = M.target:get(), engine = M.engine:get() })
end

--- The engine in use: the one chosen where this machine has it, else the first
--- it has, or nil. A tracked read.
function M.current()
  local found, wanted = M.found:get(), M.engine:get()
  for _, engine in ipairs(found) do
    if engine.id == wanted then return engine end
  end
  return found[1]
end

--- The language this session speaks, by LANG, where it is one listed here.
local function session_language()
  local code = (morf.env("LANG") or ""):match("^(%l%l)")
  for _, language in ipairs(M.LANGUAGES) do
    if language[1] == code then return code end
  end
end

--- Reads the choices and which engines there are.
function M.load()
  M.found:set(engines.available())
  local held = sys.load(prefs(), {})
  if held.source then M.source:set(held.source) end
  M.target:set(held.target or session_language() or "en")
  if held.engine then M.engine:set(held.engine) end
end

--- `code`'s name, "" for one not listed.
function M.name_of(code)
  if code == "auto" then return "Detect" end
  for _, language in ipairs(M.LANGUAGES) do
    if language[1] == code then return language[2] end
  end
  return ""
end

function M.set_source(code) M.source:set(code) keep() end
function M.set_target(code) M.target:set(code) keep() end
function M.set_engine(id) M.engine:set(id) keep() end

--- What this engine's note says: whether text leaves the machine. A tracked read.
function M.privacy()
  local engine = M.current()
  if not engine then return "No translator here: install argos-translate or translate-shell" end
  if engine.offline then return "Offline: " .. engine.name .. ". Your text stays on this machine" end
  return "Online: Send gives your text to " .. engine.name
end

local asked = 0

-- Why `engine` cannot take this request, or nil.
local function refusal(engine, request)
  if request.text:match("^%s*$") then return "Nothing to translate" end
  if not engine then return "No translator here" end
  if request.source == "auto" and not engine.auto then
    return engine.name .. " needs the source language named"
  end
  if engine.limit and #request.text > engine.limit then
    return ("%s takes %d bytes at a time"):format(engine.name, engine.limit)
  end
end

--- Sends the text to the engine in use: the one way text leaves the machine.
--- `done(words, why)`.
function M.translate(done)
  local engine = M.current()
  local request = { text = M.input:get(), source = M.source:get(), target = M.target:get() }
  local why = refusal(engine, request)
  if why then
    M.message:set(why)
    if done then done(nil, why) end
    return false
  end
  asked = asked + 1
  local mine = asked
  M.busy:set(true)
  M.message:set("")
  engines.LIST[engine.id].run(request, function(words, reason, detected)
    if mine ~= asked then return end
    M.busy:set(false)
    if words then
      M.output:set(words)
      M.detected:set(detected or "")
    else
      M.message:set(tostring(reason))
    end
    if done then done(words, reason) end
  end)
  return true
end

--- Swaps the two languages, and the texts where there is a translation.
function M.swap()
  local source, target = M.source:get(), M.target:get()
  local found = M.detected:get()
  if source == "auto" then source = found ~= "" and found:sub(1, 2) or "en" end
  M.source:set(target)
  M.target:set(source)
  if M.output:get() ~= "" then
    M.input:set(M.output:get())
    M.output:set("")
  end
  M.detected:set("")
  keep()
end

--- The clipboard, or the selection, into the input: it goes no further.
function M.paste(selection, done)
  local argv = { "wl-paste", "-n" }
  if selection then argv[#argv + 1] = "--primary" end
  sys.run(argv, { read = true, timeout_ms = 2000 }, function(result)
    if result.ok and result.stdout ~= "" then
      M.input:set(result.stdout)
      M.output:set("")
      if done then done(true) end
    else
      M.message:set(selection and "Nothing is selected" or "The clipboard holds no text")
      if done then done(false) end
    end
  end)
end

function M.copy()
  if M.output:get() == "" then return false end
  sys.copy(M.output:get())
  M.message:set("Copied")
  return true
end

-- ---------------------------------------------------------- the command line --

--- `eva-translate`'s words: `{ source, target, engine, paste, stdin, words }`.
function M.read_words(args)
  local out, words = {}, {}
  local index = 1
  while args[index] do
    local word = args[index]
    if word == "-t" or word == "-s" or word == "-e" then
      index = index + 1
      out[({ ["-t"] = "target", ["-s"] = "source", ["-e"] = "engine" })[word]] = args[index]
    elseif word == "--clipboard" then out.paste = "clipboard"
    elseif word == "--selection" then out.paste = "selection"
    elseif word == "-" then out.stdin = true
    else words[#words + 1] = word end
    index = index + 1
  end
  out.words = table.concat(words, " ")
  return out
end

local function engine_lines()
  local lines = {}
  for _, engine in ipairs(M.found:get()) do
    lines[#lines + 1] = ("%-10s %s (%s)"):format(engine.id, engine.name, engine.offline and "offline" or "online")
  end
  if #lines == 0 then return nil, "No translator here" end
  return table.concat(lines, "\n")
end

--- `eva-translate`'s command: `done(text, why)`.
function M.job(args, input, done)
  if args[1] == "engines" then
    done(engine_lines())
    return
  end
  local asked_for = M.read_words(args)
  if asked_for.source then M.source:set(asked_for.source) end
  if asked_for.target then M.target:set(asked_for.target) end
  if asked_for.engine then
    M.engine:set(asked_for.engine)
    if not M.current() or M.current().id ~= asked_for.engine then
      done(nil, "No engine " .. asked_for.engine .. " here")
      return
    end
  end
  local engine = M.current()
  if not asked_for.source and engine and engine.auto then M.source:set("auto") end
  local function go()
    M.translate(function(words, why) done(words, why) end)
  end
  if asked_for.paste then
    M.paste(asked_for.paste == "selection", function(ok)
      if ok then go() else done(nil, M.message:get()) end
    end)
    return
  end
  M.input:set(asked_for.stdin and (input or "") or asked_for.words)
  go()
end

return M
