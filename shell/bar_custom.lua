-- Bar modules a person writes. No nodes.
--
-- From a command, in `bar.custom`: `{ id, name, icon, command, interval, stream,
-- tooltip, press, right }`. Its output is the module's text, or JSON with any of
-- `text`, `tooltip`, `icon`, `tone` and `percentage`. `interval` is how often it
-- runs, in ms (0 once); with `stream` it keeps running and each line it prints is
-- a new reading.
--
-- From Lua, in a root on the search path: `<root>/plugin/*.lua` run at startup,
-- in order, each registering what it adds:
--
--     local bar = require("eva.bar")
--     bar.modules["ups"] = { name = "UPS", icon = "battery_saver",
--       text = function() return "98%" end, press = function() end }
--
-- A module is the same table shell/bar_modules.lua keeps. A file that fails is
-- reported and the rest load. Files run as text, in the shell's own Lua, as the
-- person's own code.
local morf = require("morf")
local M = {}

local parsed = {}

--- What a command printed as a reading: JSON's fields, or the text itself.
function M.parse(output)
  local text = tostring(output or ""):match("^%s*(.-)%s*$")
  if text:sub(1, 1) == "{" then
    local ok, value = pcall(morf.json.decode, text)
    if ok and type(value) == "table" then
      return { text = tostring(value.text or ""), tooltip = value.tooltip, icon = value.icon, tone = value.tone,
        percentage = tonumber(value.percentage) }
    end
  end
  return { text = text:match("^[^\n]*") }
end

-- The readings of a `bar.custom` row, while something reads them.
local function reader(row)
  local id = tostring(row.id)
  if parsed[id] then return parsed[id] end
  local reading = morf.signal("eva.bar.custom." .. id, { text = "" })
  local started = false
  local function start()
    started = true
    if row.stream then
      morf.process.spawn { command = row.command, on_stdout = function(line) reading:set(M.parse(line)) end }
      return
    end
    local function sample()
      morf.process.run(row.command, { timeout_ms = 10000 }, function(result)
        if result and result.ok then reading:set(M.parse(result.stdout)) end
      end)
    end
    sample()
    if (tonumber(row.interval) or 0) > 0 then morf.time.timer(math.max(500, row.interval), sample, true) end
  end
  parsed[id] = function()
    if not started then morf.time.timer(1, function() if not started then start() end end, false) end
    return reading:get()
  end
  return parsed[id]
end

local function from_row(row, run)
  local read = reader(row)
  local press, right = row.press, row.right
  return { id = "custom_" .. tostring(row.id), name = row.name or tostring(row.id), tier = tonumber(row.tier) or 1,
    icon = function() return read().icon or row.icon or "terminal" end,
    text = function() return read().text end,
    gauge = row.gauge and function()
      return math.max(0, math.min(1, (read().percentage or 0) / 100))
    end or nil,
    tone = function() return read().tone end,
    tooltip = function() return read().tooltip or row.tooltip or row.name or tostring(row.id) end,
    press = press and function() run(press) end or nil,
    menu = right and function()
      return { { label = "Run", icon = "play_arrow", on_clicked = function() run(right) end } }
    end or nil }
end

--- The search path: each root holds `plugin/*.lua`.
function M.roots()
  local home = morf.env and morf.env("EVA_BAR_ROOT")
  if home and home ~= "" then return { home } end
  local config = (morf.env and morf.env("XDG_CONFIG_HOME")) or (morf.fs.home() .. "/.config")
  return { config .. "/eva/bar", config .. "/eva/bar/after" }
end

local function load_file(path, api)
  local ok, text = pcall(morf.fs.read, path)
  if not ok or type(text) ~= "string" then return nil, "cannot read it" end
  local chunk, why = load(text, "@" .. path, "t")
  if not chunk then return nil, why end
  package.preload["eva.bar"] = function() return api end
  package.loaded["eva.bar"] = api
  local fine, failure = pcall(chunk)
  if not fine then return nil, failure end
  return true
end

M.failures = {}

--- Every module of the Lua files, in the search path's order; a later file
--- replaces one of the same name.
function M.from_files()
  local api = { modules = {} }
  local order = {}
  setmetatable(api.modules, { __newindex = function(t, key, value)
    if rawget(t, key) == nil then order[#order + 1] = key end
    rawset(t, key, value)
  end })
  M.failures = {}
  for _, root in ipairs(M.roots()) do
    local ok, entries = pcall(morf.fs.list, root .. "/plugin")
    local names = {}
    for _, entry in ipairs(ok and entries or {}) do
      if entry.name:match("%.lua$") then names[#names + 1] = entry.name end
    end
    table.sort(names)
    for _, name in ipairs(names) do
      local path = root .. "/plugin/" .. name
      local done, why = load_file(path, api)
      if not done then
        M.failures[#M.failures + 1] = { path = path, why = tostring(why) }
        morf.log("warn", "eva: bar module " .. path .. ": " .. tostring(why))
      end
    end
  end
  local out = {}
  for _, key in ipairs(order) do
    local spec = rawget(api.modules, key)
    if type(spec) == "table" then
      spec.id = "lua_" .. tostring(key)
      spec.name = spec.name or tostring(key)
      out[#out + 1] = spec
    end
  end
  return out
end

--- The person's modules: the settings', then the files'.
function M.modules(run)
  local out = {}
  local rows = require("config").get("bar.custom")
  for _, row in ipairs(type(rows) == "table" and rows or {}) do
    if row.id and type(row.command) == "table" and #row.command > 0 then out[#out + 1] = from_row(row, run) end
  end
  for _, spec in ipairs(M.from_files()) do out[#out + 1] = spec end
  return out
end

return M
