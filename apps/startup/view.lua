-- eva-startup's window: what starts with the session, the installed apps to add
-- from, and the user's timers.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("common.controls")
local model = require("model")
local S = theme.space

local M = {}

local ROWS = 40
local ICON = 32

local function get(v) if type(v) == "function" then return v() end return v end

-- The row's own icon, by what the launcher finds, or a plain one where there is
-- none.
local function row_icon(item)
  local apps = require("apps")
  local function hit()
    local row = item()
    return row and row.icon ~= "" and apps.icon(row.icon) or nil
  end
  local function named() local found = hit() return found ~= nil and found.name ~= nil end
  local function pictured() local found = hit() return found ~= nil and found.path ~= nil end
  return ui.Item {
    width = ICON, height = ICON, anchors = { vertical_center = true },
    ui.Icon {
      width = ICON, height = ICON, source_width = ICON * 2, source_height = ICON * 2, visible = named,
      name = function() local found = hit() return found and found.name or "" end,
    },
    ui.Image {
      width = ICON, height = ICON, fill_mode = "preserve_aspect_fit", visible = pictured,
      source = function() local found = hit() return found and found.path or "" end,
    },
    kit.icon("apps", 26, kit.ink("lo"), {
      anchors = { center_in = true }, visible = function() return not named() and not pictured() end,
    }),
  }
end

local function apps_row(index, item, w)
  local right = function() return S.TARGET * 2 + S.xl end
  local text = function() return math.max(1, get(w) - ICON - S.m - right()) end
  local function subtitle()
    local row = item()
    if not row then return "" end
    local what = row.comment ~= "" and row.comment or row.exec
    return row.origin == "system" and (what .. " · system") or what
  end
  return ui.Item {
    width = w, height = controls.ROW_H,
    row_icon(item),
    ui.Column {
      x = ICON + S.m, anchors = { vertical_center = true }, gap = S.xxs,
      kit.text {
        id = "startup-name-" .. index, width = text, elide = "right", font_size = theme.size.normal, font_weight = 500,
        color = kit.ink("hi"), text = function() local row = item() return row and row.name or "" end,
      },
      kit.text {
        id = "startup-note-" .. index, width = text, elide = "right", font_size = theme.size.small, color = kit.ink("lo"),
        text = subtitle,
      },
    },
    ui.Row {
      anchors = { right = true, vertical_center = true }, gap = S.s, align = "center",
      P.switch {
        id = "startup-switch-" .. index, name = "Start with the session",
        on = function() local row = item() return row ~= nil and row.enabled end,
        on_toggled = function(on)
          local row = item()
          if not row or row.enabled == on then return end
          if on then model.enable(row) else model.disable(row) end
        end,
      },
      ui.Item {
        width = S.TARGET, height = S.TARGET,
        ui.Item {
          width = S.TARGET, height = S.TARGET,
          visible = function() local row = item() return row ~= nil and model.removable(row) end,
          L.icon_button {
            id = "startup-delete-" .. index, icon = "delete", name = "Remove", width = S.TARGET, height = S.TARGET,
            on_clicked = function() local row = item() if row then model.remove(row) end end,
          },
        },
      },
    },
  }
end

local function apps_page(w, h)
  local function rows() return model.rows:get() end
  return ui.Item {
    id = "startup-apps", width = w, height = h,
    P.empty {
      id = "startup-apps-empty", icon = "rocket_launch", title = "Nothing starts with the session", width = w,
      text = "Add an app, or a command of your own.", visible = function() return #rows() == 0 end,
    },
    controls.list {
      id = "startup-list", width = w, height = h, count = ROWS, items = rows,
      build = function(index, item) return apps_row(index, item, w) end,
    },
  }
end

local function add_row(index, item, w)
  return kit.action {
    id = "startup-pick-" .. index, width = w, height = controls.ROW_H, cursor = "pointer",
    accessible_name = "Add to the session",
    on_clicked = function() local app = item() if app then model.add(app) end end,
    row_icon(item),
    ui.Column {
      x = ICON + S.m, anchors = { vertical_center = true }, gap = S.xxs,
      kit.text {
        width = function() return math.max(1, get(w) - ICON - S.m - S.TARGET) end, elide = "right",
        font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi"),
        text = function() local app = item() return app and app.name or "" end,
      },
      kit.text {
        width = function() return math.max(1, get(w) - ICON - S.m - S.TARGET) end, elide = "right",
        font_size = theme.size.small, color = kit.ink("lo"),
        text = function() local app = item() return app and app.description or "" end,
      },
    },
    kit.icon("add", 22, kit.ink("lo"), { anchors = { right = true, right_margin = S.s, vertical_center = true } }),
  }
end

local function add_page(w, h)
  local add = 120
  local top = S.TARGET * 2 + S.s + L.lh(theme.size.small) + S.m
  local function body() return math.max(1, get(h) - top) end
  local function half() return math.max(1, (get(w) - add - S.s * 2) / 2) end
  return ui.Item {
    id = "startup-add", width = w, height = h,
    ui.Row {
      gap = S.s, align = "center",
      controls.entry { id = "startup-command-name", width = half, value = model.command_name, placeholder = "A name" },
      controls.entry {
        id = "startup-command", width = half, value = model.command, placeholder = "A command",
        on_accepted = function(value) model.add_command(model.command_name:get(), value) end,
      },
      P.button {
        id = "startup-command-add", label = "Add", width = add,
        on_clicked = function() model.add_command(model.command_name:get(), model.command:get()) end,
      },
    },
    ui.Item {
      y = S.TARGET + S.xs, width = w, height = L.lh(theme.size.small),
      controls.note { id = "startup-message", width = w, text = function() return model.message:get() end },
    },
    ui.Item {
      y = S.TARGET + S.s + L.lh(theme.size.small), width = w, height = S.TARGET,
      (controls.entry { id = "startup-search", width = w, value = model.query, placeholder = "Search the installed apps" }),
    },
    ui.Item {
      y = top, width = w, height = body,
      P.empty {
        id = "startup-add-empty", icon = "search_off", title = "No apps found", width = w,
        visible = function() return #model.matches() == 0 end,
      },
      controls.list {
        id = "startup-picks", width = w, height = body, count = ROWS, items = model.matches,
        build = function(index, item) return add_row(index, item, w) end,
      },
    },
  }
end

local function timer_row(index, item, w)
  local function title()
    local row = item()
    if not row then return "" end
    return row.alarm or row.name
  end
  local function subtitle()
    local row = item()
    if not row then return "" end
    local who = row.alarm and "Clock · " or ""
    return who .. "Next " .. model.when(row.next) .. " · last " .. model.when(row.last)
  end
  return ui.Item {
    width = w, height = controls.ROW_H,
    kit.icon(function() local row = item() return row and row.alarm and "alarm" or "schedule" end, 24, kit.ink("accent"),
      { x = S.xs, anchors = { vertical_center = true } }),
    ui.Column {
      x = ICON + S.m, anchors = { vertical_center = true }, gap = S.xxs,
      kit.text {
        id = "startup-timer-" .. index, width = function() return math.max(1, get(w) - ICON - S.m) end, elide = "right",
        font_size = theme.size.normal, font_weight = 500, color = kit.ink("hi"), text = title,
      },
      kit.text {
        id = "startup-timer-note-" .. index, width = function() return math.max(1, get(w) - ICON - S.m) end, elide = "right",
        font_size = theme.size.small, color = kit.ink("lo"), text = subtitle,
      },
    },
  }
end

local function scheduled_page(w, h)
  local function rows() return model.timers:get() end
  return ui.Item {
    id = "startup-scheduled", width = w, height = h,
    P.empty {
      id = "startup-timers-none", icon = "event_busy", title = "No user session of systemd", width = w,
      text = "Scheduled jobs are its timers.", visible = function() return model.scheduled:get() == "none" end,
    },
    P.empty {
      id = "startup-timers-empty", icon = "schedule", title = "No timers", width = w,
      visible = function() return model.scheduled:get() == "ready" and #rows() == 0 end,
    },
    controls.list {
      id = "startup-timers", width = w, height = h, count = ROWS, items = rows,
      build = function(index, item) return timer_row(index, item, w) end,
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  return (controls.pages {
    id = "startup", width = w, height = h, tab = model.tab,
    tabs = {
      { key = "apps", name = "Startup apps", icon = "rocket_launch", build = apps_page },
      { key = "add", name = "Add", icon = "add", build = add_page },
      { key = "scheduled", name = "Scheduled", icon = "schedule", build = scheduled_page },
    },
  })
end

return M
