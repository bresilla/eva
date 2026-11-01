-- The Windows and Dock pages of Settings, in the page template. Each is a
-- section of choices that share its width and rows with a switch.
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")

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
        on_clicked = function() require("utilities").request("windows/more") end } }
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

function M.build_dock(model, w, h)
  local sections = { id = "dock-scroll", width = w, height = h, active = model.active }
  if not model.taskbar then
    sections[#sections + 1] = choices(w, { group = "dock-show", title = "Show the dock",
      items = model.shows, now = model.get("dock.enabled"), pick = model.set("dock.enabled") })
    sections[#sections + 1] = choices(w, { group = "dock-edge", title = "Position",
      items = model.edges, now = model.get("dock.edge"), pick = model.set("dock.edge") })
    sections[#sections + 1] = choices(w, { group = "dock-hide", title = "Hide it",
      items = model.hides, now = model.get("dock.autohide"), pick = model.set("dock.autohide") })
    sections[#sections + 1] = choices(w, { group = "dock-size", title = "Size",
      items = model.sizes, now = model.get("dock.size"), pick = model.set("dock.size") })
  end
  local rows = { id = "dock-options", caption_id = "dock-options-caption", width = w, title = "Behaviour" }
  if model.taskbar then
    rows[#rows + 1] = toggle(w, "dock-taskbar-hide", "visibility_off", "Slide the taskbar away",
      model.get("dock.taskbar_hide"), model.set("dock.taskbar_hide"))
  else
    rows[#rows + 1] = toggle(w, "dock-magnify", "zoom_in", "Swell near the pointer", model.get("dock.magnify"),
      model.set("dock.magnify"))
  end
  rows[#rows + 1] = toggle(w, "dock-isolate", "monitor", "Only this screen's windows", model.get("dock.isolate"),
    model.set("dock.isolate"))
  sections[#sections + 1] = P.section(rows)
  return P.page(sections)
end

return M
