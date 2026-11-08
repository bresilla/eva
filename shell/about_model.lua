-- The About, Updates and Displays pages. About sums the machine up and lists
-- every fact of it (info_model.lua); Updates checks what waits
-- (system_updates.lua); Displays arranges the monitors (displays_model.lua).
local morf = require("morf")
local about = require("lib.services.about")
local timedate = require("lib.services.timedate")
local host = require("lib.services.host")
local page_model = require("page_model")

local M = {}

function M.about(active)
  local model = page_model.new("about", active)
  local rows = morf.signal("eva.about.rows", {})
  local hostname = morf.signal("eva.about.hostname", "")
  local extra = { eva = about.eva_version() }

  local function read()
    rows:set(about.facts(extra))
    timedate.hostname(function(reply)
      if type(reply) == "table" then hostname:set(reply.StaticHostname or reply.Hostname or "") end
    end)
  end
  model.on_show(function()
    read()
    about.gpus(function(names) extra.gpus = names read() end)
    local hypr = require("lib.compositor.hyprland")
    if hypr.available() then
      hypr.version(function(info)
        if type(info) == "table" and info.version then extra.compositor = "Hyprland " .. info.version read() end
      end)
    end
  end)

  function model.rows() return rows:get() end
  function model.hostname() return hostname:get() end
  function model.hostname_declared() return timedate.hostname_declared() end
  model.nixos = host.nixos
  -- Every fact, the summary's and the cards' below it, for a paste.
  model.info = require("info_model")
  model.on_show(function() model.info.gather() end)
  function model.copy()
    local text = about.as_text(rows:get()) .. "\n\n" .. model.info.text()
    if host.held("copy the facts") then model.say("Would copy it all (dry run)") return true end
    local ok = pcall(morf.clipboard.set, text)
    model.say(ok and "Copied" or "Could not reach the clipboard", not ok)
    return ok
  end
  function model.set_hostname(name)
    local valid, why = timedate.valid_hostname(name)
    if not valid then model.say(why, true) return false end
    return model.action(function(done) timedate.set_hostname(name, done) return true end, read)
  end
  return model
end

--- Updates: the versions running, and what waits (system_updates.lua), asked
--- again as the page comes on show.
function M.updates(active)
  local model = page_model.new("updates", active)
  function model.version() return morf.version or "" end
  function model.eva() return about.eva_version() or "" end
  model.nixos = host.nixos
  model.check = require("system_updates")
  model.on_show(function()
    if model.check.state:get() ~= "running" then model.check.start() end
  end)
  return model
end

--- Displays: the monitors' arrangement (displays_model.lua), read again as the
--- page comes on show, and screens' brightness over the cable.
function M.displays(active)
  local model = page_model.new("displays", active)
  model.arrange = require("displays_model")
  model.on_show(function()
    model.arrange.refresh()
    model.arrange.load_profiles()
  end)
  model.ddc = require("ddc_model")
  function model.ddc_on() return require("config").get("displays.ddc") ~= false end
  function model.set_ddc(on) require("config").set("displays.ddc", on == true) end
  return model
end

return M
