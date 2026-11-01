-- The system pages: Date and time, Region, Users, Privacy, Firewall, About,
-- Updates and Displays. Each model owns its readings and actions. A value the
-- system configuration holds says so where it would be changed.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local C = theme.color
local S = theme.space

local M = {}

--- What a NixOS configuration keeps, in place of the controls that would fail.
local function declared(id, inner, visible, option)
  return F.note(inner, "This system's configuration sets this: change " .. option
    .. " and rebuild. It cannot be changed from here.", { id = id, visible = visible })
end

function M.datetime_page(model, w, h)
  local inner = P.inner(w)
  local function free() return not model.timezone_declared() end
  local zones = F.picker { id = "datetime-zone", width = inner, placeholder = "Search time zones", max = 6, visible = free,
    searched = true, items = model.zones,
    row = function(item)
      return { icon = "schedule", title = item.name, on = item.zone == model.timezone(),
        pick = function() model.set_timezone(item.zone) end }
    end }
  local set_text = morf.signal("eva.datetime.text", "")
  local set_box = P.field { id = "datetime-set", width = inner, placeholder = "2026-11-01 09:30",
    on_changed = function(value) set_text:set(value) end, visible = function() return not model.ntp() end }
  return P.page { id = "datetime-scroll", width = w, height = h, active = model.active,
    P.section { id = "datetime-now", width = w, title = "Now",
      F.fact { id = "datetime-clock", width = inner, icon = "schedule", title = model.clock,
        subtitle = function() return model.timezone() ~= "" and model.timezone() or "Clock service not reachable" end },
      F.toggle { id = "datetime-twelve", width = inner, icon = "more_time", title = "12-hour clock",
        on = model.twelve_hour, set = model.set_twelve_hour },
    },
    P.section { id = "datetime-auto", width = w, title = "Setting the clock",
      F.toggle { id = "datetime-ntp", width = inner, icon = "sync", title = "Set automatically",
        subtitle = function()
          if not model.can_ntp() then return "No time service on this system" end
          return model.synced() and "In step with network time" or "Not in step yet"
        end,
        on = model.ntp, enabled = model.can_ntp, set = model.set_ntp },
      set_box,
      P.button { id = "datetime-set-save", label = "Set the clock", visible = function() return not model.ntp() end,
        on_clicked = function() model.set_time(set_text:get()) end },
    },
    P.section { id = "datetime-zones", width = w, title = "Time zone",
      declared("datetime-declared", inner, model.timezone_declared, "time.timeZone"),
      zones,
    },
    F.status("datetime-status", w, model),
  }
end

function M.region_page(model, w, h)
  local inner = P.inner(w)
  local function free() return not model.locale_declared() end
  local function picker(id, placeholder, now, set)
    return (F.picker { id = id, width = inner, placeholder = placeholder, max = 6, visible = free, searched = true,
      items = model.locales,
      row = function(item)
        return { icon = "language", title = item.name, on = item.name == now(), pick = function() set(item.name) end }
      end })
  end
  return P.page { id = "region-scroll", width = w, height = h, active = model.active,
    P.section { id = "region-language", width = w, title = "Language",
      F.fact { id = "region-current", width = inner, icon = "language", title = "System language",
        subtitle = function() return model.language() ~= "" and model.language() or "Not set" end },
      declared("region-declared", inner, model.locale_declared, "i18n.defaultLocale"),
      picker("region-lang", "Search languages", model.language, model.set_language),
      F.note(inner, "It applies at the next login.", { visible = free }),
    },
    P.section { id = "region-formats", width = w, title = "Formats",
      F.fact { id = "region-format", width = inner, icon = "calendar_month", title = "Dates, numbers and money",
        subtitle = function() return model.format() ~= "" and model.format() or "As the language" end },
      declared("region-format-declared", inner, model.locale_declared, "i18n.extraLocaleSettings"),
      picker("region-fmt", "Search formats", model.format, model.set_format),
    },
    F.status("region-status", w, model),
  }
end

--- A round picture of `row` (fn), or its initial.
local function face(id, row, size)
  local mask = kit.shape { width = size, height = size, shape = "circle", color = "#ffffff" }
  local function path() return (row() or {}).face end
  return ui.Item { id = id, width = size, height = size,
    kit.shape { anchors = { fill = true }, shape = "circle", color = function() return C.primaryContainer end },
    ui.Image { anchors = { fill = true }, source = function() return path() or "" end, visible = function() return path() ~= nil end,
      fill_mode = "preserve_aspect_crop", mask = mask },
    kit.icon("person", size // 2, function() return C.onPrimaryContainer end,
      { anchors = { center_in = true }, fill = true, visible = function() return path() == nil end }),
  }
end

function M.users_page(model, w, h)
  local inner = P.inner(w)
  local me = model.me
  local name = morf.signal("eva.users.name", "")
  local name_box, name_input = P.field { id = "users-name", width = inner, placeholder = "Your name",
    on_changed = function(value) name:set(value) end, on_accepted = function() model.set_label(name:get()) end }
  morf.effect("eva.users.name.fill", function()
    if model.active() then name_input.text = me().label or "" end
  end)
  local accounts = F.list(inner, "users-row-", function() return #model.list() end, function(index, width)
    local function row() return model.list()[index] or {} end
    return P.row { id = "users-account-" .. index, width = width, icon = "person", on = function() return row().me == true end,
      title = function() return row().label or "" end,
      subtitle = function()
        local r = row()
        return (r.name or "") .. (r.admin and " · Administrator" or " · Standard user") .. (r.me and " · You" or "")
      end }
  end, "No accounts to list", 12)
  local function choosing() return model.choosing:get() end
  return P.page { id = "users-scroll", width = w, height = h, active = model.active,
    P.section { id = "users-me", width = w, title = "You",
      ui.Row { width = inner, gap = S.m, align = "center",
        face("users-face", me, S.TOUCH + S.l),
        ui.Column { gap = S.xs, width = inner - S.TOUCH - S.l - S.m,
          kit.text { id = "users-label", text = function() return me().label or "" end, width = inner - S.TOUCH - S.l - S.m,
            elide = "right", font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi") },
          kit.subtitle { width = inner - S.TOUCH - S.l - S.m, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
            text = "Shown on the lock screen and at login" },
        },
      },
      P.button { id = "users-change-face", icon = "add_a_photo", label = "Change picture", width = inner,
        on_clicked = function() model.choosing:set(not choosing()) end },
      F.chooser { id = "users-chooser", width = inner, open = choosing, path = "~/Pictures",
        filters = { { name = "Pictures", patterns = { "png", "jpg", "jpeg", "webp" } } },
        on_accepted = function(path) model.choosing:set(false) model.set_face(path) end,
        on_cancelled = function() model.choosing:set(false) end },
      name_box,
      P.button { id = "users-save-name", label = "Save name", width = inner, on_clicked = function() model.set_label(name:get()) end },
      F.status("users-status", inner, model),
    },
    P.section { id = "users-accounts", width = w, title = "Accounts", accounts,
      F.note(inner, "This system's configuration keeps its accounts: add or remove them under users.users and rebuild.",
        { id = "users-declared", visible = model.declared }),
    },
  }
end

function M.privacy_page(model, w, h)
  local inner = P.inner(w)
  local kinds = {}
  for _, kind in ipairs(model.KINDS) do kinds[#kinds + 1] = { kind.id, kind.icon, kind.name } end
  local function short(item) return { item[1], item[2], (item[3]:gsub("Running in the background", "Background")) } end
  local items = {}
  for index, item in ipairs(kinds) do items[index] = short(item) end
  local apps = F.list(inner, "privacy-row-", function() return #model.rows() end, function(index, width)
    local function row() return model.rows()[index] or {} end
    local function on() return row().on == true end
    return P.row { id = "privacy-app-" .. index, width = width, icon = function() return (model.kind() or {}).icon or "apps" end,
      on = on, title = function() return row().app and model.app_name(row()) or "" end,
      subtitle = function() return row().app or "" end,
      trailing = ui.Row { gap = S.xs, align = "center",
        P.button { id = "privacy-forget-" .. index, label = "Forget", accessible_name = "Forget this answer",
          on_clicked = function() model.forget(row()) end },
        P.switch { id = "privacy-switch-" .. index, name = "Allowed", on = on, on_toggled = function(now) model.set(row(), now) end } } }
  end, "No app has asked", 16)
  local recent = F.list(inner, "privacy-recent-", function() return math.min(#model.recent(), 8) end, function(index, width)
    local function row() return model.recent()[index] or {} end
    return P.row { id = "privacy-used-" .. index, width = width, on = function() return false end,
      icon = function() return row().kind == "location" and "location_on" or "mic" end,
      title = function() return row().app or "" end,
      subtitle = function() return row().at and model.when(row().at) or "" end }
  end, "Nothing has used these lately", 8)
  return P.page { id = "privacy-scroll", width = w, height = h, active = model.active,
    P.section { id = "privacy-kinds", width = w, title = "App permissions",
      F.note(inner, "These are answers apps got through a portal: Flatpak and Snap apps. A program installed the ordinary way runs with your own rights and never asks."),
      F.note(inner, "xdg-permission-store is not running, so nothing can be read.",
        { id = "privacy-missing", visible = model.missing }),
      F.choices { id = "privacy-kind", width = inner, items = items, per_row = 2,
        now = function() return model.selected:get() end, pick = function(key) model.selected:set(key) end },
      apps,
    },
    P.section { id = "privacy-recent", width = w, title = "Recent use", recent },
    P.section { id = "privacy-security", width = w, title = "Security",
      F.fact { id = "privacy-boot", width = inner, icon = "verified_user", title = "Secure boot",
        subtitle = function()
          local v = model.secure_boot()
          if v == nil then return "Not an EFI system, or it cannot be read" end
          return v and "On" or "Off"
        end },
      F.fact { id = "privacy-disk", width = inner, icon = "enhanced_encryption", title = "Disk encryption",
        subtitle = function()
          local v = model.encrypted()
          if v == nil then return "Cannot be told" end
          return v and "The system disk is encrypted" or "The system disk is not encrypted"
        end },
      F.toggle { id = "privacy-agent", width = inner, icon = "admin_panel_settings", title = "Password prompts in the shell",
        subtitle = "Off, leave them to another polkit agent", on = model.agent, set = model.set_agent },
      F.link { id = "privacy-firewall", width = inner, icon = "security", title = "Firewall",
        subtitle = "Incoming connections", go = function() model.request("firewall", "privacy") end },
      P.button { id = "privacy-clear-recent", icon = "delete_history", label = "Clear recent files", width = inner,
        on_clicked = model.clear_recent },
    },
    F.status("privacy-status", w, model),
  }
end

function M.firewall_page(model, w, h)
  local inner = P.inner(w)
  local NAMES = { firewalld = "firewalld", ufw = "ufw", nixos = "NixOS firewall" }
  return P.page { id = "firewall-scroll", width = w, height = h, active = model.active,
    P.section { id = "firewall-state", width = w, title = "Firewall", visible = model.present,
      F.toggle { id = "firewall-on", width = inner, icon = "security", title = "Block incoming connections",
        subtitle = function() return (NAMES[model.backend()] or "") .. " · " .. (model.on() and "On" or "Off") end,
        on = model.on, enabled = function() return not model.declarative() end, set = model.set },
      F.note(inner, "NixOS builds this firewall from its configuration: change networking.firewall.enable and its ports there, and rebuild.",
        { id = "firewall-declared", visible = model.declarative }),
      F.status("firewall-status", inner, model),
    },
    (function()
      local none = P.empty { id = "firewall-none", width = w, icon = "security", title = "No firewall found",
        text = "Neither firewalld nor ufw is installed." }
      none.visible = function() return not model.present() end
      return none
    end)(),
  }
end

function M.about_page(model, w, h)
  local inner = P.inner(w)
  local name = morf.signal("eva.about.name", "")
  local box, input = P.field { id = "about-hostname", width = inner, placeholder = "Device name",
    visible = function() return not model.hostname_declared() end,
    on_changed = function(value) name:set(value) end, on_accepted = function() model.set_hostname(name:get()) end }
  morf.effect("eva.about.name.fill", function() input.text = model.hostname() end)
  local facts = F.list(inner, "about-row-", function() return #model.rows() end, function(index, width)
    local function row() return model.rows()[index] or {} end
    return P.row { id = "about-fact-" .. index, width = width, on = function() return false end,
      title = function() return row().name or "" end, subtitle = function() return row().value or "" end }
  end, nil, 16)
  return P.page { id = "about-scroll", width = w, height = h, active = model.active,
    P.section { id = "about-facts", width = w, title = "This machine", facts,
      P.button { id = "about-copy", icon = "content_copy", label = "Copy all", width = inner, on_clicked = model.copy },
      F.status("about-status", inner, model),
    },
    P.section { id = "about-name", width = w, title = "Device name",
      declared("about-declared", inner, model.hostname_declared, "networking.hostName"),
      box,
      P.button { id = "about-hostname-save", label = "Rename", width = inner,
        visible = function() return not model.hostname_declared() end,
        on_clicked = function() model.set_hostname(name:get()) end },
    },
    P.section { id = "about-more", width = w, title = "More", visible = model.can_info,
      F.link { id = "about-info", width = inner, icon = "memory", title = "System information",
        subtitle = "Every sensor and device, in eva-info", go = model.open_info },
    },
  }
end

function M.updates_page(model, w, h)
  local inner = P.inner(w)
  return P.page { id = "updates-scroll", width = w, height = h, active = model.active,
    P.section { id = "updates-versions", width = w, title = "Running now",
      F.fact { id = "updates-eva", width = inner, icon = "dashboard_customize", title = "eva",
        subtitle = function() return model.eva() ~= "" and model.eva() or "Unknown" end },
      F.fact { id = "updates-morf", width = inner, icon = "memory", title = "morf", subtitle = model.version },
    },
    P.section { id = "updates-do", width = w, title = "Updates",
      F.link { id = "updates-open", width = inner, icon = "system_update", title = "Check for updates",
        subtitle = "System, apps and firmware, in eva-update", go = model.open, visible = model.available },
      F.note(inner, "eva-update is not installed here.", { id = "updates-missing",
        visible = function() return not model.available() end }),
      F.note(inner, "This system is updated by rebuilding its configuration: nixos-rebuild switch.",
        { id = "updates-nixos", visible = model.nixos }),
      F.status("updates-status", inner, model),
    },
  }
end

function M.displays_page(model, w, h)
  local inner = P.inner(w)
  local outputs = F.list(inner, "displays-row-", function() return #model.outputs() end, function(index, width)
    local function row() return model.outputs()[index] or {} end
    return P.row { id = "displays-output-" .. index, width = width, icon = "monitor",
      on = function() return row().enabled ~= false end,
      title = function() local r = row() return r.description ~= "" and r.description or r.name or "" end,
      subtitle = function() return row().name and ((row().name) .. " · " .. model.summary(row())) or "" end }
  end, "No displays reported", 8)
  return P.page { id = "displays-scroll", width = w, height = h, active = model.active,
    P.section { id = "displays-list", width = w, title = "Connected", outputs,
      P.button { id = "displays-open", icon = "open_in_new", label = "Arrange displays", width = inner, tone = "primary",
        visible = model.can_open, on_clicked = model.open },
      F.note(inner, "Resolution, arrangement, scale, rotation, mirroring and profiles are all in eva-displays.",
        { id = "displays-note" }),
      F.status("displays-status", inner, model),
    },
    P.section { id = "displays-more", width = w, title = "Related",
      F.link { id = "displays-night", width = inner, icon = "nightlight", title = "Night light",
        subtitle = "Warmer colours", go = function() model.request("nightlight", "displays") end },
      F.link { id = "displays-access", width = inner, icon = "accessibility_new", title = "Accessibility",
        subtitle = "Colour filters and the screen's zoom", go = function() model.request("accessibility", "displays") end },
    },
  }
end

return M
