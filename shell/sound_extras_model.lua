-- What the Sound pages add to the audio model: cards' profiles and codecs, the
-- event sound theme, and the preferred devices.
local morf = require("morf")
local config = require("config")
local extras = require("lib.services.sound_extras")
local page_model = require("page_model")

local M = {}

--- Adds to `model` (from sound_model). `key` is the page's.
function M.extend(model)
  local page = page_model.new(model.key, model.active)
  model.say, model.action, model.message, model.failed = page.say, page.action, page.message, page.failed
  local cards = morf.signal("eva." .. model.key .. ".cards", {})
  local themes = morf.signal("eva." .. model.key .. ".themes", {})
  local setting = model.kind == "output" and "sound.preferred_outputs" or "sound.preferred_inputs"

  local function refresh() extras.cards(function(rows) cards:set(rows) end) end
  page.on_show(function()
    refresh()
    themes:set(extras.themes())
  end)

  function model.cards() return cards:get() end
  function model.bluetooth_cards()
    local out = {}
    for _, card in ipairs(cards:get()) do if card.bluetooth then out[#out + 1] = card end end
    return out
  end
  function model.other_cards()
    local out = {}
    for _, card in ipairs(cards:get()) do
      if not card.bluetooth and #card.profiles > 1 then out[#out + 1] = card end
    end
    return out
  end
  function model.set_profile(card, profile)
    return model.action(function(done) extras.set_profile(card.name, profile.key, done) return true end, refresh)
  end

  function model.themes() return themes:get() end
  function model.theme() return config.get("sound.theme") or "" end
  function model.set_theme(row)
    config.set("sound.theme", row.key)
    return model.action(function(done) extras.apply(row.key, done) return true end)
  end
  function model.preview(row)
    return model.action(function(done) extras.preview(row, done) return true end)
  end

  function model.preferred() return config.get(setting) or {} end
  --- A preferred device's name as a person reads it, if it is here.
  function model.device_name(name)
    local list = model.devices
    for index = 1, list:len() do
      local row = list:get(index)
      if row and row.name == name then return row.description or name end
    end
    return name
  end
  local function store(list) config.set(setting, list) end
  local function copy()
    local list = {}
    for index, name in ipairs(model.preferred()) do list[index] = name end
    return list
  end
  --- Puts the default device on the list, last.
  function model.prefer_current()
    local now = model.default()
    if not now then return false end
    local list = copy()
    for _, name in ipairs(list) do if name == now.name then return false end end
    list[#list + 1] = now.name
    store(list)
    return true
  end
  function model.drop_preferred(index)
    local list = copy()
    table.remove(list, index)
    store(list)
  end
  function model.raise_preferred(index)
    local list = copy()
    if index < 2 or not list[index] then return end
    list[index - 1], list[index] = list[index], list[index - 1]
    store(list)
  end
  return model
end

return M
