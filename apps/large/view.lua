-- eva-large's overlay: the words as large as the screen takes them, on a card
-- that grows in on the theme's spring, the QR on a second card of the same field
-- budding out of it. A press or Escape ends it.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local frame = require("common.frame")
local controls = require("common.controls")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

-- What the words are measured at, and the fewest pixels they shrink to.
M.BASE = 100
M.SMALLEST = S.xl
M.MARGIN = S.xl
M.PAD = S.xl
M.DIM = 0.72

local size = morf.signal("large.size", M.BASE)

local function screen()
  morf.window.screens_revision()
  local s = (morf.screens or {})[1] or {}
  return s.width or 1920, s.height or 1080
end

local function wide()
  local w, h = screen()
  return w >= h
end

local function qr_side()
  if model.qr:get() == "" then return 0 end
  local w, h = screen()
  return math.floor(math.min(w, h) * (wide() and 0.3 or 0.42))
end

local function gap() return model.qr:get() == "" and 0 or S.l end

-- The card that holds the words.
local function card_w()
  local w = screen()
  return w - 2 * M.MARGIN - (wide() and qr_side() + gap() or 0)
end
local function card_h()
  local _, h = screen()
  return h - 2 * M.MARGIN - (wide() and 0 or qr_side() + gap())
end
local function box_w() return math.max(1, card_w() - 2 * M.PAD) end
local function box_h() return math.max(1, card_h() - 2 * M.PAD) end

local function message()
  local words = model.text:get()
  if words ~= "" then return words end
  return model.from:get() == "" and "" or "Nothing to show"
end

local function longest_word()
  local best, most = "", 0
  for word in message():gmatch("%S+") do
    if #word > most then best, most = word, #word end
  end
  return best
end

--- The largest size `w` by `h` of text measured at the base size allows in a
--- box, wrapped; `word` bounds it by the longest word's width.
function M.estimate(text_w, text_h, word_w, room_w, room_h)
  if text_w <= 0 or text_h <= 0 then return M.BASE end
  local by_area = math.sqrt(room_w * room_h / (text_w * text_h))
  local by_word = word_w > 0 and room_w / word_w or by_area
  local by_height = room_h / text_h
  return math.max(M.SMALLEST, math.floor(M.BASE * math.min(by_area, by_word, by_height)))
end

local function words_card()
  local all = kit.text { text = message, font_size = M.BASE, font_weight = 600, opacity = 0 }
  local word = kit.text { text = longest_word, font_size = M.BASE, font_weight = 600, opacity = 0 }
  local shown = kit.text {
    id = "large-text", text = message, width = box_w, wrap = true, horizontal_alignment = "center",
    anchors = { center_in = true }, font_size = function() return size:get() end, font_weight = 600,
    color = kit.ink("hi"),
  }
  local now = M.BASE
  local function set(value)
    now = value
    size:set(value)
  end
  morf.effect("large.estimate", function()
    set(M.estimate(all.layout_width or 0, all.layout_height or 0, word.layout_width or 0, box_w(), box_h()))
  end)
  -- Runs on each new layout of the words, one step down until they fit.
  morf.effect("large.shrink", function()
    if (shown.layout_height or 0) > box_h() and now > M.SMALLEST then
      set(math.max(M.SMALLEST, math.floor(now * 0.94)))
    end
  end)
  return kit.card {
    id = "large-card", width = card_w, height = card_h, radius = kit.round(S.xl),
    x = M.MARGIN, y = M.MARGIN,
    behavior = { width = theme.spring.spatial, height = theme.spring.spatial },
    ui.Item { width = 1, height = 1, clip = true, all, word },
    ui.Item { anchors = { fill = true, margins = M.PAD }, clip = true, shown },
  }
end

local function qr_card()
  local function side() return qr_side() end
  local function x()
    local w = screen()
    if wide() then return w - M.MARGIN - side() end
    return (w - side()) / 2
  end
  local function y()
    local _, h = screen()
    if wide() then return (h - side()) / 2 end
    return h - M.MARGIN - side()
  end
  return kit.card {
    id = "large-qr-card", width = side, height = side, radius = kit.round(S.l),
    x = x, y = y,
    visible = function() return model.qr:get() ~= "" end,
    opacity = 1, enter = { opacity = 0 },
    behavior = { width = theme.spring.spatial, height = theme.spring.spatial, x = theme.spring.spatial,
      y = theme.spring.spatial, opacity = theme.spring.effects },
    ui.Image {
      id = "large-qr", anchors = { fill = true, margins = S.s }, fill_mode = "preserve_aspect_fit",
      source = function() return model.qr:get() end,
    },
  }
end

--- Builds the overlay.
function M.overlay()
  local function full_w() return (screen()) end
  local function full_h() local _, h = screen() return h end
  local cards = controls.cards({
    id = "large", width = full_w, height = full_h, busy = function() return true end,
  }, function()
    return ui.Item { anchors = { fill = true }, words_card(), qr_card() }
  end)
  local root = ui.Item {
    anchors = { fill = true },
    ui.Rect {
      id = "large-dim", anchors = { fill = true },
      color = function() return C.scrim:alpha(M.DIM) end,
      opacity = function() return model.leaving:get() and 0 or 1 end, enter = { opacity = 0 },
      behavior = { opacity = theme.spring.effects },
    },
    ui.Item {
      id = "large-body", anchors = { fill = true },
      scale = function() return model.leaving:get() and 0.96 or 1 end, enter = { scale = 0.92 },
      opacity = function() return model.leaving:get() and 0 or 1 end,
      behavior = { scale = theme.spring.spatial, opacity = theme.spring.effects },
      cards,
    },
    ui.MouseArea {
      id = "large-area", anchors = { fill = true }, focus = true,
      accepted_buttons = { "left", "right", "middle" },
      on_pressed = function() model.finish() end,
      on_key_pressed = function(_, _, _, _, name)
        if name == "Escape" then model.finish() return true end
      end,
    },
  }
  return frame.overlay { id = "large", root = root, close = model.finish }
end

return M
