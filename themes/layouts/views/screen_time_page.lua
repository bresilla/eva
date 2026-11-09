-- The Screen time page: what each app has had, the limits, downtime and bedtime,
-- and one page on, an app's own limit. In the page template. `model` is
-- shell/screen_time_model.lua.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local config = require("config")
local P = require("themes.layouts.page")
local F = require("themes.layouts.option_rows")

local V = {}
local ROWS = 12

-- A time of day to type, under what it is.
local function time_field(model, id, key, title, inner)
  return ui.Column { id = id, width = inner, gap = theme.space.xs,
    kit.subtitle { id = id .. "-label", width = inner, font_size = theme.size.small, color = kit.ink("lo"), text = title },
    F.text { id = id .. "-field", width = inner, title = title, value = function() return config.get(key) end,
      set = function(text) model.set_time(key, text) end } }
end

--- The page at `w` x `h`.
function V.build(model, w, h)
  local inner = P.inner(w)
  local function flag(id, key, icon, title, subtitle)
    return F.switch { id = id, width = inner, icon = icon, title = title, subtitle = subtitle,
      on = function() return config.get(key) == true end, set = function(on) config.set(key, on == true) end }
  end
  local apps = { id = "screen-time-apps", width = w, title = "Apps",
    F.choices { id = "screen-time-period", width = inner, title = "How far back", choices = model.PERIODS,
      read = function() return model.period:get() end, set = function(value) model.period:set(value) end },
    P.row { id = "screen-time-total", width = inner, height = 44, icon = "hourglass_top", title = "In all",
      subtitle = function()
        local _, total = model.shown()
        return model.words(total)
      end },
  }
  for index = 1, ROWS do
    local function row() return (model.shown())[index] end
    apps[#apps + 1] = P.row { id = "screen-time-app-" .. index, width = inner, icon = "apps",
      visible = function() return row() ~= nil end,
      title = function() local r = row() return r and r.name or "" end,
      subtitle = function()
        local r = row()
        if not r then return "" end
        local minutes = model.limit(r.key)
        return model.words(r.seconds) .. (minutes and " · Limit " .. model.words(minutes * 60) or "")
      end,
      trailing = P.chevron(),
      on_clicked = function()
        local r = row()
        if not r then return end
        model.selected:set(r.key)
        require("utilities").request("screen_time/app")
      end }
  end

  return P.page { id = "screen-time-scroll", width = w, height = h,
    P.section { id = "screen-time-about", width = w,
      flag("screen-time-enabled", "wellbeing.enabled", "hourglass_bottom", "Count screen time", "Which app has the focus, while unlocked"),
      P.row { id = "screen-time-local", width = inner, icon = "lock", title = "Stays on this machine",
        subtitle = "Counted here. Nothing leaves it" },
      P.row { id = "screen-time-honest", width = inner, icon = "info", title = "Limits warn",
        subtitle = "You can override them: a shell cannot stop an app" },
    },
    P.section(apps),
    P.section { id = "screen-time-downtime", width = w, title = "Downtime",
      flag("screen-time-downtime-on", "wellbeing.downtime.on", "do_not_disturb_on", "Downtime",
        "Only apps you allow go without a warning"),
      time_field(model, "screen-time-downtime-from", "wellbeing.downtime.from", "Starts, as 22:00", inner),
      time_field(model, "screen-time-downtime-to", "wellbeing.downtime.to", "Ends, as 07:00", inner),
    },
    P.section { id = "screen-time-bedtime", width = w, title = "Bedtime",
      flag("screen-time-bedtime-on", "wellbeing.bedtime.on", "bedtime", "Bedtime on a schedule",
        "The screen winds down for the night"),
      flag("screen-time-bedtime-grey", "wellbeing.bedtime.grayscale", "filter_b_and_w", "Grey screen", "Colours off till the morning"),
      flag("screen-time-bedtime-quiet", "wellbeing.bedtime.quiet", "notifications_paused", "Sleep mode", "Turns on the Sleep focus"),
      time_field(model, "screen-time-bedtime-from", "wellbeing.bedtime.from", "Starts, as 22:30", inner),
      time_field(model, "screen-time-bedtime-to", "wellbeing.bedtime.to", "Ends, as 07:00", inner),
    },
    P.section { id = "screen-time-forget", width = w, title = "What is kept",
      P.buttons { id = "screen-time-forget-buttons", width = inner,
        { id = "screen-time-forget-button", label = "Forget it all", icon = "delete_sweep", on_clicked = model.forget } } },
  }
end

--- One app's page at `w` x `h`.
function V.app(model, w, h)
  local inner = P.inner(w)
  local function key() return model.selected:get() end
  return P.page { id = "screen-time-app-scroll", width = w, height = h,
    P.section { id = "screen-time-app-section", width = w, title = "This app",
      P.row { id = "screen-time-app-today", width = inner, icon = "apps", title = function() return (model.name_of(key())) end,
        subtitle = function() return model.words(model.used(key())) .. " today" end },
      P.row { id = "screen-time-app-honest", width = inner, icon = "info", title = "A limit warns",
        subtitle = "It can be overridden: a shell cannot stop an app" },
      F.choices { id = "screen-time-limit", width = inner, title = "Daily limit", choices = model.LIMITS,
        read = function() return model.limit(key()) or 0 end, set = function(minutes) model.set_limit(key(), minutes) end },
      F.switch { id = "screen-time-allowed", width = inner, icon = "bedtime_off", title = "Allowed during downtime",
        on = function() return model.allowed(key()) end, set = function(on) model.set_allowed(key(), on == true) end },
    } }
end

return V
