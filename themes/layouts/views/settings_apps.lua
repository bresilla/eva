-- The Default apps and Startup apps pages.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local S = theme.space

local M = {}

function M.defaults_page(model, w, h)
  local inner = P.inner(w)
  local section = { id = "apps-kinds", width = w, title = "What opens what" }
  for _, kind in ipairs(model.KINDS) do
    local function open() return model.open:get() == kind.id end
    section[#section + 1] = F.link { id = "apps-" .. kind.id, width = inner, icon = kind.icon, title = kind.name,
      subtitle = function() return model.current(kind) end, go = function() model.toggle(kind) end }
    section[#section + 1] = (F.picker { id = "apps-pick-" .. kind.id, width = inner, placeholder = "Search apps", max = 6,
      visible = open, none = "No app here says it can",
      items = function() return model.candidates(kind) end,
      row = function(item)
        return { icon = "apps", title = item.name, on = item.name == model.current(kind),
          pick = function() model.choose(kind, item) end }
      end })
  end
  return P.page { id = "apps-scroll", width = w, height = h, active = model.active,
    F.note(w, "Home Manager keeps mimeapps.list: a change here is replaced at its next switch. Set xdg.mimeApps there to keep it.",
      { id = "apps-managed", visible = model.managed }),
    P.section(section),
    F.status("apps-status", w, model),
  }
end

function M.startup_page(model, w, h)
  local inner = P.inner(w)
  local entries = F.list(inner, "startup-row-", function() return #model.entries() end, function(index, width)
    local function row() return model.entries()[index] or {} end
    local function on() return row().enabled == true end
    return P.row { id = "startup-entry-" .. index, width = width, icon = "rocket_launch", on = on,
      title = function() return row().name or "" end,
      subtitle = function() local r = row() return r.own and (r.system and "Changed by you" or "Yours") or "From the system" end,
      trailing = ui.Row { gap = S.xs, align = "center",
        P.button { id = "startup-remove-" .. index, label = "Remove", accessible_name = "Remove this entry",
          visible = function() local r = row() return r.own == true and r.system ~= true end,
          on_clicked = function() model.remove_entry(row()) end },
        P.switch { id = "startup-switch-" .. index, name = "Starts at login", on = on,
          on_toggled = function(now) model.set_entry(row(), now) end } } }
  end, "Nothing starts with the session", 24)
  local add = F.picker { id = "startup-add", width = inner, placeholder = "Add an app", max = 5, searched = true,
    items = model.installed,
    row = function(item) return { icon = "add", title = item.name, pick = function() model.add(item) end } end }
  local services = F.list(inner, "startup-service-", function() return #model.services() end, function(index, width)
    local function row() return model.services()[index] or {} end
    local function on() return row().enabled == true end
    return P.row { id = "startup-unit-" .. index, width = width, icon = "memory", on = on,
      title = function() return row().unit or "" end,
      subtitle = function() local r = row() return (r.running and "Running" or "Stopped") .. ((r.description or "") ~= "" and (" · " .. r.description) or "") end,
      trailing = P.switch { id = "startup-unit-switch-" .. index, name = "Service enabled", on = on,
        on_toggled = function(now) model.set_service(row(), now) end } }
  end, "No user services to list", 32)
  -- A command of one's own: a name and what to run.
  local name, command = morf.signal("eva.startup.name", ""), morf.signal("eva.startup.command", "")
  local name_box, name_field = P.field { id = "startup-command-name", width = inner, placeholder = "A name",
    on_changed = function(value) name:set(value) end }
  local command_box, command_field
  local function add_command()
    local given = name:get():find("%S") and command:get():find("%S")
    if model.add_command(name:get(), command:get()) and given then
      name:set("") command:set("") name_field.text = "" command_field.text = ""
    end
  end
  command_box, command_field = P.field { id = "startup-command", width = inner, placeholder = "A command",
    on_changed = function(value) command:set(value) end, on_accepted = add_command }
  local timers = F.list(inner, "startup-timer-", function() return #model.timers() end, function(index, width)
    local function row() return model.timers()[index] or {} end
    return P.row { id = "startup-timer-row-" .. index, width = width, on = function() return false end,
      icon = function() return row().alarm and "alarm" or "schedule" end,
      title = function() local r = row() return r.alarm or r.name or "" end,
      subtitle = function()
        local r = row()
        if not r.unit then return "" end
        return (r.alarm and "Clock · " or "") .. "Next " .. model.when(r.next) .. " · last " .. model.when(r.last)
      end }
  end, nil, 24)
  return P.page { id = "startup-scroll", width = w, height = h, active = model.active,
    P.section { id = "startup-apps", width = w, title = "Apps", entries, add, F.status("startup-status", inner, model) },
    P.section { id = "startup-own", width = w, title = "A command of your own",
      name_box, command_box,
      P.button { id = "startup-command-add", icon = "add", label = "Start it with the session", width = inner,
        on_clicked = add_command } },
    P.section { id = "startup-services", width = w, title = "User services", services },
    P.section { id = "startup-scheduled", width = w, title = "Scheduled",
      F.note(inner, "Scheduled jobs are the timers of systemd's user session, and there is none here.",
        { id = "startup-timers-none", visible = function() return model.scheduled:get() == "none" end }),
      F.note(inner, "No timers.",
        { id = "startup-timers-empty", visible = function() return model.scheduled:get() == "ready" and #model.timers() == 0 end }),
      timers },
  }
end

return M
