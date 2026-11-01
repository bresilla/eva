-- Saved window layouts: what is open and where, kept by name, put back on
-- request or after login. No nodes.
--
-- A floating window comes back to its exact box; a tiled one to its workspace,
-- where the compositor tiles it. A window already open is moved. One that is not
-- is started from its desktop entry, and placed once it shows; what was in it
-- does not come back. A window with no desktop entry cannot be started, and an
-- app that keeps to one window comes back as one: the report names both.
local morf = require("morf")
local config = require("config")
local windows = require("windows_model")
local lib = require("lib.services.window_layouts")

local M = {}

-- What the last restore did: `{ name, moved, opened, missing, late }`.
M.report = morf.signal("eva.layouts.report", false)
-- How long after starting apps their windows are looked for, in ms.
M.WAITS = { 1500, 4000, 8000 }
-- How long the window list takes to come back.
M.FRESH_MS = 300

function M.list()
  local saved = config.get("windows.layouts")
  return type(saved) == "table" and saved or {}
end

function M.get(name)
  for _, layout in ipairs(M.list()) do if layout.name == name then return layout end end
end

local function known(class)
  local entry = require("apps").entry_for(class)
  return entry ~= nil
end

local function write(list)
  table.sort(list, function(a, b) return a.name < b.name end)
  config.set("windows.layouts", list)
end

-- A window's size, place and floating come by no event: `fn` runs once the list
-- has been asked for again.
local function fresh(fn)
  local hyprland = require("services").hyprland
  if hyprland.refresh then hyprland.refresh() end
  morf.time.timer(M.FRESH_MS, fn, false)
end

--- Saves what is open under `name`, over any of that name. `done(count)` with
--- how many windows, `done(nil, why)` when it cannot.
function M.save(name, done)
  done = done or function() end
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then return done(nil, "A layout needs a name") end
  fresh(function()
    local rows = lib.capture(windows.list(), windows.monitors(), known)
    if #rows == 0 then return done(nil, "No windows are open") end
    local list = {}
    for _, layout in ipairs(M.list()) do
      if layout.name ~= name then list[#list + 1] = layout end
    end
    list[#list + 1] = { name = name, saved = morf.time.now(), windows = rows }
    write(list)
    done(#rows)
  end)
end

function M.remove(name)
  local list = {}
  for _, layout in ipairs(M.list()) do
    if layout.name ~= name then list[#list + 1] = layout end
  end
  write(list)
  if config.get("windows.layout_login") == name then config.set("windows.layout_login", "") end
end

--- The layout restored after login, "" for none.
function M.login() return config.get("windows.layout_login") end
function M.set_login(name) config.set("windows.layout_login", name or "") end

--- Puts one window where a saved row says.
local function place(row, window)
  local steps = windows.steps
  if lib.placed(row, window) then return false end
  local list = steps.to_workspace(row.workspace, false)
  if row.floating then
    for _, step in ipairs(steps.box(row.x, row.y, row.width, row.height)) do list[#list + 1] = step end
  elseif window.floating then
    list[#list + 1] = steps.float(false)[1]
  end
  if row.pinned ~= (window.pinned == true) then list[#list + 1] = steps.pin()[1] end
  windows.run(window.address, list)
  return true
end

--- Sends the workspaces to their screens, where those screens are here.
local function screens(rows)
  local here, done = {}, {}
  for _, m in ipairs(windows.monitors()) do here[m.name] = true end
  local spaces = require("workspaces_model")
  for _, row in ipairs(rows) do
    if row.monitor ~= "" and here[row.monitor] and not done[row.workspace] then
      done[row.workspace] = true
      spaces.to_monitor(row.workspace, row.monitor)
    end
  end
end

local function labels(rows)
  local out = {}
  for _, row in ipairs(rows) do out[#out + 1] = lib.label(row) end
  return out
end

local restoring = 0

--- Moves what is open into `name`, starts what is not and can be, and keeps
--- placing as windows arrive. False with no such layout.
function M.restore(name)
  local layout = M.get(name)
  if not layout then return false end
  local rows = layout.windows or {}
  restoring = restoring + 1
  local turn = restoring
  fresh(function()
    local matched, missing = lib.match(rows, windows.list())
    local moved = 0
    for _, pair in ipairs(matched) do
      if place(pair.saved, pair.window) then moved = moved + 1 end
    end
    screens(rows)
    local started, cannot = {}, {}
    local apps = require("apps")
    for _, row in ipairs(missing) do
      local entry = apps.entry_for(row.class)
      if entry then
        started[#started + 1] = row
        apps.launch(entry.id)
      else
        cannot[#cannot + 1] = row
      end
    end
    M.report:set({ name = name, moved = moved, opened = 0, missing = labels(cannot), late = labels(started) })
    if #started == 0 then return end
    for _, ms in ipairs(M.WAITS) do
      morf.time.timer(ms, function()
        if turn ~= restoring then return end
        fresh(function()
          local arrived, late = lib.match(rows, windows.list())
          for _, pair in ipairs(arrived) do place(pair.saved, pair.window) end
          local still = {}
          for _, row in ipairs(late) do
            if apps.entry_for(row.class) then still[#still + 1] = row end
          end
          M.report:set({ name = name, moved = moved, opened = #started - #still, missing = labels(cannot), late = labels(still) })
        end)
      end, false)
    end
  end)
  return true
end

--- The last restore, in a sentence.
function M.report_text()
  local report = M.report:get()
  if not report then return "" end
  local parts = { ("%s: %d moved, %d reopened"):format(report.name, report.moved, report.opened) }
  if #report.late > 0 then parts[#parts + 1] = "still waiting for " .. table.concat(report.late, ", ") end
  if #report.missing > 0 then parts[#parts + 1] = "no way to start " .. table.concat(report.missing, ", ") end
  return table.concat(parts, "; ")
end

-- Marks this compositor's session as restored: a shell started again within it
-- leaves the windows where they are.
local function first_here()
  local runtime = morf.env("XDG_RUNTIME_DIR")
  local session = morf.env("HYPRLAND_INSTANCE_SIGNATURE") or ""
  if not runtime or session == "" then return true end
  local path = runtime .. "/eva/layout-restored"
  local ok, was = pcall(morf.fs.read, path)
  if ok and was == session then return false end
  morf.fs.write(path, session, { atomic = true, parents = true })
  return true
end

--- Restores the layout chosen for login, once per session, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  local name = M.login()
  if name == "" or not M.get(name) or not require("services").hyprland.available() then return end
  morf.time.timer(3000, function()
    if first_here() then M.restore(name) end
  end, false)
end

return M
