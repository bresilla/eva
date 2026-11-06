-- eva-text's state: the pad, what was on it before, and what a press makes of it.
-- A generated secret stays in `secret` below and the node showing it, never in a
-- signal; `made` says only that there is one. No nodes.
local morf = require("morf")
local sys = require("apps.common.sys")
local codec = require("lib.shell.launcher.codec")
local password = require("lib.shell.launcher.password")
local transforms = require("apps.text.transforms")

local M = {
  text = morf.signal("text.text", ""),
  tab = morf.signal("text.tab", 1),
  length = morf.signal("text.length", 2),
  made = morf.signal("text.made", ""),
  undoing = morf.signal("text.undoing", 0),
  message = morf.signal("text.message", ""),
}

M.LENGTHS = { 16, 24, 32, 64 }
M.WORDS = 6
M.UNDO = 32

local before = {}
local secret = ""
local shown = function() end

-- Puts `next_text` on the pad, the old text kept for Undo.
local function replace(next_text)
  before[#before + 1] = M.text:get()
  if #before > M.UNDO then table.remove(before, 1) end
  M.undoing:set(#before)
  M.text:set(next_text)
end

--- Runs transform `id` on the pad.
function M.apply(id)
  local item = transforms.find(id)
  if not item then return false end
  transforms.run(item, M.text:get(), function(answer, why)
    if not answer then M.message:set(why or "That did not work") return end
    replace(answer)
    M.message:set("")
  end)
  return true
end

function M.undo()
  if #before == 0 then return false end
  M.text:set(table.remove(before))
  M.undoing:set(#before)
  return true
end

function M.clear()
  if M.text:get() ~= "" then replace("") end
end

function M.copy()
  sys.copy(M.text:get())
  M.message:set("Copied")
end

--- The clipboard onto the pad.
function M.paste()
  sys.run({ "wl-paste", "-n" }, { read = true, timeout_ms = 2000 }, function(result)
    if result.ok then replace(result.stdout) else M.message:set("The clipboard holds no text") end
  end)
end

function M.uuid() replace(morf.encoding.uuid()) end
function M.lorem() replace(codec.lorem(1)) end

--- How the view shows a secret: `action(words)`.
function M.on_secret(action) shown = action end

local function hold(value, bits, kind)
  secret = value
  shown(value)
  M.made:set(("%s, %d bits"):format(kind, bits))
end

--- Makes a password of the chosen length.
function M.make_password()
  local length = M.LENGTHS[M.length:get()]
  hold(password.generate(length), password.bits(length, #password.alphabet()), "Password")
end

--- Makes a passphrase.
function M.make_passphrase()
  hold(password.passphrase(M.WORDS), password.passphrase_bits(M.WORDS), "Passphrase")
end

function M.copy_secret()
  if secret == "" then return false end
  sys.copy(secret)
  M.message:set("Copied")
  return true
end

-- ---------------------------------------------------------- the command line --

local function words_after(args, from)
  local out = {}
  for index = from, #args do out[#out + 1] = args[index] end
  return table.concat(out, " ")
end

local DECODED = { base64 = "unbase64", url = "unurl", hex = "unhex" }

local function list()
  local lines = {}
  for _, group in ipairs(transforms.GROUPS) do
    local ids = {}
    for _, item in ipairs(group.items) do ids[#ids + 1] = item.id end
    lines[#lines + 1] = ("%-6s %s"):format(group.key, table.concat(ids, " "))
  end
  lines[#lines + 1] = ("%-6s uuid lorem password passphrase"):format("make")
  return table.concat(lines, "\n")
end

local function ending_newline(text) return text:sub(-1) == "\n" end

--- `eva-text`'s command: `done(text, why, raw)`. `input` is what was piped in.
function M.job(args, input, done)
  local how = args[1]
  if how == "list" then done(list()) return end
  if how == "uuid" then done(morf.encoding.uuid()) return end
  if how == "lorem" then done(codec.lorem(tonumber(args[2]))) return end
  if how == "password" then
    local symbols = args[3] ~= "--no-symbols" and args[2] ~= "--no-symbols"
    done(password.generate(tonumber(args[2]) or M.LENGTHS[2], { symbols = symbols }))
    return
  end
  if how == "passphrase" then
    done(password.passphrase(tonumber(args[2]) or M.WORDS))
    return
  end
  local wanted = (args[2] == "-d" and DECODED[how]) or how
  local item = transforms.find(wanted)
  if not item then
    done(nil, "unknown transform: " .. tostring(how) .. " (eva-text list)")
    return
  end
  local text = input or words_after(args, args[2] == "-d" and 3 or 2)
  transforms.run(item, text, function(answer, why)
    if not answer then done(nil, why) return end
    done(answer, nil, item.bytes or ending_newline(answer))
  end)
end

return M
