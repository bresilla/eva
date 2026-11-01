-- eva-keys' window: a search field over the list of bindings. Pressing a row
-- listens for its new chord; a chord another row has waits to be confirmed.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local model = require("model")
local S = theme.space

local M = {}

local ROWS = 200
local KEYS = 280
local NARROW = 620

local function row(index, w, found)
  local function item() return found()[index] end
  local function narrow() return w() < NARROW end
  local function keys_w() return narrow() and w() * 0.45 or KEYS end
  local function listening() local it = item() return it ~= nil and model.recording:get() == it.id end
  local function custom() local it = item() return it ~= nil and it.custom == true end
  local function room() return custom() and S.TARGET + S.xs or 0 end
  return ui.Item {
    id = "keys-row-" .. index, width = w, height = S.TARGET,
    visible = function() return item() ~= nil end,
    kit.action {
      id = "keys-row-" .. index .. "-press", cursor = "pointer", anchors = { fill = true },
      accessible_name = function() local it = item() return it and ("Change " .. it.what) or "" end,
      enabled = function() local it = item() return it ~= nil and it.editable == true and model.can_edit() end,
      on_clicked = function() local it = item() if it then model.record(it.id) end end,
      kit.text {
        id = "keys-row-" .. index .. "-keys", width = keys_w, anchors = { vertical_center = true }, elide = "right",
        font_size = theme.size.normal, color = kit.ink("accent"),
        text = function()
          if listening() then return "Press the keys" end
          local it = item()
          return it and (it.keys ~= "" and it.keys or "Not bound") or ""
        end,
      },
      kit.text {
        id = "keys-row-" .. index .. "-what", x = function() return keys_w() + S.m end,
        width = function() return math.max(1, w() - keys_w() - S.m - room()) end,
        anchors = { vertical_center = true }, elide = "right",
        font_size = theme.size.normal, color = kit.ink("hi"),
        text = function() local it = item() return it and it.what or "" end,
      },
    },
    kit.action {
      id = "keys-row-" .. index .. "-reset", width = S.TARGET, height = S.TARGET, cursor = "pointer", z = 2,
      anchors = { right = true }, accessible_name = "Back to the default", visible = custom,
      on_clicked = function() local it = item() if it then model.reset(it.id) end end,
      kit.icon("restart_alt", 20, kit.ink("lo"), { anchors = { center_in = true } }),
    },
  }
end

--- The bar along the foot, while a chord is awaited or collides.
local function notice(w)
  local waiting = function() return model.pending:get() ~= false end
  local function shown() return waiting() or model.recording:get() ~= "" or model.message:get() ~= "" end
  local choose = 2 * (120 + S.s)
  return ui.Item {
    id = "keys-notice", z = 3, width = w, height = S.TARGET, anchors = { bottom = true }, visible = shown,
    kit.text {
      id = "keys-notice-text", anchors = { vertical_center = true }, elide = "right",
      width = function() return math.max(1, w() - (waiting() and choose or 0)) end,
      font_size = theme.size.normal, color = kit.ink("hi"),
      text = function()
        if waiting() then return model.clash_text() end
        if model.recording:get() ~= "" then return "Press the new keys, or Escape to leave it" end
        return model.message:get()
      end,
    },
    ui.Row {
      anchors = { right = true, vertical_center = true }, gap = S.s, visible = waiting,
      P.button { id = "keys-confirm", label = "Use it", width = 120, tone = "primary", on_clicked = model.confirm },
      P.button { id = "keys-cancel", label = "Cancel", width = 120, on_clicked = model.cancel },
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local found_list, found_query, found_loaded
  local function found()
    local query, loaded = model.query:get(), model.loaded:get()
    if query ~= found_query or loaded ~= found_loaded then
      found_query, found_loaded = query, loaded
      found_list = model.found()
    end
    return found_list
  end
  local function listening() return model.recording:get() ~= "" end
  local field = kit.text_field("entry", {
    id = "keys-search", width = w, height = S.TARGET, placeholder = "Search the bindings",
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"), focus = function() return not listening() end,
    on_key_pressed = model.take,
    text = function() return model.query:get() end,
    on_text_changed = function(value) model.query:set(value) end,
  })
  local list = { gap = S.xxs, width = w }
  for index = 1, ROWS do list[index] = row(index, w, found) end
  local foot = S.TARGET + S.m
  local scroll = kit.scroll {
    id = "keys-list", width = w, clip = true,
    height = function() return math.max(1, h() - 2 * foot) end,
    ui.Column(list),
  }
  return ui.Item {
    id = "keys-root", width = w, height = h,
    ui.MouseArea { id = "keys-listen", width = 1, height = 1, focus = listening, on_key_pressed = model.take },
    field,
    ui.Item { y = foot, width = w, height = function() return math.max(1, h() - 2 * foot) end, scroll },
    notice(w),
    kit.text {
      id = "keys-hint", z = 2, anchors = { bottom = true, bottom_margin = S.xs }, font_size = theme.size.small, color = kit.ink("lo"),
      text = "Press a row to give it new keys",
      visible = function()
        for _, item in ipairs(model.rows:get()) do if item.custom then return false end end
        return model.can_edit() and model.recording:get() == "" and not model.pending:get() and model.message:get() == ""
      end,
    },
    kit.text {
      id = "keys-count", z = 2, anchors = { right = true, bottom = true, bottom_margin = S.xs },
      visible = function() return model.recording:get() == "" and not model.pending:get() and model.message:get() == "" end,
      font_size = theme.size.small, color = kit.ink("lo"),
      text = function()
        local shown = #found()
        return shown == 1 and "1 binding" or (shown .. " bindings")
      end,
    },
    P.button { id = "keys-reset-all", label = "Reset all", width = 120, height = S.TARGET, z = 2,
      anchors = { bottom = true }, visible = function()
        for _, item in ipairs(model.rows:get()) do if item.custom then return model.recording:get() == "" and not model.pending:get() end end
        return false
      end, on_clicked = model.reset_all },
  }
end

return M
