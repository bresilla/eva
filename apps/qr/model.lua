-- eva-qr's state. The password lives in its text input and in `password` below,
-- never in a signal, and is encoded in this process by lib/util/qr.lua. The code it
-- makes stays out of the signals with it: `revision` says only that there is a new
-- one. No nodes.
local morf = require("morf")
local sys = require("apps.common.sys")
local config = require("config")
local qr = require("lib.util.qr")

local M = {
  mode = morf.signal("qr.mode", 1),
  text = morf.signal("qr.text", ""),
  ssid = morf.signal("qr.ssid", ""),
  security = morf.signal("qr.security", 1),
  hidden = morf.signal("qr.hidden", false),
  level = morf.signal("qr.level", 2),
  revision = morf.signal("qr.revision", 0),
  full = morf.signal("qr.full", false),
  saved = morf.signal("qr.saved", {}),
  message = morf.signal("qr.message", ""),
}

M.MODES = { "Text", "Wi-Fi" }
M.LEVELS = qr.LEVELS
M.SECURITY = qr.SECURITY
M.WAIT = 150

local TOO_LONG = "That is too long for a code"

local password = ""
local code
local pending
local making

-- Puts `value` in the password's input: set by the view.
local fill = function() end

--- What the code holds: the text, or the network's string with its password.
local function payload()
  if M.mode:get() == 1 then return M.text:get() end
  if M.ssid:get() == "" then return "" end
  return qr.wifi({ ssid = M.ssid:get(), security = M.SECURITY[M.security:get()], hidden = M.hidden:get() }, password)
end

local function encoded(data, done)
  return qr.encode(data, M.LEVELS[M.level:get()], done)
end

local function show(next_code, words)
  code = next_code
  M.message:set(words or "")
  M.revision:set(M.revision:get() + 1)
end

--- Makes the code from what the fields hold now.
function M.encode()
  pending = nil
  if making then making.cancel() end
  making = nil
  local data = payload()
  if data == "" then
    show(nil)
    return
  end
  making = encoded(data, function(next_code)
    show(next_code, next_code == nil and TOO_LONG or "")
  end)
end

--- Makes the code a moment after the last change.
function M.touch()
  if pending then pending:cancel() end
  pending = morf.time.timer(M.WAIT, M.encode, false)
end

for _, signal in ipairs { M.mode, M.text, M.ssid, M.security, M.hidden, M.level } do
  local first = true
  morf.effect("qr.follow." .. tostring(signal), function()
    signal:get()
    if first then first = false return end
    M.touch()
  end)
end

--- The password's input changed.
function M.set_password(value)
  password = value or ""
  M.touch()
end

--- How the view fills the password's input.
function M.on_fill(action) fill = action end

--- Modules across the code, 0 with none. A tracked read.
function M.size()
  M.revision:get()
  return code and code.size or 0
end

--- The code's outline. A tracked read.
function M.path()
  M.revision:get()
  return code and code.path or ""
end

--- Whether there is a code to do anything with.
function M.ready() return M.size() > 0 end

-- What the fields hold now as a PNG: `done(bytes)`, nil where it will not fit.
local function picture(data, done)
  encoded(data, function(made)
    if not made then done(nil) return end
    qr.png(made, { scale = 12, quiet = 2 }, done)
  end)
end

--- The code as a PNG on the clipboard.
function M.copy()
  local data = payload()
  if data == "" then return false end
  picture(data, function(bytes)
    if not bytes then M.message:set(TOO_LONG) return end
    if not sys.dry() then morf.clipboard.set(bytes, "image/png") end
    M.message:set("Copied as an image")
  end)
  return true
end

local function folder()
  return morf.fs.expand(config.get("capture.folder") or "~/Pictures/Captures")
end

--- Where a press of Save puts the code.
function M.default_path()
  return folder() .. "/qr_" .. morf.time.format("%Y%m%d_%H-%M-%S") .. ".png"
end

--- Writes the code to `path`: `done(ok, words)`.
function M.save(path, done)
  local data = payload()
  local function finish(ok, words)
    M.message:set(words)
    if done then done(ok, words) end
  end
  if data == "" then finish(false, "Nothing to make a code of") return end
  picture(data, function(bytes)
    if not bytes then finish(false, TOO_LONG) return end
    if sys.dry() then finish(true, "Would save " .. path) return end
    local ok = pcall(morf.fs.write, path, bytes, { parents = true })
    if not ok then finish(false, "Could not write " .. path) return end
    finish(true, "Saved " .. path)
  end)
end

-- ---------------------------------------------------------- saved networks --

--- `nmcli -t -f NAME,TYPE`'s lines: the names of the Wi-Fi connections.
function M.parse_saved(lines)
  local out = {}
  for line in tostring(lines or ""):gmatch("[^\r\n]+") do
    local name = line:match("^(.*):802%-11%-wireless$")
    if name then out[#out + 1] = (name:gsub("\\(.)", "%1")) end
  end
  table.sort(out, function(a, b) return a:lower() < b:lower() end)
  return out
end

function M.has_saved() return #M.saved:get() > 0 end

--- Lists the networks NetworkManager has saved.
function M.load_saved()
  if not sys.has("nmcli") then return end
  sys.run({ "nmcli", "-t", "-f", "NAME,TYPE", "connection", "show" }, { read = true, timeout_ms = 5000 }, function(result)
    if result.ok then M.saved:set(M.parse_saved(result.stdout)) end
  end)
end

local SECURITY_OF = { ["wpa-psk"] = 1, sae = 1, ["wpa-eap"] = 1, none = 2 }

--- Fills the fields from saved network `name`, its secret into the input only.
function M.pick_saved(name)
  M.ssid:set(name)
  sys.run({ "nmcli", "-e", "no", "-s", "-g", "802-11-wireless-security.key-mgmt,802-11-wireless-security.psk,802-11-wireless.hidden",
    "connection", "show", "id", name }, { read = true, timeout_ms = 5000 }, function(result)
    local lines = {}
    for line in ((result.stdout or "") .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
    local key, secret, hidden = lines[1] or "", lines[2] or "", lines[3] or ""
    M.security:set(SECURITY_OF[key] or 3)
    M.hidden:set(hidden == "yes")
    if result.ok and secret ~= "" then
      fill(secret)
      password = secret
      M.touch()
    elseif result.ok and key ~= "" then
      M.message:set("NetworkManager kept the password back: type it")
    end
  end)
end

-- ---------------------------------------------------------- the command line --

--- Takes `eva-qr`'s words: what to show, and `png` where to write it. `input`
--- is what was piped in: the password of a network, or the text after `-`.
function M.take(words, input)
  local index, png = 1, nil
  if words[1] == "--png" then
    png, index = words[2], 3
  end
  local rest = {}
  for at = index, #words do rest[#rest + 1] = words[at] end
  input = input and input:gsub("\r?\n$", "") or nil
  if rest[1] == "wifi" then
    M.mode:set(2)
    local names = {}
    local at = 2
    while rest[at] do
      local word = rest[at]
      if word == "--hidden" then M.hidden:set(true)
      elseif word == "--security" then
        at = at + 1
        for number, name in ipairs(M.SECURITY) do
          if name == rest[at] then M.security:set(number) end
        end
      else names[#names + 1] = word end
      at = at + 1
    end
    M.ssid:set(table.concat(names, " "))
    password = input or ""
  elseif rest[1] == "-" then
    M.text:set(input or "")
  else
    M.text:set(table.concat(rest, " "))
  end
  return png
end

--- What the tool holds, for a test or a scenario: never the password.
function M.state()
  return { mode = M.MODES[M.mode:get()], text = M.text:get(), ssid = M.ssid:get(),
    security = M.SECURITY[M.security:get()], hidden = M.hidden:get(), level = M.LEVELS[M.level:get()],
    size = M.size(), has_password = password ~= "", full = M.full:get(), saved = M.saved:get(),
    message = M.message:get() }
end

return M
