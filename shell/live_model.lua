-- What is going on right now, for the live pill: a call, a recording, screen
-- sharing, a timer, media. No nodes.
--
-- An activity is `{ key, icon, tone, title, subtitle, short, progress, controls }`.
-- `title`, `subtitle`, `short` (a few characters for the pill) and `progress`
-- (0..1, or nil) are read in bindings. `controls` are `{ id, icon, name, press }`.
--
-- `services.call` is a phone call: `active()`, `name()`, `started()` (a time),
-- `hang_up()`, `toggle_mute()`, `muted()`. `services.alarm.timer()` is a running
-- timer: `{ label, ends }` (a time), or nil; `services.alarm.cancel_timer()` stops it.
local morf = require("morf")
local clock = require("clock_format")
local M = {}

local function services() return require("services") end

-- The sources, most pressing first.
local function catalogue(bar)
  local media = function() return require("media_state") end
  return {
    { key = "call", icon = "call", tone = "ok",
      on = function() local c = services().call return c ~= nil and c.active() == true end,
      title = function() return services().call.name() end,
      subtitle = function() return services().call.muted() and "Muted" or "On a call" end,
      short = function()
        morf.time.clock:get()
        return clock.elapsed(morf.time.now() - services().call.started())
      end,
      controls = function()
        return { { id = "mute", name = "Mute", icon = services().call.muted() and "mic_off" or "mic",
            press = function() services().call.toggle_mute() end },
          { id = "hang-up", name = "Hang up", icon = "call_end", tone = "alert", press = function() services().call.hang_up() end } }
      end },
    { key = "recording", icon = "fiber_manual_record", tone = "alert",
      on = function() return bar.recording() end,
      title = function() return "Recording" end,
      subtitle = function() return "Screen" end,
      short = function() return clock.elapsed(require("capture").elapsed:get()) end,
      controls = function()
        return { { id = "stop", name = "Stop recording", icon = "stop", tone = "alert",
          press = function() require("capture").record() end } }
      end },
    { key = "share", icon = "screen_share", tone = "warn",
      on = function() return bar.privacy.in_use("screen") end,
      title = function() return "Sharing your screen" end,
      subtitle = function()
        local names = {}
        for i, user in ipairs(bar.privacy.users("screen")) do names[i] = user.app end
        return table.concat(names, ", ")
      end,
      short = function() return "Live" end,
      controls = function() return {} end },
    { key = "timer", icon = "timer", tone = "accent",
      on = function()
        local alarm = services().alarm
        return alarm ~= nil and alarm.timer ~= nil and alarm.timer() ~= nil
      end,
      title = function() return services().alarm.timer().label or "Timer" end,
      subtitle = function()
        return "Ends at " .. morf.time.format(clock.pattern(clock.options()), services().alarm.timer().ends)
      end,
      short = function()
        morf.time.clock:get()
        return clock.elapsed(services().alarm.timer().ends - morf.time.now())
      end,
      progress = function()
        morf.time.clock:get()
        local t = services().alarm.timer()
        if not t.total or t.total <= 0 then return nil end
        return math.max(0, math.min(1, 1 - (t.ends - morf.time.now()) / t.total))
      end,
      controls = function()
        return { { id = "cancel", name = "Cancel the timer", icon = "close",
          press = function() services().alarm.cancel_timer() end } }
      end },
    { key = "torch", icon = "flashlight_on", tone = "warn",
      on = function()
        local ok, on = pcall(function()
          local torch = require("quick_hardware").torch()
          return torch.present() and torch.on()
        end)
        return ok and on == true
      end,
      title = function() return "Flashlight" end,
      subtitle = function() return "On" end,
      short = function() return "On" end,
      controls = function()
        return { { id = "off", name = "Turn off", icon = "flashlight_off",
          press = function() require("quick_hardware").torch().set(false) end } }
      end },
    { key = "media", icon = "music_note", tone = "accent",
      on = function() return media().playing() end,
      title = function() return media().field("title")() end,
      subtitle = function() return media().field("artist")() end,
      short = function() return media().field("title")() end,
      progress = media().fraction(function() return true end),
      controls = function()
        local m = media()
        return { { id = "previous", name = "Previous", icon = "skip_previous", press = function() m.control("previous") end },
          { id = "toggle", name = "Pause", icon = m.playing() and "pause" or "play_arrow", press = function() m.control("play_pause") end },
          { id = "next", name = "Next", icon = "skip_next", press = function() m.control("next") end } }
      end },
  }
end

--- The model for the bar model `bar`.
function M.new(bar)
  local sources = catalogue(bar)
  local model = {
    expanded = morf.signal("eva.bar.live.expanded", false),
    -- The key of the activity put first by hand, "" for the most pressing.
    chosen = morf.signal("eva.bar.live.chosen", ""),
  }

  --- The activities going on, the one on show first.
  function model.list()
    local on, first = {}, model.chosen:get()
    for _, source in ipairs(sources) do
      if source.on() then
        if source.key == first then table.insert(on, 1, source) else on[#on + 1] = source end
      end
    end
    return on
  end

  --- The activity in the pill, or nil.
  function model.current() return model.list()[1] end
  --- The one in the bubble beside it, or nil.
  function model.second() return model.list()[2] end
  --- How many there are.
  function model.count() return #model.list() end

  --- The next activity into the pill.
  function model.cycle()
    local list = model.list()
    if #list > 1 then model.chosen:set(list[2].key) end
  end

  function model.toggle() model.expanded:set(not model.expanded:get()) end
  function model.collapse() model.expanded:set(false) end

  --- One line per activity.
  function model.summary()
    local lines = {}
    for i, source in ipairs(model.list()) do lines[i] = source.title() end
    return table.concat(lines, "\n")
  end

  return model
end

return M
