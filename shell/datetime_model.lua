-- The Date and time and Region pages: readings from timedate1 and locale1,
-- and what each change is allowed to do on this system.
local morf = require("morf")
local config = require("config")
local timedate = require("lib.services.timedate")
local page_model = require("page_model")

local M = {}

function M.new(key, active)
  local model = page_model.new(key, active)
  local time = morf.signal("eva.datetime.time", {})
  local zones = morf.signal("eva.datetime.zones", {})
  local locale = morf.signal("eva.datetime.locale", {})
  local locales = morf.signal("eva.datetime.locales", {})

  local function refresh()
    timedate.time(function(reply) time:set(type(reply) == "table" and reply or {}) end)
    timedate.locale(function(reply) locale:set(type(reply) == "table" and reply or {}) end)
  end
  model.on_show(function()
    refresh()
    if #zones:get() == 0 then
      timedate.timezones(function(list)
        local rows = {}
        for index, zone in ipairs(type(list) == "table" and list or {}) do
          rows[index] = { key = zone, name = zone:gsub("_", " "), zone = zone, words = zone }
        end
        zones:set(rows)
      end)
    end
    if #locales:get() == 0 then
      timedate.locales(function(list)
        local rows = {}
        for index, name in ipairs(list or {}) do rows[index] = { key = name, name = name, words = name } end
        locales:set(rows)
      end)
    end
  end)

  function model.reachable() return time:get().Timezone ~= nil end
  function model.timezone() return time:get().Timezone or "" end
  function model.zones() return zones:get() end
  function model.timezone_declared() return timedate.timezone_declared() end
  function model.ntp() return time:get().NTP == true end
  function model.can_ntp() return time:get().CanNTP == true end
  function model.synced() return time:get().NTPSynchronized == true end
  function model.twelve_hour() return config.get("bar.clock.twelve_hour") == true end
  function model.set_twelve_hour(on) config.set("bar.clock.twelve_hour", on == true) end
  function model.clock()
    morf.time.minute_clock:get()
    return morf.time.format(model.twelve_hour() and "%A %-d %B, %-I:%M %p" or "%A %-d %B, %H:%M")
  end

  function model.set_timezone(zone)
    return model.action(function(done) timedate.set_timezone(zone, done) return true end, refresh)
  end
  function model.set_ntp(on)
    return model.action(function(done) timedate.set_ntp(on, done) return true end, refresh)
  end
  --- Sets the clock from "YYYY-MM-DD HH:MM", read as local time.
  function model.set_time(text)
    local stamp = morf.time.parse(text, "%Y-%m-%d %H:%M")
    if not stamp then model.say("Write it as 2026-11-01 09:30", true) return false end
    return model.action(function(done) timedate.set_time(stamp, done) return true end, refresh)
  end

  function model.locale()
    return timedate.parse_locale(locale:get().Locale)
  end
  function model.locales() return locales:get() end
  function model.locale_declared() return timedate.locale_declared() end
  function model.language() return model.locale().LANG or "" end
  function model.format() return model.locale().LC_TIME or model.locale().LANG or "" end
  local function assign(values)
    local now, out = model.locale(), {}
    for name, value in pairs(values) do now[name] = value end
    for name, value in pairs(now) do if value ~= "" then out[#out + 1] = name .. "=" .. value end end
    table.sort(out)
    return model.action(function(done) timedate.set_locale(out, done) return true end, refresh)
  end
  function model.set_language(name) return assign { LANG = name } end
  --- Dates, numbers and money in `name`, the language staying as it is.
  function model.set_format(name)
    return assign { LC_TIME = name, LC_NUMERIC = name, LC_MONETARY = name, LC_MEASUREMENT = name, LC_PAPER = name }
  end
  return model
end

return M
