-- eva-update's window: what waits, by the flake's inputs and the package managers,
-- and the log of a rebuild as it runs.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("common.controls")
local model = require("model")
local S = theme.space

local M = {}

local INPUT_H = 56
local LINE_H = 24
local INPUTS = 48
local MANAGERS = 6
local AGE_W = 96

local function get(v) if type(v) == "function" then return v() end return v end

local function input_row(index, w)
  local function item() return model.inputs:get()[index] end
  local function tone()
    local input = item()
    if not input or input.modified <= 0 then return kit.ink("lo")() end
    local days = model.days(input.modified)
    if days >= model.OLD then return kit.signal("alert")() end
    if days >= model.STALE then return kit.signal("warn")() end
    return kit.ink("hi")()
  end
  local function text_w() return math.max(1, get(w) - AGE_W - S.s) end
  return ui.Item {
    id = "update-input-" .. index, width = w, height = function() return item() and INPUT_H or 0 end,
    visible = function() return item() ~= nil end,
    ui.Column {
      width = text_w, gap = S.xxs, anchors = { vertical_center = true },
      kit.text {
        id = "update-input-name-" .. index, width = text_w, elide = "right", font_size = theme.size.normal, font_weight = 500,
        color = kit.ink("hi"), text = function() local input = item() return input and input.name or "" end,
      },
      kit.text {
        id = "update-input-source-" .. index, width = text_w, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
        text = function()
          local input = item()
          if not input then return "" end
          local date = input.modified > 0 and morf.time.format("%-d %b %Y", input.modified) or ""
          return ("%s %s %s"):format(input.source, input.rev, date)
        end,
      },
    },
    kit.text {
      id = "update-input-age-" .. index, anchors = { right = true, vertical_center = true }, width = AGE_W,
      horizontal_alignment = "right", font_size = theme.size.normal, color = tone,
      text = function() local input = item() return input and model.age(input.modified) or "" end,
    },
  }
end

local function manager_row(index, w)
  local function item() return model.managers:get()[index] end
  return ui.Item {
    id = "update-manager-" .. index, width = w, height = function() return item() and INPUT_H or 0 end,
    visible = function() return item() ~= nil end,
    ui.Column {
      width = w, gap = S.xxs, anchors = { vertical_center = true },
      kit.text {
        id = "update-manager-name-" .. index, width = w, elide = "right", font_size = theme.size.normal, font_weight = 500,
        color = kit.ink("hi"),
        text = function()
          local manager = item()
          if not manager then return "" end
          return ("%s: %d %s"):format(manager.name, manager.count, manager.count == 1 and "update" or "updates")
        end,
      },
      kit.text {
        id = "update-manager-packages-" .. index, width = w, elide = "right", font_size = P.SUB, color = kit.ink("lo"),
        text = function()
          local manager = item()
          if not manager then return "" end
          return manager.count == 0 and "Up to date" or table.concat(manager.packages, ", ")
        end,
      },
    },
  }
end

local function overview(w, h)
  local function inner() return get(w) - 2 * P.PAD end
  local inputs = { width = inner, gap = 0 }
  for index = 1, INPUTS do inputs[index] = input_row(index, inner) end
  local managers = { width = inner, gap = 0 }
  for index = 1, MANAGERS do managers[index] = manager_row(index, inner) end
  local function nixos() return model.nixos:get() end
  local function found() return model.flake:get() ~= "" and #model.inputs:get() > 0 end
  return (kit.scroll {
    id = "update-overview", width = w, height = h, clip = true,
    ui.Column {
      width = w, gap = P.GAP,
      P.section {
        id = "update-flake", title = "Flake inputs", width = w,
        note = function() return tostring(#model.inputs:get()) end,
        visible = function() return nixos() and found() end,
        kit.text {
          id = "update-flake-path", width = inner, elide = "left", font_size = P.SUB, color = kit.ink("lo"),
          text = function() return model.flake:get() end,
        },
        ui.Column(inputs),
      },
      P.empty {
        id = "update-no-flake", icon = "lock", title = "No flake.lock", width = w,
        text = "Name one with EVA_UPDATE_FLAKE, or the setting update.flake, or keep it at /etc/nixos.",
        visible = function() return nixos() and not found() end,
      },
      P.section {
        id = "update-managers", title = "Packages", width = w,
        visible = function() return #model.managers:get() > 0 end,
        ui.Column(managers),
      },
      P.empty {
        id = "update-none", icon = "system_update", title = "Nothing to ask", width = w,
        text = "This machine has no package manager this tool knows.",
        visible = function() return not nixos() and model.checking:get() == 0 and #model.managers:get() == 0 end,
      },
    },
  })
end

local function log_row(_, s)
  local index = s.index()
  local node = kit.text {
    id = "update-line-" .. index, width = function() return s.width() end, height = LINE_H, elide = "right",
    vertical_alignment = "center", font_size = P.SUB, font_family = theme.mono, color = kit.ink("hi"),
    text = function() local row = s.row() return row and row.text or "" end,
  }
  return node, function() end
end

local function log_page(w, h)
  local list, handle = kit.widgets.virtual_list {
    id = "update-log", width = w, height = h, rows = model.rows, row_height = LINE_H, delegate = log_row,
  }
  -- The newest line stays in sight.
  morf.effect("update.tail", function()
    model.lines:get()
    handle.scroll_by(1e9)
  end)
  return ui.Item {
    id = "update-log-page", width = w, height = h,
    list,
    P.empty {
      id = "update-log-empty", icon = "article", title = "No rebuild yet", width = w,
      text = "Its log shows here as it runs.",
      visible = function() return model.lines:get() == 0 end,
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local foot = P.BUTTON_H + L.lh(theme.size.small) + S.s * 2
  local function running() return model.state:get() == "running" end
  local function body_h() return math.max(1, h() - foot) end
  local tabs = {
    { key = "overview", name = "Updates", icon = "system_update", build = overview },
    { key = "log", name = "Rebuild", icon = "terminal", build = log_page },
  }
  return ui.Item {
    id = "update-root", width = w, height = h,
    ui.Item {
      width = w, height = body_h,
      (controls.pages { id = "update", width = w, height = body_h, tab = model.tab, tabs = tabs }),
    },
    ui.Item {
      y = body_h, width = w, height = foot,
      ui.Item {
        y = S.xs, width = w, height = L.lh(theme.size.small),
        controls.note {
          id = "update-note", width = w,
          text = function()
            if model.message:get() ~= "" then return model.message:get() end
            if model.checking:get() > 0 then return "Asking the package managers" end
            local count = model.pending()
            return count == 0 and "Nothing waits" or (count .. " waiting")
          end,
        },
      },
      ui.Item {
        y = L.lh(theme.size.small) + S.s, width = w, height = P.BUTTON_H,
        P.buttons {
          width = w,
          { id = "update-check", label = "Check again", icon = "refresh", enabled = function() return model.checking:get() == 0 end,
            on_clicked = function() model.start() end },
          { id = "update-rebuild", label = "Rebuild", icon = "build", tone = "primary",
            visible = function() return model.nixos:get() and model.flake:get() ~= "" and not running() end,
            on_clicked = function() model.rebuild() end },
          { id = "update-cancel", label = "Stop", icon = "stop", visible = running, on_clicked = function() model.cancel() end },
        },
      },
    },
  }
end

return M
