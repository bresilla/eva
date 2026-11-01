-- Reduce motion: everything lands at once. Every behavior, entrance, exit,
-- spring, claim and play passes through here and lands.
local morf = require("morf")
local ui = require("morf.ui")
local M = {}

local AT_ONCE = { duration = 0 }

local function land_step(step)
  for _, nested in ipairs(step) do land_step(nested) end
  for _, nested in ipairs(step.parallel or step.sequence or {}) do land_step(nested) end
  step.delay, step.loops, step.alternate = nil, nil, nil
  if step.duration then step.duration = 1 end
  if step.pause then step.pause = 1 end
end

--- From here on nothing in this runtime travels. A reload starts a new one.
function M.install()
  for name, make in pairs(ui) do
    if type(make) == "function" and name:match("^%u") then
      ui[name] = function(props, ...)
        if type(props) == "table" then
          props.behavior, props.enter, props.exit, props.stretch = nil, nil, nil, nil
        end
        return make(props, ...)
      end
    end
  end
  ui.spring = function() return AT_ONCE end
  local claims = ui.claims
  ui.claims = function(node, spec)
    for key, entry in pairs(spec) do
      if key == "motion" then spec.motion = AT_ONCE
      elseif type(entry) == "table" and entry.motion then entry.motion = AT_ONCE end
    end
    return claims(node, spec)
  end
  local play = morf.animation.play
  morf.animation.play = function(group)
    land_step(group)
    return play(group)
  end
end

return M
