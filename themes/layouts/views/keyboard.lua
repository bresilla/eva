-- The shell's own keyboard: the shared panel of keys (themes/keyboard.lua), with
-- a handle and the strip of offers above it and the emoji in its place. What
-- belongs here stays out of that panel, which the lock and the greeter use too.
local morf = require("morf")
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local C = theme.color
local S = theme.space
local V = {}

-- A board's share of the panel in each stance.
local ONE_HAND, FLOATING, SPLIT = .8, .8, .62

function V.build(model)
  local shared = require("themes.keyboard")
  local responsive = require("responsive")
  local state = require("keyboard_model")
  local config = require("config")
  local boards = require("keyboard_board")
  local PAD = shared.PAD
  local W = responsive.fit(shared.MAX_WIDTH, 0)
  local _, screen_h = responsive.size()
  local HANDLE, STRIP = S.l, S.TARGET
  -- The theme styles the keys: its colours, and its own key face.
  local look = kit.keyboard_look {
    panel = function() return C.surfaceContainer:alpha(0) end,
    key = function() return C.surfaceContainerHighest end,
    key_dim = function() return C.surfaceContainerHigh end,
    accent = kit.signal("accent"), on_accent = function() return C.onPrimary end,
    text = kit.ink("hi"), dim = kit.ink("lo"),
    press = function() return C.secondaryContainer end,
    font = theme.font, radius = theme.key_radius, icons = theme.icon_font,
  }
  local gestures = require("keyboard_gestures")
  local contacts = gestures.contacts("keyboard")

  local function floating() return config.get("keyboard.floating") == true end
  local function one_handed()
    return not floating() and config.get("keyboard.hand") ~= "both"
  end
  local function split()
    return config.get("keyboard.split") == true and not floating() and not one_handed()
      and W >= responsive.MEDIUM
  end
  -- How wide the keys stand now, and how far apart the halves are.
  local function stance()
    local inner = W - 2 * PAD
    if floating() then return math.floor(inner * FLOATING), 0 end
    if one_handed() then return math.floor(inner * ONE_HAND), 0 end
    if split() then
      local keys = math.floor(inner * SPLIT)
      return keys, inner - keys
    end
    return inner, 0
  end
  local function fitted()
    local tallest = math.floor((screen_h * .5 - STRIP - HANDLE - 2 * PAD) / 4.4)
    local metrics = shared.metrics(W - 2 * PAD, tallest)
    -- A finger's target on a phone, before the person's own scale.
    local base = metrics.key_height
    if responsive.phone() then base = math.max(base, math.min(S.TOUCH, tallest)) end
    metrics.key_height = math.max(30, math.floor(base * config.get("keyboard.height")))
    return metrics
  end
  local function shape_of()
    local keys, apart = stance()
    local metrics = fitted()
    return table.concat({ keys, apart, metrics.key_height, tostring(config.get("keyboard.number_row")),
      state.layout().id }, "/")
  end

  local generation = morf.signal("eva.keyboard.board", 0)
  local current
  local function board_x()
    generation:get()
    if not one_handed() then return 0 end
    if config.get("keyboard.hand") == "left" then return 0 end
    return W - current.width
  end
  local host = ui.Item { id = "eva.keyboard.boards", x = board_x, y = HANDLE + STRIP, width = W, height = 1,
    visible = function() return state.pane:get() == "keys" end,
    behavior = { x = theme.spring.spatial } }

  local function build_board()
    local before = current
    local keys_w, apart = stance()
    local metrics = fitted()
    local seam = boards.new {
      action = kit.action, face = look.key_face, active = model.active, layout = state.layout(),
      width = keys_w, gap = metrics.gap, key_height = metrics.key_height, split = apart,
      number_row = config.get("keyboard.number_row") == true,
      send = model.strike, pressed = model.pressed, move = model.move,
    }
    local mode = before and before.panel.keys.mode:get() or "full"
    local panel, seen = boards.capture(function()
      return shared.panel {
        prefix = "eva.osk", width = keys_w + 2 * PAD, action = seam.action, key_face = seam.face,
        look = look, send = seam.send, active = model.active, touch = contacts,
        metrics = metrics, mode = mode, numbers = seam.numbers,
      }
    end)
    seam.adopt(panel.keys, seen, "eva.osk")
    ui.reparent(panel.content, host)
    current = { panel = panel, seam = seam, shape = shape_of(), width = keys_w + 2 * PAD }
    if before then
      local page = before.panel.keys.page:get()
      panel.keys.page:set(page)
      panel.keys.shift:set(before.panel.keys.shift:get())
      ui.destroy(before.panel.content)
    end
    generation:set(generation:get() + 1)
  end
  build_board()

  -- The panel's own controls, and whatever else asks, see one set of keys
  -- across rebuilds.
  local function proxy(name)
    return {
      get = function() generation:get() return current.panel.keys[name]:get() end,
      set = function(_, value) return current.panel.keys[name]:set(value) end,
    }
  end
  local keys = {
    mode = proxy("mode"), numbers = proxy("numbers"), page = proxy("page"), shift = proxy("shift"),
    cancel = function()
      current.seam.cancel()
      current.panel.keys.cancel()
    end,
    reset = function()
      current.seam.cancel()
      current.panel.keys.reset()
    end,
    height = function()
      generation:get()
      return current.panel.keys.height() - current.seam.lift
    end,
  }

  -- A change of shape waits for the turn after whatever brought it about.
  local waiting = false
  morf.effect("eva.keyboard.shape", function()
    local wanted = shape_of()
    if not current or wanted == current.shape or waiting then return end
    waiting = true
    morf.time.timer(1, function()
      waiting = false
      if shape_of() ~= current.shape then build_board() end
    end, false)
  end)

  local function board_height() return keys.height() + 2 * PAD end
  local function floor_gap() return floating() and 0 or config.get("keyboard.bottom_gap") end
  local function height() return HANDLE + STRIP + board_height() + floor_gap() end
  local function width()
    if floating() then return math.floor((W - 2 * PAD) * FLOATING) + 2 * PAD end
    return W
  end

  local parts = { model = model, state = state, keys = keys, width = width, W = W, handle = HANDLE,
    strip = STRIP, board_height = board_height, one_handed = one_handed }
  local strip_view = require("themes").view("keyboard_strip")
  -- Built each time they are wanted, across the width the keyboard has then.
  local function strip(when)
    return ui.Loader { width = W, height = 1, active = function() return floating() == when end,
      source = function() return strip_view.build(parts) end }
  end
  local emoji = ui.Loader { width = W, height = 1, y = HANDLE + STRIP,
    active = function() return state.pane:get() == "emoji" end,
    source = function() return require("themes").view("keyboard_emoji").build(parts) end }

  local content = ui.Item { id = "eva.keyboard.content", width = width, height = height,
    host, strip(true), strip(false), emoji, strip_view.side(parts),
    kit.decor("corners", { anchors = { fill = true }, length = 8, inset = 3, color = kit.stroke("mark") }),
  }
  return { width = width, height = height, keys = keys, content = content,
    floating = floating, stance = stance, shown = model.shown }
end
return V
