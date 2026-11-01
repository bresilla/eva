-- eva-keys: the live bindings of the compositor and the shell's own, as one
-- searchable list, and a new chord for any row. No nodes.
local morf = require("morf")
local keybinds = require("key_rows")
local keys = require("keys_model")

local M = {
  rows = morf.signal("keys.rows", {}),
  query = morf.signal("keys.query", ""),
  message = morf.signal("keys.message", ""),
  -- The row a chord is being pressed for, "" for none.
  recording = morf.signal("keys.recording", ""),
  -- A chord that collides: `{ id, keys, clashes }`, or false.
  pending = morf.signal("keys.pending", false),
}

M.MODIFIERS = keybinds.MODIFIERS
M.chord = keybinds.chord
M.action = keybinds.action
M.merge = keybinds.merge

--- Whether a row may take a new chord: there is a compositor to send it to and
--- a keyboard to press it on.
function M.can_edit() return keys.available() and not require("responsive").phone() end

--- Reads the live bindings.
function M.load()
  morf.process.run({ "hyprctl", "binds", "-j" }, {}, function(result)
    local binds = {}
    if result and result.ok then
      local ok, list = pcall(morf.json.decode, result.stdout or "")
      if ok and type(list) == "table" then binds = list end
    else
      M.message:set("The compositor's bindings cannot be read here")
    end
    M.rows:set(M.merge(binds, keys.overrides(), keys.capture_key()))
  end)
end

-- The shell sends a change as it hears of it: the list follows a moment later.
local function settle()
  morf.time.timer(500, M.load, false)
  morf.time.timer(1500, M.load, false)
end

--- The rows matching the query, every word of it, in either column.
function M.found()
  local out = {}
  local words = {}
  for word in M.query:get():lower():gmatch("%S+") do words[#words + 1] = word end
  for _, row in ipairs(M.rows:get()) do
    local text = (row.keys .. " " .. row.what .. " " .. row.group):lower()
    local all = true
    for _, word in ipairs(words) do all = all and text:find(word, 1, true) ~= nil end
    if all then out[#out + 1] = row end
  end
  return out
end

local function row_of(id)
  for _, row in ipairs(M.rows:get()) do if row.id == id then return row end end
end

local function assign(id, chord)
  keys.set(id, chord)
  M.message:set("")
  settle()
  return true
end

--- Takes a chord for `id`: at once when nothing else has it, else it waits to
--- be confirmed. False when it cannot be had.
function M.offer(id, chord)
  local refused = keybinds.refused(chord)
  if refused then M.message:set(refused) return false end
  local clashes = keybinds.conflicts(M.rows:get(), chord, id)
  if #clashes == 0 then return assign(id, chord) end
  M.pending:set({ id = id, keys = chord, clashes = clashes })
  return true
end

--- Starts listening for a new chord for `id`.
function M.record(id)
  local row = row_of(id)
  if not (row and row.editable and M.can_edit()) then return false end
  M.pending:set(false)
  M.message:set("")
  M.recording:set(id)
  keys.hold_keys(true)
  return true
end

--- Stops listening, leaving the row as it was.
function M.stop()
  if M.recording:get() == "" then return end
  M.recording:set("")
  keys.hold_keys(false)
end

--- A key press while listening: the chord, or Escape to give up.
function M.take(_, text, mods, repeating, name)
  local id = M.recording:get()
  if id == "" then return false end
  if repeating then return true end
  if name == "Escape" then M.stop() return true end
  local chord = keybinds.recorded(name, text, mods)
  if chord then
    M.stop()
    M.offer(id, chord)
  end
  return true
end

--- Gives the waiting chord to its row: those it collides with let go of it.
function M.confirm()
  local waiting = M.pending:get()
  if not waiting then return false end
  M.pending:set(false)
  for _, row in ipairs(waiting.clashes) do
    if row.editable then keys.set(row.id, "") end
  end
  return assign(waiting.id, waiting.keys)
end

function M.cancel() M.pending:set(false) end

--- Takes `id` back to its default.
function M.reset(id)
  keys.reset(id)
  M.message:set("")
  settle()
end

function M.reset_all()
  keys.reset_all()
  settle()
end

--- What the waiting chord collides with, in words.
function M.clash_text()
  local waiting = M.pending:get()
  if not waiting then return "" end
  local names = {}
  for _, row in ipairs(waiting.clashes) do names[#names + 1] = row.what end
  return waiting.keys .. " already does: " .. table.concat(names, ", ")
end

return M
