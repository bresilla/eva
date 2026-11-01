-- The island: a pill grown out of the top of the frame, a layer of the frame's
-- own field, that morphs between what it is showing. State and actions; the look
-- is the theme's. It is off unless asked for.
local morf = require("morf")
local config = require("config")
local M = {}

-- What it can show, in the order a right press walks them.
M.FACES = { "auto", "media", "clock", "weather" }
M.face = morf.signal("eva.island.face", "auto")
M.open = morf.signal("eva.island.open", false)

function M.enabled() return config.get("island.enabled") == true end

--- What is on show now: the chosen face, or under "auto" the music when
--- something plays and the clock otherwise.
function M.showing()
  local face = M.face:get()
  if face ~= "auto" then return face end
  return require("media_state").something() and "media" or "clock"
end

--- The next face along.
function M.cycle()
  local at = 1
  for i, face in ipairs(M.FACES) do if face == M.face:get() then at = i end end
  M.face:set(M.FACES[at % #M.FACES + 1])
end

function M.toggle() M.open:set(not M.open:get()) end

--- The view's parts, or nil while it is off: `{ node, shape, panel }`.
function M.build(desk)
  if not M.enabled() then return nil end
  return require("themes").view("island").build(M, desk)
end

--- `island [on|off|toggle|next|state]`.
function M.verb(how)
  how = how or "state"
  if how == "on" or how == "off" then config.set("island.enabled", how == "on")
  elseif how == "toggle" then M.toggle()
  elseif how == "next" then M.cycle()
  elseif how ~= "state" then error("`" .. tostring(how) .. "`: on, off, toggle, next or state") end
  return { enabled = M.enabled(), face = M.face:get(), showing = M.showing(), open = M.open:get() }
end

return M
