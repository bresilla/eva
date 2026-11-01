-- The devices a person wants when they are there: as devices come and go, one
-- on the list that outranks the default becomes the default.
local morf = require("morf")
local config = require("config")
local M = {}

--- Of `rows` (devices with `name` and `id`), the one to use given `preferred`
--- (names, most wanted first) and the current default's name, or nil to stay.
function M.wanted(rows, preferred, current)
  local rank, here = {}, {}
  for index, name in ipairs(preferred or {}) do rank[name] = index end
  for _, row in ipairs(rows or {}) do here[row.name] = row end
  for index, name in ipairs(preferred or {}) do
    local row = here[name]
    if row then
      if name == current then return nil end
      local held = rank[current]
      if not held or index < held then return row end
      return nil
    end
  end
  return nil
end

local function names(list)
  local out = {}
  for index = 1, list:len() do
    local row = list:get(index)
    if row then out[#out + 1] = row end
  end
  return out
end

--- Follows outputs and inputs, on the primary output.
function M.start(audio)
  audio = audio or morf.audio
  if morf.window.primary and not morf.window.primary() then return end
  if not audio or not audio.sinks then return end
  local dry = require("lib.services.host").dry()
  local seen = { output = nil, input = nil }
  local function follow(kind, list, default, key)
    morf.effect("eva.audio.rules." .. kind, function()
      local ok, rows = pcall(function() return audio.available() and names(list) or {} end)
      rows = ok and rows or {}
      local present = {}
      for _, row in ipairs(rows) do present[#present + 1] = row.name end
      table.sort(present)
      local now = table.concat(present, "\n")
      local changed = seen[kind] ~= nil and seen[kind] ~= now
      seen[kind] = now
      if not changed then return end
      local current = default()
      local row = M.wanted(rows, config.get(key), current and current.name)
      if row and not dry then pcall(audio.set_default, row.id) end
    end)
  end
  follow("output", audio.sinks, audio.default_sink, "sound.preferred_outputs")
  follow("input", audio.sources, audio.default_source, "sound.preferred_inputs")
end

return M
