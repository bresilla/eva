-- The Fonts page (shell/fonts_model.lua): the kit's font picker over the
-- installed families, a preview of the family it is on at the size, weight and
-- text chosen here, and what sets it for the shell.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local composites = require("themes.kit.composites")
local S = theme.space

local M = {}

local PICKER_H = 300
local PREVIEW_H = 180

local function preview(model, w)
  local function family() return model.chosen:get() end
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
  return ui.Item { width = w, height = PREVIEW_H, clip = true,
    ui.Column {
      width = w, gap = S.s,
      kit.text {
        id = "fonts-family", width = w, elide = "right", font_size = theme.size.small, color = kit.ink("lo"),
        text = function()
          local name = family()
          if name == "" then return "Pick a family" end
          return ("%s · %d px · weight %d"):format(name, size(), model.weight:get())
        end,
      },
      faced { id = "fonts-sample", width = w, wrap = true, color = kit.ink("hi"), font_size = size,
        text = function() return model.sample:get() end },
      faced { id = "fonts-alphabet", width = w, wrap = true, color = kit.ink("lo"), font_size = theme.size.normal,
        text = model.ALPHABET },
    },
  }
end

-- One choice of several, as a row of buttons sharing the width.
local function choices(id, w, labels, chosen, choose, visible)
  local row = { id = id, width = w }
  for index, label in ipairs(labels) do
    row[index] = { id = id .. "-" .. tostring(label):lower():gsub("%s+", "-"), label = tostring(label), group = id,
      visible = visible and function() return visible(index) end or nil,
      selected = function() return chosen() == index end, on_clicked = function() choose(index) end }
  end
  return P.buttons(row)
end

function M.page(model, w, h)
  local inner = P.inner(w)
  local sizes, samples, weights = {}, {}, {}
  for index, size in ipairs(model.SIZES) do sizes[index] = size end
  for index, sample in ipairs(model.SAMPLES) do samples[index] = sample.name end
  for index, weight in ipairs(model.WEIGHTS) do weights[index] = weight end
  local function sample_at()
    for index, sample in ipairs(model.SAMPLES) do
      if sample.text == model.sample:get() then return index end
    end
    return 0
  end
  local picker = composites.font_picker {
    id = "fonts", width = inner, height = PICKER_H, row_height = S.xxl + S.l, sample = false, filter = false,
    fonts = model.shown, placeholder = "Search installed fonts…",
    preview = "The quick brown fox · 0123456789",
    value = function() return model.chosen:get() end,
    status = function() return model.status:get() end,
    on_search = model.search,
    on_picked = model.choose,
  }
  local text_box = P.field { id = "fonts-text", width = inner, placeholder = "Sample text",
    on_changed = function(value) model.sample:set(value) end }
  return P.page { id = "fonts-scroll", width = w, height = h, active = model.active,
    P.section { id = "fonts-families", width = w, title = "Families",
      P.row { id = "fonts-mono-row", width = inner, icon = "code", title = "Monospace only",
        subtitle = "Families whose letters all take one width",
        on = function() return model.mono_only:get() end,
        trailing = P.switch { id = "fonts-mono", name = "Monospace only", on = function() return model.mono_only:get() end,
          on_toggled = function(on) model.set_mono(on) end } },
      picker,
    },
    P.section { id = "fonts-preview", width = w, title = "Preview",
      preview(model, inner),
      choices("fonts-size", inner, sizes, function() return model.size:get() end, function(index) model.size:set(index) end),
      choices("fonts-weight", inner, weights, function()
        for index, weight in ipairs(model.WEIGHTS) do if weight == model.weight:get() then return index end end
      end, function(index) model.weight:set(model.WEIGHTS[index]) end,
        function(index) return model.has_weight(model.WEIGHTS[index]) end),
      text_box,
      choices("fonts-sample-kind", inner, samples, sample_at,
        function(index) model.sample:set(model.SAMPLES[index].text) end),
    },
    P.section { id = "fonts-shell", width = w, title = "The shell's font",
      P.row { id = "fonts-current", width = inner, icon = "font_download", on = function() return false end,
        title = function() local font = require("themes").font return font and font ~= "" and font or "The theme's own" end,
        subtitle = function()
          local said = model.message:get()
          return said ~= "" and said or "What every label of the shell is drawn in"
        end },
      P.buttons { width = inner,
        { id = "fonts-use", label = "Use for the shell", icon = "check", tone = "primary",
          enabled = function() return model.chosen:get() ~= "" end,
          on_clicked = function() model.apply(model.chosen:get()) end },
        { id = "fonts-default", label = "Theme default", icon = "restart_alt", on_clicked = function() model.apply("") end },
      },
    },
  }
end

return M
