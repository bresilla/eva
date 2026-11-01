-- eva's lock screen, in two stages -- a phone's, and a desk's too.
--
-- At rest it is a thing to look at: the time, large, the date and the
-- weather above it, whatever is playing as a row with its controls, and a
-- small swell on the frame's bottom edge saying where the way in is. An
-- upward swipe or drag reveals the unlock sheet -- one
-- liquid surface with the frame -- carrying the account in its cookie, the
-- pill for the password and whatever PAM has to say (a face being looked
-- for, a finger). A physical keyboard can reveal it by typing, keeping the
-- first character, or with Enter. Escape on
-- an empty field, or a while with nothing typed, and the sheet sinks back.
-- On a phone (a screen taller than wide, or no keyboard attached) the sheet
-- carries the on-screen keyboard. The right password and all of it sinks
-- into the edge, the frame opens, and the desk is there again.
--
--   morf -c eva/lock               the lock, held under ext-session-lock
--   morf -c eva/lock -- window     the same, in a window, holding nothing
--
-- Its own file: nothing here reaches into the shell's folder. What the lock
-- and the greeter share is in the library -- lib.auth (PAM and greetd),
-- lib.accounts, lib.lule and lib.material for the colours, lib.osk.

local morf = require("morf")
local accounts = require("lib.services.accounts")
local auth = require("lib.shell.auth")
local reveal = require("themes.reveal")
require("themes.ui_scale").apply()

local HELD = morf.operands[1] ~= "window"
-- Why this lock was asked for, and what it may show and do because of it.
local lock_settings = require("models.lock_settings")
local REASON = require("models.lock_reason").take()
local prefs = lock_settings.load()
if REASON == "lockdown" then lock_settings.lockdown(prefs) end
-- A fingerprint stack to listen on (helpers/pam/readers.sh), said in the hint.
local FINGER = prefs.readers and morf.fs.exists("/etc/pam.d/eva-lock-finger")
-- `-- window preview`: never asks PAM -- any password but "wrong" opens it.
-- For pictures and tests: a lock that asked PAM and was killed mid-way
-- would count as a failed login.
local PREVIEW = not HELD and morf.operands[2] == "preview"

local screen = morf.screens[1]
local W = (screen and screen.width) or 1920
local H = (screen and screen.height) or 1080
-- Everything in proportion to a 1080p screen.
-- A phone's design is the upright 1080 x 1920 one.
local s = require("themes.auth_metrics")(W, H, true)

morf.surface.width = W
morf.surface.height = H
morf.surface.anchors = { top = true, left = true, right = true, bottom = true }
morf.surface.layer = "overlay"
morf.surface.keyboard_focus = "exclusive"
-- Colours mix as the shell's do: a translucent tint is as faint as it says.
morf.surface.blend = "srgb"
morf.surface.namespace = "eva-lock"
morf.surface.session_lock = HELD

-- logind's lock hint follows the held lock, so services that read the
-- session's LockedHint see it: set once the lock is asked for, cleared when
-- it ends or the compositor refuses it.
local function locked_hint(value)
  local dbus = morf.dbus
  if not dbus then return end
  local ok, session = pcall(dbus.proxy, "system", "org.freedesktop.login1",
    "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session")
  if ok and session then pcall(session.call, session, "SetLockedHint", value) end
end
if HELD then
  morf.lock.on_state(function(state)
    locked_hint(state == "pending" or state == "locked")
  end)
end

-- Visual design is selected independently from the wallpaper's palette.
local visual = require("themes").current
local C, palette = require("themes.auth_palette")("lock")
local FONT, ICONS = visual.tokens.auth_font or visual.tokens.font, visual.tokens.icon_font
local text, icon = require("themes.typography")(visual.tokens, C, s)
local function WALLPAPER()
  local tool=palette:get()
  local chosen=prefs.wallpaper~="" and prefs.wallpaper or nil
  local path=morf.env("EVA_WALLPAPER") or chosen or (tool and tool.wallpaper) or ""
  return path~="" and morf.fs.exists(path) and path or ""
end

-- ------------------------------------------------------------------ state --

local me = accounts.me() or { name = "", label = "", initial = "?" }
local MAX_DOTS = 18
local password = require("models.password").new("lock", MAX_DOTS)
local typed = password.typed
local busy = morf.signal("lock.busy", false)
local message = morf.signal("lock.message", "")
local bad = morf.signal("lock.bad", false)
local shake = morf.signal("lock.shake", 0)
-- "closed" (coming in), "rest", "sheet" (the way in is open), "opening"
-- (unlocked: all of it going away).
local stage = morf.signal("lock.stage", "closed")
-- How far a swipe has pulled the sheet up, 0..1, while it is being drawn.
local pull = morf.signal("lock.pull", 0)

local function say(words, wrong)
  message:set(words or "")
  bad:set(wrong == true)
end
local clear = password.clear

-- What the lock keeps while it stands. No window after an idle lock on a phone:
-- a pocket presses keys.
local phone_screen = require("themes.phone_wake")
local keyboard = require("models.keyboard_state").new("lock")
local tries = require("models.lock_attempts").new(prefs.attempts)
local guard = (REASON == "idle" and prefs.grace_seconds > 0) and require("models.logind").guard() or nil
local grace = require("models.lock_grace").new {
  seconds = prefs.grace_seconds, reason = REASON, guard = guard, phone = phone_screen.present(),
}
if prefs.force_layout ~= "" then morf.time.timer(0, function() keyboard.force(prefs.force_layout) end, false) end

-- A shortcut waiting on the password: its id, handed to the shell once the
-- door is open. Only the shell opens anything.
local waiting
local function forget_waiting() waiting = nil end

-- The screen leaves the wallpaper, and the shell under it comes in as it did at
-- login.
local door
local function lift()
  stage:set("opening")
  say("")
  keyboard.restore()
  phone_screen.allow_ambient(false)
  if HELD and morf.env("EVA_DRY_RUN") ~= "1" then
    morf.process.run({ "morf", "ipc", "call", "reveal" }, { timeout_ms = 2000, max_output = 256 }, function() end)
    if waiting then
      morf.process.run({ "morf", "ipc", "call", "lock_shortcut", waiting },
        { timeout_ms = 2000, max_output = 256 }, function() end)
    end
  end
  morf.time.timer(reveal.LEAVE, function()
    if HELD then morf.surface.session_lock = false else morf.quit() end
  end, false)
end
local handlers = {
  user = me.name,
  listen = false,
  tries = prefs.reader_tries,
  on_busy = function(b) busy:set(b) end,
  on_info = function(words, wrong) if not busy:get() then say(words, wrong) end end,
  on_failed = function(why)
    grace.revoke("wrong password")
    tries.failed()
    say(why ~= "" and why or "Wrong password", true)
    clear()
    shake:set(1)
    morf.time.timer(70, function() shake:set(0) end, false)
  end,
  on_open = lift,
}
if not prefs.readers then handlers.reader = false end
if PREVIEW then
  door = {
    submit = function(_, pw)
      handlers.on_busy(true)
      morf.time.timer(700, function()
        handlers.on_busy(false)
        if pw == "wrong" then handlers.on_failed("Wrong password") else lift() end
      end, false)
    end,
    listen = function() end, stop = function() end,
  }
else
  door = auth.lock(handlers)
end

-- Back to rest after a while with the sheet up and nothing typed.
local idle
local function poke()
  if idle then idle:cancel() end
  idle = morf.time.timer(15000, function()
    idle = nil
    if stage:get() == "sheet" and typed:get() == 0 and not busy:get() then
      stage:set("rest")
      waiting = nil
      say("")
    end
  end, false)
end

local function open_sheet()
  if stage:get() ~= "rest" then return end
  stage:set("sheet")
  pull:set(0)
  poke()
end

-- The one opening without the password: a key in the window after an idle lock.
local function take_grace()
  if not grace.take() then return false end
  if door.finish then door:finish() else lift() end
  return true
end

local function submit()
  if busy:get() or stage:get() ~= "sheet" then return end
  if not tries.allowed() then return end
  if password.empty() then
    say("Type your password", false)
    return
  end
  say("")
  door:submit(password.take())
end

-- The emergency card, over the lock. It opens nothing.
local card_open = morf.signal("lock.emergency.open", false)
local card_said = morf.signal("lock.emergency.said", "")
local card_timer
local function close_card()
  if card_timer then card_timer:cancel() card_timer = nil end
  card_open:set(false)
  card_said:set("")
end
local function open_card()
  card_open:set(true)
  if card_timer then card_timer:cancel() end
  card_timer = morf.time.timer(30000, close_card, false)
end

local function type_text(t)
  if not password.add(t) then return end
  if bad:get() then say("") end
  poke()
end
local function backspace()
  password.erase()
  poke()
end
local function escape()
  if card_open:get() then close_card() return end
  if password.empty() then
    -- Looked at in a window, it holds nothing: Escape at rest is the way
    -- out, in case the door will not open.
    if stage:get() == "rest" and not HELD then morf.quit() return end
    stage:set("rest")
    forget_waiting()
    say("")
  else
    clear()
    say("")
  end
end

-- --------------------------------------------------------------- the time --

local function now(format) return morf.time.format(format, morf.time.now()) end
local CLOCK = prefs.clock.twelve_hour and "%-I:%M" or "%H:%M"
local clock = morf.signal("lock.clock", now(CLOCK))
local day = morf.signal("lock.day", now("%A, %-d %B"))
morf.time.timer(1000, function()
  clock:set(now(CLOCK))
  day:set(now("%A, %-d %B"))
end, true)

-- The screen the lock is used on; the others show the frame, the desk and
-- the time, and nothing to press. Use the monitor focused when locking,
-- just like desktop authentication prompts; the first output is a fallback.
local main_output = morf.signal("lock.main", (morf.screens and morf.screens[1] and morf.screens[1].name) or "")
pcall(function()
  require("lib.compositor.hyprland").json("monitors", function(list)
    for _, m in ipairs(type(list) == "table" and list or {}) do
      if m.focused and m.name then main_output:set(m.name) return end
    end
  end)
end)

-- --------------------------------------------------------------- a screen --

-- One tree per screen, at that screen's size: a held lock covers every
-- output, and a laptop's panel and a 4K monitor each get their own layout.
-- What they share -- the password, the stage, the door -- is above.
local function keyboard_attached()
  local ok, value = pcall(function() return require("models.keyboards").attached() end)
  return not ok or value
end
local function key(keysym, typed_text)
        local RETURN, KP_ENTER, BACKSPACE, ESCAPE, F3 = 0xff0d, 0xff8d, 0xff08, 0xff1b, 0xffc0
        local st = stage:get()
        if st ~= "rest" and st ~= "sheet" then return end
        if take_grace() then return end
        -- The light follows the key a moment later.
        morf.time.timer(60, keyboard.look, false)
        if busy:get() then return end
        if keysym == ESCAPE then escape() return end
        if keysym == F3 then keyboard.step() return end
        if card_open:get() then close_card() end
        if st == "rest" then
          -- Touch-only devices still require the upward reveal gesture.
          -- Modifiers and wake keys carry no text and leave the clock alone.
          if not keyboard_attached() then return end
          if keysym == RETURN or keysym == KP_ENTER then open_sheet() return end
          if not typed_text or typed_text == "" or typed_text:byte(1) < 32 then return end
          open_sheet()
        end
        if keysym == RETURN or keysym == KP_ENTER then
          submit()
        elseif keysym == BACKSPACE then
          backspace()
        elseif typed_text and typed_text ~= "" and typed_text:byte(1) >= 32 then
          type_text(typed_text)
        end
      end
local function resting() return stage:get() == "rest" or stage:get() == "sheet" end
local desktop = require("models.lock_desktop").new {
  active = resting,
  primary = function(output) return not HELD or main_output:get() == output end,
}

-- What stands on the lock besides the time.
local parts = {
  prefs = prefs, keyboard = keyboard, grace = grace, tries = tries,
  status = require("models.auth_status").new { active = resting, status = prefs.status },
  notifications = require("models.lock_notifications").reader(prefs),
  emergency = require("models.lock_emergency").new(prefs),
  widgets = require("models.desktop_widgets").for_lock(prefs.widgets),
  power = prefs.power_buttons and require("models.auth_power").new() or nil,
  card_open = card_open, card_said = card_said, open_card = open_card, close_card = close_card,
  take_grace = take_grace,
  shortcuts = require("models.lock_shortcuts").new {
    prefs = prefs,
    media_available = function() return prefs.media and desktop.media_available() end,
    play_pause = function() desktop.play_pause() end,
    run = function(argv) morf.process.run(argv, { timeout_ms = 15000, max_output = 256 }, function() end) end,
    ask = function(id, name)
      waiting = id
      open_sheet()
      say("Unlock to open " .. name, false)
    end,
  },
}

local context = {
  desktop = desktop,
  parts = parts,
  blur = prefs.blur, tint = prefs.tint,
  message = message, bad = bad, clear = clear,
  HELD = HELD,
  main_output = main_output,
  text = text,
  icon = icon,
  C = C,
  WALLPAPER = WALLPAPER,
  stage = stage,
  pull = pull,
  busy = busy,
  say = say,
  submit = submit,
  type_text = type_text,
  backspace = backspace,
  escape = escape,
  clock = clock,
  day = day,
  me = me,
  keyboard_attached = keyboard_attached,
  typed = typed,
  shake = shake,
  MAX_DOTS = MAX_DOTS,
  open_sheet = open_sheet,
  FINGER = FINGER,
  FONT = FONT,
  ICONS = ICONS,
  key = key,
}

local function build(width, height, name)
  local ctx = setmetatable({output_name=name}, {__index=context})
  ctx.s = require("themes.auth_metrics")(width, height, context.keyboard_attached())
  ctx.text, ctx.icon = require("themes.typography")(visual.tokens, C, ctx.s)
  return require(visual.lock)(ctx)(width, height, name)
end

-- Output removal must never leave the only password controls on a dead screen.
morf.effect("lock.outputs", function()
  if morf.window.screens_revision then morf.window.screens_revision() end
  local selected = main_output:get()
  for _, output in ipairs(morf.screens or {}) do
    if output.name == selected then return end
  end
  main_output:set((morf.screens[1] or {}).name or "")
end)

if HELD and morf.lock.surface then
  -- Called for each output, and again for one plugged in while locked.
  morf.lock.surface(function(output)
    return build(tonumber(output.width) or W, tonumber(output.height) or H, tostring(output.name or ""))
  end)
else
  -- Window/preview surfaces resize too. Keep the controller and its private
  -- draft, replacing only the output's presentation when logical size changes.
  local ui=require("morf.ui")
  local root=ui.Rect {id="lock-output",anchors={fill=true},color=function() return C.surface:alpha(1) end}
  local child,built_w,built_h
  morf.effect("lock.geometry",function()
    local width,height=root.layout_width or W,root.layout_height or H
    if width<=0 or height<=0 then width,height=W,H end
    width,height=math.floor(width+.5),math.floor(height+.5)
    if child and width==built_w and height==built_h then return end
    if child then ui.destroy(child,true) end
    built_w,built_h=width,height
    child=build(width,height,screen and screen.name or "")
    ui.reparent(child,root)
  end,{owner=root})
end

-- The readers (helpers/pam): a finger from the start, even at rest -- touch
-- the sensor while the clock shows and the lock goes -- and a face only
-- while the sheet is up, so the camera is not kept on for a glance at the
-- time. With the sheet up they race, and the first yes opens the door.
-- A blanked phone listens for nothing: a finger reader scans the sensor
-- continuously, and the power key wakes the screen to listen again.
morf.effect("lock.listen", function()
  local st = stage:get()
  if phone_screen.asleep() then
    door:stop()
  elseif st == "sheet" then
    door:listen()
  elseif st == "rest" then
    door:stop("eva-lock-face")
    door:stop("eva-lock-reader")
    door:listen("eva-lock-finger")
  else
    door:stop()
  end
end)

-- The window after an idle lock starts when the compositor confirms the lock.
if HELD then morf.lock.on_locked(function() grace.arm() end) end
-- The screen script may leave the panel lit while this lock stands, if chosen.
if prefs.always_on.enabled then phone_screen.allow_ambient(true) end

-- A locked screen goes dark after a while at rest, and comes back with input.
-- The phone's blanking is its own.
if HELD and prefs.blank_after > 0 and not phone_screen.present() and morf.idle then
  local idle_config = require("models.idle_config")
  local dark = false
  morf.idle.subscribe(prefs.blank_after * 1000, function(idle)
    if idle and stage:get() == "rest" and not dark then
      dark = true
      idle_config.dpms("off")
    elseif not idle and dark then
      dark = false
      idle_config.dpms("on")
    end
  end)
end

-- In a window, `morf ipc call stage sheet` puts it where a test wants it;
-- a held lock answers no such thing.
if not HELD then
  morf.ipc.stage = function(to)
    if to == "sheet" then stage:set("rest") open_sheet() elseif to == "rest" then stage:set("rest") end
    if to == "opening" and PREVIEW then stage:set("opening") end
    return stage:get()
  end
  morf.ipc.card = function(how)
    if how == "open" then open_card() else close_card() end
    return card_open:get()
  end
end

-- In: the frame closes and the bud comes up out of it.
morf.time.timer(30, function() stage:set("rest") end, false)
