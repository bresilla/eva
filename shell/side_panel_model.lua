-- Navigation and presentation state, independent of a theme's tab geometry
-- and transition timing. Page builders remain injected by the controllers.
local morf = require("morf")
local M = {}
function M.new(ctx)
  local model = { id = ctx.id, edge = ctx.edge, tabs = {},
    tab = require("themes.session").keep("eva." .. ctx.id .. ".tab", 1),
    displayed = require("themes.session").keep("eva." .. ctx.id .. ".displayed", 1),
    opened = require("themes.session").keep("eva." .. ctx.id .. ".opened", false),
  }
  local builders = {}
  for i, tab in ipairs(ctx.tabs) do
    model.tabs[i] = { key = tab.key, name = tab.name, icon = tab.icon, fit = tab.fit }
    builders[tab.key] = tab.build
  end
  -- A tab kept through a rebuild that left this panel with fewer tabs.
  if not model.tabs[model.tab:get()] then model.tab:set(1) model.displayed:set(1) end
  --- How tall the page on show wants to stand, or nil for all there is.
  function model.fit()
    local tab = model.tabs[model.tab:get()]
    return tab and tab.fit and tab.fit() or nil
  end
  function model.index(key)
    for i, tab in ipairs(model.tabs) do if tab.key == key then return i end end
  end
  function model.select(key)
    local i = type(key) == "number" and key or model.index(key)
    if i and model.tabs[i] then model.tab:set(i) return i end
  end
  function model.showing(key)
    local tab = model.tabs[model.tab:get()]
    return tab ~= nil and tab.key == key
  end
  function model.present(index)
    if model.tabs[index] and index == model.tab:get() then model.displayed:set(index) end
  end
  function model.page(key, width, height) return builders[key](width, height) end
  function model.desk_size()
    local _, _, width, height = require("bar").desk()
    return width, height
  end
  morf.effect("eva." .. ctx.id .. ".presentation", function()
    local open, shown = model.opened:get(), model.displayed:get()
    for i, tab in ipairs(model.tabs) do
      require("presentation").set(ctx.id .. "." .. tab.key, open and shown == i)
    end
  end)
  return model
end
return M
