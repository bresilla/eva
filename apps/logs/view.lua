-- eva-logs' window: the words and choices that narrow the journal, over a pool of
-- rows rebound as it scrolls, the newest first, and the chosen entry in full.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local fit = require("themes.layouts.fit")
local controls = require("common.controls")
local model = require("model")
local S, C = theme.space, theme.color

local M = {}

local ROW_H = 48
local MEDIUM = 600
local DOT = S.s

local function get(v) if type(v) == "function" then return v() end return v end

local function tone(priority)
  if priority <= 3 then return kit.signal("alert")() end
  if priority == 4 then return kit.signal("warn")() end
  return kit.ink("lo")()
end

local function entry_row(_, s)
  local function row() return s.row() or {} end
  local index = s.index()
  local time_w = 72
  local function text_w() return math.max(1, s.width() - DOT - S.m - S.s) end
  local node = ui.Item {
    width = function() return s.width() end, height = ROW_H,
    ui.Rect {
      anchors = { fill = true }, radius = kit.round(S.m),
      color = function()
        if s.current() then return C.primary:alpha(0.14) end
        return s.hovered() and C.onSurface:alpha(0.05) or C.onSurface:alpha(0)
      end,
      behavior = { color = { duration = theme.duration.small } },
    },
    ui.Rect {
      x = S.xs, y = (ROW_H - DOT) / 2, width = DOT, height = DOT, radius = DOT / 2,
      color = function() return tone(row().priority or 6) end,
    },
    ui.Column {
      x = DOT + S.m, width = text_w, gap = S.xxs, anchors = { vertical_center = true }, clip = true,
      ui.Item {
        width = text_w, height = L.lh(P.SUB),
        kit.text {
          id = "logs-name-" .. index, width = function() return math.max(1, text_w() - time_w) end, elide = "right",
          font_size = P.SUB, font_weight = 500, color = kit.ink("hi"), text = function() return row().name or "" end,
        },
        kit.text {
          id = "logs-time-" .. index, anchors = { right = true }, width = time_w, horizontal_alignment = "right",
          font_size = P.SUB, color = kit.ink("lo"),
          text = function() local r = row() return r.at and model.time(r) or "" end,
        },
      },
      kit.text {
        id = "logs-text-" .. index, width = text_w, elide = "right", font_size = P.SUB,
        color = function() return tone(row().priority or 6) end, text = function() return row().text or "" end,
      },
    },
  }
  return node, function() end
end

local function fact(id, label, value, w)
  return ui.Item {
    width = w, height = L.lh(P.SUB),
    kit.text { width = function() return get(w) * 0.34 end, elide = "right", font_size = P.SUB, color = kit.ink("lo"), text = label },
    kit.text {
      id = id, anchors = { right = true }, width = function() return get(w) * 0.66 end, elide = "left",
      horizontal_alignment = "right", font_size = P.SUB, font_weight = 500, color = kit.ink("hi"), text = value,
    },
  }
end

local function detail_card(w, h)
  local function chosen() return (model.chosen()) or {} end
  local function inner() return get(w) - 2 * P.PAD end
  return kit.card {
    id = "logs-detail", width = w, height = h, radius = kit.round(P.RADIUS), clip = true,
    ui.Item {
      x = P.PAD, y = P.PAD, width = inner, height = S.TARGET,
      kit.text {
        id = "logs-detail-name", width = function() return inner() - S.TARGET - S.s end, elide = "right",
        anchors = { vertical_center = true }, font_size = L.SIZE.title, color = kit.ink("hi"),
        text = function() return chosen().name or "" end,
      },
      ui.Item {
        anchors = { right = true }, width = S.TARGET, height = S.TARGET,
        L.icon_button {
          id = "logs-detail-close", icon = "close", name = "Close details", width = S.TARGET, height = S.TARGET,
          on_clicked = function() model.select("") end,
        },
      },
    },
    (kit.scroll {
      id = "logs-detail-scroll", x = P.PAD, y = P.PAD + S.TARGET + S.s, width = inner, clip = true,
      height = function() return math.max(1, get(h) - 2 * P.PAD - S.TARGET - S.s - P.BUTTON_H - S.m) end,
      ui.Column {
        width = inner, gap = S.s,
        kit.text {
          id = "logs-detail-text", width = inner, wrap = true, font_size = theme.size.normal, color = kit.ink("hi"),
          text = function() return chosen().text or "" end,
        },
        L.rule { width = inner, strength = "faint" },
        fact("logs-detail-time", "Time", function()
          local entry = chosen()
          return entry.at and model.time(entry, "%-d %b %H:%M:%S") or ""
        end, inner),
        fact("logs-detail-priority", "Priority", function()
          local level = chosen().priority
          return level and model.LEVELS[math.floor(level)] or ""
        end, inner),
        fact("logs-detail-unit", "Unit", function() return chosen().unit or "" end, inner),
        fact("logs-detail-pid", "Process", function() return tostring(chosen().pid or "") end, inner),
      },
    }),
    ui.Item {
      x = P.PAD, y = function() return get(h) - P.PAD - P.BUTTON_H end, width = inner, height = P.BUTTON_H,
      P.buttons {
        width = inner,
        { id = "logs-only-unit", label = "Only this unit", icon = "filter_alt", visible = function() return (chosen().unit or "") ~= "" end,
          on_clicked = function() model.set_unit(chosen().unit) end },
        { id = "logs-copy", label = "Copy", icon = "content_copy", on_clicked = model.copy },
      },
    },
  }
end

--- The header's follow.
function M.actions()
  return L.icon_button {
    id = "logs-follow", name = "Follow", width = S.TARGET, height = S.TARGET,
    icon = function() return model.follow:get() and "pause" or "play_arrow" end,
    on = function() return model.running:get() end,
    on_clicked = function() model.set_follow(not model.follow:get()) end,
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local list_node
  local function roomy() return get(w) >= MEDIUM end
  local function open() return model.selected:get() ~= "" end
  local function half() return roomy() and (get(w) - S.s) / 2 or get(w) end
  local function top()
    return (roomy() and S.TARGET * 2 + S.s or S.TARGET * 4 + S.s * 3) + L.lh(theme.size.small) + S.s * 2
  end
  local function body_h() return math.max(1, get(h) - top()) end
  local list_w = fit.beside(w, open)
  list_node = kit.widgets.virtual_list {
    id = "logs-list", width = list_w, height = body_h, rows = model.rows, row_height = ROW_H,
    delegate = entry_row, current = model.selected_index,
    on_current_changed = function(index) model.select_row(index) end,
    on_key_pressed = function(_, _, _, _, key)
      if key ~= "Escape" or not open() then return false end
      model.select("")
      return true
    end,
  }
  local search = kit.text_field("entry", {
    id = "logs-search", width = half, height = S.TARGET, focus = true, placeholder = "Search, Return for the whole journal",
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"),
    text = function() return model.query:get() end,
    on_text_changed = function(value) model.query:set(value) end,
    on_accepted = function(value) model.search(value) end,
    on_key_pressed = function(_, _, _, _, key)
      if key ~= "Down" then return false end
      require("morf").focus.set(list_node, true)
      return true
    end,
  })
  local unit = controls.entry {
    id = "logs-unit", width = half, value = model.unit, placeholder = "Unit, Return to narrow to it",
    on_accepted = function(value) model.set_unit(value) end,
  }
  local function line(column) return ({ 0, roomy() and 0 or S.TARGET + S.s, S.TARGET + S.s, roomy() and S.TARGET + S.s or (S.TARGET + S.s) * 3 })[column] end
  return ui.Item {
    id = "logs-root", width = w, height = h,
    search,
    ui.Item { x = function() return roomy() and half() + S.s or 0 end, y = function() return line(2) end, width = half, height = S.TARGET, unit },
    ui.Item {
      y = function() return roomy() and line(3) or (S.TARGET + S.s) * 2 end, width = half, height = S.TARGET,
      controls.segments {
        id = "logs-priority", items = { "All", "Info", "Warnings", "Errors" }, width = half,
        current = function() return model.priority:get() end, on_changed = model.set_priority,
      },
    },
    ui.Item {
      x = function() return roomy() and half() + S.s or 0 end, y = function() return line(4) end, width = half, height = S.TARGET,
      controls.segments {
        id = "logs-boot", items = { "This boot", "Last boot" }, width = half,
        current = function() return model.boot:get() end, on_changed = model.set_boot,
      },
    },
    ui.Item {
      y = function() return top() - L.lh(theme.size.small) - S.xs end, width = w, height = L.lh(theme.size.small),
      controls.note {
        id = "logs-note", width = w,
        text = function()
          if model.message:get() ~= "" then return model.message:get() end
          local shown, kept = model.shown:get(), model.kept:get()
          local state = model.running:get() and ", following" or ""
          if shown ~= kept then return ("%d of %d entries%s"):format(shown, kept, state) end
          return ("%d entries%s"):format(kept, state)
        end,
      },
    },
    ui.Item {
      y = top, width = list_w, height = body_h,
      list_node,
      P.empty {
        id = "logs-empty", icon = "article", title = "Nothing here", width = list_w,
        text = function()
          if model.missing:get() then return "This system has no journalctl." end
          return "No entry matches what is chosen."
        end,
        visible = function() return model.shown:get() == 0 end,
      },
    },
    ui.Item {
      y = top, width = w, height = body_h,
      fit.sheet { id = "logs-sheet", width = w, height = body_h, open = open, build = detail_card },
    },
  }
end

return M
