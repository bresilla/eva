-- Hot corners: the pointer resting in a corner of the screen does what that
-- corner is set to, if the key it is guarded by is held. Not under a finger.
local morf = require("morf")
local ui = require("morf.ui")
local config = require("config")
local M = {}

M.CORNERS = {
  { key = "top_left", name = "Top left" }, { key = "top_right", name = "Top right" },
  { key = "bottom_left", name = "Bottom left" }, { key = "bottom_right", name = "Bottom right" },
}

-- What a corner can do: `verb` is an IPC verb, with `args`.
M.ACTIONS = {
  { key = "none", name = "Nothing" },
  { key = "overview", name = "Overview", verb = "overview", args = { "toggle" } },
  { key = "launcher", name = "Launcher", verb = "launcher", args = { "toggle" } },
  { key = "dashboard", name = "Dashboard", verb = "dashboard", args = { "toggle" } },
  { key = "settings", name = "Quick settings", verb = "utilities", args = { "toggle" } },
  { key = "notifications", name = "Notifications", verb = "sidebar", args = { "toggle", "notifications" } },
  { key = "desktop", name = "Show desktop", verb = "show_desktop", args = {} },
  { key = "session", name = "Session menu", verb = "session", args = { "toggle" } },
  { key = "lock", name = "Lock", verb = "lock_now", args = {} },
  { key = "command", name = "Run a command" },
}
M.GUARDS = { { "", "No key" }, { "ctrl", "Ctrl" }, { "alt", "Alt" }, { "shift", "Shift" }, { "super", "Super" } }

local SIZE = 6
local BY = {}
for _, action in ipairs(M.ACTIONS) do BY[action.key] = action end

local ipc

local function setting(corner, field) return config.get("windows.corners." .. corner .. "." .. field) end
function M.action(corner) return setting(corner, "action") or "none" end
function M.guard(corner) return setting(corner, "guard") or "" end
function M.hold() return tonumber(config.get("windows.corners.hold")) or 150 end
function M.set_action(corner, key) config.set("windows.corners." .. corner .. ".action", key) end
function M.set_guard(corner, key) config.set("windows.corners." .. corner .. ".guard", key) end

local function next_of(list, now, key)
  for i, item in ipairs(list) do
    if key(item) == now then return key(list[i % #list + 1]) end
  end
  return key(list[1])
end
function M.next_action(corner)
  M.set_action(corner, next_of(M.ACTIONS, M.action(corner), function(a) return a.key end))
end
function M.next_guard(corner)
  M.set_guard(corner, next_of(M.GUARDS, M.guard(corner), function(g) return g[1] end))
end
function M.action_name(corner) return (BY[M.action(corner)] or BY.none).name end
function M.guard_name(corner)
  for _, g in ipairs(M.GUARDS) do if g[1] == M.guard(corner) then return g[2] end end
  return "No key"
end

--- Whether what is held meets the corner's guard.
function M.guarded(corner, modifiers)
  local want = M.guard(corner)
  return want == "" or (modifiers or ""):find(want, 1, true) ~= nil
end

--- Does what `corner` is set to.
function M.fire(corner)
  local key = M.action(corner)
  local action = BY[key]
  if key == "none" or not action then return false end
  if key == "command" then
    local words = setting(corner, "command")
    if type(words) ~= "table" or #words == 0 then return false end
    if require("windows_model").held_back() then
      morf.log("info", "eva: hot corner (dry run): " .. table.concat(words, " "))
      return true
    end
    morf.process.run(words, {}, function() end)
    return true
  end
  if ipc and ipc[action.verb] then ipc[action.verb](table.unpack(action.args)) return true end
  return false
end

function M.attach(table_of_verbs) ipc = table_of_verbs end

--- The corners' areas, to lie over the whole screen.
function M.build()
  local children = { id = "hot-corners", anchors = { fill = true }, z = 300,
    visible = function() return not require("responsive").touch() end }
  for _, corner in ipairs(M.CORNERS) do
    local key = corner.key
    local waiting, held, spent = nil, "", false
    local anchors = { [key:match("^(%a+)_")] = true, [key:match("_(%a+)$")] = true }
    local area
    area = ui.MouseArea { id = "hot-corner-" .. key, anchors = anchors, width = SIZE, height = SIZE,
      visible = function() return M.action(key) ~= "none" end,
      on_position_changed = function(_, _, _, _, _, _, modifiers) held = modifiers or "" end,
      on_pressed = function(_, _, _, _, _, modifiers) held = modifiers or held end }
    morf.effect("eva.hot_corner." .. key, function()
      if not area.contains_pointer then
        if waiting then waiting:cancel() waiting = nil end
        spent = false
        return
      end
      if waiting or spent then return end
      waiting = morf.time.timer(M.hold(), function()
        waiting = nil
        spent = true
        local snap = package.loaded.snap
        if M.guarded(key, held) and not (snap and snap.busy:get()) then M.fire(key) end
      end, false)
    end, { owner = area })
    children[#children + 1] = area
  end
  return ui.Item(children)
end

return M
