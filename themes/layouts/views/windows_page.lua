-- The Windows pages of Settings, in the page template. Each is a section of
-- choices that share its width and rows with a switch.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local C, S = theme.color, theme.space

local M = {}

local function choices(w, spec)
  local row = { width = P.inner(w) }
  for _, c in ipairs(spec.items) do
    row[#row + 1] = { id = spec.group .. "-" .. tostring(c[1]), icon = c[2], label = c[3], group = spec.group,
      selected = function() return spec.now() == c[1] end, on_clicked = function() spec.pick(c[1]) end }
  end
  return P.section { id = spec.group, caption_id = spec.group .. "-caption", width = w, title = spec.title, P.buttons(row) }
end

local function toggle(w, id, icon, name, on, set)
  return P.row { id = id, width = P.inner(w), icon = icon, title = name, on = on,
    trailing = P.switch { id = id .. "-switch", name = name, on = on, on_toggled = set } }
end

function M.build_windows(model, w, h)
  local sections = { id = "windows-scroll", width = w, height = h, active = model.active }
  if not model.touch then
    local corners = { id = "windows-corners", caption_id = "windows-corners-caption", width = w, title = "Hot corners" }
    for _, corner in ipairs(model.corners.CORNERS) do
      local key = corner.key
      corners[#corners + 1] = P.row { id = "windows-corner-" .. key, width = P.inner(w), icon = "crop_free", title = corner.name,
        subtitle = function() return model.corners.action_name(key) end,
        on_clicked = function() if model.active() then model.corners.next_action(key) end end,
        trailing = P.button { id = "windows-guard-" .. key, width = 96,
          label = function() return model.corners.guard_name(key) end,
          on_clicked = function() if model.active() then model.corners.next_guard(key) end end } }
    end
    sections[#sections + 1] = P.section(corners)
    sections[#sections + 1] = choices(w, { group = "windows-scope", title = "Alt+Tab shows windows from",
      items = model.scopes, now = model.get("windows.switcher.scope"), pick = model.set("windows.switcher.scope") })
    sections[#sections + 1] = P.section { id = "windows-switcher", caption_id = "windows-switcher-caption", width = w, title = "Window switcher",
      toggle(w, "windows-group", "stacks", "One card per application", model.get("windows.switcher.group"),
        model.set("windows.switcher.group")) }
  end
  if not model.phone then
    sections[#sections + 1] = P.section { id = "windows-snap", caption_id = "windows-snap-caption", width = w, title = "Snapping",
      toggle(w, "windows-assist", "dashboard", "Offer the room left", model.get("windows.snap_assist"),
        model.set("windows.snap_assist")),
      toggle(w, "windows-pip", "picture_in_picture", "Take a playing video along, small", model.get("windows.pip_auto"),
        model.set("windows.pip_auto")),
      P.row { id = "windows-more", width = P.inner(w), icon = "stacks", title = "Scratchpads", trailing = P.chevron(),
        on_clicked = function() require("utilities").request("windows/more") end },
      P.row { id = "windows-rules", width = P.inner(w), icon = "rule", title = "Window rules",
        subtitle = "Where an app opens, and how", trailing = P.chevron(),
        on_clicked = function() require("utilities").request("windows/rules") end },
      P.row { id = "windows-layouts", width = P.inner(w), icon = "dashboard", title = "Saved layouts",
        subtitle = "Put windows back by name, or after login", trailing = P.chevron(),
        on_clicked = function() require("utilities").request("windows/layouts") end } }
    sections[#sections + 1] = P.section { id = "windows-dim", caption_id = "windows-dim-caption", width = w, title = "Focus",
      toggle(w, "windows-dim-inactive", "brightness_low", "Dim inactive windows", model.get("windows.dim_inactive"),
        model.set("windows.dim_inactive")),
      F.slider { id = "windows-dim-strength", width = P.inner(w), icon = "contrast", name = "How much", from = model.dim_min,
        to = model.dim_max, step = .05, value = model.get("windows.dim_strength"), set = model.set("windows.dim_strength"),
        format = function(value) return ("%d%%"):format(math.floor(value * 100 + .5)) end } }
  else
    sections[#sections + 1] = choices(w, { group = "windows-scrub", title = "The bottom edge walks",
      items = model.scrubs, now = model.get("windows.scrub"), pick = model.set("windows.scrub") })
  end
  if not model.touch then
    sections[#sections + 1] = kit.subtitle { width = w, wrap = true, font_size = theme.size.small, color = kit.ink("lo"),
      text = "A corner's button says which key must be held for it to work." }
  end
  return P.page(sections)
end

-- ---------------------------------------------------------- window rules --

function M.build_rules(model, w, h)
  local inner = P.inner(w)
  local rules = model.rules
  local function rule_row(index, width)
    local function rule() return model.rule(index) or {} end
    return P.row { id = "rule-" .. index, width = width, icon = "rule", title = function() return rules.label(rule()) end,
      subtitle = function() return rules.summary(rule()) end, on = function() return rule().enabled ~= false end,
      on_clicked = function() rules.edit(rule()) end,
      trailing = P.switch { id = "rule-" .. index .. "-switch", name = "Rule on",
        on = function() return rule().enabled ~= false end,
        on_toggled = function(on) rules.set_enabled(rule().id, on) end } }
  end
  local function running_row(index, width)
    local function window() return model.running()[index] or {} end
    return P.row { id = "rule-from-" .. index, width = width, icon = "select_window",
      title = function() return window().class or "" end, subtitle = function() return window().title or "" end,
      on_clicked = function() rules.edit(rules.from_window(window().address)) end, trailing = P.chevron() }
  end
  return P.page { id = "rules-scroll", width = w, height = h, active = model.active,
    P.section { id = "rules-list", caption_id = "rules-list-caption", width = w, title = "Rules",
      F.list(inner, "rules-row-", function() return #rules.list() end, rule_row, "No rules yet", 24),
      P.button { id = "rules-add", label = "Add a rule", icon = "add", on_clicked = function() rules.edit({}) end } },
    P.section { id = "rules-running", caption_id = "rules-running-caption", width = w, title = "From a running window",
      F.list(inner, "rules-window-", function() return #model.running() end, running_row, "No windows are open", 12) },
    F.note(w, "A rule acts on a window as it opens. Opacity, blur and dimming reach windows already open.") }
end

function M.build_rule(model, w, h)
  local inner = P.inner(w)
  local rules = model.rules
  local function value(field) return function() return rules.draft:get()[field] end end
  local function text(id, field, label, placeholder)
    local box, handle = P.field { id = id, width = inner, placeholder = placeholder,
      on_changed = function(typed)
        if tostring(rules.draft:get()[field] or "") ~= typed then rules.change(field, typed) end
      end }
    morf.effect("eva.rule.fill." .. id, function()
      local now = tostring(rules.draft:get()[field] or "")
      if handle.text ~= now then handle.text = now end
    end, { owner = box })
    return ui.Column { width = inner, gap = S.xxs, F.note(inner, label), box }
  end
  local flags = { id = "rule-flags", caption_id = "rule-flags-caption", width = w, title = "It also" }
  for _, flag in ipairs(rules.FLAGS) do
    flags[#flags + 1] = F.toggle { id = "rule-flag-" .. flag[1], width = inner, icon = flag[3], title = flag[2],
      on = function() return value(flag[1])() == true end, set = function(on) rules.change(flag[1], on == true) end }
  end
  return P.page { id = "rule-scroll", width = w, height = h, active = model.active,
    P.buttons { width = w,
      { id = "rule-save", label = "Save", tone = "primary", on_clicked = function() rules.commit() end },
      { id = "rule-delete", label = "Delete", visible = function() return value("id")() ~= nil end,
        on_clicked = function() rules.delete() end } },
    F.note(w, function() return rules.message:get() end, { id = "rule-message", color = function() return C.error end,
      visible = function() return rules.message:get() ~= "" end }),
    P.section { id = "rule-match", caption_id = "rule-match-caption", width = w, title = "Which windows",
      text("rule-class", "class", "Class", "^firefox$"),
      text("rule-title", "title", "Title", "Any") },
    P.section { id = "rule-place", caption_id = "rule-place-caption", width = w, title = "How it opens",
      F.choices { id = "rule-layout", width = inner, items = model.layouts, now = function() return value("layout")() or "" end,
        pick = function(key) rules.change("layout", key) end },
      text("rule-size", "size", "Size, in pixels", "800 600"),
      text("rule-move", "move", "Position", "30 40"),
      text("rule-workspace", "workspace", "Workspace", "2"),
      F.toggle { id = "rule-silent", width = inner, icon = "visibility_off", title = "Stay here as it opens",
        on = function() return value("silent")() == true end, set = function(on) rules.change("silent", on == true) end },
      F.note(inner, "Screen"),
      F.choices { id = "rule-monitor", width = inner, per_row = 2, items = rules.screens(),
        now = function() return value("monitor")() or "" end, pick = function(key) rules.change("monitor", key) end },
      F.slider { id = "rule-opacity", width = inner, icon = "opacity", name = "Opacity", from = .1, to = 1, step = .05,
        value = function() return tonumber(value("opacity")()) or 1 end, set = function(v) rules.change("opacity", v) end,
        format = function(v) return ("%d%%"):format(math.floor(v * 100 + .5)) end } },
    P.section(flags) }
end

-- --------------------------------------------------------- saved layouts --

function M.build_layouts(model, w, h)
  local inner = P.inner(w)
  local layouts = model.layouts
  local box, handle = P.field { id = "layouts-name", width = inner, placeholder = "A name for what is open",
    on_accepted = function() model.save(handle.text) end }
  local function row(index, width)
    local function layout() return model.saved(index) or {} end
    local remove = kit.action { id = "layouts-remove-" .. index, width = S.TARGET, height = S.TARGET, cursor = "pointer",
      accessible_name = "Delete this layout", on_clicked = function() layouts.remove(layout().name) end,
      kit.icon("delete", 20, kit.ink("lo"), { anchors = { center_in = true } }) }
    return P.row { id = "layouts-row-" .. index, width = width, icon = "dashboard", title = function() return layout().name or "" end,
      subtitle = function() return model.count(layout()) end,
      trailing = ui.Row { gap = S.xs, align = "center",
        P.button { id = "layouts-restore-" .. index, label = "Restore", width = 104, height = S.TARGET,
          on_clicked = function() layouts.restore(layout().name) end },
        P.switch { id = "layouts-login-" .. index, name = "Restore after login",
          on = function() return layouts.login() == layout().name end,
          on_toggled = function(on) layouts.set_login(on and layout().name or "") end },
        remove } }
  end
  return P.page { id = "layouts-scroll", width = w, height = h, active = model.active,
    P.section { id = "layouts-save", caption_id = "layouts-save-caption", width = w, title = "Save what is open", box,
      P.button { id = "layouts-save-now", label = "Save", tone = "primary", on_clicked = function() model.save(handle.text) end },
      F.note(inner, function() return model.message:get() end, { id = "layouts-message",
        visible = function() return model.message:get() ~= "" end }) },
    P.section { id = "layouts-list", caption_id = "layouts-list-caption", width = w, title = "Saved",
      F.list(inner, "layouts-saved-", function() return #layouts.list() end, row, "Nothing saved yet", 16),
      F.note(inner, function() return layouts.report_text() end, { id = "layouts-report",
        visible = function() return layouts.report_text() ~= "" end }) },
    F.note(w, "The switch restores a layout after each login. Floating windows return to their exact place, "
      .. "tiled ones to their workspace. A window that is closed is started again, but what was in it is not: tabs, "
      .. "documents and terminal sessions start fresh. An app with no desktop entry cannot be started, and one that "
      .. "keeps to a single window comes back as one.") }
end

return M
