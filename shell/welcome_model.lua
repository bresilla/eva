-- The first-run welcome: which step it is on, and whether this person has had
-- it. It is a Settings page, so it opens in the Settings window, and it opens
-- the real pages. Only the shell starts
-- it: the lock and the greeter never load this file. No nodes.
local morf = require("morf")
local host = require("lib.services.host")
local M = { DELAY_MS = 1500 }

M.step = morf.signal("eva.welcome.step", 1)

local function seen_path() return morf.paths.state("welcome-seen") end
local function has_keys() return not require("responsive").touch() end

--- The steps of this device, in order: keys need a keyboard.
function M.steps()
  local out = { "look", "network", "gestures" }
  if has_keys() then out[#out + 1] = "keys" end
  return out
end

--- Whether this person has been here before: anything the
--- shell keeps from a past session.
local function returning()
  local settings = morf.env and morf.env("EVA_SETTINGS")
  if (not settings or settings == "") and morf.fs.exists(morf.paths.state("eva.json")) then return true end
  return morf.fs.exists(morf.paths.state("notifications/history.json"))
    or morf.fs.exists(morf.paths.state("calendar-reminders.json"))
end

local function mark() morf.fs.write(seen_path(), "1\n", { atomic = true, parents = true }) end

--- Opens it from the first step.
function M.open()
  M.step:set(1)
  return require("pages").settings("welcome")
end

--- Shows it, the first time a person logs in, on the primary screen. Once only:
--- the mark goes down as it opens, and Settings has it from then on.
--- EVA_WELCOME=0 keeps it away and =1 brings it to a run that would not have it.
function M.start()
  if morf.window.primary and not morf.window.primary() then return false end
  local wanted = morf.env and morf.env("EVA_WELCOME")
  if wanted == "0" then return false end
  local headless = morf.capabilities and morf.capabilities.headless
  if wanted ~= "1" and (host.dry() or headless) then return false end
  if morf.fs.exists(seen_path()) then return false end
  mark()
  if returning() then return false end
  morf.time.timer(M.DELAY_MS, M.open, false)
  return true
end

local function shut()
  require("utilities").close()
  M.step:set(1)
end

function M.next()
  if M.step:get() >= #M.steps() then return shut() end
  M.step:set(M.step:get() + 1)
end
function M.back() M.step:set(math.max(1, M.step:get() - 1)) end
function M.skip() shut() end

--- Whether the step on show is the last.
function M.last() return M.step:get() >= #M.steps() end
--- Whether there is a step to go back to.
function M.can_back() return M.step:get() > 1 end

--- Where this machine is online: `{ title, subtitle }`.
function M.network()
  local net = require("services").net
  local state = net and net.state
  if not state or not state.available then
    return { title = "No network service", subtitle = "NetworkManager is not running here" }
  end
  if state.wifi.connected then return { title = "Connected to " .. state.wifi.ssid, subtitle = "Pick another, or leave it be" } end
  if state.wired.connected then return { title = "Connected by cable", subtitle = "Wi-Fi is there if you want it" } end
  return { title = "Not connected", subtitle = "Pick a network" }
end

--- Opens eva-keys, with every key there is.
function M.all_keys() return host.open_tool("keys") end

return M
