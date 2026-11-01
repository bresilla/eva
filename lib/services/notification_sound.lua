-- How a notification is heard: one seam, whatever the theme draws.
--
--   local sound = require("lib.services.notification_sound")
--   sound.play { event = "message-new-instant", file = "", volume = 60,
--     ring = "sound", through_silent = false }
--   sound.say("New message from Ada")
--
-- A sound theme's event sound, through the first player found: feedbackd where
-- it runs (sound or haptics, by its own profile), then `pw-play`, `paplay`,
-- `canberra-gtk-play`. The ring mode decides first: silent plays nothing,
-- vibrate only reaches feedbackd.
--
-- EVA_FAKE_SOUND names a file each request is appended to instead of playing.
local morf = require("morf")

local M = {}

local FEEDBACK, FEEDBACK_PATH = "org.sigxcpu.Feedback", "/org/sigxcpu/Feedback"
local EVENT = { low = "message-new-email", normal = "message-new-instant", critical = "dialog-warning" }
local PLAYERS = { "pw-play", "paplay" }

local function fake() local path = morf.env and morf.env("EVA_FAKE_SOUND") return path ~= "" and path or nil end
local function dry()
  local value = morf.env and morf.env("EVA_DRY_RUN")
  return value ~= nil and value ~= "" and value ~= "0"
end

local function log(line)
  local path = fake()
  local ok, was = pcall(morf.fs.read, path)
  morf.fs.write(path, (ok and type(was) == "string" and was or "") .. line .. "\n")
end

local function on_path(program)
  for dir in ((morf.env and morf.env("PATH") or "") .. ":/usr/bin:/usr/local/bin"):gmatch("[^:]+") do
    if morf.fs.exists(dir .. "/" .. program) then return true end
  end
  return false
end

--- The event for an urgency: 0 low, 1 normal, 2 critical.
function M.event(urgency)
  return urgency == 0 and EVENT.low or urgency == 2 and EVENT.critical or EVENT.normal
end

-- The directories a sound theme can stand in.
local function sound_dirs()
  local dirs = {}
  local home = morf.env and morf.env("XDG_DATA_HOME")
  dirs[#dirs + 1] = home and home ~= "" and home or (morf.fs.home() .. "/.local/share")
  local data = morf.env and morf.env("XDG_DATA_DIRS")
  for dir in ((data and data ~= "") and data or "/usr/local/share:/usr/share"):gmatch("[^:]+") do dirs[#dirs + 1] = dir end
  return dirs
end

--- The file an event sound lives in, or nil.
function M.find(event)
  for _, dir in ipairs(sound_dirs()) do
    for _, theme in ipairs { "freedesktop", "ocean", "oxygen" } do
      for _, ext in ipairs { ".oga", ".ogg", ".wav" } do
        local path = ("%s/sounds/%s/stereo/%s%s"):format(dir, theme, event, ext)
        if morf.fs.exists(path) then return path end
      end
    end
  end
end

local bus
local function feedback(event)
  bus = bus or require("lib.services.dbus").new({ bus = "session" })
  if not bus.has_owner(FEEDBACK) then return false end
  return bus.call_async(FEEDBACK, FEEDBACK_PATH, FEEDBACK, "TriggerFeedback",
    { "eva", event, { signature = "a{sv}", value = {} }, -1 }) == true
end

--- Plays `spec`; the word for what happened: "fake", "feedback", the player's
--- name, "silent", "dry" or "none".
function M.play(spec)
  local event = spec.event or EVENT.normal
  local ring = spec.ring or "sound"
  if ring == "silent" and not spec.through_silent then return "silent" end
  local file = spec.file or ""
  if file == "" then file = M.find(event) or "" end
  if fake() then
    log(("play event=%s file=%s volume=%s ring=%s"):format(event, file, tostring(spec.volume or 100), ring))
    return "fake"
  end
  if dry() then return "dry" end
  if feedback(event) then return "feedback" end
  if ring == "vibrate" and not spec.through_silent then return "silent" end
  local volume = math.max(0, math.min(100, tonumber(spec.volume) or 100)) / 100
  if file ~= "" then
    for _, player in ipairs(PLAYERS) do
      if on_path(player) then
        local argv = player == "pw-play" and { player, "--volume", ("%.2f"):format(volume), file }
          or { player, ("--volume=%d"):format(math.floor(volume * 65536)), file }
        morf.process.run(argv, {}, function() end)
        return player
      end
    end
  end
  if on_path("canberra-gtk-play") then
    morf.process.run({ "canberra-gtk-play", "-i", event }, {}, function() end)
    return "canberra-gtk-play"
  end
  return "none"
end

--- Reads `text` aloud; false without a speech tool.
function M.say(text)
  if fake() then log("say " .. tostring(text)) return true end
  if dry() or not on_path("spd-say") then return false end
  morf.process.run({ "spd-say", "--", tostring(text) }, {}, function() end)
  return true
end

return M
