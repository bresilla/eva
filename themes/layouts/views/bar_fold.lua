-- The Bar's "When the bar is full" page: what goes into the dot first, what stays
-- to the last, and which indicators never show. In the page template.
local P = require("themes.layouts.page")
local F = require("themes.layouts.option_rows")

local V = {}

--- The page at `w` x `h`. `status` is shell/status_model.lua, `board` the bar's.
function V.build(status, board, modules, w, h)
  local inner = P.inner(w)
  local function rule_row(id, title, rules)
    return F.choices { id = "bar-fold-" .. id, width = inner, title = title, choices = rules,
      read = function() return status.rule(id) end, set = function(rule) status.set_rule(id, rule) end }
  end

  local indicators = { id = "bar-fold-indicators", width = w, title = "Status icons",
    note = "A microphone or camera in use always shows" }
  local with_hide = {}
  for i, rule in ipairs(status.RULES) do with_hide[i] = rule end
  with_hide[#with_hide + 1] = status.HIDE
  for _, row in ipairs(status.ruled()) do indicators[#indicators + 1] = rule_row(row.key, row.label, with_hide) end

  local on_bar = { id = "bar-fold-modules", width = w, title = "On the bar", note = "Folds first, or stays to the last" }
  local tiers = {}
  for _, module in ipairs(modules) do tiers[module.id] = module end
  for _, zone in ipairs(board.zones) do
    for _, item in ipairs(board.shown(zone)) do
      local module = tiers[item.id]
      if module and module.tier ~= 0 then on_bar[#on_bar + 1] = rule_row(item.id, module.name, status.RULES) end
    end
  end

  return P.page { id = "bar-fold-scroll", width = w, height = h,
    P.section(indicators), #on_bar > 0 and P.section(on_bar) or nil }
end

return V
