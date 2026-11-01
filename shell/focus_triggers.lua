-- What a Focus mode can come on from: the clock, open apps, screens, the
-- charger, a game controller, screen sharing and fullscreen. Runs on the primary
-- screen. EVA_FAKE_FOCUS stands in for the machine: comma-separated words from
-- `sharing`, `fullscreen`, `charging`, `gamepad`, `app:CLASS`, `screens:N`.
local morf = require("morf")
local config = require("config")
local focus = require("focus_model")

local M = {}

local TICK, SHARE_POLL = 15000, 10000

local function fake()
  local spec = morf.env and morf.env("EVA_FAKE_FOCUS")
  if not spec or spec == "" then return nil end
  local out = { apps = {}, words = {}, screens = 1 }
  for word in spec:gmatch("[^,%s]+") do
    local app = word:match("^app:(.+)$")
    local screens = word:match("^screens:(%d+)$")
    if app then out.apps[app:lower()] = true
    elseif screens then out.screens = tonumber(screens)
    else out.words[word] = true end
  end
  return out
end
local FAKE = fake()

local function hyprland()
  local ok, lib = pcall(require, "lib.compositor.hyprland")
  return ok and lib.available() and lib or nil
end

local function open_apps()
  local apps = {}
  if FAKE then return FAKE.apps end
  local h = hyprland()
  local rows = h and h.state.clients
  for i = 1, rows and rows:len() or 0 do
    local row = rows:get(i)
    if (row.class or "") ~= "" then apps[row.class:lower()] = true end
  end
  return apps
end

local function outputs()
  local names = {}
  for _, screen in ipairs(morf.screens or {}) do names[screen.name] = true end
  return names
end

local function charging()
  if FAKE then return FAKE.words.charging == true end
  local ok, reading = pcall(function() return require("battery_status_model").read() end)
  return ok and type(reading) == "table" and reading.charging == true
end

-- A joystick handler in the kernel's device list.
local function gamepad()
  if FAKE then return FAKE.words.gamepad == true end
  local ok, text = pcall(morf.fs.read, morf.env("EVA_INPUT_DEVICES") or "/proc/bus/input/devices")
  return ok and type(text) == "string" and text:find("Handlers=[^\n]*js%d") ~= nil
end

--- Whether the compositor shows a fullscreen window.
function M.fullscreen()
  if FAKE then return FAKE.words.fullscreen == true end
  local h = hyprland()
  return h ~= nil and h.state.fullscreen == true
end

--- Whether a `pw-dump` listing holds a running screen capture stream.
function M.screen_stream(text)
  local ok, nodes = pcall(morf.json.decode, text or "")
  if not ok or type(nodes) ~= "table" then return false end
  for _, node in ipairs(nodes) do
    local info = type(node) == "table" and node.info or nil
    local props = type(info) == "table" and info.props or nil
    if type(props) == "table" and props["media.class"] == "Stream/Input/Video" and info.state == "running" then
      return true
    end
    if type(props) == "table" and props["media.class"] == "Video/Source" and info.state == "running"
      and tostring(props["node.name"] or ""):match("^xdp") then
      return true
    end
  end
  return false
end

local streaming = false
local function recording()
  local capture = package.loaded.capture
  return capture ~= nil and capture.recording ~= nil and capture.recording:get() == true
end
--- Whether the screen is going somewhere: eva's own recorder, or a PipeWire
--- screen capture stream.
function M.sharing()
  if FAKE then return FAKE.words.sharing == true end
  return streaming or recording()
end

local function poll_streams()
  if FAKE or (morf.capabilities and morf.capabilities.headless) then return end
  if config.get("focus.sharing") ~= true or not require("services").installed("pw-dump") then return end
  morf.process.run({ "pw-dump" }, {}, function(result)
    streaming = result ~= nil and result.ok == true and M.screen_stream(result.stdout)
  end)
end

--- What `focus.tick` reads now.
function M.seen()
  return { apps = open_apps(), screens = FAKE and FAKE.screens or #(morf.screens or {}), outputs = outputs(),
    charging = charging(), gamepad = gamepad() }
end

local function settle()
  local auto = ""
  if config.get("focus.sharing") and M.sharing() then auto = "sharing"
  elseif config.get("focus.fullscreen") and M.fullscreen() then auto = "fullscreen" end
  if focus.auto:get() ~= auto then focus.auto:set(auto) end
  focus.tick(M.seen())
end

local started = false
--- Starts following; the primary screen's job.
function M.start()
  if started then return end
  started = true
  settle()
  morf.time.timer(TICK, settle, true)
  morf.time.timer(SHARE_POLL, poll_streams, true)
  morf.effect("eva.focus.triggers", function()
    config.get("focus.sharing")
    config.get("focus.fullscreen")
    config.get("focus.modes")
    M.sharing()
    M.fullscreen()
    open_apps()
    morf.time.timer(1, settle, false)
  end)
end

M.settle = settle
return M
