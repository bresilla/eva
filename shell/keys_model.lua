-- New chords for the compositor's keys: kept in `keys.overrides` as `{ id, keys
-- }`, sent through lib.compositor.hyprland_config now and after every reload,
-- as every other pushed setting is. An empty chord leaves the row unbound.
--
-- A key eva binds (shell/keybinds.lua) is bound again to its verb. Any other is
-- moved: a Lua-configured Hyprland lists it only as a reference into its own
-- registry, so the plan fetches the function from there and binds it under the
-- new chord. Resetting reloads the configuration, which is the default.
local morf = require("morf")
local config = require("config")
local rows = require("key_rows")
local keybinds = require("keybinds")
local hyprconf = require("lib.compositor.hyprland_config")

local M = {}

M.SUBMAP = "eva-keys-record"
-- How long a recording may hold the compositor's keys back.
M.RECORD_MS = 15000
local MORF = "morf"

--- The chords kept, id -> chord; tracked inside a binding.
function M.overrides()
  local out = {}
  for _, row in ipairs(config.get("keys.overrides") or {}) do out[row.id] = row.keys end
  return out
end

local function store(map)
  local list = {}
  for id, keys in pairs(map) do list[#list + 1] = { id = id, keys = keys } end
  table.sort(list, function(a, b) return a.id < b.id end)
  config.set("keys.overrides", list)
end

--- The capture key, which its own setting keeps.
function M.capture_key() return config.get("capture.hotkey") end

--- Gives `id` the chord, "" for none.
function M.set(id, chord)
  if id == "capture" then config.set("capture.hotkey", chord) return end
  local map = M.overrides()
  map[id] = chord
  store(map)
end

--- Takes `id` back to its default.
function M.reset(id)
  if id == "capture" then config.set("capture.hotkey", "Print") return end
  local map = M.overrides()
  map[id] = nil
  store(map)
end

function M.reset_all() store({}) end

local function bind_named(verb)
  for _, bind in ipairs(keybinds.BINDS) do
    if bind.verb == verb and not bind.quiet then return bind end
  end
end

-- Every way the chord may have been spelled to `hl.bind`: `hl.unbind` goes by
-- the text, ignoring only case and spaces.
local function spellings(chord)
  local mask, key = rows.parts(chord)
  local mods = {}
  for _, modifier in ipairs(rows.MODIFIERS) do
    if mask & modifier[1] ~= 0 then mods[#mods + 1] = modifier[2] end
  end
  local out = {}
  local function walk(picked, left)
    if #left == 0 then
      local words = { table.unpack(picked) }
      words[#words + 1] = key
      out[#out + 1] = table.concat(words, " + ")
      return
    end
    for i, word in ipairs(left) do
      local rest = { table.unpack(left) }
      table.remove(rest, i)
      local next_picked = { table.unpack(picked) }
      next_picked[#next_picked + 1] = word
      walk(next_picked, rest)
    end
  end
  walk({}, mods)
  return out
end

local function unbind_lua(chord)
  local out = {}
  for _, word in ipairs(spellings(chord)) do out[#out + 1] = ("hl.unbind(%q)"):format(word) end
  return table.concat(out, " ")
end

local function conf_chord(chord)
  local mask, key = rows.parts(chord)
  local mods = {}
  for _, modifier in ipairs(rows.MODIFIERS) do
    if mask & modifier[1] ~= 0 then mods[#mods + 1] = modifier[2] end
  end
  return table.concat(mods, " ") .. "," .. key
end

-- The options a bind carries, as `hl.bind` takes them.
local function opts_lua(bind, description)
  local fields = {}
  local names = { locked = "locked", release = "release", ["repeat"] = "repeating", longPress = "long_press",
    non_consuming = "non_consuming" }
  local sorted = {}
  for from in pairs(names) do sorted[#sorted + 1] = from end
  table.sort(sorted)
  for _, from in ipairs(sorted) do
    if bind[from] then fields[#fields + 1] = names[from] .. " = true" end
  end
  if description and description ~= "" then fields[#fields + 1] = ("description = %q"):format(description) end
  return "{ " .. table.concat(fields, ", ") .. " }"
end

--- The live binds of `chord`.
local function at(binds, chord)
  local out, normal = {}, rows.normal(chord)
  for _, bind in ipairs(binds or {}) do
    if tostring(bind.submap or "") == "" and rows.normal(rows.chord(bind)) == normal then out[#out + 1] = bind end
  end
  return out
end

--- What sending `want` over `applied` takes, both id -> chord: the keys that
--- change let go first, so two chords may swap, each new one then bound.
--- `binds` is hyprctl's list. Answers the plan, or nil and why.
function M.plan(want, applied, binds, how)
  local ids = {}
  for id, chord in pairs(want) do
    if applied[id] ~= chord and id:match("^[vb]") then ids[#ids + 1] = id end
  end
  table.sort(ids)
  if #ids == 0 then return {} end
  local lets, chunks, steps = {}, {}, {}
  for _, id in ipairs(ids) do
    local chord = want[id]
    local verb, was = id:match("^verb:(.+)$"), id:match("^bind:(.+)$")
    local eva = verb and bind_named(verb)
    local from = applied[id] or (eva and eva.keys) or was
    if not from or (verb and not eva) then return nil, "no such key: " .. id end
    if chord ~= "" and rows.refused(chord) then return nil, rows.refused(chord) end
    if not chord:match("^[%w_:+ ]*$") then return nil, "bad chord" end
    if how == "lua" then
      lets[#lets + 1] = unbind_lua(from)
      if chord ~= "" then
        if eva then
          local call = ("%s ipc call %s"):format(MORF, verb)
          chunks[#chunks + 1] = ("hl.bind(%q, hl.dsp.exec_cmd(%q), %s)"):format(chord, call, opts_lua({}, eva.label))
        else
          for _, bind in ipairs(at(binds, from)) do
            if bind.dispatcher ~= "__lua" then return nil, "only a Lua-configured key can be moved here" end
            local ref = math.tointeger(tonumber(bind.arg))
            if not ref then return nil, "bad reference" end
            chunks[#chunks + 1] = ("hl.bind(%q, registry[%d], %s)"):format(chord, ref, opts_lua(bind, bind.description))
          end
        end
      end
    else
      steps[#steps + 1] = { keyword = "unbind", value = conf_chord(from) }
      if chord ~= "" then
        if eva then
          steps[#steps + 1] = { keyword = "bind", value = conf_chord(chord) .. ",exec," .. MORF .. " ipc call " .. verb }
        else
          for _, bind in ipairs(at(binds, from)) do
            steps[#steps + 1] = { keyword = "bind", value = ("%s,%s,%s"):format(conf_chord(chord), bind.dispatcher, bind.arg or "") }
          end
        end
      end
    end
  end
  if how ~= "lua" then return steps end
  local chunk = table.concat(lets, " ")
  if #chunks > 0 then chunk = "local registry = debug.getregistry() " .. chunk .. " " .. table.concat(chunks, " ") end
  return { { eval = chunk } }
end

--- The steps holding the compositor's keys back while a chord is recorded: its
--- bindings would take the chord before the window hears it. Escape and a
--- timer each let go, should the window never come back.
function M.record_steps(on, how)
  if how ~= "lua" then
    return { { dispatch = "submap", arg = on and M.SUBMAP or "reset" } }
  end
  if not on then return { { eval = 'hl.dispatch(hl.dsp.submap("reset"))' } } end
  return { { eval = ('hl.define_submap(%q, function() hl.bind("escape", hl.dsp.submap("reset"), { non_consuming = true }) end) '
    .. 'hl.dispatch(hl.dsp.submap(%q)) '
    .. 'hl.timer(function() hl.dispatch(hl.dsp.submap("reset")) end, { timeout = %d, type = "oneshot" })')
    :format(M.SUBMAP, M.SUBMAP, M.RECORD_MS) } }
end

--- Holds the compositor's keys back, or lets them go.
function M.hold_keys(on, done)
  hyprconf.apply(function(how) return M.record_steps(on, how) end, done)
end

local applied = {}

local function binds_then(fn)
  local hyprland = require("input_model").hyprland()
  if not hyprland.binds then return fn({}) end
  hyprland.binds(function(list) fn(type(list) == "table" and list or {}) end)
end

--- Sends what changed; a chord taken back reloads, which is the default.
local function push()
  local want = M.overrides()
  if next(want) == nil and next(applied) == nil then return end
  for id in pairs(applied) do
    if want[id] == nil then
      applied = {}
      hyprconf.reload()
      return
    end
  end
  binds_then(function(binds)
    hyprconf.apply(function(how)
      local plan, why = M.plan(want, applied, binds, how)
      if plan then applied = want end
      return plan, why
    end)
  end)
end

--- Whether there is a compositor to send a chord to.
function M.available() return require("input_model").available() end

--- Follows the kept chords, on the primary output.
function M.start()
  if morf.window.primary and not morf.window.primary() then return end
  if not M.available() then return end
  hyprconf.on_reload(function()
    applied = {}
    push()
  end)
  morf.effect("eva.keys.overrides", function()
    M.overrides()
    morf.time.timer(1, push, false)
  end)
end

return M
