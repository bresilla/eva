-- The window switcher (shell/window_switcher.lua): a plate of window cards in
-- the middle of the screen, and the choice a shape of the plate's own field,
-- swelling out of it and running to the next card. An application with more
-- windows than one shows a stack and their number.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local card = require("themes.layouts.window_card")
local S, C = theme.space, theme.color
local V = {}

local SWELL = S.s
local SEAM = 18

function V.build(model)
  local spatial, fade = theme.spring.spatial, theme.spring.effects
  local radius = L.control_round(2 * S.xl)
  local plate = model.plate
  local function slot(address) return model.slots:get()[address] or { x = 0, y = 0, width = 0, height = 0 } end

  local function chosen_box()
    local c = model.chosen()
    if not c then return { x = 0, y = 0, width = 0, height = 0 } end
    return slot(c.address)
  end
  -- The choice's box, on the springs the shape tracks.
  local marker = ui.Item { id = "switcher-choice",
    x = function() return chosen_box().x - SWELL end, y = function() return chosen_box().y - SWELL end,
    width = function() return chosen_box().width + 2 * SWELL end,
    height = function() return chosen_box().height + 2 * SWELL end,
    behavior = { x = spatial, y = spatial, width = spatial, height = spatial },
    stretch = theme.stretch and theme.stretch.drawer or nil,
    kit.surface { anchors = { fill = true }, z = 4, radius = radius, color = "transparent", border_width = 2,
      border_color = kit.stroke("hot") } }

  local field = ui.Sdf { id = "switcher-field", anchors = { fill = true, margins = -2 * S.xl },
    fill_color = function() return C.surfaceContainer end, blend = SEAM, blend_profile = "circular",
    shadow_color = "#00000060", shadow_blur = 12,
    ui.SdfShape { id = "switcher-plate", shape = "box", radius = radius, anchors = { fill = true, margins = 2 * S.xl } },
    ui.SdfShape { id = "switcher-swell", shape = "box", radius = radius, operation = "smooth_union",
      fill_color = function() return C.secondaryContainer end, track = marker } }

  local function delegate(row)
    local address = row.address
    local index = math.floor(row.index)
    local title = morf.signal("eva.switcher.card.title." .. address, row.title)
    local count = morf.signal("eva.switcher.card.count." .. address, math.floor(row.count))
    local class = row.class
    local function stacked(depth)
      return kit.surface { x = depth * S.xs, y = -depth * S.xs, z = -depth,
        width = function() return slot(address).width end, height = function() return slot(address).height end,
        radius = radius, color = function() return C.surfaceContainerHighest end,
        visible = function() return count:get() > depth end }
    end
    local badge = kit.surface { id = "switcher-count-" .. index, z = 3, width = S.xl, height = S.xl, radius = S.xl / 2,
      anchors = { top = true, right = true, top_margin = S.xs, right_margin = S.xs },
      color = function() return C.primary end, visible = function() return count:get() > 1 end,
      L.label { anchors = { center_in = true }, text = function() return tostring(count:get()) end,
        color = function() return C.onPrimary end } }
    return ui.Item { id = "switcher-card-" .. index,
      x = function() return slot(address).x end, y = function() return slot(address).y end,
      width = function() return slot(address).width end, height = function() return slot(address).height end,
      behavior = { x = spatial, y = spatial, width = spatial, height = spatial },
      stacked(2), stacked(1),
      card.picture { id = "switcher-picture-" .. index, radius = radius, glyph = 48,
        address = function() return address end, class = function() return class end,
        initial = function() return row.initial_class end, title = function() return title:get() end },
      ui.Item { anchors = { bottom = true, horizontal_center = true, bottom_margin = S.s }, z = 2,
        width = function() return math.max(40, slot(address).width - 2 * S.s) end, height = 28,
        card.caption { id = "switcher-title-" .. index, height = 28, class = function() return class end,
          initial = function() return row.initial_class end, title = function() return title:get() end,
          room = function() return math.max(40, slot(address).width - 2 * S.s) end } },
      badge,
      ui.MouseArea { id = "switcher-card-area-" .. index, anchors = { fill = true }, cursor = "pointer",
        accessible_role = "button", accessible_name = function() return title:get() end,
        on_entered = function() model.pick(index) end,
        on_clicked = function() model.pick(index, true) end },
    }, function(next_row)
      title:set(next_row.title)
      count:set(math.floor(next_row.count))
    end
  end

  local keys = ui.Item { id = "switcher-keys", width = 1, height = 1, tab_navigation = false,
    on_key_pressed = model.key, on_key_released = model.released }
  local box = ui.Item { id = "window-switcher",
    x = function() return plate:get().x end, y = function() return plate:get().y end,
    width = function() return plate:get().width end, height = function() return plate:get().height end,
    accessible_role = "dialog", accessible_name = "Window switcher",
    visible = function() return model.shown:get() end,
    opacity = function() return model.shown:get() and 1 or 0 end,
    scale = function() return model.shown:get() and 1 or .94 end,
    behavior = { opacity = fade, scale = spatial },
    field,
    ui.Repeater { id = "switcher-cards", model = model.rows, delegate = delegate },
    marker,
    ui.MouseArea { anchors = { fill = true }, z = -1,
      on_wheel = function(_, _, _, _, _, step) model.wheel(step) end } }

  local root = ui.Item { id = "window-switcher-root", anchors = { fill = true },
    visible = function() return model.opened:get() end, box, keys,
    ui.MouseArea { anchors = { fill = true }, z = -1, visible = function() return model.shown:get() end,
      on_clicked = function() model.cancel() end } }

  return { node = root, shown = function(open) keys.focus = open end }
end

return V
