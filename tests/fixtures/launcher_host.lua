-- What the launcher's specs share: the real shell, some desktop files, and a
-- folder of names that make `run.has` say a program is there. `morf test` keeps the
-- XDG folders in a scratch directory, so all of it stays away from the person's own.

local test = morf.test

local M = {}

M.SHELL = [==[
  package.loaded["lib.integrations.weather"] = {
    new = function() return { get = function() return { available = false, daily = {} } end } end,
  }
  -- A stand-in for what NetworkManager, BlueZ and PipeWire would report.
  if morf.env("EVA_TEST_RADIOS") == "1" then
    local list = function(rows)
      return { len = function() return #rows end, get = function(_, i) return rows[i] end }
    end
    local services = require("services")
    services.net = { state = { available = true, wifi_enabled = true, devices = list {},
      vpn_connections = list { { id = "Work", uuid = "u-1", type = "wireguard", active = false } },
      wired = { device = "", connected = false, carrier = false, ip4 = "" }, access_points = list {
        { ssid = "Home", key = "home", in_use = true, known = true, secure = true, strength = 80, security = "wpa" },
        { ssid = "Cafe", key = "cafe", known = true, secure = true, strength = 60, security = "wpa" },
        { ssid = "Locked", key = "locked", secure = true, strength = 30, security = "wpa" },
      } } }
    services.bt = { state = { available = true, powered = true, discovering = false, devices = list {
      { path = "/d/1", address = "AA:BB", alias = "Buds", paired = true } } } }
    local sinks = { { id = 1, name = "speakers", description = "Speakers", kind = "sink" },
      { id = 2, name = "phones", description = "Headphones", kind = "sink" } }
    morf.audio = { available = function() return true end, default_sink = function() return sinks[1] end,
      default_source = function() return nil end, sinks = list(sinks), sources = list {}, streams = list {} }
  end
  -- Stand-ins for a compositor's windows, the web, and a player.
  local window_calls = {}
  if morf.env("EVA_TEST_WINDOWS") == "toplevels" then
    local function call(name)
      return function(...)
        local words = { name }
        for _, value in ipairs { ... } do words[#words + 1] = tostring(value) end
        window_calls[#window_calls + 1] = table.concat(words, " ")
      end
    end
    morf.toplevels = { list = function()
      return { { identifier = 1, title = "Notes", app_id = "notes" },
        { identifier = 2, title = "Reader", app_id = "reader", activated = true } }
    end, activate = call("activate"), close = call("close"), set_maximized = call("maximize"),
      set_fullscreen = call("fullscreen"), set_minimized = call("minimize") }
  elseif morf.env("EVA_TEST_WINDOWS") == "hyprland" then
    local h = require("lib.compositor.hyprland")
    h.available = function() return true end
    h.state.clients:replace({ { address = "0xabc", title = "A terminal", class = morf.env("EVA_TEST_WINDOW_CLASS") or "foot",
      workspace = 1, pid = 7, x = 0, y = 0, width = 800, height = 600, mapped = true } }, "address")
    h.dispatch = function(name, arg) window_calls[#window_calls + 1] = name .. " " .. tostring(arg) end
  end
  local http_asked = {}
  if morf.env("EVA_TEST_HTTP") then
    local answers = {
      { "mymemory", { responseStatus = 200, responseData = { translatedText = "hola" } } },
      { "dictionaryapi", { { meanings = { { partOfSpeech = "noun", definitions = { { definition = "A greeting" } } } } } } },
      { "wikipedia", { title = "Linux", extract = "A family of operating systems.",
        content_urls = { desktop = { page = "https://en.wikipedia.org/wiki/Linux" } } } },
    }
    morf.http.get = function(url, _, done)
      http_asked[#http_asked + 1] = url
      if morf.env("EVA_TEST_HTTP") == "down" then done { ok = false } return end
      for _, answer in ipairs(answers) do
        if url:find(answer[1], 1, true) then
          done { ok = true, json = function() return answer[2] end }
          return
        end
      end
      done { ok = false }
    end
  end
  local media_calls = {}
  require("init")
  local launcher = require("launcher")
  if morf.env("EVA_TEST_MEDIA") == "1" then
    local media = require("media_state")
    media.active = function() return { title = "A Song", artist = "Someone", playing = true } end
    media.something = function() return true end
    media.playing = function() return true end
    media.control = function(verb) media_calls[#media_calls + 1] = verb end
  end
  morf.ipc.window_calls = function() return window_calls end
  morf.ipc.http_asked = function() return http_asked end
  morf.ipc.media_calls = function() return media_calls end
  morf.ipc.origin = function(source, exec) return require("apps").origin_of { source = source, exec = exec } end
  morf.ipc.parse_task = function(text) return require("launcher_modes.time").parse_task(text) end
  morf.ipc.presented = function(name) return require("presentation").active(name)() end
  morf.ipc.seam = function()
    local timers = require("timers_model")
    local held = {}
    timers.use { add = function(entry) held[#held + 1] = entry.label end, cancel = function() end, list = function() return {} end }
    timers.alarm(morf.time.now() + 60, "late")
    return held
  end
  local typed = {}
  morf.input_method = { delete = function(n) typed[#typed + 1] = "delete " .. n end,
    commit = function(text) typed[#typed + 1] = "commit " .. text end }
  morf.ipc.heard = function(text, cursor)
    require("text_expansion").heard(true, text, tonumber(cursor), tonumber(cursor))
    return true
  end
  morf.ipc.typed = function() return typed end
  morf.ipc.keyboard_open = function() return require("keyboard").drawer.open:get() end
  morf.ipc.preview_clear = function() launcher.preview_open:set(false) return true end
  morf.ipc.toggle_preview = function() return launcher.toggle_preview() end
  morf.ipc.timers_path = function() return morf.paths.state("eva-timers.json") end
  morf.ipc.dashboard_open = function() return require("dashboard").drawer.open:get() end
  local status_reads = 0
  do
    local index = require("lib.shell.launcher.search_index")
    for _, entry in ipairs(index.all()) do
      local description = entry.description
      if type(description) == "function" then
        entry.description = function()
          status_reads = status_reads + 1
          return description()
        end
      end
    end
  end
  morf.ipc.status_reads = function(query)
    status_reads = 0
    require("universal").search(query, 40)
    return status_reads
  end
  morf.ipc.timed_query = function(query)
    local started = morf.time.now_ms()
    require("universal").search(query, 40)
    return morf.time.now_ms() - started
  end
  morf.ipc.columns = function() return launcher.columns:get() end
  local copied = {}
  morf.clipboard.set = function(data) copied[#copied + 1] = data end
  morf.ipc.q = function(text) launcher.set_query(text) return true end
  morf.ipc.rows = function()
    local out = {}
    for i = 1, launcher.results:len() do
      local entry = launcher.results:get(i)
      out[i] = { kind = entry.kind, id = entry.id, name = entry.name, description = entry.description, tag = entry.tag,
        key = entry.key, spans = entry.spans ~= nil, cells = entry.cells and #entry.cells or nil }
    end
    return out
  end
  morf.ipc.state = function()
    return { query = launcher.query:get(), selected = launcher.selected:get(), acting = launcher.acting:get(),
      open = launcher.drawer.open:get(), mode = launcher.mode:get(), cell = launcher.cell:get(),
      preview = launcher.preview_open:get(), large = launcher.large_type:get(), folder = launcher.folder:get(),
      category = launcher.category:get(), name = (launcher.mode_name()) }
  end
  morf.ipc.chosen = function() local r = launcher.chosen() return r and r.name end
  morf.ipc.activate = function() launcher.activate(launcher.chosen()) return true end
  morf.ipc.act_names = function()
    local out = {}
    for i, a in ipairs(launcher.actions_of(launcher.chosen())) do out[i] = a.name end
    return out
  end
  morf.ipc.do_action = function(name)
    for _, a in ipairs(launcher.actions_of(launcher.chosen())) do
      if a.name == name then
        local step = a.run()
        if step == "close" then launcher.drawer.set(false)
        elseif type(step) == "string" and step ~= "keep" then launcher.set_query(step) end
        return true
      end
    end
    return false
  end
  morf.ipc.do_action_row = function(name)
    for i = 1, launcher.results:len() do
      local entry = launcher.results:get(i)
      if entry.name == name then launcher.activate(launcher.row_of(entry)) return true end
    end
    return false
  end
  morf.ipc.copied = function() return copied end
  morf.ipc.setting = function(key, value)
    if value ~= nil then
      local ok, decoded = pcall(morf.json.decode, value)
      require("config").set(key, ok and decoded ~= nil and decoded or value)
    end
    return require("config").get(key)
  end
  morf.ipc.settings_detail = function() return require("settings_model").detail:get() end
  morf.ipc.sidebar_open = function() return require("sidebar").drawer.open:get() end
  morf.ipc.settings_missing = function()
    local model = require("settings_model")
    local index = require("lib.shell.launcher.search_index")
    local missing = {}
    for _, page in ipairs(model.DETAILS) do
      if not index.get("setting:" .. page.key) then missing[#missing + 1] = "page " .. page.key end
    end
    for _, tile in ipairs(model.TOGGLES) do
      if not index.get("tile:" .. tile.id) then missing[#missing + 1] = "tile " .. tile.id end
    end
    return missing
  end
  morf.ipc.timed_search = function()
    local apps = require("apps")
    local rows = apps.rows()
    for i = 1, 1000 do
      rows[#rows + 1] = { kind = "app", id = "made-" .. i, name = "Made Application " .. i, description = "A row", icon = "",
        keywords = "", categories = {}, desktop_actions = {}, command = {} }
    end
    local started = morf.time.now_ms()
    require("universal").search("made app", 40)
    return morf.time.now_ms() - started
  end
]==]

local function write(path, text)
  assert(morf.fs.write(path, text, { parents = true }))
end

M.write = write

--- The desktop files every spec finds: a browser with actions, an editor, a
--- terminal program.
function M.apps()
  local folder = morf.env("XDG_DATA_HOME") .. "/applications/"
  write(folder .. "fixture-browser.desktop", table.concat({
    "[Desktop Entry]", "Type=Application", "Name=Fixture Browser", "Comment=Reads the web", "Exec=fixture-browser %u",
    "Icon=web-browser", "Categories=Network;WebBrowser;", "Keywords=internet;www;", "Actions=new-window;private;", "",
    "[Desktop Action new-window]", "Name=New Window", "Exec=fixture-browser --new-window", "",
    "[Desktop Action private]", "Name=New Private Window", "Exec=fixture-browser --private", "" }, "\n"))
  write(folder .. "fixture-editor.desktop", table.concat({
    "[Desktop Entry]", "Type=Application", "Name=Fixture Editor", "Comment=Writes text", "Exec=fixture-editor %F",
    "Categories=Development;IDE;", "" }, "\n"))
  write(folder .. "fixture-top.desktop", table.concat({
    "[Desktop Entry]", "Type=Application", "Name=Fixture Top", "Exec=fixture-top", "Terminal=true",
    "Categories=System;Monitor;", "" }, "\n"))
end

--- A folder of empty programs, so a mode finds these names on PATH; what they
--- answer comes from `test.stub_run`.
local paths = 0
function M.path(names)
  paths = paths + 1
  local folder = morf.env("XDG_CACHE_HOME") .. "/launcher-bin-" .. paths
  morf.fs.mkdir(folder, { parents = true })
  for _, name in ipairs(names) do write(folder .. "/" .. name, "#!/bin/sh\n") end
  return folder
end

--- The shell, opened at the launcher. Options: `size`, `env`, `settings` (a table
--- written to the settings file), `style`, `path` (program names).
function M.load(options)
  options = options or {}
  M.apps()
  for _, program in ipairs { "systemctl", "loginctl" } do test.stub_run(program, { code = 0 }) end
  test.stub_run("task", { code = 0, stdout = "[]" })
  local settings = morf.env("XDG_STATE_HOME") .. "/launcher-settings-" .. tostring(morf.time.now_ms()) .. ".json"
  morf.fs.write(settings, morf.json.encode(options.settings or { theme = { source = "#ffb0ca" } }), { parents = true })
  local env = { EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1", EVA_FAKE_OSD = "1", EVA_STYLE = options.style or "material",
    LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"), EVA_SETTINGS = settings }
  if options.path then env.PATH = M.path(options.path) end
  for key, value in pairs(options.env or {}) do env[key] = value end
  test.load("../shell/init.lua", { source = (options.prelude or "") .. M.SHELL .. (options.source_extra or ""),
    size = options.size or { 1920, 1080 }, env = env })
  test.settle(1500)
  test.ipc("launcher", "open")
  test.settle(800)
  return env
end

--- Sets the query and lets the search run.
function M.search(text, ms)
  test.ipc("q", text)
  test.advance(ms or 300)
end

--- The names of the rows listed, in order.
function M.names()
  local out = {}
  for i, r in ipairs(test.ipc("rows")) do out[i] = r.name end
  return out
end

--- The row named `name`, or nil.
function M.row(name)
  for _, r in ipairs(test.ipc("rows")) do
    if r.name == name then return r end
  end
end

--- Whether `text` shows up in an info line.
function M.logged(text)
  for _, line in ipairs(test.logs("info")) do
    if line.message:find(text, 1, true) then return true end
  end
  return false
end

return M
