-- One board of lib.shell.osk dressed for the shell through the seams osk gives:
-- `action` builds each key and places it, `key_face` draws it and `send` hears
-- it. Over those go a language's letters, long-press accents, split halves, a
-- buzz, shift held for caps lock, the space bar as a trackpad.
--
-- osk's alternates and its preview are private to it, and move only through
-- signals it makes in osk.new: `capture` keeps those as they are made.
local morf = require("morf")
local model = require("keyboard_model")
local layouts = require("keyboard_layouts")

local M = {}

local HOLD = 380
-- How far a finger moves on the space bar for one step of the cursor.
M.STEP = 12

--- Runs `build`, handing back what it made and the signals it made, by name.
function M.capture(build)
  local make, seen = morf.signal, {}
  morf.signal = function(name, value)
    local signal = make(name, value)
    seen[name] = signal
    return signal
  end
  local ok, made = pcall(build)
  morf.signal = make
  if not ok then error(made, 0) end
  return made, seen
end

local function parse(id) return id:match("^.-%.key%.([^.]+)%.([^.]+)%.(.+)$") end

--- `spec`: `action` and `face` (the theme's), `active()`, `layout`, `width`,
--- `gap`, `key_height`, `number_row`, `split` (how far apart the halves
--- stand, 0 for none), `send(event)`, `pressed(name)`, `move(key, mods)`.
function M.new(spec)
  local B = {}
  local W, GAP, KH, layout = spec.width, spec.gap, spec.key_height, spec.layout
  local unit = (W - 11 * GAP) / 10
  local shape = { width = W, gap = GAP, unit = unit, key_height = KH }
  local plan = layouts.plan(layout, shape, spec.number_row)
  local short_plan = layouts.plan(layout, shape, false, true)
  local signals, keys = {}, nil
  local current, written, picking
  local track

  B.numbers = (plan and plan.numbers) or spec.number_row
  B.lift = plan and plan.lift * (KH + GAP) or 0

  local function plan_of(mode, page)
    if page ~= "letters" then return nil end
    if mode == "full" or mode == "fulln" then return plan end
    if mode == "letters" then return short_plan end
  end

  local function spread(name, x, w)
    if spec.split <= 0 then return x, w end
    if name == "space" then return x, w + spec.split end
    if x + w / 2 < W / 2 then return x, w end
    return x + spec.split, w
  end

  -- Where a key stands, and what it carries: osk's place unless planned.
  local function place(mode, page, name, x, y, w)
    local p = plan_of(mode, page)
    local spot = p and p.keys[name]
    if spot and spot.hidden then return x, y, w, spot end
    if spot then x, y, w = spot.x or x, spot.row and spot.row * (KH + GAP) or y, spot.w or w
    elseif p and p.lift > 0 then y = y - p.lift * (KH + GAP) end
    x, w = spread(name, x, w)
    return x, y, w, spot
  end

  local function shifted() return keys and keys.shift:get() ~= "off" end
  local function cased(text)
    if shifted() then return layouts.upper(layout, text) end
    return text
  end
  local function comma() return model.intent().comma end

  --- The theme's key face, carrying the language's letters.
  function B.face(key)
    local mode, page, name = parse(key.id)
    if not name then return spec.face(key) end
    local _, _, w, spot = place(mode, page, name, 0, 0, key.width)
    key.width = w
    if spot and spot.char then
      local char = spot.char
      key.label = function() return cased(char) end
      local own = layouts.alternates(layout, char, {})[1]
      if layout.alts and layout.alts[char] then key.hint = own end
    elseif name == "," and page == "letters" then
      local label = key.label
      key.label = function() return comma() or label() end
    end
    local trackpad = model.trackpad
    local face = spec.face(key)
    if spec.fade_on_trackpad ~= false and key.kind == "char" then
      face.opacity = function() return trackpad:get() and 0.35 or 1 end
    end
    return face
  end

  local function start_track(sx, sy) track = { x = sx, y = sy, on = false } end
  local function follow_track(sx, sy)
    if not track then return end
    local dx, dy = sx - track.x, sy - track.y
    if not track.on then
      if math.abs(dx) < M.STEP * 1.5 and math.abs(dy) < M.STEP * 2 then return end
      track.on = true
      model.trackpad:set(true)
    end
    local mods = shifted() and { shift = true } or nil
    while math.abs(dx) >= M.STEP do
      spec.move(dx > 0 and "right" or "left", mods)
      track.x = track.x + (dx > 0 and M.STEP or -M.STEP)
      dx = sx - track.x
    end
    while math.abs(dy) >= M.STEP * 2 do
      spec.move(dy > 0 and "down" or "up", mods)
      track.y = track.y + (dy > 0 and M.STEP * 2 or -M.STEP * 2)
      dy = sy - track.y
    end
  end
  local function end_track()
    track = nil
    if model.trackpad:get() then model.trackpad:set(false) end
  end

  --- The theme's key target, placed and listening.
  function B.action(props)
    local mode, page, name = parse(props.id)
    if not name then return spec.action(props) end
    local from_x = props.x
    local x, y, w, spot = place(mode, page, name, from_x, props.y - GAP, props.width)
    props.x, props.y, props.width = x, y + GAP, w
    if spot and spot.hidden then props.visible = false end
    local press, drag, release = props.on_pressed, props.on_dragged, props.on_released
    local lock_timer, locked = nil, false

    local function offer()
      local up = signals.preview
      if not up or not up.on:get() then return end
      up.x:set(x) up.y:set(y) up.w:set(w)
      if spot and spot.char then up.text:set(cased(spot.char))
      elseif name == "," and comma() then up.text:set(comma()) end
    end

    props.on_pressed = function(sx, sy, ...)
      if spec.active() then
        spec.pressed(name)
        current = { spot = spot, name = name, x = x, y = y, w = w }
        written, picking = nil, false
      end
      press(sx, sy, ...)
      if not spec.active() then return end
      offer()
      if name == "space" then start_track(sx, sy) end
      if name == "shift" then
        locked = false
        lock_timer = morf.time.timer(HOLD, function()
          lock_timer, locked = nil, true
          keys.shift:set("lock")
          require("haptics").fire("long")
        end, false)
      end
    end
    props.on_dragged = function(sx, sy, dx, dy, lx, ly, mods)
      if name == "space" then follow_track(sx, sy) end
      return drag(sx, sy, dx, dy, (lx or 0) + x - from_x, ly, mods)
    end
    props.on_released = function(...)
      if lock_timer then lock_timer:cancel() lock_timer = nil end
      picking = signals.alternates ~= nil and #signals.alternates.list:get() > 0
      release(...)
      picking = false
      current = nil
      if name == "space" then end_track() end
      if locked then
        locked = false
        keys.shift:set("lock")
      end
    end
    return spec.action(props)
  end

  --- What osk says was struck, in the language's letters.
  function B.send(event)
    if track and track.on and event.text == " " then return end
    local text = event.text
    if text and current and not picking then
      local spot = current.spot
      if spot and spot.char then
        event.text = cased(spot.char)
      elseif current.name == "," and text == "," and comma() then
        event.text = comma()
      end
    end
    spec.send(event)
  end

  local function same(a, b)
    if not b or #a ~= #b then return false end
    for i, value in ipairs(a) do if value ~= b[i] then return false end end
    return true
  end

  -- What osk offered on a long press, in the language's letters and its case.
  local function offers(list)
    local spot = current.spot
    local out = {}
    if spot and spot.char then
      local kept = {}
      for _, value in ipairs(list) do
        if not value:match("^%a$") and not value:find("[\128-\255]") then kept[#kept + 1] = value end
      end
      out = layouts.alternates(layout, spot.char, kept)
    else
      for i, value in ipairs(list) do out[i] = value end
    end
    if shifted() then for i, value in ipairs(out) do out[i] = layouts.upper(layout, value) end end
    return out
  end

  --- Takes in what osk.new made and the signals it made.
  function B.adopt(board, seen, prefix)
    keys = board
    local function named(name) return seen[prefix .. "." .. name] end
    signals.preview = { on = named("preview"), x = named("preview.x"), y = named("preview.y"),
      w = named("preview.w"), text = named("preview.text") }
    signals.alternates = { list = named("alts"), x = named("alts.x"), y = named("alts.y") }
    local alternates = signals.alternates
    local cell = math.floor(KH * 0.9)
    morf.effect(prefix .. ".offers", function()
      local list = alternates.list:get()
      if #list == 0 or not current or same(list, written) then return end
      local mine = offers(list)
      if #mine == 0 then mine = list end
      written = mine
      alternates.list:set(mine)
      alternates.y:set(current.y)
      local reach = W + spec.split
      alternates.x:set(math.max(0, math.min(reach - #mine * cell, current.x + current.w / 2 - cell / 2)))
      require("haptics").fire("long")
    end, { owner = board.node })
  end

  --- Ends whatever a cancelled press left running.
  function B.cancel()
    current, written, picking = nil, nil, false
    end_track()
  end

  return B
end

return M
