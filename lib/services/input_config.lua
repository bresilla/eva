-- Keyboards and pointers, as Hyprland takes them: pure plans over
-- lib.compositor.hyprland_config, which sends them and refuses anything that
-- does not validate. Nothing here writes the person's configuration files.
--
-- Hyprland spells a few options differently in its two languages: `OPTIONS`
-- keeps both, as `{ lua path, kind, hyprlang path }`.
local morf = require("morf")
local hyprconf = require("lib.compositor.hyprland_config")

local M = {}

M.OPTIONS = {
  repeat_rate = { "input:repeat_rate", "int" },
  repeat_delay = { "input:repeat_delay", "int" },
  numlock = { "input:numlock_by_default", "bool" },
  sensitivity = { "input:sensitivity", "float" },
  accel_profile = { "input:accel_profile", "str" },
  left_handed = { "input:left_handed", "bool" },
  natural_scroll = { "input:natural_scroll", "bool" },
  scroll_factor = { "input:scroll_factor", "float" },
  tap_to_click = { "input:touchpad:tap_to_click", "bool", "input:touchpad:tap-to-click" },
  touchpad_natural = { "input:touchpad:natural_scroll", "bool" },
  disable_while_typing = { "input:touchpad:disable_while_typing", "bool" },
  clickfinger = { "input:touchpad:clickfinger_behavior", "bool" },
  drag_lock = { "input:touchpad:drag_lock", "bool" },
  touchpad_scroll = { "input:touchpad:scroll_factor", "float" },
  cursor_timeout = { "cursor:inactive_timeout", "float" },
  zoom = { "cursor:zoom_factor", "float" },
}

-- What a device takes on its own: `{ kind }` by the name both languages use.
M.DEVICE = {
  enabled = "bool", sensitivity = "float", accel_profile = "str", natural_scroll = "bool", left_handed = "bool",
  scroll_factor = "float",
}

--- The option's path in `how`, and its kind.
local function path_of(name, how)
  local entry = M.OPTIONS[name]
  if not entry then return nil end
  return how == "lua" and entry[1] or (entry[3] or entry[1]), entry[2]
end

--- The name each option is read back by.
function M.read_names()
  local names = {}
  for _, entry in pairs(M.OPTIONS) do names[#names + 1] = entry[3] or entry[1] end
  table.sort(names)
  return names
end

--- `layouts` ({ { layout, variant } }) as Hyprland's two comma lists.
function M.layout_words(layouts)
  local names, variants = {}, {}
  for index, row in ipairs(layouts or {}) do
    names[index], variants[index] = row.layout or row[1] or "", row.variant or row[2] or ""
  end
  return table.concat(names, ","), table.concat(variants, ",")
end

--- A device name Hyprland will accept back: lowercase words and dashes.
local function device_ok(name) return type(name) == "string" and name:match("^[%w_:%.%-]+$") ~= nil end

--- The steps for one device's options, or nil and why.
function M.device_plan(name, values, how)
  if not device_ok(name) then return nil, "bad device name" end
  local keys = {}
  for key in pairs(values or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  local fields, steps = {}, {}
  for _, key in ipairs(keys) do
    local kind = M.DEVICE[key]
    local checked = kind and hyprconf.value(kind, values[key])
    if not checked then return nil, "refusing " .. tostring(key) end
    fields[#fields + 1] = key .. " = " .. checked.lua
    steps[#steps + 1] = { keyword = "device[" .. name .. "]:" .. key, value = checked.conf }
  end
  if how ~= "lua" then return steps end
  if #fields == 0 then return {} end
  return { { eval = 'hl.device({ name = "' .. name .. '", ' .. table.concat(fields, ", ") .. " })" } }
end

--- A step setting a path-valued option (`input:kb_file`,
--- `decoration:screen_shader`), which a plain value refuses for its slashes.
--- An empty path clears it.
function M.path_step(option, path, how)
  if not tostring(path):match("^[%w_%./%-]*$") then return nil, "bad path" end
  if how == "lua" then
    return { eval = "hl.config(" .. hyprconf.nest(option, '"' .. path .. '"') .. ")" }
  end
  return { keyword = option, value = path == "" and '""' or path }
end

--- Everything chosen as one plan. `state`: `chosen` (by OPTIONS name),
--- `layouts`, `switch` and `options` (xkb), `devices` (name -> values).
function M.plan(state, how)
  local list = {}
  local names = {}
  for name in pairs(state.chosen or {}) do
    if M.OPTIONS[name] then names[#names + 1] = name end
  end
  table.sort(names)
  for _, name in ipairs(names) do
    local path, kind = path_of(name, how)
    list[#list + 1] = { path, kind, state.chosen[name] }
  end
  if state.layouts and #state.layouts > 0 then
    local layout, variant = M.layout_words(state.layouts)
    list[#list + 1] = { "input:kb_layout", "str", layout }
    list[#list + 1] = { "input:kb_variant", "str", variant }
  end
  if state.switch ~= nil or state.options ~= nil then
    local parts = {}
    if (state.switch or "") ~= "" then parts[1] = state.switch end
    if (state.options or "") ~= "" then parts[#parts + 1] = state.options end
    list[#list + 1] = { "input:kb_options", "str", table.concat(parts, ",") }
  end
  local plan, why = hyprconf.options_plan(list, how)
  if not plan then return nil, why end
  local devices = {}
  for name in pairs(state.devices or {}) do devices[#devices + 1] = name end
  table.sort(devices)
  for _, name in ipairs(devices) do
    local steps, failed = M.device_plan(name, state.devices[name], how)
    if not steps then return nil, failed end
    for _, step in ipairs(steps) do plan[#plan + 1] = step end
  end
  return plan
end

--- What `hyprland.options` answered, by OPTIONS name: bools and numbers as
--- themselves.
function M.readings(replies)
  local out = {}
  for name, entry in pairs(M.OPTIONS) do
    local reply = replies and replies[entry[3] or entry[1]]
    if type(reply) == "table" then
      if entry[2] == "bool" then out[name] = (tonumber(reply.int) or 0) ~= 0
      elseif entry[2] == "int" then out[name] = tonumber(reply.int)
      elseif entry[2] == "float" then out[name] = tonumber(reply.float)
      else out[name] = reply.str end
    end
  end
  return out
end

-- ----------------------------------------------------------- the layouts --

-- Those on offer where the system's list cannot be found.
local COMMON = { { "us", "English (US)" }, { "gb", "English (UK)" }, { "de", "German" }, { "fr", "French" },
  { "es", "Spanish" }, { "it", "Italian" }, { "pt", "Portuguese" }, { "nl", "Dutch" }, { "se", "Swedish" },
  { "no", "Norwegian" }, { "dk", "Danish" }, { "fi", "Finnish" }, { "pl", "Polish" }, { "cz", "Czech" },
  { "hu", "Hungarian" }, { "ro", "Romanian" }, { "gr", "Greek" }, { "tr", "Turkish" }, { "ru", "Russian" },
  { "ua", "Ukrainian" }, { "al", "Albanian" }, { "il", "Hebrew" }, { "ara", "Arabic" }, { "jp", "Japanese" },
  { "kr", "Korean" }, { "cn", "Chinese" }, { "in", "Indian" } }

--- Reads an xkb rules `.lst` for its layouts and variants.
function M.parse_rules(text)
  local layouts, by_id, section = {}, {}, nil
  for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    local head = line:match("^!%s*(%S+)")
    if head then section = head
    elseif section == "layout" then
      local id, name = line:match("^%s+(%S+)%s+(.+)$")
      if id then
        by_id[id] = { key = id, layout = id, variant = "", name = name, words = id }
        layouts[#layouts + 1] = by_id[id]
      end
    elseif section == "variant" then
      local variant, parent, name = line:match("^%s+(%S+)%s+(%S+):%s+(.+)$")
      if variant and by_id[parent] then
        layouts[#layouts + 1] = { key = parent .. ":" .. variant, layout = parent, variant = variant,
          name = name, words = parent .. " " .. variant .. " " .. by_id[parent].name }
      end
    end
  end
  return layouts
end

--- `xkbcli list` as layouts. It prints YAML, one key to a line.
function M.parse_xkbcli(text)
  local out, row, parents = {}, nil, {}
  local function close()
    if not (row and row.layout and row.name) then return end
    if row.variant == "" then parents[row.layout] = row.name end
    row.key = row.variant ~= "" and (row.layout .. ":" .. row.variant) or row.layout
    row.words = row.layout .. " " .. row.variant .. " " .. (parents[row.layout] or "")
    out[#out + 1] = row
  end
  for line in tostring(text or ""):gmatch("[^\n]+") do
    local layout = line:match("^%- layout: '([^']*)'")
    if layout then
      close()
      row = { layout = layout, variant = "" }
    elseif row then
      local variant = line:match("^%s+variant: '([^']*)'")
      if variant then row.variant = variant end
      local name = line:match("^%s+description: (.+)$")
      if name then row.name = (name:gsub("^'(.*)'$", "%1")) end
    end
  end
  close()
  return out
end

--- `done(rows)` with the whole list where the rules file cannot be found.
function M.catalogue_long(done)
  if not require("lib.services.host").installed("xkbcli") then return end
  require("lib.services.host").read({ "xkbcli", "list" }, function(text)
    local rows = M.parse_xkbcli(text)
    if #rows > 0 then done(rows) end
  end)
end

--- The layouts this system has, `{ key, layout, variant, name, words }`, and
--- whether that is the short list of common ones.
function M.catalogue()
  local root = morf.env("XKB_CONFIG_ROOT")
  for _, path in ipairs { root and (root .. "/rules/base.lst") or "/nonexistent",
    "/run/current-system/sw/share/X11/xkb/rules/base.lst", "/usr/share/X11/xkb/rules/base.lst",
    "/etc/X11/xkb/rules/base.lst" } do
    if morf.fs.exists(path) then
      local ok, text = pcall(morf.fs.read, path)
      local found = ok and M.parse_rules(text) or {}
      if #found > 0 then return found end
    end
  end
  local out = {}
  for index, row in ipairs(COMMON) do
    out[index] = { key = row[1], layout = row[1], variant = "", name = row[2], words = row[1] }
  end
  return out, true
end

-- ----------------------------------------------------------- the cursors --

--- The cursor themes installed: folders holding `cursors` under the icon
--- paths, by name.
function M.cursor_themes(dirs)
  local home = morf.fs.home()
  local roots = dirs or { home .. "/.icons", home .. "/.local/share/icons", "/run/current-system/sw/share/icons",
    "/usr/share/icons" }
  local seen, out = {}, {}
  for _, root in ipairs(roots) do
    local ok, entries = pcall(morf.fs.list, root, { follow = true })
    for _, entry in ipairs(ok and type(entries) == "table" and entries or {}) do
      local name = type(entry) == "table" and entry.name or entry
      if not seen[name] and morf.fs.exists(root .. "/" .. name .. "/cursors") then
        seen[name] = true
        out[#out + 1] = { key = name, name = name }
      end
    end
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

return M
