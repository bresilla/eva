-- The Bar's "When the bar is full" page: what goes into the dot first, what stays
-- to the last, and which indicators never show. In the page template.
local P = require("themes.layouts.page")
local F = require("themes.layouts.option_rows")

local V = {}
local MODULES = 16

-- What can fold on the bar now, in its zones' order, read from the bar's model
-- once it has one: `{ id, name }` each.
local function foldable()
  local model, out, named = require("bar").model, {}, {}
  if not model then return out end
  for _, module in ipairs(model.modules) do named[module.id] = module end
  for _, zone in ipairs(model.board.zones) do
    for _, item in ipairs(model.board.shown(zone)) do
      local module = named[item.id]
      if module and module.tier ~= 0 and #out < MODULES then out[#out + 1] = module end
    end
  end
  return out
end

--- The page at `w` x `h`. `status` is shell/status_model.lua.
function V.build(status, w, h)
  local inner = P.inner(w)
  local indicators = { id = "bar-fold-indicators", width = w, title = "Status icons",
    P.row { id = "bar-fold-about", width = inner, icon = "info", title = "When room runs out",
      subtitle = "Icons fold into the dot in the order set here" },
    P.row { id = "bar-fold-always", width = inner, icon = "mic", title = "Always shown",
      subtitle = "A microphone, camera or screen share in use" },
  }
  local with_hide = {}
  for i, rule in ipairs(status.RULES) do with_hide[i] = rule end
  with_hide[#with_hide + 1] = status.HIDE
  for _, row in ipairs(status.ruled()) do
    indicators[#indicators + 1] = F.select { id = "bar-fold-" .. row.key, width = inner, title = row.label, choices = with_hide,
      read = function() return status.rule(row.key) end, set = function(rule) status.set_rule(row.key, rule) end }
  end

  local on_bar = { id = "bar-fold-modules", width = w, title = "On the bar",
    visible = function() return #foldable() > 0 end }
  for index = 1, MODULES do
    local function module() return foldable()[index] end
    local row = F.select { id = "bar-fold-module-" .. index, width = inner, choices = status.RULES,
      title = function() local item = module() return item and item.name or "" end,
      read = function() local item = module() return item and status.rule(item.id) or "auto" end,
      set = function(rule)
        local item = module()
        if item then status.set_rule(item.id, rule) end
      end }
    row.visible = function() return module() ~= nil end
    on_bar[#on_bar + 1] = row
  end

  return P.page { id = "bar-fold-scroll", width = w, height = h, P.section(indicators), P.section(on_bar) }
end

return V
