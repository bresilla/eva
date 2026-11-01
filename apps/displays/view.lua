-- eva-displays' window: the monitors on a canvas to drag, the selected one's
-- settings, the countdown after applying, and the saved profiles.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local composites = require("themes.kit.composites")
local displays = require("lib.shell.displays")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

local TILES = 8
local SIDE = 360
local NARROW = 900
local CANVAS_MIN = 240

local function get(v) if type(v) == "function" then return v() end return v end

-- The scale and offset fitting the outputs in a canvas `w` by `h`.
local function fit(outputs, w, h)
  local left, top, right, bottom
  for _, o in ipairs(outputs) do
    if o.enabled then
      local ow, oh = displays.logical(o)
      left = left and math.min(left, o.x) or o.x
      top = top and math.min(top, o.y) or o.y
      right = right and math.max(right, o.x + ow) or o.x + ow
      bottom = bottom and math.max(bottom, o.y + oh) or o.y + oh
    end
  end
  if not left then return { scale = 0.1, x = 0, y = 0, left = 0, top = 0 } end
  local margin = S.xl
  local scale = math.min((w - 2 * margin) / math.max(1, right - left), (h - 2 * margin) / math.max(1, bottom - top))
  scale = math.max(0.01, scale)
  return {
    scale = scale, left = left, top = top,
    x = (w - (right - left) * scale) / 2, y = (h - (bottom - top) * scale) / 2,
  }
end

local function canvas(w, h)
  local area = kit.card { id = "displays-canvas", width = w, height = h, radius = kit.round(P.RADIUS) }
  local frozen
  local function frame() return frozen or fit(model.outputs:get(), get(w), get(h)) end
  local function tile(index)
    local function output() return model.outputs:get()[index] end
    local function shown()
      local o = output()
      return o ~= nil and o.enabled and o.mirror == ""
    end
    local function selected()
      local o = output()
      return o ~= nil and o.name == model.selected:get()
    end
    local function size()
      local o = output()
      if not o then return 1, 1 end
      local ow, oh = displays.logical(o)
      return math.max(1, ow * frame().scale), math.max(1, oh * frame().scale)
    end
    local grab
    local press = ui.MouseArea {
      id = "displays-tile-" .. index, cursor = "grab", visible = shown,
      accessible_name = function() local o = output() return o and o.name or "" end,
      x = function()
        local o, f = output(), frame()
        return o and f.x + (o.x - f.left) * f.scale or 0
      end,
      y = function()
        local o, f = output(), frame()
        return o and f.y + (o.y - f.top) * f.scale or 0
      end,
      width = function() local tw = size() return tw end,
      height = function() local _, th = size() return th end,
      on_pressed = function(sx, sy)
        local o = output()
        if not o then return end
        model.selected:set(o.name)
        frozen = frame()
        grab = { sx = sx, sy = sy, x = o.x, y = o.y, name = o.name }
      end,
      on_position_changed = function(sx, sy)
        if not grab then return end
        local f = frozen or frame()
        model.place(grab.name, grab.x + (sx - grab.sx) / f.scale, grab.y + (sy - grab.sy) / f.scale)
      end,
      on_released = function()
        if not grab then return end
        grab, frozen = nil, nil
        model.settle()
      end,
      kit.surface {
        anchors = { fill = true }, radius = kit.round(S.s),
        color = function() return selected() and C.primaryContainer or C.surfaceContainerHighest end,
        border_width = function() return selected() and 2 or 1 end,
        border_color = function() return selected() and C.primary or C.outlineVariant end,
      },
      ui.Column {
        anchors = { center_in = true }, gap = S.xxs, align = "center",
        kit.text {
          text = function() local o = output() return o and o.name or "" end, font_weight = 600,
          color = function() return selected() and C.onPrimaryContainer or C.onSurface end,
          font_size = theme.size.normal,
        },
        kit.text {
          text = function()
            local o = output()
            return o and ("%dx%d"):format(o.width, o.height) or ""
          end,
          color = function() return selected() and C.onPrimaryContainer or C.onSurfaceVariant end,
          font_size = theme.size.small,
        },
      },
    }
    return press
  end
  for index = 1, TILES do ui.reparent(tile(index), area) end
  return area
end

local function resolution_items()
  local items = {}
  for _, mode in ipairs(model.resolutions(model.output())) do
    items[#items + 1] = ("%d × %d"):format(mode.width, mode.height)
  end
  return items
end

local function settings(w)
  local inner = function() return P.inner(w) end
  local function row(id, title, control, visible)
    return ui.Item {
      id = id, width = inner, height = S.TARGET, visible = visible,
      kit.text { anchors = { vertical_center = true }, text = title, color = kit.ink("hi"), font_size = theme.size.normal },
      ui.Item { anchors = { right = true, vertical_center = true }, width = control.width_hint, height = S.TARGET, control.node },
    }
  end
  local function combo(id, items, current, on_changed)
    local field = 180
    local node = composites.combo_box {
      id = id, width = field, height = S.TARGET, items = items, current = current, variant = "dropdown",
      on_changed = on_changed,
    }
    return { node = node, width_hint = field }
  end
  local function selected() return model.selected:get() end
  local resolution = row("displays-resolution", "Resolution", combo("displays-resolution-field", resolution_items, function()
    local o = model.output()
    for i, mode in ipairs(model.resolutions(o)) do
      if o and mode.width == o.width and mode.height == o.height then return i end
    end
    return 1
  end, function(index)
    local mode = model.resolutions(model.output())[index]
    if mode then model.set_resolution(selected(), mode.width, mode.height) end
  end))
  local rate = row("displays-refresh", "Refresh", combo("displays-refresh-field", function()
    local items = {}
    for _, value in ipairs(model.refreshes(model.output())) do items[#items + 1] = ("%.2f Hz"):format(value) end
    return items
  end, function()
    local o = model.output()
    for i, value in ipairs(model.refreshes(o)) do
      if o and value == o.refresh then return i end
    end
    return 1
  end, function(index)
    local value = model.refreshes(model.output())[index]
    if value then model.set(selected(), "refresh", value) end
  end), function()
    local o = model.output()
    return o ~= nil and (o.refresh or 0) > 0
  end)
  local scale_labels = {}
  for i, value in ipairs(displays.SCALES) do scale_labels[i] = ("%d%%"):format(value * 100) end
  local scale = row("displays-scale", "Scale", combo("displays-scale-field", scale_labels, function()
    local o = model.output()
    for i, value in ipairs(displays.SCALES) do
      if o and value == o.scale then return i end
    end
    return 1
  end, function(index) model.set(selected(), "scale", displays.SCALES[index]) end))
  local rotation_labels = {}
  for i, item in ipairs(displays.ROTATIONS) do rotation_labels[i] = item[2] end
  local rotation = row("displays-rotation", "Rotation", combo("displays-rotation-field", rotation_labels, function()
    local o = model.output()
    return o and (o.transform % 4) + 1 or 1
  end, function(index) model.set(selected(), "transform", displays.ROTATIONS[index][1]) end))
  local mirror
  if displays.supports().mirror then
    mirror = row("displays-mirror", "Mirror", combo("displays-mirror-field", function()
      local items = { "None" }
      for _, o in ipairs(model.outputs:get()) do
        if o.name ~= selected() then items[#items + 1] = o.name end
      end
      return items
    end, function()
      local o = model.output()
      local index = 1
      for _, other in ipairs(model.outputs:get()) do
        if other.name ~= selected() then
          index = index + 1
          if o and other.name == o.mirror then return index end
        end
      end
      return 1
    end, function(index)
      local i = 1
      for _, other in ipairs(model.outputs:get()) do
        if other.name ~= selected() then
          i = i + 1
          if i == index then model.set(selected(), "mirror", other.name) return end
        end
      end
      model.set(selected(), "mirror", "")
    end))
  end
  return P.section {
    id = "displays-settings", width = w,
    title = function()
      local o = model.output()
      return o and o.name or "Monitor"
    end,
    P.row {
      id = "displays-enabled", width = inner, height = S.TARGET + S.s, title = function()
        local o = model.output()
        if not o then return "No monitor" end
        local words = (o.make .. " " .. o.model):match("^%s*(.-)%s*$")
        return words ~= "" and words or o.name
      end,
      trailing = P.switch {
        id = "displays-enabled-switch", name = "Use this monitor",
        on = function() local o = model.output() return o ~= nil and o.enabled end,
        on_toggled = function(on) model.set(selected(), "enabled", on) end,
      },
    },
    resolution, rate, scale, rotation,
    P.row {
      id = "displays-vrr", width = inner, height = S.TARGET + S.s, title = "Variable refresh rate",
      trailing = P.switch {
        id = "displays-vrr-switch", name = "Variable refresh rate",
        on = function() local o = model.output() return o ~= nil and o.vrr end,
        on_toggled = function(on) model.set(selected(), "vrr", on) end,
      },
    },
    mirror,
  }
end

-- The saved profiles: a pool of rows following the list.
local function profiles(w)
  local inner = function() return P.inner(w) end
  local function at(index) return model.profiles:get()[index] end
  local rows = {}
  for index = 1, 6 do
    local function shown() return at(index) ~= nil end
    rows[#rows + 1] = P.row {
      id = "displays-profile-" .. index, width = inner, visible = shown, icon = "desktop_windows",
      title = function() local p = at(index) return p and p.name or "" end,
      subtitle = function()
        local p = at(index)
        if not p then return "" end
        return p.auto and "Applies when these monitors connect" or "Applied by hand"
      end,
      on_clicked = function() local p = at(index) if p then model.use_profile(p.name) end end,
      trailing = ui.Row {
        gap = S.s, align = "center",
        P.switch {
          id = "displays-profile-auto-" .. index, name = "Apply by itself",
          on = function() local p = at(index) return p ~= nil and p.auto end,
          on_toggled = function(on) local p = at(index) if p then model.set_auto(p.name, on) end end,
        },
        L.icon_button {
          id = "displays-profile-delete-" .. index, icon = "delete", name = "Delete profile",
          width = S.TARGET, height = S.TARGET,
          on_clicked = function() local p = at(index) if p then model.delete_profile(p.name) end end,
        },
      },
    }
  end
  local name = morf.signal("displays.profile.name", "")
  local field = kit.text_field("entry", {
    id = "displays-profile-name", width = function() return math.max(1, P.inner(w) - 120 - S.s) end, height = S.TARGET,
    placeholder = "Profile name", text = function() return name:get() end,
    color = kit.ink("hi"), placeholder_color = kit.ink("lo"),
    on_text_changed = function(value) name:set(value) end,
    on_accepted = function(value) if model.save_profile(value) then name:set("") end end,
  })
  rows[#rows + 1] = ui.Row {
    gap = S.s, align = "center", field,
    P.button {
      id = "displays-profile-save", label = "Save", width = 120,
      on_clicked = function() if model.save_profile(name:get()) then name:set("") end end,
    },
  }
  rows.id, rows.width, rows.title = "displays-profiles", w, "Profiles"
  return P.section(rows)
end

local function actions(w)
  return P.buttons {
    width = w, visible = function() return model.countdown:get() == 0 end,
    { id = "displays-identify", label = "Identify", icon = "tag", on_clicked = model.identify },
    {
      id = "displays-apply", label = "Apply", icon = "check", tone = "primary",
      on_clicked = model.apply,
    },
  }
end

-- The bar in the buttons' place while a change waits to be kept.
local function confirm(w, y, h)
  return ui.Item {
    id = "displays-confirm", width = w, y = y, height = h, z = 10,
    visible = function() return model.countdown:get() > 0 end,
    kit.card {
      anchors = { fill = true }, radius = kit.round(P.RADIUS),
      kit.text {
        id = "displays-confirm-text", x = S.l, anchors = { vertical_center = true }, color = kit.ink("hi"),
        font_size = theme.size.normal,
        text = function() return ("Keep this arrangement? Reverting in %d s"):format(model.countdown:get()) end,
      },
      ui.Row {
        anchors = { right = true, right_margin = S.m, vertical_center = true }, gap = S.s,
        P.button { id = "displays-revert", label = "Revert", on_clicked = model.revert },
        P.button { id = "displays-keep", label = "Keep", tone = "primary", on_clicked = model.keep },
      },
    },
  }
end

local function status(w)
  return kit.text {
    id = "displays-status", width = w, height = L.lh(theme.size.small), font_size = theme.size.small,
    color = kit.ink("lo"), elide = "right",
    text = function() return model.message:get() end,
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local function narrow() return w() < NARROW end
  local function panel_w() return narrow() and w() or SIDE end
  local foot = S.TARGET + S.m + L.lh(theme.size.small) + S.s
  local function canvas_w() return narrow() and w() or math.max(1, w() - SIDE - S.l) end
  local function canvas_h()
    if narrow() then return math.max(CANVAS_MIN, math.min(h() * 0.34, 320)) end
    return math.max(1, h() - foot - S.m)
  end
  local function page_h()
    if narrow() then return math.max(1, h() - canvas_h() - foot - S.m) end
    return math.max(1, h() - S.m)
  end
  local page = P.page {
    id = "displays-panel", width = panel_w, height = page_h,
    settings(panel_w), profiles(panel_w),
  }
  return ui.Item {
    id = "displays-root", width = w, height = h,
    canvas(canvas_w, canvas_h),
    ui.Column {
      gap = S.s, y = function() return canvas_h() + S.m end, width = canvas_w,
      status(canvas_w), actions(canvas_w),
    },
    ui.Item {
      x = function() return narrow() and 0 or canvas_w() + S.l end,
      y = function() return narrow() and canvas_h() + foot + S.m or 0 end,
      width = panel_w, height = page_h, page,
    },
    confirm(canvas_w, function() return canvas_h() + S.m end, foot),
  }
end

return M
