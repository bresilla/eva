-- What the grid and the Software page ask of lib/services/software.lua: where an
-- app came from, taking it off, putting one on, and what is under way. No nodes.
local morf = require("morf")
local service = require("lib.services.software")

local M = { LABELS = service.LABELS }

-- What is under way, or false: `{ verb, name }`.
M.job = morf.signal("eva.software.job", false)
-- Moves as the list of apps or the Nix profile changes.
M.revision = morf.signal("eva.software.revision", 0)

local scanned = false

--- Reads the Nix profile once, for `source` to name its elements.
function M.scan()
  if scanned then return end
  scanned = true
  service.scan(function() M.revision:set(M.revision:get() + 1) end)
end

M.machine = service.machine

--- Where `row` came from and whether it can go.
function M.source(row) return service.source_of(row) end

local function say(summary, body, bad)
  local notifs = package.loaded.notifs
  if notifs then notifs.push { summary = summary, body = body or "", app = "Software", icon = "system-software-install",
    urgency = bad and 2 or 1 } end
end

local function settled()
  scanned = false
  M.scan()
  require("apps").refresh(true)
  require("lib.shell.launcher.rows").bump()
end

local function run(verb, name, work, past)
  if M.job:get() then
    say("Software is busy", "One change at a time: " .. M.job:get().name .. " is still going", true)
    return false
  end
  M.job:set { verb = verb, name = name }
  work(function(text, why)
    M.job:set(false)
    if text == nil then say("Could not " .. verb .. " " .. name, tostring(why or "It stopped with no reason"), true)
    else say(name .. " " .. past) end
    settled()
  end)
  return true
end

--- Takes the app of `row` off the machine.
function M.uninstall(row)
  return run("remove", row.name or row.id, function(done) service.remove(row, done) end, "removed")
end

--- Puts `item` (`{ backend, id, name }`) on the machine.
function M.install(item)
  return run("install", item.name or item.id, function(done) service.install(item, done) end, "installed")
end

--- Brings a hidden app back to the grid.
function M.show(row)
  require("lib.shell.launcher.pins").set_hidden(row.id, false)
  settled()
  M.revision:set(M.revision:get() + 1)
end

--- The apps of the launcher by where they came from: `{ kind, label, rows }` each,
--- those that can go first.
function M.by_source()
  M.revision:get()
  local groups, order = {}, {}
  for _, row in ipairs(require("apps").installed()) do
    local source = M.source(row)
    if not groups[source.kind] then
      groups[source.kind] = { kind = source.kind, label = source.label, removable = source.removable, why = source.why, rows = {} }
      order[#order + 1] = groups[source.kind]
    end
    groups[source.kind].rows[#groups[source.kind].rows + 1] = { row = row, source = source }
    groups[source.kind].removable = groups[source.kind].removable or source.removable
  end
  table.sort(order, function(a, b)
    if a.removable ~= b.removable then return a.removable end
    return a.label < b.label
  end)
  return order
end

return M
