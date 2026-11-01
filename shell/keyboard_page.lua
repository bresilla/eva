-- The Settings page behind Eva's "On-screen keyboard". The view is the selected
-- theme's; this is its model.
local config = require("config")
local M = {}

local function flag(name)
  return {
    on = function() return config.get("keyboard." .. name) == true end,
    set = function(now) config.set("keyboard." .. name, now == true) end,
  }
end

function M.model()
  local layouts = require("keyboard_layouts")
  local model = { flag = flag, languages = layouts.all() }
  --- Whether language `id` is one of those to switch between.
  function model.has_language(id)
    for _, have in ipairs(config.get("keyboard.languages")) do if have == id then return true end end
    return false
  end
  function model.set_language(id, now)
    local out = {}
    for _, have in ipairs(config.get("keyboard.languages")) do
      if have ~= id then out[#out + 1] = have end
    end
    if now then out[#out + 1] = id end
    config.set("keyboard.languages", out)
  end
  function model.height() return config.get("keyboard.height") end
  function model.set_height(scale) config.set("keyboard.height", scale) end
  function model.bottom_gap() return config.get("keyboard.bottom_gap") end
  function model.set_bottom_gap(gap) config.set("keyboard.bottom_gap", gap) end
  function model.hand() return config.get("keyboard.hand") end
  function model.set_hand(hand)
    config.set("keyboard.hand", hand)
    if hand ~= "both" then config.set("keyboard.floating", false) end
  end
  function model.forget_words() require("keyboard_learn").forget() end
  return model
end

function M.page(w, h)
  return require("themes").view("keyboard_page").build(M.model(), w, h)
end

return M
