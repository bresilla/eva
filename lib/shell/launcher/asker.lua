-- Answers that take a while, for a search that must not wait for them: a slot
-- per source, each holding one question at a time. A question starts only once
-- the typing has paused, a newer one kills the one before it, and until an
-- answer lands the last answer stands, so the list never flashes empty.
--
--   local ask = asker.new { on_answer = refresh, debounce_ms = 120 }
--   local files, settled = ask("files", term, function(done)
--     return morf.process.run(argv, {}, function(r) done(parse(r)) end)
--   end)
--
-- Answers are kept by question, so going back over what was typed is instant.

local morf = require("morf")

local M = {}

local KEPT = 48

--- A new asker. Options: `on_answer` (called as answers land), `debounce_ms`
--- (120), `ttl_ms` (how long an answer stands; none by default).
function M.new(opts)
  opts = opts or {}
  local wait = opts.debounce_ms or 120
  local slots = {}

  local function slot_of(name)
    local slot = slots[name]
    if not slot then
      slot = { answers = {}, order = {} }
      slots[name] = slot
    end
    return slot
  end

  local function keep(slot, key, value)
    if slot.answers[key] == nil then
      slot.order[#slot.order + 1] = key
      if #slot.order > KEPT then slot.answers[table.remove(slot.order, 1)] = nil end
    end
    slot.answers[key] = { value = value, at = morf.time.now_ms() }
  end

  local function fresh(answer, ttl)
    return answer and (not ttl or morf.time.now_ms() - answer.at < ttl)
  end

  local function stop(slot)
    if slot.timer then slot.timer:cancel() slot.timer = nil end
    if slot.running then
      pcall(function() slot.running:kill() end)
      slot.running = nil
    end
  end

  --- The answer to `key` in slot `name`, and whether it is that question's:
  --- until it lands, the last answer given, and false. `start(done)` asks;
  --- `options.debounce_ms` and `options.ttl_ms` override the asker's.
  local function ask(name, key, start, options)
    options = options or {}
    local slot = slot_of(name)
    local answer = slot.answers[key]
    if fresh(answer, options.ttl_ms or opts.ttl_ms) then
      if slot.wanted ~= key then
        stop(slot)
        slot.wanted = key
      end
      slot.last = answer.value
      return answer.value, true
    end
    -- A stale answer stands until the new one lands, and asks again once.
    if answer and slot.wanted == key and not slot.timer and not slot.running then slot.wanted = nil end
    if slot.wanted ~= key then
      stop(slot)
      slot.wanted = key
      local serial = (slot.serial or 0) + 1
      slot.serial = serial
      slot.timer = morf.time.timer(math.max(1, options.debounce_ms or wait), function()
        slot.timer = nil
        slot.running = start(function(value)
          if slot.serial ~= serial then return end
          slot.running = nil
          slot.last = value
          keep(slot, key, value)
          if opts.on_answer then opts.on_answer(name, key) end
        end)
      end, false)
    end
    return slot.last, false
  end

  local object = setmetatable({}, { __call = function(_, ...) return ask(...) end })

  --- Forgets slot `name`'s answers, or every slot's.
  function object.forget(name)
    if name then
      if slots[name] then stop(slots[name]) slots[name] = nil end
      return
    end
    for key, slot in pairs(slots) do stop(slot) slots[key] = nil end
  end

  return object
end

return M
