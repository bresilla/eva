-- The Displays page's arrangement (shell/displays_model.lua): the monitors on a
-- canvas to drag, the countdown after applying, the selected one's settings,
-- and the saved profiles, each a section of the page.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local composites = require("themes.kit.composites")
local displays = require("lib.shell.displays")
local C, S = theme.color, theme.space

local M = {}

local TILES = 8
local CANVAS_H = 320

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
  -- A quarter of the canvas round the monitors: room to drag one about.
  local mx, my = math.max(S.xl, w / 4), math.max(S.xl, h / 4)
  local scale = math.min((w - 2 * mx) / math.max(1, right - left), (h - 2 * my) / math.max(1, bottom - top))
  scale = math.max(0.01, scale)
  return {
    scale = scale, left = left, top = top,
    x = (w - (right - left) * scale) / 2, y = (h - (bottom - top) * scale) / 2,
  }
end

-- The monitors, each a tile to drag; a drag snaps to the others' edges.
local function canvas(model, w, h)
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
    -- A drag on a monitor is its own, not the page's scroll.
    return ui.MouseArea {
      id = "displays-tile-" .. index, cursor = "grab", visible = shown, drag_axis = "both",
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
            return o and ("%d×%d"):format(o.width, o.height) or ""
          end,
          color = function() return selected() and C.onPrimaryContainer or C.onSurfaceVariant end,
          font_size = theme.size.small,
        },
      },
    }
  end
  for index = 1, TILES do ui.reparent(tile(index), area) end
  return area
end

--- The canvas, what the last change said, and Identify and Apply; while a
--- change waits to be kept, Keep and Revert in their place with the seconds left.
function M.arrangement(model, w)
  local inner = P.inner(w)
  local function waiting() return model.countdown:get() > 0 end
  return P.section { id = "displays-arrangement", width = w, title = "Arrangement",
    canvas(model, inner, CANVAS_H),
    kit.text {
      id = "displays-status", width = inner, elide = "right", font_size = theme.size.small, color = kit.ink("lo"),
      visible = function() return model.message:get() ~= "" end, text = function() return model.message:get() end,
    },
    ui.Item { width = inner, height = P.BUTTON_H, visible = function() return not waiting() end,
      P.buttons { width = inner,
        { id = "displays-identify", label = "Identify", icon = "tag", on_clicked = model.identify },
        { id = "displays-apply", label = "Apply", icon = "check", tone = "primary", on_clicked = model.apply },
      } },
    ui.Column { id = "displays-confirm", width = inner, gap = S.s, visible = waiting,
      kit.text {
        id = "displays-confirm-text", width = inner, color = kit.ink("hi"), font_size = theme.size.normal,
        text = function() return ("Keep this arrangement? Reverting in %d s"):format(model.countdown:get()) end,
      },
      P.buttons { width = inner,
        { id = "displays-revert", label = "Revert", on_clicked = model.revert },
        { id = "displays-keep", label = "Keep", tone = "primary", on_clicked = model.keep },
      },
    },
  }
end

local function resolution_items(model)
  local items = {}
  for _, mode in ipairs(model.resolutions(model.output())) do
    items[#items + 1] = ("%d×%d"):format(mode.width, mode.height)
  end
  return items
end

--- The selected monitor: on or off, its mode, refresh, scale, rotation,
--- variable refresh and the monitor it mirrors.
function M.monitor(model, w)
  local inner = P.inner(w)
  local FIELD = 180
  local ICONS = { ["displays-resolution"] = "aspect_ratio", ["displays-refresh"] = "speed", ["displays-scale"] = "zoom_in",
    ["displays-rotation"] = "screen_rotation", ["displays-mirror"] = "screen_share" }
  local function row(id, title, control, visible)
    return P.row { id = id, width = inner, icon = ICONS[id], title = title, visible = visible,
      trailing = ui.Item { width = FIELD, height = S.TARGET, control } }
  end
  local function combo(id, items, current, on_changed)
    return (composites.combo_box {
      id = id, width = FIELD, height = S.TARGET, items = items, current = current, variant = "select",
      on_changed = on_changed,
    })
  end
  local function selected() return model.selected:get() end
  local resolution = row("displays-resolution", "Resolution", combo("displays-resolution-field",
    function() return resolution_items(model) end, function()
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
      id = "displays-enabled", width = inner, icon = "monitor",
      on = function() local o = model.output() return o ~= nil and o.enabled end,
      title = function()
        local o = model.output()
        if not o then return "No monitor" end
        local words = ((o.make or "") .. " " .. (o.model or "")):match("^%s*(.-)%s*$")
        return words ~= "" and words or o.name
      end,
      subtitle = function()
        local o = model.output()
        if not o then return "" end
        if o.enabled == false then return "Off" end
        local words = ((o.make or "") .. (o.model or "")):match("%S")
        return words and o.name or "In use"
      end,
      trailing = P.switch {
        id = "displays-enabled-switch", name = "Use this monitor",
        on = function() local o = model.output() return o ~= nil and o.enabled end,
        on_toggled = function(on) model.set(selected(), "enabled", on) end,
      },
    },
    resolution, rate, scale, rotation,
    P.row {
      id = "displays-vrr", width = inner, icon = "motion_blur", title = "Variable refresh rate",
      trailing = P.switch {
        id = "displays-vrr-switch", name = "Variable refresh rate",
        on = function() local o = model.output() return o ~= nil and o.vrr end,
        on_toggled = function(on) model.set(selected(), "vrr", on) end,
      },
    },
    mirror,
  }
end

--- The saved profiles, a pool of rows following the list, and a name to save
--- the arrangement under.
function M.profiles(model, w)
  local inner = P.inner(w)
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
  local SAVE = 120
  local box, field = P.field {
    id = "displays-profile-name", width = math.max(1, inner - SAVE - S.s), placeholder = "Profile name",
    on_changed = function(value) name:set(value) end,
    on_accepted = function(value) if model.save_profile(value) then name:set("") field.text = "" end end,
  }
  rows[#rows + 1] = ui.Row {
    gap = S.s, align = "center", box,
    P.button {
      id = "displays-profile-save", label = "Save", tone = "primary", width = SAVE,
      on_clicked = function() if model.save_profile(name:get()) then name:set("") field.text = "" end end,
    },
  }
  rows.id, rows.width, rows.title = "displays-profiles", w, "Profiles"
  return P.section(rows)
end

return M
