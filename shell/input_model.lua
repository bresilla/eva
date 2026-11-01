-- Keyboards and pointers: what was chosen, what the compositor has now, and
-- pushing the one onto the other. Only what was changed is ever sent, so
-- everything else stays the person's own Hyprland configuration; it is sent
-- again after every reload, which forgets what was pushed.
local morf = require("morf")
local config = require("config")
local host = require("lib.services.host")
local lib = require("lib.services.input_config")
local hyprconf = require("lib.compositor.hyprland_config")
local page_model = require("page_model")

local M = {}

-- What switches layouts, and the keys xkb can change.
M.SWITCHES = { { "grp:alt_shift_toggle", "swap_horiz", "Alt+Shift" }, { "grp:win_space_toggle", "space_bar", "Super+Space" },
  { "grp:ctrl_shift_toggle", "keyboard_control_key", "Ctrl+Shift" }, { "grp:caps_toggle", "keyboard_capslock", "Caps Lock" } }
M.CAPS = { { "", "keyboard_capslock", "Caps Lock" }, { "caps:escape", "keyboard", "Escape" }, { "ctrl:nocaps", "keyboard_control_key", "Control" } }
M.COMPOSE = { { "", "block", "None" }, { "compose:ralt", "keyboard_option_key", "Right Alt" }, { "compose:rctrl", "keyboard_control_key", "Right Ctrl" },
  { "compose:menu", "menu", "Menu" } }
M.ACCEL = { { "", "tune", "Default" }, { "adaptive", "speed", "Adaptive" }, { "flat", "straighten", "Flat" } }

local stand_in
local function available()
  if host.fake() and not stand_in then
    stand_in = require("lib.services.host_fake").hyprland()
    hyprconf.use(stand_in)
  end
  return hyprconf.available ~= nil and hyprconf.available()
end
M.available = available

local function hypr()
  if stand_in then return stand_in end
  return require("lib.compositor.hyprland")
end

local function get(key) return config.get("input." .. key) end

--- What is sent: the choices, as the plan takes them.
function M.state()
  local chosen = {}
  for name, value in pairs(get("chosen") or {}) do chosen[name] = value end
  local keep = {}
  for _, key in ipairs { "caps", "compose" } do
    local word = chosen[key]
    chosen[key] = nil
    if type(word) == "string" and word ~= "" then keep[#keep + 1] = word end
  end
  local layouts = get("layouts") or {}
  return { chosen = chosen, layouts = layouts, devices = get("devices") or {},
    switch = #layouts > 1 and get("switch") or nil,
    options = #keep > 0 and table.concat(keep, ",") or nil }
end

--- Whether anything is chosen at all.
local function anything()
  local s = M.state()
  return next(s.chosen) ~= nil or #s.layouts > 0 or next(s.devices) ~= nil or s.options ~= nil
end

--- Pushes everything chosen, and whatever else `extra` adds to the plan.
function M.apply(done)
  if not available() then if done then done(false, { "unavailable" }) end return end
  hyprconf.apply(function(how)
    local state, plan, why = M.state()
    if not anything() then return {} end
    plan, why = lib.plan(state, how)
    return plan, why
  end, done)
end

--- Pushes the choices now and after each reload, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  if not available() then return end
  if anything() then M.apply() end
  hyprconf.on_reload(function() M.apply() end)
end

--- Sets an option by its OPTIONS name, or forgets it for nil.
function M.choose(name, value)
  local chosen = {}
  for key, old in pairs(get("chosen") or {}) do chosen[key] = old end
  chosen[name] = value
  config.set("input.chosen", chosen)
  M.apply()
end

local names

--- A model of the pages. `key` is the page.
function M.new(key, active)
  local model = page_model.new(key, active)
  model.SWITCHES, model.CAPS, model.COMPOSE, model.ACCEL = M.SWITCHES, M.CAPS, M.COMPOSE, M.ACCEL
  local live = morf.signal("eva.input." .. key .. ".live", {})
  local devices = morf.signal("eva.input." .. key .. ".devices", {})
  model.available = available

  function model.refresh()
    if not available() then return end
    hypr().options(lib.read_names(), function(replies) if replies then live:set(lib.readings(replies)) end end)
    hypr().devices(function(found) if type(found) == "table" then devices:set(found) end end)
  end
  model.on_show(model.refresh)

  --- An option as it stands: what was chosen, else what the compositor has.
  function model.value(name, otherwise)
    local chosen = (get("chosen") or {})[name]
    if chosen ~= nil then return chosen end
    local now = live:get()[name]
    if now ~= nil then return now end
    return otherwise
  end
  function model.set(name, value) M.choose(name, value) end

  -- ------------------------------------------------------------- layouts --

  function model.layouts() return get("layouts") or {} end
  function model.current() return hypr().state and hypr().state.keyboard_layout or "" end
  function model.catalogue()
    names = names or lib.catalogue()
    return names
  end
  function model.layout_name(row)
    local id = row.variant ~= "" and (row.layout .. ":" .. row.variant) or row.layout
    for _, known in ipairs(model.catalogue()) do if known.key == id then return known.name end end
    return row.layout
  end
  local function store(list)
    config.set("input.layouts", list)
    M.apply()
  end
  local function copy()
    local list = {}
    for index, row in ipairs(model.layouts()) do list[index] = { layout = row.layout, variant = row.variant or "" } end
    return list
  end
  function model.add_layout(row)
    local list = copy()
    for _, have in ipairs(list) do
      if have.layout == row.layout and have.variant == (row.variant or "") then return false end
    end
    list[#list + 1] = { layout = row.layout, variant = row.variant or "" }
    store(list)
    return true
  end
  function model.remove_layout(index)
    local list = copy()
    if #list <= 1 then return false end
    table.remove(list, index)
    store(list)
    return true
  end
  function model.move_layout(index, step)
    local list = copy()
    local other = index + step
    if not list[index] or not list[other] then return false end
    list[index], list[other] = list[other], list[index]
    store(list)
    return true
  end
  function model.switch() return get("switch") or "" end
  function model.set_switch(word)
    config.set("input.switch", word)
    M.apply()
  end
  --- The next layout, on every keyboard.
  function model.next_layout()
    hyprconf.run({ { request = "/switchxkblayout all next" } }, function(ok, replies)
      if not ok then model.say(tostring(replies and replies[1] or "It did not change"), true) end
    end)
  end

  -- ------------------------------------------------------------- devices --

  --- The compositor's devices: `{ key, name, kind, icon }`.
  function model.devices()
    local out, found = {}, devices:get()
    for _, group in ipairs { { "mice", "mouse", "mouse" }, { "keyboards", "keyboard", "keyboard" },
      { "tablets", "tablet", "stylus_note" }, { "touch", "touch", "touch_app" } } do
      for _, row in ipairs(found[group[1]] or {}) do
        if row.name and not row.name:find("virtual", 1, true) then
          out[#out + 1] = { key = row.name, name = row.name, kind = group[2], icon = group[3] }
        end
      end
    end
    return out
  end
  --- Whether a touchpad is there: a mouse named so.
  function model.touchpad()
    for _, row in ipairs(model.devices()) do
      local name = row.name:lower()
      if name:find("touchpad", 1, true) or name:find("trackpad", 1, true) then return true end
    end
    return false
  end
  function model.mouse()
    for _, row in ipairs(model.devices()) do if row.kind == "mouse" then return true end end
    return not available()
  end
  function model.can_keys() return host.tool("keys") ~= nil end
  function model.open_keys() return host.open_tool("keys") end
  model.selected = morf.signal("eva.input." .. key .. ".selected", "")
  function model.device_value(name, field, otherwise)
    local values = (get("devices") or {})[name] or {}
    if values[field] ~= nil then return values[field] end
    return otherwise
  end
  function model.set_device(name, field, value)
    local all = {}
    for device, values in pairs(get("devices") or {}) do
      local row = {}
      for k, v in pairs(values) do row[k] = v end
      all[device] = row
    end
    all[name] = all[name] or {}
    all[name][field] = value
    config.set("input.devices", all)
    M.apply()
  end
  function model.forget_device(name)
    local all = {}
    for device, values in pairs(get("devices") or {}) do if device ~= name then all[device] = values end end
    config.set("input.devices", all)
    M.apply()
  end

  -- -------------------------------------------------------------- cursor --

  local themes
  function model.cursor_themes()
    themes = themes or (stand_in and require("lib.services.host_fake").cursor_themes()) or lib.cursor_themes()
    return themes
  end
  local cursor = morf.signal("eva.input." .. key .. ".cursor", { theme = "", size = 24 })
  function model.cursor() return cursor:get() end
  function model.set_cursor(name, size)
    local now = cursor:get()
    local wanted = { theme = name or now.theme, size = size or now.size }
    cursor:set(wanted)
    if wanted.theme == "" then return end
    local plan = hyprconf.cursor_plan(wanted.theme, wanted.size)
    if plan then hyprconf.run(plan) end
  end

  return model
end

return M
