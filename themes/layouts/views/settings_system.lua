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

--- Every fact the machine gives (info_model.lua), a card to each kind, built
--- again as more of them come in. The versions are the summary's already.
local FACT_H = 28
local function details(model, w)
  local inner = P.inner(w)
  local info = model.info
  local cards = morf.list_model({})
  morf.effect("eva.about.details", function()
    local revision = info.revision:get()
    local rows = {}
    for _, section in ipairs(info.sections(info.facts:get())) do
      if section.key ~= "versions" then rows[#rows + 1] = { id = section.key .. "@" .. revision, section = section } end
    end
    cards:replace(rows, "id")
  end)
  return ui.Repeater { as = "column", gap = P.GAP, width = w, model = cards, delegate = function(row)
    local section, facts = row.section, {}
    for index, fact in ipairs(section.rows) do facts[index] = { fact[1], fact[2] } end
    return P.section { id = "about-detail-" .. section.key, width = w, title = section.title,
      kit.facts(facts, inner, FACT_H, math.min(math.floor(inner * 0.42), 180)) }
  end }
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
    details(model, w),
  }
end

local LINE_H, LOG_H = 24, 280

--- A line of the rebuild's log, in the mono face.
local function log_row(_, s)
  local index = s.index()
  local node = kit.text {
    id = "update-line-" .. index, width = function() return s.width() end, height = LINE_H, elide = "right",
    vertical_alignment = "center", font_size = P.SUB, font_family = theme.mono, color = kit.ink("hi"),
    text = function() local row = s.row() return row and row.text or "" end,
  }
  return node, function() end
end

--- Updates: what runs now; on NixOS the flake's inputs by age and a rebuild
--- with its log, elsewhere what each package manager has waiting.
function M.updates_page(model, w, h)
  local inner = P.inner(w)
  local U = model.check
  local function nixos() return U.nixos:get() end
  local function found() return U.flake:get() ~= "" and #U.inputs:get() > 0 end
  local function running() return U.state:get() == "running" end
  local inputs = F.list(inner, "update-input-", function() return #U.inputs:get() end, function(index, width)
    local function input() return U.inputs:get()[index] or {} end
    local function tone()
      local i = input()
      if not i.modified or i.modified <= 0 then return kit.ink("lo")() end
      local days = U.days(i.modified)
      if days >= U.OLD then return kit.signal("alert")() end
      if days >= U.STALE then return kit.signal("warn")() end
      return kit.ink("hi")()
    end
    return P.row { id = "update-input-row-" .. index, width = width, icon = "deployed_code", on = function() return false end,
      title = function() return input().name or "" end,
      subtitle = function()
        local i = input()
        if not i.name then return "" end
        local date = i.modified > 0 and morf.time.format("%-d %b %Y", i.modified) or ""
        return ("%s %s %s"):format(i.source, i.rev, date)
      end,
      trailing = kit.text { id = "update-input-age-" .. index, width = 96, horizontal_alignment = "right",
        font_size = theme.size.normal, color = tone,
        text = function() local i = input() return i.modified and U.age(i.modified) or "" end } }
  end, nil, 48)
  local managers = F.list(inner, "update-manager-", function() return #U.managers:get() end, function(index, width)
    local function manager() return U.managers:get()[index] or {} end
    return P.row { id = "update-manager-row-" .. index, width = width, icon = "inventory_2", on = function() return false end,
      title = function()
        local m = manager()
        if not m.name then return "" end
        return ("%s: %d %s"):format(m.name, m.count, m.count == 1 and "update" or "updates")
      end,
      subtitle = function()
        local m = manager()
        if not m.name then return "" end
        return m.count == 0 and "Up to date" or table.concat(m.packages, ", ")
      end }
  end, nil, 6)
  local log, handle = kit.widgets.virtual_list { id = "update-log", width = inner, height = LOG_H, rows = U.rows,
    row_height = LINE_H, delegate = log_row }
  -- The newest line stays in sight.
  morf.effect("update.tail", function()
    U.lines:get()
    handle.scroll_by(1e9)
  end)
  return P.page { id = "updates-scroll", width = w, height = h, active = model.active,
    P.section { id = "updates-versions", width = w, title = "Running now",
      F.fact { id = "updates-eva", width = inner, icon = "dashboard_customize", title = "eva",
        subtitle = function() return model.eva() ~= "" and model.eva() or "Unknown" end },
      F.fact { id = "updates-morf", width = inner, icon = "memory", title = "morf", subtitle = model.version },
    },
    P.section { id = "updates-do", width = w, title = "Updates",
      kit.text { id = "update-note", width = inner, elide = "right", font_size = theme.size.small, color = kit.ink("lo"),
        text = function()
          if U.message:get() ~= "" then return U.message:get() end
          if U.checking:get() > 0 then return "Asking the package managers" end
          local count = U.pending()
          return count == 0 and "Nothing waits" or (count .. " waiting")
        end },
      P.buttons { width = inner,
        { id = "update-check", label = "Check again", icon = "refresh", enabled = function() return U.checking:get() == 0 end,
          on_clicked = function() U.start() end },
        { id = "update-rebuild", label = "Rebuild", icon = "build", tone = "primary",
          visible = function() return nixos() and U.flake:get() ~= "" and not running() end,
          on_clicked = function() U.rebuild() end },
        { id = "update-cancel", label = "Stop", icon = "stop", visible = running, on_clicked = function() U.cancel() end },
      },
    },
    P.section { id = "update-flake", width = w, title = "Flake inputs", visible = function() return nixos() and found() end,
      kit.text { id = "update-flake-path", width = inner, elide = "left", font_size = P.SUB, color = kit.ink("lo"),
        text = function() return U.flake:get() end },
      inputs },
    P.empty { id = "update-no-flake", icon = "lock", title = "No flake.lock", width = w,
      text = "Name one with EVA_UPDATE_FLAKE, or the setting update.flake, or keep it at /etc/nixos.",
      visible = function() return nixos() and not found() end },
    P.section { id = "update-managers", width = w, title = "Packages",
      visible = function() return #U.managers:get() > 0 end, managers },
    P.empty { id = "update-none", icon = "system_update", title = "Nothing to ask", width = w,
      text = "This machine has no package manager eva knows.",
      visible = function() return not nixos() and U.checking:get() == 0 and #U.managers:get() == 0 end },
    P.section { id = "update-log-section", width = w, title = "Rebuild",
      visible = function() return U.lines:get() > 0 or running() end, log },
  }
end

function M.displays_page(model, w, h)
  local inner = P.inner(w)
  local arrange = require("themes").view("displays_page")
  return P.page { id = "displays-scroll", width = w, height = h, active = model.active,
    arrange.arrangement(model.arrange, w), arrange.monitor(model.arrange, w), arrange.profiles(model.arrange, w),
    P.section { id = "displays-ddc", width = w, title = "External screens",
      F.toggle { id = "displays-ddc-on", width = inner, icon = "brightness_medium", title = "Brightness over the cable",
        subtitle = "The brightness slider and keys reach the screen they are on, by DDC/CI",
        enabled = model.ddc.allowed, on = model.ddc_on, set = model.set_ddc },
      F.list(inner, "displays-ddc-row-", function() return #model.ddc.rows() end, function(index, width)
        local function row() return model.ddc.rows()[index] or {} end
        return P.row { id = "displays-ddc-screen-" .. index, width = width, icon = "monitor", title = function() return row().name or "" end,
          subtitle = function() return row().percent and ("%d%% · %s"):format(row().percent, row().model or "") or "Not answering" end }
      end, nil, 4),
      F.note(inner, "Needs programs.eva.hardware.ddc.enable in the NixOS configuration: it installs ddcutil and opens the monitors' buses to the person at the seat.",
        { id = "displays-ddc-note", visible = function() return not model.ddc.allowed() end }),
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
