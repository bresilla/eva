-- eva-phone's page in the Tools window: a dial pad that finds people by their
-- letters, the recent calls and the contacts. The call itself is the shell's.
local morf = require("morf")
local model = require("apps.phone.model")

local M = {}

local started, visible = false, morf.signal("eva.tools.phone.visible", false)
local function ready()
  if started then return end
  started = true
  -- The recents, looked at on show, are seen.
  morf.effect("phone.seen", function()
    if visible:get() and model.tab:get() == 2 then model.seen() end
  end)
end

--- The page, `w` by `h`.
function M.build(w, h)
  ready()
  return require("apps.phone.view").build(function() return w end, function() return h end)
end

--- `eva-phone tel:NUMBER`: the number typed.
function M.open(args)
  if args[1] and args[1] ~= "" then model.number:set((args[1]:gsub("^tel:", ""))) end
end

function M.shown(on) visible:set(on) end

-- `morf ipc call tool phone VERB`.
M.verbs = {
  state = function()
    return { number = model.number:get(), message = model.message:get(), recents = #model.recents(),
      people = #model.people(), matches = #model.matches(), tab = model.tab:get(), can_call = model.can_call(),
      unseen = model.unseen() }
  end,
  tab = function(index) model.tab:set(tonumber(index)) return true end,
  press = function(keys)
    for key in tostring(keys):gmatch(".") do model.press(key) end
    return model.number:get()
  end,
  call = function(number) return model.call(number) end,
}

return M
