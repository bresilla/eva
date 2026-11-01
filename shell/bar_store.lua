-- Where the bar's board keeps its lists: by form factor, unless the screen has
-- its own (`bar.outputs`), and whether the bar stands on that screen. No nodes.
local morf = require("morf")
local config = require("config")
local M = {}

local function copy(list)
  local out = {}
  for i, v in ipairs(list or {}) do out[i] = v end
  return out
end

--- The name of the screen this runtime draws on.
function M.output()
  morf.window.screens_revision()
  return ((morf.screens or {})[1] or {}).name or ""
end

local function rows() return config.get("bar.outputs") or {} end

--- The row of screen `name`, or nil.
function M.row(name)
  for _, row in ipairs(rows()) do if row.name == name then return row end end
end

-- `change(row)` on a copy of the row of `name`; one left with nothing to say
-- is dropped.
local function edit(name, change)
  local out, found = {}, false
  for _, row in ipairs(rows()) do
    if row.name == name then
      found = true
      local next_row = {}
      for key, value in pairs(row) do next_row[key] = value end
      change(next_row)
      if (next_row.on or "") ~= "" or next_row.modules then out[#out + 1] = next_row end
    else
      out[#out + 1] = row
    end
  end
  if not found then
    local next_row = { name = name, on = "" }
    change(next_row)
    if (next_row.on or "") ~= "" or next_row.modules then out[#out + 1] = next_row end
  end
  config.set("bar.outputs", out)
end

--- What screen `name` says of the bar: "on", "off" or "" to follow the setting.
function M.on(name)
  local row = M.row(name)
  return row and row.on or ""
end

function M.set_on(name, value)
  edit(name, function(row) row.on = value end)
end

--- Whether screen `name` keeps its own modules.
function M.own(name)
  local row = M.row(name)
  return row ~= nil and row.modules ~= nil
end

--- Screen `name` on its own modules, starting from the form's, or back on them.
function M.set_own(name, own, form)
  edit(name, function(row)
    if not own then
      row.modules, row.small = nil, nil
      return
    end
    row.modules = {}
    for _, zone in ipairs(require("bar_layout").ZONES) do
      row.modules[zone] = copy(config.get("bar.modules." .. form .. "." .. zone))
    end
    row.small = copy(config.get("bar.small." .. form))
  end)
end

--- The board's store for this screen: `form()` names the form factor and
--- `output()` the screen.
function M.new(form, output)
  local store = {}
  local function own()
    local row = M.row(output())
    return row and row.modules and row or nil
  end
  function store.order(zone)
    local row = own()
    if row then return row.modules[zone] or {} end
    return config.get("bar.modules." .. form() .. "." .. zone)
  end
  function store.set_order(zone, list)
    if own() then
      edit(output(), function(row)
        local modules = {}
        for key, value in pairs(row.modules) do modules[key] = value end
        modules[zone] = list
        row.modules = modules
      end)
    else
      config.set("bar.modules." .. form() .. "." .. zone, list)
    end
  end
  function store.small()
    local row = own()
    if row then return row.small or {} end
    return config.get("bar.small." .. form())
  end
  function store.set_small(list)
    if own() then edit(output(), function(row) row.small = list end)
    else config.set("bar.small." .. form(), list) end
  end
  function store.reset()
    if own() then M.set_own(output(), true, form()) return end
    for _, zone in ipairs(require("bar_layout").ZONES) do config.reset("bar.modules." .. form() .. "." .. zone) end
    config.reset("bar.small." .. form())
  end
  return store
end

return M
