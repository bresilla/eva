-- What belongs to a workspace rather than a window: its name, how it tiles,
-- and the scratchpads, Hyprland's special workspaces. The compositor forgets
-- names and layouts when a workspace goes, so they are kept in the settings
-- and given back as each workspace comes.
local morf = require("morf")
local config = require("config")
local services = require("services")
local windows = require("windows_model")
local hyprland = services.hyprland
local M = {}

M.LAYOUTS = { "dwindle", "master", "scrolling", "monocle" }
local KNOWN = {}
for _, layout in ipairs(M.LAYOUTS) do KNOWN[layout] = true end

local function quoted(text) return ("%q"):format(tostring(text)) end
-- Kept in the settings as a list of `{ id, value }`, handed out by id as text.
local function stored(kind)
  local out = {}
  local all = config.get("windows.workspaces." .. kind)
  for _, entry in ipairs(type(all) == "table" and all or {}) do out[tostring(entry.id)] = entry.value end
  return out
end
local function store(kind, id, value)
  local map = stored(kind)
  map[tostring(id)] = value
  local list = {}
  for key, v in pairs(map) do list[#list + 1] = { id = key, value = v } end
  table.sort(list, function(a, b) return a.id < b.id end)
  config.set("windows.workspaces." .. kind, list)
end

-- ------------------------------------------------------------------- names --

--- The name kept for workspace `id`, "" for none.
function M.name(id) return stored("names")[tostring(id)] or "" end

local function send_name(id, name)
  windows.send(("hl.dispatch(hl.dsp.workspace.rename({ workspace = %q, name = %s }))"):format(tostring(id), quoted(name)),
    "renameworkspace", ("%d %s"):format(id, name))
end

--- Names workspace `id`; "" takes the name away.
function M.rename(id, name)
  id = windows.int(id)
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  store("names", id, name ~= "" and name or nil)
  send_name(id, name ~= "" and name or tostring(id))
  return true
end

--- What a workspace is called on screen.
function M.label(id)
  local name = M.name(id)
  if name ~= "" then return name end
  return tostring(id)
end

-- ----------------------------------------------------------------- layouts --

-- The layouts as the compositor last said, by workspace id as text.
M.tiled = morf.signal("eva.workspaces.tiled", {})

local function read_layouts()
  if not hyprland.json then return end
  hyprland.json("j/workspaces", function(rows)
    if type(rows) ~= "table" then return end
    local out = {}
    for _, row in ipairs(rows) do
      if row.tiledLayout then out[tostring(windows.int(row.id))] = row.tiledLayout end
    end
    M.tiled:set(out)
  end)
end

--- How workspace `id` tiles.
function M.layout(id)
  return stored("layouts")[tostring(id)] or M.tiled:get()[tostring(id)] or "dwindle"
end

local function send_layout(id, layout)
  windows.send(("hl.workspace_rule({ workspace = %q, layout = %q })"):format(tostring(id), layout),
    nil, nil)
end

--- Sets how workspace `id` tiles.
function M.set_layout(id, layout)
  if not KNOWN[layout] then return false end
  id = windows.int(id)
  store("layouts", id, layout)
  send_layout(id, layout)
  morf.time.timer(120, read_layouts, false)
  return true
end

--- The next layout for workspace `id`.
function M.cycle_layout(id)
  local now = M.layout(id)
  for i, layout in ipairs(M.LAYOUTS) do
    if layout == now then return M.set_layout(id, M.LAYOUTS[i % #M.LAYOUTS + 1]) end
  end
  return M.set_layout(id, M.LAYOUTS[1])
end

-- Names and layouts go back to the compositor as workspaces come and on a
-- reload, which forgets them.
local function apply_all()
  for id, name in pairs(stored("names")) do send_name(windows.int(id), name) end
  for id, layout in pairs(stored("layouts")) do send_layout(windows.int(id), layout) end
  read_layouts()
end

if hyprland.on then
  local created = function(id)
    id = windows.int(id)
    if not id then return end
    local name, layout = M.name(id), stored("layouts")[tostring(id)]
    if name ~= "" then send_name(id, name) end
    if layout then send_layout(id, layout) end
  end
  hyprland.on("createworkspacev2", created)
  hyprland.on("configreloaded", apply_all)
  hyprland.on("connected", apply_all)
  hyprland.on("workspacev2", read_layouts)
end
morf.time.timer(50, apply_all, false)

-- ------------------------------------------------------------ moving them --

--- Moves workspace `id`, its windows and all, to the screen `monitor`.
function M.to_monitor(id, monitor)
  id = windows.int(id)
  return windows.send(("hl.dispatch(hl.dsp.workspace.move({ workspace = %d, monitor = %q }))"):format(id, monitor),
    "moveworkspacetomonitor", ("%d %s"):format(id, monitor))
end

--- What two screens show changes over: each keeps its own place.
function M.swap_screens(first, second)
  return windows.send(("hl.dispatch(hl.dsp.workspace.swap_monitors({ monitor1 = %q, monitor2 = %q }))"):format(first, second),
    "swapactiveworkspaces", ("%s %s"):format(first, second))
end

--- Carries each workspace in `moves` (id -> id) over to its new number: its
--- windows, its name and how it tiles.
local function renumber(moves)
  local names, layouts = stored("names"), stored("layouts")
  local carried, new_names, new_layouts = {}, {}, {}
  for from, to in pairs(moves) do
    new_names[to], new_layouts[to] = names[tostring(from)], layouts[tostring(from)]
    for _, c in ipairs(windows.on(from)) do carried[#carried + 1] = { address = c.address, to = to } end
  end
  for from in pairs(moves) do
    store("names", from, nil)
    store("layouts", from, nil)
  end
  for to in pairs(new_names) do store("names", to, new_names[to]) end
  for to in pairs(new_layouts) do store("layouts", to, new_layouts[to]) end
  for _, move in ipairs(carried) do windows.to_workspace(move.address, move.to, false) end
  for to in pairs(moves) do
    send_name(to, new_names[to] or tostring(to))
    if new_layouts[to] then send_layout(to, new_layouts[to]) end
  end
  return #carried
end

--- Two workspaces change places, windows, names and layouts together.
function M.swap(first, second)
  first, second = windows.int(first), windows.int(second)
  if first == second then return false end
  renumber({ [first] = second, [second] = first })
  return true
end

--- Workspace `from` goes to number `to`; those between shift one along.
function M.reorder(from, to)
  from, to = windows.int(from), windows.int(to)
  if from == to then return false end
  local moves = { [from] = to }
  local step = from < to and 1 or -1
  for id = from + step, to, step do moves[id] = id - step end
  renumber(moves)
  return true
end

-- -------------------------------------------------------------- scratchpads --

--- The scratchpads: those set up, and any special workspace there is, each
--- `{ name, command, icon, count, shown }`.
function M.scratchpads()
  local out, by = {}, {}
  local set = config.get("windows.scratchpads")
  for _, s in ipairs(type(set) == "table" and set or {}) do
    by[s.name] = { name = s.name, command = s.command or "", icon = s.icon or "web_stories", count = 0 }
    out[#out + 1] = by[s.name]
  end
  for _, w in ipairs(windows.workspaces()) do
    local name = tostring(w.name or ""):match("^special:(.+)$")
    if name then
      if not by[name] then
        by[name] = { name = name, command = "", icon = "web_stories", count = 0 }
        out[#out + 1] = by[name]
      end
      by[name].count = w.windows or 0
    end
  end
  local shown = {}
  for _, m in ipairs(windows.monitors()) do
    local name = tostring(m.special_workspace_name or ""):match("^special:(.+)$")
    if name then shown[name] = true end
  end
  for _, s in ipairs(out) do s.shown = shown[s.name] == true end
  return out
end

--- Shows or hides the scratchpad `name`, starting its program the first time.
function M.toggle_scratch(name)
  for _, s in ipairs(M.scratchpads()) do
    if s.name == name and s.count == 0 and s.command ~= "" then
      windows.send(("hl.exec_cmd(%s, { workspace = %s })"):format(quoted(s.command), quoted("special:" .. name .. " silent")),
        "exec", ("[workspace special:%s silent] %s"):format(name, s.command))
    end
  end
  return windows.send(("hl.dispatch(hl.dsp.workspace.toggle_special(%s))"):format(quoted(name)),
    "togglespecialworkspace", name)
end

--- Sends a window to the scratchpad `name`.
function M.to_scratch(address, name)
  return windows.to_workspace(address, "special:" .. name, false)
end

return M
