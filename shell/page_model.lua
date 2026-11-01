-- What every system Settings page shares: whether it is on show, what its last
-- action said, and a first read as it comes on show. No nodes.
local morf = require("morf")
local M = {}

local serial = 0

--- A page model for `key`. `active` (fn) is whether it is on show; the
--- presentation's scope for that page by default.
function M.new(key, active)
  serial = serial + 1
  local name = "eva.page." .. key .. "." .. serial
  local model = { key = key, active = active or require("presentation").active("settings." .. key),
    message = morf.signal(name .. ".message", ""), failed = morf.signal(name .. ".failed", false),
    busy = morf.signal(name .. ".busy", false) }
  function model.say(text, failed)
    model.failed:set(failed == true)
    model.message:set(text or "")
  end
  --- `done` for an action: says `why` on failure, nothing on success.
  function model.answer(after)
    return function(result, why)
      model.busy:set(false)
      if result == nil or result == false then
        model.say(tostring(why or "It did not work"), true)
      else
        model.say("")
        if after then after(result) end
      end
    end
  end
  --- Runs `fn(answer)` once on show, marking the page busy.
  function model.action(fn, after)
    if not model.active() then return false end
    model.busy:set(true)
    model.say("")
    local answer = model.answer(after)
    local ok, sent, why = pcall(fn, answer)
    if not ok then answer(nil, sent) return false end
    if sent == nil and why then answer(nil, why) return false end
    return true
  end
  --- Calls `fn` each time the page comes on show.
  function model.on_show(fn)
    local was = false
    morf.effect(name .. ".show", function()
      local now = model.active() == true
      if now and not was then fn() end
      if not now and was then model.say("") end
      was = now
    end)
  end
  return model
end

return M
