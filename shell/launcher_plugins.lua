-- Plugins: Lua files of the person's, each a fragment of config that registers
-- with the launcher (shell/launcher_api.lua) and returns nothing.
--
-- A search path of roots, `EVA_PLUGIN_PATH`'s folders and then
-- $XDG_CONFIG_HOME/eva, each laid out alike:
--
--   <root>/plugin/*.lua            run at start, by name
--   <root>/lua/*.lua               for `require`, never run by themselves
--   <root>/pack/*/start/*/         a package: a root of its own
--   <root>/after/plugin/*.lua      run last, to override the rest
--
-- One that raises is reported in `> plugins` and the rest still load. EVA_NO_PLUGINS
-- or the setting `launcher.plugins` off starts without them.
local morf = require("morf")
local config = require("config")

local M = {}

--- What ran: `{ path, ok, why }` each.
M.report = {}

local function no_plugins()
  local v = morf.env and morf.env("EVA_NO_PLUGINS")
  return (v and v ~= "" and v ~= "0") or not config.get("launcher.plugins")
end

--- The roots, in order.
function M.roots()
  local out = {}
  local extra = morf.env and morf.env("EVA_PLUGIN_PATH")
  for root in tostring(extra or ""):gmatch("[^:]+") do out[#out + 1] = root end
  local base = (morf.env and morf.env("XDG_CONFIG_HOME")) or (morf.fs.home() .. "/.config")
  out[#out + 1] = base .. "/eva"
  return out
end

local function packages(root)
  local out = {}
  local ok, groups = pcall(morf.fs.list, root .. "/pack")
  for _, group in ipairs(ok and type(groups) == "table" and groups or {}) do
    local fine, entries = pcall(morf.fs.list, group.path .. "/start")
    for _, entry in ipairs(fine and type(entries) == "table" and entries or {}) do
      if entry.is_dir then out[#out + 1] = entry.path end
    end
  end
  table.sort(out)
  return out
end

--- Every root the path holds, packages included.
local function all_roots()
  local out = {}
  for _, root in ipairs(M.roots()) do
    out[#out + 1] = root
    for _, package_root in ipairs(packages(root)) do out[#out + 1] = package_root end
  end
  return out
end

local function scripts(folder)
  local ok, entries = pcall(morf.fs.list, folder)
  local out = {}
  for _, e in ipairs(ok and type(entries) == "table" and entries or {}) do
    if e.is_file and (e.name or ""):match("%.lua$") then out[#out + 1] = e.path end
  end
  table.sort(out)
  return out
end

local loaded_modules = {}

local run_file

--- `require` as a plugin has it: the launcher's API, a module of a root's `lua/`,
--- else the shell's own.
local function plugin_require(name)
  if name == "eva.launcher" then return require("launcher_api") end
  if loaded_modules[name] ~= nil then return loaded_modules[name] end
  local relative = name:gsub("%.", "/")
  for _, root in ipairs(all_roots()) do
    for _, path in ipairs { root .. "/lua/" .. relative .. ".lua", root .. "/lua/" .. relative .. "/init.lua" } do
      if morf.fs.is_file(path) then
        local value = run_file(path)
        loaded_modules[name] = value == nil and true or value
        return loaded_modules[name]
      end
    end
  end
  return require(name)
end

run_file = function(path)
  local text = morf.fs.read(path)
  local env = setmetatable({ require = plugin_require }, { __index = _G })
  local chunk, why = load(text, "@" .. path, "t", env)
  if not chunk then error(why, 0) end
  return chunk()
end

local function run_plugin(path)
  local ok, why = pcall(run_file, path)
  M.report[#M.report + 1] = { path = path, ok = ok, why = not ok and tostring(why) or nil }
  if not ok then morf.log("warn", "eva: plugin " .. path .. ": " .. tostring(why)) end
end

--- Runs every plugin, once.
function M.load()
  if M.done then return end
  M.done = true
  if no_plugins() then return end
  local roots = all_roots()
  for _, root in ipairs(roots) do
    for _, path in ipairs(scripts(root .. "/plugin")) do run_plugin(path) end
  end
  for _, root in ipairs(roots) do
    for _, path in ipairs(scripts(root .. "/after/plugin")) do run_plugin(path) end
  end
end

return M
