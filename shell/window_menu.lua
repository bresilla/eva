-- The window menu: a cross of cards over the focused window -- the window
-- itself in the middle, and on each side what can be done to it. A side
-- opens into its branch: its pages down the left, the chosen page's
-- actions beside them. Opened over IPC (`window_menu toggle`), which a
-- compositor key calls; everything it does is a Hyprland dispatcher sent
-- to that one window by its address.
--
-- Keys: arrows choose a side and Enter (or the same arrow again) opens it;
-- in a branch, Up and Down move, Right and Left cross between the pages
-- and their actions, Enter runs one; Escape goes back, then shuts.
-- EVA_DRY_RUN=1 logs what would be dispatched instead.
local morf = require("morf")
local services = require("services")
local hyprland = services.hyprland
local M = {}

M.opened = morf.signal("eva.window_menu.opened", false)
M.address = morf.signal("eva.window_menu.address", "")
M.slot = morf.signal("eva.window_menu.slot", "center")
M.branch = morf.signal("eva.window_menu.branch", false)
M.sub = morf.signal("eva.window_menu.sub", 1)
M.column = morf.signal("eva.window_menu.column", "subs")
M.action = morf.signal("eva.window_menu.action", 1)
M.message = morf.signal("eva.window_menu.message", "")

local function dry_run()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return v ~= nil and v ~= "" and v ~= "0"
end

local function client(address)
  if address == "" then return nil end
  local model = hyprland.state.clients
  for i = 1, model:len() do
    local row = model:get(i)
    if row.address == address then return row end
  end
end
--- The window the menu is about, as the compositor has it now.
function M.window() return client(M.address:get()) end

-- ------------------------------------------------------------- dispatch --

local lua_config
local function flavour(done)
  if lua_config ~= nil then return done(lua_config) end
  local ok, config = pcall(require, "lib.integrations.hyprland_config")
  if not ok then lua_config = false return done(false) end
  config.flavour(function(kind) lua_config = kind == "lua" done(lua_config) end)
end

local function quoted(value) return ("%q"):format(tostring(value)) end
local function fields(t)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = k .. " = " .. (type(v) == "string" and quoted(v) or tostring(v)) end
  table.sort(out)
  return "{ " .. table.concat(out, ", ") .. " }"
end

--- Runs `steps` on the window: each `{ lua = { "window.pin", {...} },
--- conf = { dispatcher, argument } }`, the Lua form on a Lua-configured
--- Hyprland and the classic one elsewhere.
local function run(steps)
  local address = M.address:get()
  if address == "" then return false end
  local selector = "address:" .. address
  if dry_run() then
    local names = {}
    for _, s in ipairs(steps) do names[#names + 1] = s.lua[1] end
    morf.log("info", "eva: window menu (dry run): " .. table.concat(names, ", ") .. " on " .. address)
    return true
  end
  flavour(function(lua)
    if lua then
      local chunk = {}
      for _, s in ipairs(steps) do
        if s.global and #chunk == 0 then chunk[1] = ("hl.dispatch(hl.dsp.focus({ window = %s }))"):format(quoted(selector)) end
      end
      for _, s in ipairs(steps) do
        local args = s.lua[2]
        if type(args) == "string" then args = quoted(args)
        else
          local t = {}
          for k, v in pairs(args or {}) do t[k] = v end
          if not s.global then t.window = selector end
          args = fields(t)
        end
        chunk[#chunk + 1] = ("hl.dispatch(hl.dsp.%s(%s))"):format(s.lua[1], args)
      end
      hyprland.eval(table.concat(chunk, " "), function(reply, err)
        if err or (reply and not reply:match("^%s*ok%s*$")) then
          morf.log("warn", "eva: window menu: " .. tostring(err or reply))
        end
      end)
    else
      -- Classic dispatchers mostly act on the focused window: focus it first.
      local queue = { { "focuswindow", "$W" } }
      for _, s in ipairs(steps) do queue[#queue + 1] = s.conf end
      local function step(i)
        local s = queue[i]
        if not s then return end
        local arg = s[2] and (s[2]:gsub("%$W", selector)) or nil
        hyprland.dispatch(s[1], arg, function() step(i + 1) end)
      end
      step(1)
    end
  end)
  return true
end

local function S(lua, conf) return { lua = lua, conf = conf } end
local function toggle(name, conf) return S({ "window." .. name, { action = "toggle" } }, conf) end

-- --------------------------------------------------------------- pages --

local function yes(v) return v == true end
--- A floating window `fraction` of its screen, centred there.
local function sized(fraction)
  local w = M.window()
  local monitor = w and hyprland.monitor(w.monitor)
  local mw = monitor and monitor.width / (monitor.scale or 1) or 1920
  local mh = monitor and monitor.height / (monitor.scale or 1) or 1080
  local x, y = math.floor(mw * fraction), math.floor(mh * fraction)
  return {
    S({ "window.float", { action = "on" } }, { "setfloating", "$W" }),
    S({ "window.resize", { x = x, y = y } }, { "resizewindowpixel", ("exact %d %d,$W"):format(x, y) }),
    S({ "window.center", {} }, { "centerwindow", nil }),
  }
end

local function workspace_actions(follow)
  return function()
    local w = M.window() or {}
    local out = {}
    local count = math.max(5, tonumber(require("config").get("bar.workspaces.shown")) or 5)
    for id = 1, math.max(count, 10) do
      local occupied = services.workspace.occupied(id)
      out[#out + 1] = { key = "ws" .. id, label = "Workspace " .. id,
        meta = w.workspace == id and "HERE" or occupied and "IN USE" or "",
        selected = w.workspace == id,
        steps = { S({ "window.move", { workspace = tostring(id), follow = follow } },
          { follow and "movetoworkspace" or "movetoworkspacesilent", id .. ",$W" }) } }
    end
    return out
  end
end

local function monitor_actions()
  local w = M.window() or {}
  local out = {}
  local model = hyprland.state.monitors
  for i = 1, model:len() do
    local m = model:get(i)
    out[#out + 1] = { key = "mon:" .. m.name, label = m.name,
      meta = ("%dx%d"):format(m.width, m.height), selected = w.monitor == m.id,
      steps = { S({ "window.move", { monitor = m.name } }, { "movewindow", "mon:" .. m.name }) } }
  end
  return out
end

M.SLOTS = {
  { key = "center", number = "00", title = "Window" },
  { key = "top", number = "01", title = "Layout", subs = {
    { key = "state", label = "State", actions = function()
      local w = M.window() or {}
      return {
        { key = "float", label = w.floating and "Tile" or "Float", stay = true, selected = yes(w.floating),
          meta = w.floating and "FLOATING" or "TILED", steps = { toggle("float", { "togglefloating", "$W" }) } },
        { key = "fullscreen", label = "Fullscreen", stay = true, selected = (w.fullscreen or 0) == 2,
          steps = { S({ "window.fullscreen", { mode = "fullscreen" } }, { "fullscreen", "0" }) } },
        { key = "maximize", label = "Maximize", stay = true, selected = (w.fullscreen or 0) == 1,
          steps = { S({ "window.fullscreen", { mode = "maximized" } }, { "fullscreen", "1" }) } },
        { key = "pin", label = "Pin on every workspace", stay = true, selected = yes(w.pinned),
          meta = w.floating and "" or "FLOATS", steps = { toggle("pin", { "pin", "$W" }) } },
      }
    end },
    { key = "size", label = "Size", actions = function()
      return {
        { key = "center", label = "Center", steps = { S({ "window.center", {} }, { "centerwindow", nil }) } },
        { key = "half", label = "Half the screen", meta = "50%", steps = sized(0.5) },
        { key = "two_thirds", label = "Two thirds", meta = "66%", steps = sized(0.66) },
        { key = "most", label = "Most of it", meta = "85%", steps = sized(0.85) },
      }
    end },
    { key = "order", label = "Order", actions = function()
      local out = { { key = "top", label = "Bring to front", steps = { S({ "window.bring_to_top", {} }, { "bringactivetotop", nil }) } } }
      for _, d in ipairs { { "left", "l" }, { "right", "r" }, { "up", "u" }, { "down", "d" } } do
        out[#out + 1] = { key = "swap_" .. d[1], label = "Swap " .. d[1], meta = "TILED",
          steps = { S({ "window.swap", { direction = d[1] } }, { "swapwindow", d[2] }) } }
      end
      return out
    end },
  } },
  { key = "left", number = "02", title = "Workspace", subs = {
    { key = "move", label = "Move", actions = workspace_actions(true) },
    { key = "send", label = "Send", actions = workspace_actions(false) },
    { key = "special", label = "Scratchpad", actions = function()
      return {
        { key = "stash", label = "Stash away", meta = "SPECIAL",
          steps = { S({ "window.move", { workspace = "special:eva", follow = false } }, { "movetoworkspacesilent", "special:eva,$W" }) } },
        { key = "show", label = "Show the scratchpad", stay = true,
          steps = { { global = true, lua = { "workspace.toggle_special", "eva" }, conf = { "togglespecialworkspace", "eva" } } } },
      }
    end },
  } },
  { key = "right", number = "03", title = "Screen", subs = {
    { key = "monitor", label = "Monitor", actions = monitor_actions },
    { key = "group", label = "Group", actions = function()
      return {
        { key = "group", label = "Group or ungroup", stay = true, steps = { { global = true, lua = { "group.toggle", {} }, conf = { "togglegroup", nil } } } },
        { key = "lock", label = "Lock the group", stay = true, steps = { { global = true, lua = { "group.lock_active", { action = "toggle" } }, conf = { "lockactivegroup", "toggle" } } } },
        { key = "next", label = "Next in group", stay = true, steps = { { global = true, lua = { "group.next", {} }, conf = { "changegroupactive", "f" } } } },
      }
    end },
  } },
  { key = "bottom", number = "04", title = "Close", subs = {
    { key = "close", label = "Close", actions = function()
      return {
        { key = "close", label = "Close window", primary = true, steps = { S({ "window.close", {} }, { "closewindow", "$W" }) } },
        { key = "kill", label = "Force quit", meta = "SIGKILL", steps = { S({ "window.kill", {} }, { "killwindow", "$W" }) } },
      }
    end },
    { key = "info", label = "Details", actions = function()
      local w = M.window() or {}
      return {
        { key = "class", label = "Class", meta = w.class or "", info = true },
        { key = "title", label = "Title", meta = w.title or "", info = true },
        { key = "pid", label = "Process", meta = ("%d"):format(w.pid or 0), info = true },
        { key = "size", label = "Size", meta = ("%d × %d"):format(w.width or 0, w.height or 0), info = true },
        { key = "place", label = "Position", meta = ("%d, %d"):format(w.x or 0, w.y or 0), info = true },
        { key = "client", label = "Client", meta = w.xwayland and "XWayland" or "Wayland", info = true },
      }
    end },
  } },
}
local BY_KEY = {}
for _, s in ipairs(M.SLOTS) do BY_KEY[s.key] = s end
function M.slot_spec(key) return BY_KEY[key or M.slot:get()] end
function M.subs() local s = M.slot_spec() return s and s.subs or {} end
function M.actions()
  local sub = M.subs()[M.sub:get()]
  return sub and sub.actions() or {}
end

--- The cards' readings: a line and two corner words.
function M.summary(key)
  local w = M.window()
  if not w then return { "No window", "", "" } end
  if key == "center" then return { w.class ~= "" and w.class or "Window", w.title or "", "" } end
  if key == "top" then
    local state = w.fullscreen == 2 and "Fullscreen" or w.fullscreen == 1 and "Maximized" or w.floating and "Floating" or "Tiled"
    return { ("%s · %d × %d"):format(state, w.width, w.height), w.floating and "FLOAT ON" or "FLOAT OFF",
      w.pinned and "PIN ON" or "PIN OFF" }
  elseif key == "left" then
    local n, model = 0, hyprland.state.clients
    for i = 1, model:len() do if model:get(i).workspace == w.workspace then n = n + 1 end end
    return { "Workspace " .. (w.workspace_name ~= "" and w.workspace_name or tostring(w.workspace)),
      ("%d WINDOW%s"):format(n, n == 1 and "" or "S"), "MOVE · SEND" }
  elseif key == "right" then
    local m = hyprland.monitor(w.monitor) or {}
    return { m.name or "Screen", m.width and ("%dx%d"):format(m.width, m.height) or "", m.scale and ("×%.2g"):format(m.scale) or "" }
  elseif key == "bottom" then
    return { w.title ~= "" and w.title or w.class, ("PID %d"):format(w.pid or 0), w.xwayland and "XWAYLAND" or "WAYLAND" }
  end
  return { "", "", "" }
end

-- ---------------------------------------------------------- navigation --

local OPPOSITE = { top = "bottom", bottom = "top", left = "right", right = "left" }
local DIRECTION = { Up = "top", Down = "bottom", Left = "left", Right = "right" }

function M.select(key) if not M.branch:get() then M.slot:set(key) end end
function M.open_slot(key)
  key = key or M.slot:get()
  if key == "center" or not BY_KEY[key] then return false end
  M.slot:set(key) M.sub:set(1) M.column:set("subs") M.action:set(1) M.message:set("")
  M.branch:set(true)
  return true
end
function M.back()
  if M.branch:get() then
    if M.column:get() == "actions" then M.column:set("subs") return end
    M.branch:set(false)
    return
  end
  M.close()
end
function M.choose_sub(i) if M.subs()[i] then M.sub:set(i) M.action:set(1) M.message:set("") end end

--- Runs action `i` of the page on show.
function M.run(i)
  local a = M.actions()[i or M.action:get()]
  if not a or a.info or not a.steps then return false end
  M.action:set(i or M.action:get())
  local ok = run(a.steps)
  if ok and not a.stay then M.close() end
  return ok
end

function M.key(_, _, _, _, name)
  if name == "Return" or name == "KP_Enter" or name == "space" then M.accept() return true end
  if name == "Escape" then M.back() return true end
  local branch = M.branch:get()
  if not branch then
    local dir = DIRECTION[name]
    if dir then
      local slot = M.slot:get()
      if slot == dir then M.open_slot(dir)
      elseif slot == OPPOSITE[dir] then M.slot:set("center")
      else M.slot:set(dir) end
    elseif name and name:match("^[1-4]$") then
      M.open_slot(M.SLOTS[tonumber(name) + 1].key)
    end
    return true
  end
  local list = M.column:get() == "subs" and M.subs() or M.actions()
  local signal = M.column:get() == "subs" and M.sub or M.action
  local n = #list
  if name == "Up" and n > 0 then signal:set((signal:get() - 2) % n + 1)
  elseif name == "Down" and n > 0 then signal:set(signal:get() % n + 1)
  elseif name == "Right" or name == "Tab" then
    if M.column:get() == "subs" and #M.actions() > 0 then M.column:set("actions") M.action:set(1) end
  elseif name == "Left" or name == "ISO_Left_Tab" then M.back() end
  if M.column:get() == "subs" and (name == "Up" or name == "Down") then M.action:set(1) M.message:set("") end
  return true
end
function M.accept()
  if not M.branch:get() then return M.open_slot() end
  if M.column:get() == "subs" then
    if #M.actions() > 0 then M.column:set("actions") M.action:set(1) end
    return true
  end
  return M.run()
end

-- ---------------------------------------------------------------- open --

--- Whether this screen holds the focused window (the focused screen when
--- the compositor does not say where it is).
function M.here()
  local active = hyprland.state.active_window
  local w = client(active and active.address or "")
  local screen = morf.screens and morf.screens[1] and morf.screens[1].name or ""
  if w then
    local model = hyprland.state.monitors
    for i = 1, model:len() do
      local m = model:get(i)
      if m.id == w.monitor then return m.name == screen end
    end
  end
  return services.here()
end

--- Opens over the focused window; false when there is none.
function M.open()
  local active = hyprland.state.active_window
  local address = active and active.address or ""
  if not client(address) then return false end
  M.address:set(address)
  M.slot:set("center") M.branch:set(false) M.sub:set(1) M.column:set("subs") M.action:set(1) M.message:set("")
  M.opened:set(true)
  return true
end
function M.close() M.opened:set(false) M.branch:set(false) end
function M.toggle() if M.opened:get() then M.close() return false end return M.open() end

-- The window gone (closed, killed), the menu goes with it.
morf.effect("eva.window_menu.gone", function()
  if M.opened:get() and M.window() == nil then M.close() end
end)

--- This screen's size, and the window's box on it, in the shell's pixels
--- (the compositor's are logical ones, from its layout's origin).
function M.screen()
  local s = morf.screens and morf.screens[1] or {}
  return s.width or 1920, s.height or 1080
end
function M.rect()
  local w = M.window()
  if not w then return nil end
  local s = morf.screens and morf.screens[1] or {}
  local m = hyprland.monitor(w.monitor) or {}
  local ratio = (s.width and s.logical_width and s.logical_width > 0) and s.width / s.logical_width or 1
  return { x = (w.x - (m.x or 0)) * ratio, y = (w.y - (m.y or 0)) * ratio,
    width = w.width * ratio, height = w.height * ratio }
end

local view = require("themes").view("window_menu").build(M)
M.node = view.node
-- A press anywhere off the cards shuts it; Escape goes back a step first.
require("lib.kit.popup").track(view.box, { open = function() return M.opened:get() end,
  close_policy = "outside", modal = true, on_close = function() M.close() end })
morf.effect("eva.window_menu.shown", function() view.shown(M.opened:get()) end)

return M
