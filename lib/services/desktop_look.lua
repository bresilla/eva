-- The rest of the desktop in step with the shell: GTK, Qt, the cursor, the icons
-- and the terminals. A sync is a plan first -- commands to run and files to
-- write -- so what it would do can be read without doing it.
--
--     local look = require("lib.services.desktop_look")
--     look.apply(look.plan { mode = "dark", cursor_theme = "Bibata", cursor_size = 24 })
local morf = require("morf")
local M = {}

local INTERFACE = "org.gnome.desktop.interface"

local function home() return morf.env("HOME") or morf.fs.home() end
local function config_home() return morf.env("XDG_CONFIG_HOME") or (home() .. "/.config") end

--- `text` of an ini file with `key` set to `value` under `[section]`; every
--- other line stays as it was.
function M.ini_set(text, section, key, value)
  local out, in_section, done, seen = {}, false, false, false
  local head = "[" .. section .. "]"
  for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
    local name = line:match("^%[(.-)%]%s*$")
    if name then
      if in_section and not done then out[#out + 1] = key .. "=" .. value done = true end
      in_section = name == section
      seen = seen or in_section
    end
    if in_section and line:match("^%s*" .. key:gsub("%-", "%%-") .. "%s*=") then
      if not done then out[#out + 1] = key .. "=" .. value done = true end
    else
      out[#out + 1] = line
    end
  end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  if in_section and not done then
    out[#out + 1] = key .. "=" .. value
  elseif not seen then
    if #out > 0 then out[#out + 1] = "" end
    out[#out + 1] = head
    out[#out + 1] = key .. "=" .. value
  end
  return table.concat(out, "\n") .. "\n"
end

local function edit(plan, path, section, key, value)
  plan.edits[#plan.edits + 1] = { path = path, section = section, key = key, value = tostring(value) }
end

--- Qt's palette file: twenty-one roles, active, disabled and inactive alike.
function M.qt_palette(colors)
  local function hex(role) return "#ff" .. colors[role]:sub(2, 7) end
  local roles = { "foreground", "surface", "light", "midlight", "dark", "mid", "foreground", "bright", "foreground",
    "base", "surface", "shadow", "highlight", "on_highlight", "link", "link", "base", "foreground", "base", "foreground", "foreground" }
  local list = {}
  for i, role in ipairs(roles) do list[i] = hex(role) end
  local line = table.concat(list, ", ")
  return "[ColorScheme]\nactive_colors=" .. line .. "\ndisabled_colors=" .. line .. "\ninactive_colors=" .. line .. "\n"
end

--- What syncing `want` takes: `{ commands, edits, writes }`. `want` may hold
--- `mode`, `system` (true: the desktop already chose, so leave its setting),
--- `icon_theme`, `cursor_theme`, `cursor_size`, `gtk_theme`, `colors` (Qt's
--- roles, hex).
function M.plan(want)
  local plan = { commands = {}, edits = {}, writes = {} }
  local function set(key, value)
    plan.commands[#plan.commands + 1] = { "gsettings", "set", INTERFACE, key, tostring(value) }
  end
  local gtk3, gtk4 = config_home() .. "/gtk-3.0/settings.ini", config_home() .. "/gtk-4.0/settings.ini"
  local function gtk(key, value)
    edit(plan, gtk3, "Settings", key, value)
    edit(plan, gtk4, "Settings", key, value)
  end
  if want.mode then
    if not want.system then set("color-scheme", want.mode == "dark" and "prefer-dark" or "prefer-light") end
    gtk("gtk-application-prefer-dark-theme", want.mode == "dark" and 1 or 0)
  end
  if want.gtk_theme and want.gtk_theme ~= "" then
    set("gtk-theme", want.gtk_theme)
    gtk("gtk-theme-name", want.gtk_theme)
  end
  if want.icon_theme and want.icon_theme ~= "" then
    set("icon-theme", want.icon_theme)
    gtk("gtk-icon-theme-name", want.icon_theme)
    for _, qt in ipairs { "qt6ct", "qt5ct" } do
      edit(plan, config_home() .. "/" .. qt .. "/" .. qt .. ".conf", "Appearance", "icon_theme", want.icon_theme)
    end
  end
  if want.cursor_theme and want.cursor_theme ~= "" then
    local size = want.cursor_size or 24
    set("cursor-theme", want.cursor_theme)
    set("cursor-size", size)
    gtk("gtk-cursor-theme-name", want.cursor_theme)
    gtk("gtk-cursor-theme-size", size)
    plan.writes[#plan.writes + 1] = { path = home() .. "/.icons/default/index.theme",
      text = "[Icon Theme]\nInherits=" .. want.cursor_theme .. "\n" }
    plan.commands[#plan.commands + 1] = { "hyprctl", "setcursor", want.cursor_theme, tostring(size) }
  end
  if want.colors then
    for _, qt in ipairs { "qt6ct", "qt5ct" } do
      local folder = config_home() .. "/" .. qt
      local palette = folder .. "/colors/eva.conf"
      plan.writes[#plan.writes + 1] = { path = palette, text = M.qt_palette(want.colors) }
      edit(plan, folder .. "/" .. qt .. ".conf", "Appearance", "custom_palette", "true")
      edit(plan, folder .. "/" .. qt .. ".conf", "Appearance", "color_scheme_path", palette)
    end
  end
  return plan
end

--- Carries a plan out. `done` hears how many commands failed; a tool that is
--- not installed is one of those, not an error.
function M.apply(plan, done)
  local dry = morf.env("EVA_DRY_RUN")
  if dry and dry ~= "" and dry ~= "0" then
    if done then done(0) end
    return false
  end
  local function save(path, text)
    local ok, why = morf.fs.write(path, text, { atomic = true, parents = true })
    if not ok then morf.log("warn", "eva: could not write " .. path .. ": " .. tostring(why)) end
  end
  local by_path, order = {}, {}
  for _, change in ipairs(plan.edits) do
    if not by_path[change.path] then by_path[change.path] = {} order[#order + 1] = change.path end
    table.insert(by_path[change.path], change)
  end
  -- A file already as it should be stays untouched: rewriting it would replace
  -- a link a person keeps there with a plain copy.
  local function current(path)
    local ok, text = pcall(morf.fs.read, path)
    return ok and type(text) == "string" and text or nil
  end
  for _, path in ipairs(order) do
    local before = current(path)
    local text = before or ""
    for _, change in ipairs(by_path[path]) do text = M.ini_set(text, change.section, change.key, change.value) end
    if text ~= before then save(path, text) end
  end
  for _, write in ipairs(plan.writes) do
    if current(write.path) ~= write.text then save(write.path, write.text) end
  end
  local waiting, failed = #plan.commands, 0
  if waiting == 0 and done then done(0) end
  for _, argv in ipairs(plan.commands) do
    local ok, child = pcall(morf.process.run, argv, { timeout_ms = 5000, max_output = 4096 }, function(result)
      waiting = waiting - 1
      if not result.ok then failed = failed + 1 end
      if waiting == 0 and done then done(failed) end
    end)
    if not ok or not child then
      waiting = waiting - 1
      failed = failed + 1
      if waiting == 0 and done then done(failed) end
    end
  end
  return true
end

--- The escape sequences a terminal takes for `palette` (`color0`..`color15`,
--- `background`, `foreground`, `cursor`).
function M.sequences(palette)
  local out = {}
  for i = 0, 15 do
    local color = palette["color" .. i]
    if color then out[#out + 1] = ("\27]4;%d;%s\27\\"):format(i, color) end
  end
  for code, name in pairs { [10] = "foreground", [11] = "background", [12] = "cursor" } do
    if palette[name] then out[#out + 1] = ("\27]%d;%s\27\\"):format(code, palette[name]) end
  end
  return table.concat(out)
end

--- Writes `palette` to every terminal, as colour tools do. EVA_FAKE_PTS names
--- another folder of terminals.
function M.terminals(palette)
  local dry = morf.env("EVA_DRY_RUN")
  if dry and dry ~= "" and dry ~= "0" then return 0 end
  local folder = morf.env("EVA_FAKE_PTS") or "/dev/pts"
  local ok, entries = pcall(morf.fs.list, folder)
  if not ok or type(entries) ~= "table" then return 0 end
  local text, written = M.sequences(palette), 0
  for _, entry in ipairs(entries) do
    local name = type(entry) == "table" and entry.name or entry
    if tostring(name):match("^%d+$") and pcall(morf.fs.write, folder .. "/" .. name, text) then written = written + 1 end
  end
  return written
end

-- ------------------------------------------------------------------ lists --

local function data_dirs()
  local dirs = { home() .. "/.icons", home() .. "/.local/share/icons" }
  local shared = morf.env("EVA_ICON_DIRS") or morf.env("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
  for dir in shared:gmatch("[^:]+") do
    dirs[#dirs + 1] = morf.env("EVA_ICON_DIRS") and dir or (dir .. "/icons")
  end
  return dirs
end

--- The cursor and icon themes installed: `{ cursors = { names }, icons = { names } }`.
function M.themes()
  local cursors, icons, seen = {}, {}, {}
  for _, dir in ipairs(data_dirs()) do
    local ok, entries = pcall(morf.fs.list, dir, { follow = true })
    for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
      local name = entry.name
      if entry.is_dir and name ~= "default" then
        if not seen["c" .. name] and morf.fs.is_dir(entry.path .. "/cursors") then
          seen["c" .. name] = true
          cursors[#cursors + 1] = name
        end
        if not seen["i" .. name] and name ~= "hicolor" and morf.fs.is_file(entry.path .. "/index.theme")
          and not morf.fs.is_dir(entry.path .. "/cursors") then
          seen["i" .. name] = true
          icons[#icons + 1] = name
        end
      end
    end
  end
  table.sort(cursors)
  table.sort(icons)
  return { cursors = cursors, icons = icons }
end

return M
