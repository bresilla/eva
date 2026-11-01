-- eva-audio: the two pages of shell/sound_model.lua and the equalizer of
-- shell/equalizer_model.lua in a window, and what the command line asks of the
-- sound server. No nodes, and no second model of the sound.
local morf = require("morf")
local sys = require("common.sys")

local M = {
  tab = morf.signal("audio.tab", 1),
  editing = morf.signal("audio.editing", false),
  shell_up = morf.signal("audio.shell_up", true),
}

M.TABS = { "output", "input", "equalizer" }

local AUDIOGRAM = "settings.sound/equalizer/audiogram"
local STARTING_MS = 500
local SERVER_MS = 100
local SERVER_TRIES = 30

--- Puts the pages on the sound server, each reading only while it is on show.
function M.start()
  local sound = require("sound_model")
  local presentation = require("presentation")
  M.output = sound.new("output", function() return M.tab:get() == 1 end)
  M.input = sound.new("input", function() return M.tab:get() == 2 end)
  M.output.open_equalizer = function() M.tab:set(3) end
  local equalizer = require("equalizer_model")
  M.equalizer = equalizer
  equalizer.open_editor = function()
    M.editing:set(true)
    presentation.set(AUDIOGRAM, true)
  end
  equalizer.leave_editor = function()
    presentation.set(AUDIOGRAM, false)
    M.editing:set(false)
  end
  morf.effect("eva.audio.equalizer", function()
    equalizer.get("enabled")
    morf.time.timer(STARTING_MS, M.ask_shell, false)
  end)
end

--- The equalizer's state from the shell, which runs the filter.
function M.ask_shell()
  sys.shell({ "equalizer-state" }, { read = true }, function(reply)
    M.shell_up:set(type(reply) == "table")
    if type(reply) ~= "table" then
      M.equalizer.follow { status = "off", error = "The equalizer runs in the shell, and the shell is not running." }
      return
    end
    M.equalizer.follow(reply)
    if reply.status == "starting" then morf.time.timer(STARTING_MS, M.ask_shell, false) end
  end)
end

function M.select(name)
  for index, key in ipairs(M.TABS) do
    if key == name then M.tab:set(index) return true end
  end
  return false
end

--- Restarts the sound server, for what only that fixes.
function M.restart()
  sys.run({ "systemctl", "--user", "restart", "wireplumber", "pipewire", "pipewire-pulse" }, {}, function(result)
    if result.dry then return end
    if result.ok then sys.notify("Sound server restarted")
    else sys.notify("Could not restart the sound server", result.stderr, "critical") end
  end)
end

-- --------------------------------------------------------- the command line --

-- The rows of a list model.
local function rows(list)
  local out = {}
  for index = 1, list and list:len() or 0 do out[index] = list:get(index) end
  return out
end

local function microphones()
  local out = {}
  for _, row in ipairs(rows(morf.audio.sources)) do
    if not tostring(row.name or ""):match("%.monitor$") then out[#out + 1] = row end
  end
  return out
end

--- The device after the default one, round to the first.
function M.next_of(list)
  for index, row in ipairs(list) do
    if row.default then return list[index % #list + 1] end
  end
  return list[1]
end

local function words()
  local lines = {}
  local function device(row)
    lines[#lines + 1] = ("%s %s %d%%%s"):format(row.default and "*" or " ", row.description or row.name,
      math.floor(row.volume * 100 + 0.5), row.muted and " muted" or "")
  end
  for _, row in ipairs(rows(morf.audio.sinks)) do device(row) end
  for _, row in ipairs(microphones()) do device(row) end
  for _, row in ipairs(rows(morf.audio.streams)) do
    if not tostring(row.app_id or ""):match("^morf%.") then
      lines[#lines + 1] = ("  %s %s %d%%%s"):format(row.direction == "record" and "<" or ">",
        row.app_name or row.binary or "app", math.floor(row.volume * 100 + 0.5), row.muted and " muted" or "")
    end
  end
  return table.concat(lines, "\n")
end

-- What `eva-audio ARGS` asks, once the server has answered.
local function answer(args, done)
  local how = args[1]
  if how == "list" then
    done(words())
  elseif how == "next" then
    local list = args[2] == "input" and microphones() or rows(morf.audio.sinks)
    local chosen = M.next_of(list)
    if not chosen then done(nil, "no device") return end
    if sys.dry() then done(chosen.description or chosen.name) return end
    if not morf.audio.set_default(chosen.id) then done(nil, "the sound server refused") return end
    morf.time.timer(SERVER_MS, function() done(chosen.description or chosen.name) end, false)
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

--- `done(text, why)` with the answer to `args`.
function M.job(args, done)
  local tries = 0
  local function wait()
    if morf.audio.available() then answer(args, done) return end
    tries = tries + 1
    if tries >= SERVER_TRIES then done(nil, "no sound server") return end
    morf.time.timer(SERVER_MS, wait, false)
  end
  wait()
end

return M
