-- A Hyprland in Lua: the shape of lib.compositor.hyprland over a window list it
-- keeps itself, for a machine that cannot run one. `hl.*` chunks are evaluated
-- against a table with Hyprland's names and argument checks, classic
-- dispatchers go by name, and `j/` questions are answered from the list.
--
-- EVA_FAKE_WINDOWS=1 is the built-in scene; a path names a JSON file with the
-- same fields, and text starting with `{` is that JSON itself. Windows the
-- compositor really has (morf.toplevels) join the
-- list, placed by their title in the scene's `places`; focusing, closing and
-- maximizing one of those is done to the real window.
local morf = require("morf")

local M = {}

local SCENE = {
  workspaces = { { id = 1, layout = "dwindle" }, { id = 2, layout = "master" }, { id = 3, layout = "dwindle" } },
  clients = {
    { class = "kitty", title = "~/code/eva", workspace = 1, pid = 4101 },
    { class = "firefox", title = "Hyprland Wiki", workspace = 1, pid = 4102 },
    { class = "code", title = "overview.lua", workspace = 1, pid = 4103 },
    { class = "kitty", title = "btop", workspace = 2, pid = 4104 },
    { class = "mpv", title = "lecture.mkv", workspace = 2, pid = 4105, content = "video" },
    { class = "firefox", title = "Mail", workspace = 3, pid = 4106 },
    { class = "org.gnome.Nautilus", title = "Pictures", workspace = 3, floating = true, pid = 4107,
      x = 420, y = 180, width = 720, height = 480 },
    { class = "spotify", title = "Spotify", workspace = "special:music", pid = 4108 },
  },
  places = {},
  focus = 1,
}

local function deep(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = deep(v) end
  return out
end

local function read(spec)
  if spec == "1" then return deep(SCENE) end
  local ok, text = true, spec
  if spec:sub(1, 1) ~= "{" then ok, text = pcall(morf.fs.read, spec) end
  if ok and text then
    local parsed, scene = pcall(morf.json.decode, text)
    if parsed and type(scene) == "table" then return scene end
  end
  morf.log("warn", "eva: the window stand-in cannot read " .. tostring(spec))
  return deep(SCENE)
end

--- A stand-in for `scene`: the library's table, and `stand_in = true`.
function M.new(scene)
  scene = scene or deep(SCENE)
  local H = { stand_in = true, wire = {} }
  local listeners = {}
  local windows, workspaces, specials = {}, {}, {}
  local order, serial = {}, 0
  local active, shown, shown_special = nil, 1, ""
  local cursor = { x = 0, y = 0 }
  local rules = {}

  H.state = morf.state {
    connected = true, monitors = {}, outputs = {}, workspaces = {}, clients = {},
    active_workspace = { id = 1, name = "1" },
    active_window = { address = "", class = "", title = "" },
    focused_monitor = "", keyboard = "", keyboard_layout = "English (US)", submap = "", fullscreen = false, urgent = "",
  }
  local state = H.state

  local function screen() return (morf.screens or {})[1] or { name = "HEADLESS-1", width = 1920, height = 1080 } end
  local function monitors()
    local s = screen()
    local out = { { id = 0, name = s.name or "HEADLESS-1", x = 0, y = 0, width = s.width or 1920, height = s.height or 1080,
      scale = 1 } }
    if scene.second_monitor then
      out[2] = { id = 1, name = "DP-9", x = out[1].width, y = 0, width = 2560, height = 1440, scale = 1 }
    end
    return out
  end
  local RESERVED = { 16, 16, 16, 16 }

  local function address(i)
    serial = serial + 1
    return ("0x%x"):format(0xa000 + (i or serial) * 16)
  end
  local function by_address(a)
    for _, w in ipairs(windows) do if w.address == a then return w end end
  end
  local function selected(args)
    local w = args and args.window
    if w == nil then return by_address(active) end
    local a = tostring(w):match("^address:(.+)$")
    return a and by_address(a) or nil
  end
  local function emit(name, ...)
    for _, fn in ipairs(listeners[name] or {}) do fn(...) end
  end

  -- Tiles a workspace's windows into the monitor, by its layout.
  local function arrange(id)
    local m = monitors()[1]
    local x0, y0 = RESERVED[1], RESERVED[2]
    local w0, h0 = m.width - RESERVED[1] - RESERVED[3], m.height - RESERVED[2] - RESERVED[4]
    local tiled = {}
    for _, w in ipairs(windows) do
      if w.workspace == id and not w.floating then tiled[#tiled + 1] = w end
    end
    local layout = (workspaces[id] or {}).layout or "dwindle"
    local gap, n = 8, #tiled
    for i, w in ipairs(tiled) do
      if n == 1 or layout == "monocle" then w.x, w.y, w.width, w.height = x0, y0, w0, h0
      elseif layout == "master" then
        if i == 1 then w.x, w.y, w.width, w.height = x0, y0, math.floor(w0 * .55) - gap / 2, h0
        else
          local h = (h0 - gap * (n - 2)) // (n - 1)
          w.x, w.y, w.width, w.height = x0 + math.floor(w0 * .55) + gap / 2, y0 + (i - 2) * (h + gap),
            w0 - math.floor(w0 * .55) - gap / 2, h
        end
      elseif layout == "scrolling" then
        local width = (w0 - gap) // 2
        w.x, w.y, w.width, w.height = x0 + (i - 1) * (width + gap), y0, width, h0
      elseif i == 1 then w.x, w.y, w.width, w.height = x0, y0, (w0 - gap) // 2, h0
      else
        local h = (h0 - gap * (n - 2)) // (n - 1)
        w.x, w.y, w.width, w.height = x0 + (w0 - gap) // 2 + gap, y0 + (i - 2) * (h + gap), (w0 - gap) // 2, h
      end
    end
  end

  local function workspace_row(id)
    local row = workspaces[id] or {}
    local count, last = 0, nil
    for _, w in ipairs(windows) do
      if w.workspace == id then count = count + 1 last = w end
    end
    return { id = id, name = row.name or tostring(id), monitor = row.monitor or monitors()[1].name, monitor_id = 0,
      windows = count, fullscreen = false, last_window = last and last.address or "",
      last_window_title = last and last.title or "", persistent = false, special = id < 0,
      visible = id == shown, active = id == shown, urgent = false, tiled_layout = row.layout or "dwindle" }
  end

  -- Hands the models what the list says now.
  local function publish()
    local mons = monitors()
    for _, m in ipairs(mons) do
      m.description, m.make, m.model, m.serial = "Stand-in", "eva", "stand-in", ""
      m.transform, m.refresh_rate, m.available_modes, m.mirror_of = 0, 60, {}, -1
      m.focused, m.disabled, m.vrr, m.dpms = m.id == 0, false, false, true
      m.active_workspace = m.id == 0 and shown or 11
      m.active_workspace_name = m.id == 0 and ((workspaces[shown] or {}).name or tostring(shown)) or "11"
      m.special_workspace, m.special_workspace_name = 0, shown_special
      m.reserved = RESERVED
    end
    state.focused_monitor = mons[1].name
    state.monitors:replace(mons, "id")
    state.outputs:replace(mons, "name")
    for id in pairs(workspaces) do if id > 0 then arrange(id) end end
    local rows = {}
    for rank, a in ipairs(order) do
      local w = by_address(a)
      if w then w.focus_history = rank - 1 end
    end
    for _, w in ipairs(windows) do
      local row = {}
      for k, v in pairs(w) do row[k] = v end
      row.workspace_name = (workspaces[w.workspace] or specials[w.workspace] or {}).name or tostring(w.workspace)
      row.monitor = w.monitor or 0
      row.active = w.address == active
      rows[#rows + 1] = row
    end
    table.sort(rows, function(a, b)
      if a.workspace ~= b.workspace then return a.workspace < b.workspace end
      return a.address < b.address
    end)
    state.clients:replace(rows, "address")
    local list = {}
    for id in pairs(workspaces) do list[#list + 1] = workspace_row(id) end
    for id in pairs(specials) do
      local row = workspace_row(id)
      row.name = specials[id].name
      list[#list + 1] = row
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    state.workspaces:replace(list, "id")
    state.active_workspace.id = shown
    state.active_workspace.name = (workspaces[shown] or {}).name or tostring(shown)
    local w = by_address(active)
    state.active_window.address = w and w.address or ""
    state.active_window.class = w and w.class or ""
    state.active_window.title = w and w.title or ""
    emit("refreshed", "clients")
  end

  local function workspace_id(value)
    local text = tostring(value)
    local name = text:match("^special:(.*)$")
    if name then
      for id, row in pairs(specials) do if row.name == "special:" .. name then return id end end
      local id = -100 - #windows - serial
      specials[id] = { name = "special:" .. name }
      return id
    end
    if text == "previous" then return shown end
    if text == "empty" then
      local id = 1
      while true do
        local used = false
        for _, w in ipairs(windows) do if w.workspace == id then used = true end end
        if not used then return id end
        id = id + 1
      end
    end
    local relative = text:match("^[er]?([+-]%d+)$")
    if relative then return math.max(1, shown + tonumber(relative)) end
    local number = tonumber(text)
    if number then return math.floor(number) end
    for id, row in pairs(workspaces) do if row.name == text or "name:" .. tostring(row.name) == text then return id end end
    return nil
  end
  local function ensure(id)
    if id and id > 0 and not workspaces[id] then
      workspaces[id] = { id = id, layout = rules[id] or "dwindle" }
    end
    return id
  end

  local function focus(a)
    active = a
    for i = #order, 1, -1 do if order[i] == a then table.remove(order, i) end end
    if a then table.insert(order, 1, a) end
    local w = by_address(a)
    if w and w.toplevel and morf.toplevels then pcall(morf.toplevels.activate, w.toplevel) end
    if w and w.workspace > 0 and w.workspace ~= shown then shown = w.workspace end
    emit("activewindowv2", a or "")
  end
  local function forget(w)
    for i = #windows, 1, -1 do if windows[i] == w then table.remove(windows, i) end end
    for i = #order, 1, -1 do if order[i] == w.address then table.remove(order, i) end end
    if active == w.address then active = order[1] end
  end
  local function close(w)
    if w.toplevel and morf.toplevels then pcall(morf.toplevels.close, w.toplevel) end
    forget(w)
    emit("closewindow", w.address)
  end
  local function move_to(w, id, follow)
    ensure(id)
    w.workspace = id
    if follow ~= false and id > 0 then shown = id end
    emit("movewindowv2", w.address, id, tostring(id))
  end
  local function fail(message) error(message, 0) end
  local function toggled(action, now)
    if action == "on" then return true elseif action == "off" then return false end
    return not now
  end

  local DSP = { window = {}, workspace = {}, group = {}, cursor = {} }
  local function verb(group, name, fn)
    local home = group and DSP[group] or DSP
    home[name] = function(...)
      local args = table.pack(...)
      return { run = function() return fn(table.unpack(args, 1, args.n)) end }
    end
  end
  local function target(args)
    if args ~= nil and type(args) ~= "table" then fail("expected a table") end
    local w = selected(args)
    return w
  end
  verb("window", "float", function(a)
    local w = target(a)
    if w then w.floating = toggled(a and a.action, w.floating) end
  end)
  verb("window", "resize", function(a)
    local w = target(a)
    if not w or a == nil or a.x == nil then return end
    local cx, cy = w.x + w.width / 2, w.y + w.height / 2
    w.width, w.height = math.floor(a.x), math.floor(a.y)
    if w.floating then w.x, w.y = math.floor(cx - w.width / 2), math.floor(cy - w.height / 2) end
  end)
  verb("window", "move", function(a)
    local w = target(a)
    if not w then return end
    if a.workspace ~= nil then move_to(w, workspace_id(a.workspace), a.follow)
    elseif a.monitor then w.monitor = a.monitor == "DP-9" and 1 or 0
    elseif a.x then w.x, w.y = math.floor(a.x), math.floor(a.y) end
  end)
  verb("window", "center", function(a)
    local w, m = target(a), monitors()[1]
    if w then w.x, w.y = (m.width - w.width) // 2, (m.height - w.height) // 2 end
  end)
  verb("window", "pin", function(a)
    local w = target(a)
    if w then w.pinned = toggled(a and a.action, w.pinned) end
  end)
  verb("window", "close", function(a) local w = target(a) if w then close(w) end end)
  verb("window", "kill", function(a) local w = target(a) if w then close(w) end end)
  verb("window", "fullscreen", function(a)
    local w = target(a)
    if not w then return end
    local mode = a and a.mode == "maximized" and 1 or 2
    w.fullscreen = (a and a.action == "unset" or w.fullscreen == mode) and 0 or mode
    if w.toplevel and morf.toplevels then
      pcall(mode == 1 and morf.toplevels.set_maximized or morf.toplevels.set_fullscreen, w.toplevel, w.fullscreen ~= 0)
    end
  end)
  verb("window", "bring_to_top", function(a) target(a) end)
  verb("window", "alter_zorder", function(a)
    if type(a) ~= "table" then fail("hl.window.alter_zorder: expected a table { mode, window? }") end
    if not a.mode then fail("hl.window.alter_zorder: 'mode' is required") end
    target(a)
  end)
  verb("window", "set_prop", function(a)
    local w = target(a)
    if a.prop ~= "opacity" and a.prop ~= "no_blur" and a.prop ~= "opaque" then fail("Invalid prop name") end
    if w and a.prop == "opacity" then w.opacity = tonumber(a.value) end
  end)
  verb("window", "cycle_next", function() end)
  verb("window", "swap", function() end)
  verb("window", "drag", function() end)
  verb(nil, "focus", function(a)
    if a.window then
      local w = selected(a)
      if w then focus(w.address) end
    elseif a.workspace ~= nil then
      local id = ensure(workspace_id(a.workspace))
      if id then
        shown = id
        local here
        for _, candidate in ipairs(order) do
          local w = by_address(candidate)
          if w and w.workspace == id then here = candidate break end
        end
        active = here
        emit("workspacev2", id, tostring(id))
      end
    end
  end)
  verb("workspace", "toggle_special", function(name)
    name = tostring(name or "")
    shown_special = shown_special == "special:" .. name and "" or "special:" .. name
    emit("activespecial", shown_special, monitors()[1].name)
  end)
  verb("workspace", "rename", function(a)
    if type(a) ~= "table" then fail("hl.workspace.rename: expected a table { workspace, name? }") end
    if a.workspace == nil then fail("hl.workspace.rename: 'workspace' is required") end
    local id = workspace_id(a.workspace)
    if id and workspaces[id] then workspaces[id].name = a.name ~= "" and a.name or nil end
  end)
  verb("workspace", "move", function() end)
  verb("group", "toggle", function() end)
  verb("group", "lock_active", function() end)
  verb("group", "next", function() end)
  verb("group", "prev", function() end)
  verb(nil, "layout", function(message)
    local kind = (workspaces[shown] or {}).layout or "dwindle"
    local word = tostring(message):match("^(%S+)")
    if word == "splitratio" and not tostring(message):match("^splitratio%s+[+-]?[%d.]+$") then
      fail('failed to parse "exact" as a delta')
    end
    if kind == "dwindle" and word and word:match("^orientation") then fail("Unknown dwindle layoutmsg: " .. word) end
  end)
  verb(nil, "exec_cmd", function() end)
  verb("cursor", "move", function(a) cursor.x, cursor.y = a.x, a.y end)

  local hl = { dsp = DSP }
  function hl.dispatch(d) return d.run() end
  function hl.workspace_rule(rule)
    local id = workspace_id(rule.workspace)
    if rule.layout and id then
      rules[id] = rule.layout
      ensure(id)
      workspaces[id].layout = rule.layout
    end
  end
  function hl.config() end
  function hl.bind() end
  function hl.gesture() end
  function hl.exec_cmd() end

  local function reply(fn, ...)
    local ok, why = pcall(fn, ...)
    publish()
    if ok then return "ok" end
    return "error: =[C]:-1: " .. tostring(why)
  end
  local function record(line) H.wire[#H.wire + 1] = line end

  local function raw_workspaces()
    local out = {}
    for _, row in ipairs(H.snapshot().workspaces) do
      out[#out + 1] = { id = row.id, name = row.name, monitor = row.monitor, windows = row.windows, tiledLayout = row.tiled_layout }
    end
    return out
  end

  --- Whether a compositor is there: always, this one.
  function H.available() return true end
  function H.start() return true end
  function H.stop() end
  function H.refresh() publish() end
  function H.on(name, fn)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], fn)
    return { off = function()
      for i, f in ipairs(listeners[name]) do if f == fn then table.remove(listeners[name], i) end end
    end }
  end
  function H.request(command, callback)
    command = tostring(command)
    record(command)
    local chunk = command:match("^/eval (.*)$")
    local answer
    if chunk then return H.eval(chunk, callback, true) end
    if command == "j/activewindow" then
      answer = morf.json.encode(by_address(active) and { address = active } or {})
    elseif command == "j/workspaces" then answer = morf.json.encode(raw_workspaces())
    else answer = "ok" end
    if callback then callback(answer) end
    return true
  end
  function H.json(command, callback)
    command = tostring(command)
    record(command)
    if command:match("activewindow$") then callback(by_address(active) and { address = active } or {})
    elseif command:match("workspaces$") then callback(raw_workspaces())
    elseif command:match("cursorpos$") then callback { x = cursor.x, y = cursor.y }
    else callback({}) end
    return true
  end
  function H.batch(commands, callback) if callback then callback({}, nil) end return true end
  function H.eval(chunk, callback, recorded)
    if not recorded then record("/eval " .. tostring(chunk)) end
    local run, why = load(tostring(chunk), "eval", "t", { hl = hl, tostring = tostring, math = math })
    local answer = run and reply(run) or ("error: " .. tostring(why))
    if answer ~= "ok" then morf.log("warn", "eva: stand-in refused: " .. answer) end
    if callback then callback(answer) end
    return true
  end
  local CLASSIC = {
    workspace = function(arg) return "hl.dispatch(hl.dsp.focus({ workspace = " .. ("%q"):format(arg) .. " }))" end,
    focuswindow = function(arg) return "hl.dispatch(hl.dsp.focus({ window = " .. ("%q"):format(arg) .. " }))" end,
    closewindow = function(arg) return "hl.dispatch(hl.dsp.window.close({ window = " .. ("%q"):format(arg) .. " }))" end,
    movetoworkspace = function(arg)
      local ws, win = arg:match("^([^,]*),(.*)$")
      return ("hl.dispatch(hl.dsp.window.move({ workspace = %q, window = %q }))"):format(ws or arg, win or "")
    end,
    togglespecialworkspace = function(arg) return ("hl.dispatch(hl.dsp.workspace.toggle_special(%q))"):format(arg) end,
  }
  function H.dispatch(name, argument, callback)
    local line = "/dispatch " .. tostring(name) .. (argument and " " .. tostring(argument) or "")
    record(line)
    local form = CLASSIC[name]
    local answer = form and reply(load(form(tostring(argument or "")), "eval", "t", { hl = hl })) or "ok"
    if callback then callback(answer == "ok", answer) end
    return true
  end
  function H.keyword(_, _, callback) if callback then callback(true, "ok") end return true end
  function H.reload(_, callback) if callback then callback(true, "ok") end return true end
  function H.options(_, callback)
    callback { ["decoration:rounding"] = { int = 12 }, ["general:border_size"] = { int = 2 },
      ["general:col.active_border"] = { gradient = "ff7fb4e8 0deg" },
      ["general:col.inactive_border"] = { gradient = "ff404656 0deg" } }
    return true
  end
  function H.getoption(_, callback) if callback then callback({}) end return true end
  function H.binds(callback) if callback then callback({}) end return true end
  function H.devices(callback) if callback then callback({}) end return true end
  function H.version(callback) if callback then callback({ version = "stand-in" }) end return true end
  function H.layers(callback) if callback then callback({}) end return true end
  function H.cursor_position(callback) callback(cursor.x, cursor.y) return true end
  function H.parse_event(_, data) return data end
  H.repaired_json = function(text) return text end

  local function rows(model)
    local out = {}
    for i = 1, model:len() do out[i] = model:get(i) end
    return out
  end
  function H.monitor(key)
    for _, row in ipairs(rows(state.monitors)) do if row.name == key or row.id == key then return row end end
  end
  function H.outputs() return rows(state.outputs) end
  function H.workspace(key)
    for _, row in ipairs(rows(state.workspaces)) do if row.id == key or row.name == key then return row end end
  end
  function H.client(a)
    for _, row in ipairs(rows(state.clients)) do if row.address == a then return row end end
  end
  function H.workspace_windows(id)
    local out = {}
    for _, row in ipairs(rows(state.clients)) do if row.workspace == id then out[#out + 1] = row end end
    return out
  end
  function H.occupied(id)
    local row = H.workspace(id)
    return row ~= nil and row.windows > 0
  end
  function H.monitor_workspace() return shown end
  function H.snapshot()
    return { monitors = rows(state.monitors), outputs = rows(state.outputs), workspaces = rows(state.workspaces),
      clients = rows(state.clients) }
  end

  --- Where the pointer is, as `j/cursorpos` answers it.
  function H.set_cursor(x, y) cursor.x, cursor.y = x, y end
  H.emit = emit

  -- The scene.
  for _, row in ipairs(scene.workspaces or {}) do
    workspaces[row.id] = { id = row.id, layout = row.layout or "dwindle", name = row.name }
  end
  local function add(row, toplevel)
    local w = {}
    for k, v in pairs(row) do w[k] = v end
    w.address = address()
    w.initial_class, w.initial_title = w.class, w.title
    if type(w.workspace) == "string" then w.workspace = workspace_id(w.workspace) end
    w.workspace = w.workspace or shown
    w.x, w.y, w.width, w.height = w.x or 0, w.y or 0, w.width or 640, w.height or 480
    w.floating, w.pinned, w.hidden, w.mapped = w.floating == true, w.pinned == true, false, true
    w.fullscreen, w.xwayland, w.pid, w.focus_history = 0, false, w.pid or 0, #windows
    w.toplevel = toplevel
    ensure(w.workspace)
    windows[#windows + 1] = w
    order[#order + 1] = w.address
    return w
  end
  for _, row in ipairs(scene.clients or {}) do add(row) end
  if scene.focus and windows[scene.focus] then focus(windows[scene.focus].address) end

  -- The windows the compositor really has.
  local function adopt()
    if not morf.toplevels then return end
    local seen = {}
    for _, real in ipairs(morf.toplevels.list()) do
      seen[real.identifier] = true
      local mine
      for _, w in ipairs(windows) do if w.toplevel == real.identifier then mine = w end end
      if mine then
        mine.title, mine.class, mine.minimized = real.title, real.app_id, real.minimized
        if real.activated and active ~= mine.address then active = mine.address end
      else
        local place = (scene.places or {})[real.title] or {}
        add({ class = real.app_id, title = real.title, workspace = place.workspace or shown, floating = place.floating,
          x = place.x, y = place.y, width = place.width, height = place.height, content = place.content }, real.identifier)
      end
    end
    for i = #windows, 1, -1 do
      local w = windows[i]
      if w.toplevel and not seen[w.toplevel] then forget(w) end
    end
    publish()
  end
  publish()
  morf.effect("eva.windows.stand_in", function()
    if morf.window and morf.window.screens_revision then morf.window.screens_revision() end
    adopt()
  end)
  return H
end

--- Puts a stand-in where lib.compositor.hyprland is looked for, when
--- EVA_FAKE_WINDOWS asks for one. Call it before anything requires the library.
function M.install()
  local spec = morf.env and morf.env("EVA_FAKE_WINDOWS")
  if not spec or spec == "" or spec == "0" then return false end
  local have = package.loaded["lib.compositor.hyprland"]
  if have and have.stand_in then return true end
  package.loaded["lib.compositor.hyprland"] = M.new(read(spec))
  morf.log("info", "eva: windows come from the stand-in, not a compositor")
  return true
end

return M
