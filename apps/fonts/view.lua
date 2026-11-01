-- eva-fonts' window: the kit's font picker beside a preview of the family it is
-- on, at the size, weight and text chosen here, and what sets it for the shell.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("common.controls")
local composites = require("themes.kit.composites")
local model = require("model")
local S = theme.space

local M = {}

local WIDE = 760
local LIST_W = 340
local CONTROLS_H = 4 * (P.BUTTON_H + S.s) + S.TARGET + S.s + L.lh(theme.size.small)
local FILTER_H = S.TARGET + S.s

-- The picker takes its size as numbers: it is made again at a new size.
local function picker(w, h)
  local slot = ui.Item { id = "fonts-slot", width = w, height = h, clip = true }
  local node, made_w, made_h, waiting
  local function build()
    waiting = nil
    made_w, made_h = math.floor(w()), math.floor(h())
    if node then ui.destroy(node) end
    node = composites.font_picker {
      id = "fonts", width = made_w, height = made_h, row_height = S.xxl + S.l, sample = false, filter = false,
      fonts = model.shown, placeholder = "Search installed fonts…", focus = true,
      preview = "The quick brown fox · 0123456789",
      value = function() return model.chosen:get() end,
      status = function() return model.status:get() end,
      on_search = model.search,
      on_picked = model.choose,
    }
    ui.reparent(node, slot)
  end
  build()
  morf.effect("fonts.picker.size", function()
    local width, height = math.floor(w()), math.floor(h())
    if width == made_w and height == made_h then return end
    if waiting then waiting:cancel() end
    waiting = morf.time.timer(120, build, false)
  end, { owner = slot })
  return slot
end

local function preview(w, h)
  local function family() return model.chosen:get() end
  local function inner() return math.max(1, w() - 2 * P.PAD) end
  local function size() return model.SIZES[model.size:get()] end
  -- The theme's face, for before a family is picked.
  local plain = { text = "" }
  ui.destroy(kit.text(plain), true)
  local function faced(props)
    props.font_source = ""
    props.font_family = function()
      local name = family()
      return name ~= "" and name or plain.font_family
    end
    local node = kit.text(props)
    -- A static family takes the weight, a variable one its axis.
    morf.effect("fonts.weight." .. props.id, function()
      local weight = model.weight:get()
      node.font_weight, node.axes = weight, { wght = weight }
    end, { owner = node })
    return node
  end
  return kit.card {
    id = "fonts-preview", width = w, height = h, radius = kit.round(P.RADIUS),
    ui.Item {
      x = P.PAD, y = P.PAD, width = inner, height = function() return math.max(1, h() - 2 * P.PAD) end, clip = true,
      ui.Column {
        width = inner, gap = S.s,
        kit.text {
          id = "fonts-family", width = inner, elide = "right", font_size = theme.size.small, color = kit.ink("lo"),
          text = function()
            local name = family()
            if name == "" then return "Pick a family" end
            return ("%s · %d px · weight %d"):format(name, size(), model.weight:get())
          end,
        },
        faced {
          id = "fonts-sample", width = inner, wrap = true, color = kit.ink("hi"), font_size = size,
          text = function() return model.sample:get() end,
        },
        faced {
          id = "fonts-alphabet", width = inner, wrap = true, color = kit.ink("lo"), font_size = theme.size.normal,
          text = model.ALPHABET,
        },
      },
    },
  }
end

local function weights(w)
  local row = { width = w }
  for index, weight in ipairs(model.WEIGHTS) do
    row[index] = {
      id = "fonts-weight-" .. weight, label = tostring(weight), group = "fonts-weight",
      visible = function() return model.has_weight(weight) end,
      selected = function() return model.weight:get() == weight end,
      on_clicked = function() model.weight:set(weight) end,
    }
  end
  return P.buttons(row)
end

local function panel(w)
  local sizes, samples = {}, {}
  for index, size in ipairs(model.SIZES) do sizes[index] = tostring(size) end
  for index, sample in ipairs(model.SAMPLES) do samples[index] = sample.name end
  local function sample_at()
    for index, sample in ipairs(model.SAMPLES) do
      if sample.text == model.sample:get() then return index end
    end
    return 0
  end
  return ui.Column {
    width = w, gap = S.s,
    controls.segments {
      id = "fonts-size", width = w, items = sizes, current = function() return model.size:get() end,
      on_changed = function(index) model.size:set(index) end,
    },
    weights(w),
    controls.entry { id = "fonts-text", width = w, value = model.sample, placeholder = "Sample text" },
    controls.segments {
      id = "fonts-sample-kind", width = w, items = samples, current = sample_at,
      on_changed = function(index) model.sample:set(model.SAMPLES[index].text) end,
    },
    P.buttons {
      width = w,
      { id = "fonts-use", label = "Use for the shell", icon = "check", tone = "primary",
        enabled = function() return model.chosen:get() ~= "" end,
        on_clicked = function() model.apply(model.chosen:get()) end },
      { id = "fonts-default", label = "Theme default", icon = "restart_alt", on_clicked = function() model.apply("") end },
    },
    controls.note { id = "fonts-note", width = w, text = function() return model.message:get() end },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local function wide() return w() >= WIDE end
  local function list_w() return wide() and LIST_W or w() end
  local function list_h()
    local room = h() - FILTER_H
    return math.max(S.TARGET * 4, wide() and room or math.floor((room - CONTROLS_H) * 0.5))
  end
  local function side_x() return wide() and LIST_W + S.l or 0 end
  local function side_y() return wide() and 0 or FILTER_H + list_h() + S.s end
  local function side_w() return math.max(1, w() - side_x()) end
  local function side_h() return math.max(1, h() - side_y()) end
  local function preview_h() return math.max(S.TARGET * 3, side_h() - CONTROLS_H - S.m) end
  return ui.Item {
    id = "fonts-root", width = w, height = h,
    ui.Row {
      width = list_w, height = S.TARGET, gap = S.s, align = "center",
      ui.Item {
        width = function() return math.max(1, list_w() - S.xxl * 2 - S.l) end, height = S.TARGET,
        kit.text {
          anchors = { vertical_center = true }, font_size = theme.size.normal, color = kit.ink("hi"),
          text = "Monospace only",
        },
      },
      P.switch {
        id = "fonts-mono", name = "Monospace only", on = function() return model.mono_only:get() end,
        on_toggled = function(on) model.set_mono(on) end,
      },
    },
    ui.Item { y = FILTER_H, width = list_w, height = list_h, picker(list_w, list_h) },
    ui.Item {
      x = side_x, y = side_y, width = side_w, height = side_h,
      preview(side_w, preview_h),
      ui.Item { y = function() return preview_h() + S.m end, width = side_w, panel(side_w) },
    },
  }
end

return M
