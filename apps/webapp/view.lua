-- eva-webapp's window: a name and an address to make an app from, and the apps
-- made, each with its icon.
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
local ICON = 40
local ADD = 120

local function get(v) if type(v) == "function" then return v() end return v end

local function app_row(index, item, w)
  local right = S.TARGET * 2 + S.s
  local function text() return math.max(1, get(w) - ICON - S.m - right - S.s) end
  return ui.Item {
    width = w, height = controls.ROW_H,
    ui.Image {
      id = "webapp-icon-" .. index, width = ICON, height = ICON, anchors = { vertical_center = true },
      fill_mode = "preserve_aspect_fit", source = function() local row = item() return row and row.icon or "" end,
    },
    ui.Column {
      x = ICON + S.m, anchors = { vertical_center = true }, gap = S.xxs,
      kit.text {
        id = "webapp-name-" .. index, width = text, elide = "right", font_size = theme.size.normal, font_weight = 500,
        color = kit.ink("hi"), text = function() local row = item() return row and row.name or "" end,
      },
      kit.text {
        id = "webapp-url-" .. index, width = text, elide = "right", font_size = theme.size.small, color = kit.ink("lo"),
        text = function() local row = item() return row and row.url or "" end,
      },
    },
    ui.Row {
      anchors = { right = true, vertical_center = true }, gap = S.s, align = "center",
      L.icon_button {
        id = "webapp-open-" .. index, icon = "open_in_new", name = "Open", width = S.TARGET, height = S.TARGET,
        on_clicked = function() local row = item() if row then model.open(row) end end,
      },
      L.icon_button {
        id = "webapp-delete-" .. index, icon = "delete", name = "Remove", width = S.TARGET, height = S.TARGET,
        on_clicked = function() local row = item() if row then model.remove(row) end end,
      },
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local function rows() return model.rows:get() end
  local function half() return math.max(1, (w() - ADD - S.s * 2) / 2) end
  local top = S.TARGET + L.lh(theme.size.small) + S.m
  local function body() return math.max(1, h() - top) end
  return ui.Item {
    id = "webapp-root", width = w, height = h,
    ui.Row {
      gap = S.s, align = "center",
      controls.entry { id = "webapp-add-name", width = half, value = model.name, placeholder = "Name", focus = true },
      controls.entry {
        id = "webapp-add-url", width = half, value = model.url, placeholder = "Web address",
        on_accepted = function() model.submit() end,
      },
      P.button {
        id = "webapp-add", label = "Add", tone = "primary", width = ADD, enabled = function() return not model.busy:get() end,
        on_clicked = function() model.submit() end,
      },
    },
    ui.Item {
      y = S.TARGET + S.xs, width = w, height = L.lh(theme.size.small),
      controls.note {
        id = "webapp-message", width = w,
        text = function()
          if model.busy:get() then return "Fetching its icon" end
          local message = model.message:get()
          if message ~= "" then return message end
          local _, why = model.browser()
          return why or ""
        end,
      },
    },
    ui.Item {
      y = top, width = w, height = body,
      P.empty {
        id = "webapp-empty", icon = "language", title = "No web apps", width = w,
        text = "Give a site a name, and it opens in a window of its own.",
        visible = function() return #rows() == 0 end,
      },
      controls.list {
        id = "webapp-list", width = w, height = body, count = ROWS, items = rows,
        build = function(index, item) return app_row(index, item, w) end,
      },
    },
  }
end

return M
