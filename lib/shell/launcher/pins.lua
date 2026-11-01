-- What the person has told the launcher to keep: favourites in the order they
-- were pinned, apps hidden from it, the grid's folders, and aliases. All of it
-- lives in the settings, so a config file can set it as well as a press can.
--
-- A favourite is a name: `app:firefox.desktop`, `file:/home/me/notes.md`,
-- `setting:power`, `tile:wifi`, `mode:timer`.

local config = require("config")

local M = {}

local function list(key)
  local value = config.get(key)
  return type(value) == "table" and value or {}
end

local function without(items, value)
  local out = {}
  for _, item in ipairs(items) do
    if item ~= value then out[#out + 1] = item end
  end
  return out
end

--- The favourites, in order.
function M.favourites() return list("launcher.favourites") end

--- Whether `name` is a favourite.
function M.pinned(name)
  for _, item in ipairs(M.favourites()) do
    if item == name then return true end
  end
  return false
end

--- Pins `name`, or unpins it. Returns whether it is pinned now.
function M.toggle(name)
  local items = M.favourites()
  if M.pinned(name) then
    config.set("launcher.favourites", without(items, name))
    return false
  end
  local out = {}
  for i, item in ipairs(items) do out[i] = item end
  out[#out + 1] = name
  config.set("launcher.favourites", out)
  return true
end

--- Moves favourite `name` by `delta` places.
function M.move(name, delta)
  local items = {}
  local at
  for i, item in ipairs(M.favourites()) do
    items[i] = item
    if item == name then at = i end
  end
  if not at then return false end
  local to = math.max(1, math.min(#items, at + delta))
  table.remove(items, at)
  table.insert(items, to, name)
  config.set("launcher.favourites", items)
  return true
end

--- Whether app `id` is hidden.
function M.hidden(id)
  for _, item in ipairs(list("launcher.hidden")) do
    if item == id then return true end
  end
  return false
end

--- Hides app `id`, or brings it back.
function M.set_hidden(id, on)
  local out = without(list("launcher.hidden"), id)
  if on then out[#out + 1] = id end
  config.set("launcher.hidden", out)
end

--- The folders: `{ name, apps = { id... } }` each.
function M.folders()
  local out = {}
  for _, folder in ipairs(list("launcher.folders")) do
    if type(folder) == "table" and type(folder.name) == "string" and folder.name ~= "" then
      out[#out + 1] = { name = folder.name, apps = type(folder.apps) == "table" and folder.apps or {} }
    end
  end
  return out
end

--- The folder `id` is in, or nil.
function M.folder_of(id)
  for _, folder in ipairs(M.folders()) do
    for _, app in ipairs(folder.apps) do
      if app == id then return folder end
    end
  end
end

--- Puts app `id` in the folder `name`, made if it is new; "" takes it out.
function M.file_under(id, name)
  local folders, found = M.folders(), false
  local out = {}
  for _, folder in ipairs(folders) do
    local apps = without(folder.apps, id)
    if folder.name == name then
      apps[#apps + 1] = id
      found = true
    end
    if #apps > 0 then out[#out + 1] = { name = folder.name, apps = apps } end
  end
  if not found and name ~= "" then out[#out + 1] = { name = name, apps = { id } } end
  config.set("launcher.folders", out)
end

--- Folder `name` called `new`; a folder already called that takes its apps in.
function M.rename_folder(name, new)
  if name == new or new == "" then return end
  local out, into = {}, nil
  for _, folder in ipairs(M.folders()) do
    if folder.name == new then into = folder end
  end
  for _, folder in ipairs(M.folders()) do
    if folder.name == name then
      if into then
        for _, app in ipairs(folder.apps) do into.apps[#into.apps + 1] = app end
      else
        out[#out + 1] = { name = new, apps = folder.apps }
      end
    else
      out[#out + 1] = folder
    end
  end
  config.set("launcher.folders", out)
end

--- Folder `name` gone, its apps back among the rest.
function M.dissolve(name)
  local out = {}
  for _, folder in ipairs(M.folders()) do
    if folder.name ~= name then out[#out + 1] = folder end
  end
  config.set("launcher.folders", out)
end

--- A name no folder has yet: `base`, else `base 2`, `base 3`.
function M.free_name(base)
  local taken = {}
  for _, folder in ipairs(M.folders()) do taken[folder.name] = true end
  local name, count = base, 1
  while taken[name] do
    count = count + 1
    name = base .. " " .. count
  end
  return name
end

--- The aliases: `{ name, target }` each; a target is what the field is set to.
function M.aliases()
  local out = {}
  for _, alias in ipairs(list("launcher.aliases")) do
    if type(alias) == "table" and alias.name and alias.target then out[#out + 1] = alias end
  end
  return out
end

--- Adds an alias, replacing one of the same name.
function M.set_alias(name, target)
  local out = {}
  for _, alias in ipairs(M.aliases()) do
    if alias.name ~= name then out[#out + 1] = alias end
  end
  if target ~= "" then out[#out + 1] = { name = name, target = target } end
  config.set("launcher.aliases", out)
end

return M
