-- Text that turns into its next value: the new words stand at once, and the
-- old ones' outline melts into them. Non-visual: each theme gives its tempo.
local morf = require("morf")
local M = {}
local serial = 0

--- Builds text with `make` from `props`, whose `text` is a value or a binding;
--- `motion` is the `{ duration, easing }` of a change.
function M.make(make, props, motion)
  local source = props.text
  local function wanted()
    local value = source
    if type(value) == "function" then value = value() end
    return tostring(value or "")
  end
  local shown = wanted()
  props.text, props.morph = shown, nil
  local node = make(props)
  local running
  serial = serial + 1
  -- `text` is always the truth: the morph runs back from the old words to it.
  morf.effect("eva.text-morph." .. serial, function()
    local now = wanted()
    if now == shown then return end
    if running then running:stop() end
    node.morph_to, node.morph_progress, node.text = shown, 1, now
    shown = now
    running = morf.animation.play {
      { node = node, property = "morph_progress", to = 0, duration = motion.duration, easing = motion.easing },
      on_finished = function(reason)
        if reason ~= "completed" then return end
        running = nil
        node.morph_to = ""
      end,
    }
  end, { owner = node })
  return node
end

return M
