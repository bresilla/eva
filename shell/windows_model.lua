-- The windows, the one way everything between a person and their windows
-- reads them and acts on them: the compositor's lists as plain rows, and what
-- is sent to it. No nodes. Which compositor that is, is the library's
-- business (shell/windows_stand_in.lua puts one in its place).
--
-- EVA_DRY_RUN=1 logs what would be dispatched instead, unless the compositor
-- is the stand-in, which reaches nothing.
local morf = require("morf")
local services = require("services")
local hyprland = services.hyprland
local M = {}

--- Whether EVA_DRY_RUN holds back what would start or touch anything real.
local function held_back()
  local v = morf.env and morf.env("EVA_DRY_RUN")
  return (v and v ~= "" and v ~= "0") == true
end
M.held_back = held_back

local function dry_run()
  return not hyprland.stand_in and held_back()
end
M.dry_run = dry_run

-- ---------------------------------------------------------------- reading --

--- A whole number as Lua's integer: a model hands numbers back as floats, and
--- a float is written `2.0` into a command or a name.
function M.int(value)
  local n = tonumber(value)
  return n and math.tointeger(math.floor(n)) or value
end

local function rows(model)
  local out = {}
  for i = 1, model:len() do
    local row = model:get(i)
    if row.workspace then row.workspace = M.int(row.workspace) end
    if row.id then row.id = M.int(row.id) end
    if row.monitor and type(row.monitor) == "number" then row.monitor = M.int(row.monitor) end
    out[i] = row
  end
  return out
end

--- Whether a window is one a person can reach: mapped, and not a group's
--- hidden member.
local function reachable(c) return c.mapped ~= false and not c.hidden end

--- Every reachable window, as rows; a binding that calls it follows the list.
function M.list()
  local out = {}
  for _, c in ipairs(rows(hyprland.state.clients)) do
    if reachable(c) then out[#out + 1] = c end
  end
  return out
end

--- The window `address`, or nil.
function M.get(address)
  if not address or address == "" then return nil end
  for _, c in ipairs(rows(hyprland.state.clients)) do
    if c.address == address then return c end
  end
end

--- The focused window, or nil. When the compositor names none, as while a
--- panel holds the keys, the last focused on the workspace in view.
function M.active()
  local a = hyprland.state.active_window
  local found = M.get(a and a.address or "")
  if found then return found end
  local shown = M.int(hyprland.state.active_workspace.id)
  for _, c in ipairs(M.recent()) do
    if M.int(c.workspace) == shown then return c end
  end
end

-- The order windows took the focus in: the compositor's list says so only
-- when it is next asked for.
local focused_at, focus_turn = {}, 0
if hyprland.on then
  hyprland.on("activewindowv2", function(address)
    if address and address ~= "" then
      focus_turn = focus_turn + 1
      focused_at[address] = focus_turn
    end
  end)
end

--- `list`, most recently used first.
function M.recent(list)
  local out = {}
  for i, c in ipairs(list or M.list()) do out[i] = { c = c, i = i } end
  table.sort(out, function(a, b)
    local turn_a, turn_b = focused_at[a.c.address] or 0, focused_at[b.c.address] or 0
    if turn_a ~= turn_b then return turn_a > turn_b end
    local x, y = a.c.focus_history or -1, b.c.focus_history or -1
    if x < 0 then x = math.huge end
    if y < 0 then y = math.huge end
    if x ~= y then return x < y end
    return a.i < b.i
  end)
  for i, e in ipairs(out) do out[i] = e.c end
  return out
end

--- The windows of `list` by application, each group `{ class, windows }`, in
--- the order their most recent windows have.
function M.grouped(list)
  local groups, by = {}, {}
  for _, c in ipairs(M.recent(list)) do
    local key = c.class ~= "" and c.class or c.address
    if not by[key] then
      by[key] = { class = c.class, windows = {} }
      groups[#groups + 1] = by[key]
    end
    table.insert(by[key].windows, c)
  end
  return groups
end

--- The icon for an application: `{ name }`, `{ path }` or nil (shell/apps.lua).
function M.icon(class, initial)
  local apps = require("apps")
  class = class or ""
  return apps.icon(class:lower()) or apps.icon(class) or apps.icon((initial or ""):lower())
end

--- Whether `query` finds `c` by title or class, any case.
function M.matches(c, query)
  if not query or query == "" then return true end
  local q = query:lower()
  return (c.title or ""):lower():find(q, 1, true) ~= nil or (c.class or ""):lower():find(q, 1, true) ~= nil
end

function M.monitors() return rows(hyprland.state.monitors) end

--- The monitor row a window is on, or this screen's.
function M.monitor_of(c)
  local list = M.monitors()
  for _, m in ipairs(list) do if c and m.id == c.monitor then return m end end
  for _, m in ipairs(list) do if m.name == services.output() then return m end end
  return list[1]
end

function M.workspaces() return rows(hyprland.state.workspaces) end

--- The windows on workspace `id`, as rows.
function M.on(id)
  local out = {}
  for _, c in ipairs(M.list()) do if c.workspace == id then out[#out + 1] = c end end
  return out
end

--- The factor from the compositor's logical pixels to this surface's.
function M.ratio(m)
  local s = (morf.screens or {})[1] or {}
  m = m or M.monitor_of()
  local logical = m and m.width and m.width / math.max(.01, m.scale or 1) or 0
  if s.width and logical > 0 then return s.width / logical end
  return 1
end

--- A window's box in this surface's pixels; the screen's origin is the
--- monitor's in the compositor's layout.
function M.rect(c)
  local m = M.monitor_of(c) or {}
  local ratio = M.ratio(m)
  return { x = (c.x - (m.x or 0)) * ratio, y = (c.y - (m.y or 0)) * ratio,
    width = c.width * ratio, height = c.height * ratio }
end

-- ---------------------------------------------------------------- dispatch --

local lua_config
local function flavour(done)
  if lua_config ~= nil then return done(lua_config) end
  local ok, config = pcall(require, "lib.compositor.hyprland_config")
  if not ok then lua_config = false return done(false) end
  config.flavour(function(kind) lua_config = kind == "lua" done(lua_config) end)
end
M.flavour = flavour

local function quoted(value) return ("%q"):format(tostring(value)) end
local function fields(t)
  local out = {}
  for k, v in pairs(t) do out[#out + 1] = k .. " = " .. (type(v) == "string" and quoted(v) or tostring(v)) end
  table.sort(out)
  return "{ " .. table.concat(out, ", ") .. " }"
end

local function checked(reply, err)
  if err or (reply and not reply:match("^%s*ok%s*$")) then
    morf.log("warn", "eva: windows: " .. tostring(err or reply))
  end
  M.refresh()
end

--- A step that takes the window it is for: `lua` the `hl.dsp` name and its
--- fields, `conf` the classic dispatcher and argument ($W is the window).
function M.step(lua, conf) return { lua = lua, conf = conf } end
--- A step on what has the focus, sent after the window is focused.
function M.global(lua, conf) return { global = true, lua = lua, conf = conf } end

-- The latest of what was sent, for `windows sent`.
M.sent = {}
local function note(text)
  table.insert(M.sent, 1, text)
  M.sent[17] = nil
end

-- A window's size, place and floating come by no event of their own: the list
-- is asked for again after anything the shell sends, and by whatever is about
-- to read it.
local refreshing
function M.refresh()
  if refreshing or not hyprland.refresh then return end
  refreshing = morf.time.timer(40, function()
    refreshing = nil
    hyprland.refresh()
  end, false)
end

--- Runs `steps` on `address`: the Lua form on a Lua-configured Hyprland and
--- the classic one elsewhere. False with no window.
function M.run(address, steps)
  if not address or address == "" then return false end
  local selector = "address:" .. address
  if dry_run() then
    local names = {}
    for _, s in ipairs(steps) do names[#names + 1] = s.lua[1] end
    morf.log("info", "eva: windows (dry run): " .. table.concat(names, ", ") .. " on " .. address)
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
      note(table.concat(chunk, " "))
      hyprland.eval(table.concat(chunk, " "), checked)
    else
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

--- Sends one whole-compositor change: the `lua` chunk on a Lua-configured
--- Hyprland, the classic `dispatcher` and argument elsewhere.
function M.send(lua, dispatcher, argument)
  if dry_run() then
    morf.log("info", "eva: windows (dry run): " .. lua)
    return true
  end
  flavour(function(is_lua)
    note(lua)
    if is_lua then hyprland.eval(lua, checked)
    elseif dispatcher then hyprland.dispatch(dispatcher, argument) end
  end)
  return true
end

-- -------------------------------------------------------------------- steps --

local S = M.step
M.steps = {}
local steps = M.steps
function steps.close() return { S({ "window.close", {} }, { "closewindow", "$W" }) } end
function steps.kill() return { S({ "window.kill", {} }, { "killwindow", "$W" }) } end
function steps.float(on)
  return { S({ "window.float", { action = on and "on" or "off" } }, { on and "setfloating" or "settiled", "$W" }) }
end
function steps.toggle_float() return { S({ "window.float", { action = "toggle" } }, { "togglefloating", "$W" }) } end
function steps.pin() return { S({ "window.pin", { action = "toggle" } }, { "pin", "$W" }) } end
function steps.center() return { S({ "window.center", {} }, { "centerwindow", nil }) } end
function steps.resize(x, y)
  x, y = math.floor(x), math.floor(y)
  return { S({ "window.resize", { x = x, y = y } }, { "resizewindowpixel", ("exact %d %d,$W"):format(x, y) }) }
end
function steps.place(x, y)
  x, y = math.floor(x), math.floor(y)
  return { S({ "window.move", { x = x, y = y } }, { "movewindowpixel", ("exact %d %d,$W"):format(x, y) }) }
end
function steps.to_workspace(id, follow)
  id = type(id) == "string" and id or M.int(id)
  return { S({ "window.move", { workspace = tostring(id), follow = follow == true } },
    { follow and "movetoworkspace" or "movetoworkspacesilent", id .. ",$W" }) }
end
function steps.to_monitor(name) return { S({ "window.move", { monitor = name } }, { "movewindow", "mon:" .. name }) } end
function steps.opacity(value)
  local text = ("%.2f"):format(value)
  return { S({ "window.set_prop", { prop = "opacity", value = text } }, { "setprop", "$W opacity " .. text }) }
end
function steps.raise() return { S({ "window.alter_zorder", { mode = "top" } }, { "alterzorder", "top,$W" }) } end

--- The floating box `steps` for a window: float it, size it, put it there.
function steps.box(x, y, w, h)
  local out = steps.float(true)
  for _, list in ipairs { steps.resize(w, h), steps.place(x, y) } do out[#out + 1] = list[1] end
  return out
end

-- ------------------------------------------------------- kept in the shell --

-- What the compositor keeps no record of: the windows kept above, and each
-- window's opacity.
local session = require("themes.session")
local above = session.keep("eva.windows.above", {})
local opacity = session.keep("eva.windows.opacity", {})
M.OPACITIES = { 1, .85, .7 }

function M.kept_above(address) return above:get()[address] == true end

--- Keeps a window above the others, or lets it go: it floats, and comes back
--- to the top whenever the focus moves.
function M.keep_above(address)
  local kept = {}
  for k, v in pairs(above:get()) do kept[k] = v end
  kept[address] = not kept[address] or nil
  above:set(kept)
  if kept[address] then
    local list = steps.float(true)
    list[#list + 1] = steps.raise()[1]
    M.run(address, list)
  end
  return kept[address] == true
end

function M.opacity_of(address) return opacity:get()[address] or 1 end

--- Sets a window's opacity, 1 being solid.
function M.set_opacity(address, value)
  local all = {}
  for k, v in pairs(opacity:get()) do all[k] = v end
  all[address] = value < 1 and value or nil
  opacity:set(all)
  return M.run(address, steps.opacity(value))
end

--- The next of the opacities on offer.
function M.next_opacity(address)
  local now = M.opacity_of(address)
  for i, v in ipairs(M.OPACITIES) do
    if math.abs(v - now) < .01 then return M.set_opacity(address, M.OPACITIES[i % #M.OPACITIES + 1]) end
  end
  return M.set_opacity(address, 1)
end

-- Raises the kept windows each time the focus moves, and forgets gone ones.
local raised_for
morf.effect("eva.windows.above", function()
  local focused = (hyprland.state.active_window or {}).address
  local kept = above:get()
  if focused == raised_for or next(kept) == nil then return end
  raised_for = focused
  morf.time.timer(1, function()
    for address in pairs(kept) do
      if M.get(address) then M.run(address, steps.raise()) end
    end
  end, false)
end)

-- The windows put aside to show the desktop, and the workspace they are from.
local aside = session.keep("eva.windows.aside", {})

--- Puts the windows on workspace `id` aside, on a hidden workspace of their
--- own, or brings them back: false once they are back.
function M.show_desktop(id)
  local kept = aside:get()
  if #kept > 0 then
    aside:set({})
    for _, address in ipairs(kept) do
      if M.get(address) then M.to_workspace(address, id, false) end
    end
    return false
  end
  local list = {}
  for _, c in ipairs(M.on(id)) do
    list[#list + 1] = c.address
    M.to_workspace(c.address, "special:desktop", false)
  end
  aside:set(list)
  return #list > 0
end

function M.focus(address)
  if not address or address == "" then return false end
  if dry_run() then
    morf.log("info", "eva: windows (dry run): focus " .. address)
    return true
  end
  if hyprland.available() then hyprland.dispatch("focuswindow", "address:" .. address) return true end
  return false
end
--- Goes to a window from a surface that held the keyboard: the compositor gives
--- the focus back as the surface lets go, so it is asked twice more.
function M.focus_after_keys(address)
  M.focus(address)
  for _, ms in ipairs { 120, 400 } do
    morf.time.timer(ms, function()
      local active = hyprland.state.active_window
      if M.get(address) and (active and active.address) ~= address then M.focus(address) end
    end, false)
  end
end

function M.close(address)
  require("window_shots").pause()
  return M.run(address, steps.close())
end
function M.kill(address)
  require("window_shots").pause()
  return M.run(address, steps.kill())
end
if hyprland.on then
  hyprland.on("closewindow", function(address)
    local shots = require("window_shots")
    shots.pause()
    if address then shots.forget(address) end
  end)
end
function M.to_workspace(address, id, follow) return M.run(address, steps.to_workspace(id, follow)) end
function M.to_monitor(address, name) return M.run(address, steps.to_monitor(name)) end

return M
