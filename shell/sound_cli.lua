-- `eva-audio ARGS`: what the command line asks of the sound server, with no
-- window and no shell: `next [input]` makes the device after the default
-- one the default, `list` names the devices and the apps that use them.
-- apps/common/job runs it. No nodes.
local morf = require("morf")
local host = require("lib.services.host")

local M = {}

local SERVER_MS = 100
local SERVER_TRIES = 30

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

-- What `args` asks, once the server has answered.
local function answer(args, done)
  local how = args[1]
  if how == "list" then
    done(words())
  elseif how == "next" then
    local list = args[2] == "input" and microphones() or rows(morf.audio.sinks)
    local chosen = M.next_of(list)
    if not chosen then done(nil, "no device") return end
    if host.dry() then done(chosen.description or chosen.name) return end
    if not morf.audio.set_default(chosen.id) then done(nil, "the sound server refused") return end
    morf.time.timer(SERVER_MS, function() done(chosen.description or chosen.name) end, false)
  else
    done(nil, "unknown command: " .. tostring(how))
  end
end

--- `done(text, why)` with the answer to `args`.
function M.job(args, done)
  if morf.env("EVA_FAKE_AUDIO") == "1" then require("sound_fake").install() end
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
