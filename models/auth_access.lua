-- The accessibility choices of a login screen: larger text, higher contrast,
-- less motion, an on-screen keyboard. Kept by the greeter between logins.
local morf = require("morf")
local memory = require("models.greet_memory")
local M = {}

M.OPTIONS = {
  { key = "large", icon = "format_size", name = "Larger text" },
  { key = "contrast", icon = "contrast", name = "High contrast" },
  { key = "motion", icon = "animation", name = "Reduce motion" },
  { key = "keyboard", icon = "keyboard", name = "On-screen keyboard" },
}

function M.new()
  local kept = memory.access()
  local self = { open = morf.signal("greet.access.open", false) }
  local values = {}
  for _, option in ipairs(M.OPTIONS) do
    values[option.key] = morf.signal("greet.access." .. option.key, kept[option.key] == true)
  end
  function self.on(key) return values[key]:get() end
  function self.set(key, on)
    values[key]:set(on == true)
    local out = {}
    for _, option in ipairs(M.OPTIONS) do out[option.key] = values[option.key]:get() end
    memory.set_access(out)
  end
  function self.toggle(key) self.set(key, not values[key]:get()) end
  --- What the layout must be rebuilt for.
  function self.signature()
    return tostring(values.large:get()) .. tostring(values.motion:get()) .. tostring(values.keyboard:get())
  end
  return self
end

return M
