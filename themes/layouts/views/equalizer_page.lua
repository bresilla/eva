-- The equalizer and its audiogram editor, in the page template
-- (themes/layouts/page.lua): each part a section, switches on rows, the
-- kit's chart, sliders and fields inside the cards.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local P = require("themes.layouts.page")
local F = require("themes.layouts.form")
local S = theme.space
local M = {}

local MODES = { { "auto", "Automatic", "Auto" }, { "headphones", "Headphones" }, { "speakers", "Speakers" } }
local NAMES = { headphones = "headphones", speakers = "speakers" }

local function hz_name(hz) return hz < 1000 and hz .. " Hz" or ("%g kHz"):format(hz / 1000) end

--- A switch on a row of its own.
local function flag(id, label, subtitle, w, on, set, icon)
  return P.row { id = id .. "-row", width = w, icon = icon, on = on, title = label, subtitle = subtitle,
    trailing = P.switch { id = id, name = label, on = on, on_toggled = set } }
end

--- A named slider over `low`..`high`, its reading in `units`.
local function number_slider(id, name, w, get, set, low, high, units)
  return F.slider { id = id, name = name, width = w, from = low, to = high, step = units == "%" and 1 or 0.1,
    value = get, set = set,
    format = function(v)
      if units == "%" then return ("%d%%"):format(math.floor(v + 0.5)) end
      return (("%+.1f%s"):format(v, units or ""):gsub("^[+-]0%.0", "0.0"))
    end }
end

function M.build(model, w, h)
  local inner = P.inner(w)
  local function on() return model.get("enabled") == true end
  local modes = { width = inner }
  for _, entry in ipairs(MODES) do
    local key = entry[1]
    modes[#modes + 1] = { id = "equalizer-mode-" .. key, group = "equalizer-mode", label = entry[2], short = entry[3],
      selected = function() return model.get("mode") == key end, on_clicked = function() model.set("mode", key) end }
  end
  local curve = function() return model.curve:get() end
  local function series(ear) return function() local c = curve() return c and c[ear] or {} end end
  -- The response on the theme's chart: left filled, right as its second line.
  local chart = kit.chart { width = inner, height = 114, first = series("response_left"), second = series("response_right"),
    samples = 160, bottom = -36, top = 12, columns = 8 }
  local bands = { width = inner, gap = P.ROW_GAP }
  for i, hz in ipairs(model.frequencies) do
    bands[#bands + 1] = number_slider("equalizer-band-" .. i, hz_name(hz), inner,
      function() return model.current("bands")[i] end, function(v) model.set_band(i, v) end, -12, 12, " dB")
  end
  return P.page { id = "equalizer-scroll", width = w, height = h,
    P.section { id = "equalizer-controls", width = w,
      flag("equalizer-enabled", "Equalizer", function()
          if model.error:get() ~= "" then return model.error:get() end
          if not on() then return "Sound as it is" end
          local status = model.status:get()
          if status == "starting" then return "Starting…" end
          if status == "preview" then return "Preview, the sound unchanged" end
          return "Tuned for " .. (NAMES[model.preset()] or model.preset())
        end, inner, on, function(v) model.set("enabled", v) end, "equalizer"),
      F.waiting(ui.Column { width = inner, gap = S.xs, P.buttons(modes),
        F.note(inner, "Automatic follows the output in use. Each keeps its own settings.") }, on),
    },
    P.section { id = "equalizer-curve", width = w, title = "Response",
      F.waiting(ui.Column { width = inner, gap = S.xs,
        ui.Item { id = "equalizer-response", width = inner, height = 114, chart },
        F.note(inner, function()
          local c = curve()
          return ("Left filled, right as a line · 20 Hz to 20 kHz · %.1f dB headroom"):format(c and c.preamp or 0)
        end) }, on) },
    P.section { id = "equalizer-compensation", width = w, title = "Audiogram compensation",
      flag("equalizer-compensation-enabled", "Use an audiogram", "Lift what it says you hear less", inner,
        function() return model.get("compensation") == true end, function(v) model.set("compensation", v) end, "hearing"),
      F.waiting(ui.Column { width = inner, gap = P.ROW_GAP,
        number_slider("equalizer-strength", "Strength", inner, function() return model.current("strength") end,
          function(v) model.set_current("strength", v) end, 0, 100, "%"),
        flag("equalizer-per-ear", "Each ear on its own", "A curve for the left, one for the right", inner,
          function() return model.current("per_ear") == true end, function(v) model.set_current("per_ear", v) end, "earbuds"),
        P.row { id = "equalizer-audiogram", width = inner, icon = "graphic_eq", title = "Audiogram",
          subtitle = function() return model.get("profile.label") end, trailing = P.chevron(), on_clicked = model.open_editor },
      }, function() return model.get("compensation") == true end),
      F.note(inner, "Thresholds you measured elsewhere. This shapes what you listen to; it does not test hearing."),
    },
    P.section { id = "equalizer-bands", width = w, title = "Bands",
      F.waiting(ui.Column(bands), on),
      P.button { id = "equalizer-reset", width = inner, icon = "restart_alt", label = "Reset the bands",
        on_clicked = model.reset_bands } },
    P.section { id = "equalizer-headroom", width = w, title = "Headroom",
      number_slider("equalizer-trim", "Lower everything by", inner, function() return model.current("trim") end,
        function(v) model.set_current("trim", v) end, -24, 0, " dB"),
      F.note(inner, "Overlapping boosts are allowed for already. This is not a limiter"),
    },
  }
end

function M.audiogram(model, w, h)
  local inner = P.inner(w)
  local HZ = 64
  local col = math.floor((inner - HZ - 2 * S.s) / 2)
  local function input(id, ear, index, width)
    local name = ear == "label" and "Profile name"
      or ("%s ear at %s"):format(ear == "left" and "Left" or "Right", hz_name(model.frequencies[index]))
    local box = P.field { id = id, kind = ear == "label" and "entry" or "numeric_entry", name = name, width = width,
      text = function()
        local draft = model.draft:get()
        return tostring(ear == "label" and draft.label or draft[ear][index])
      end,
      on_changed = function(value) model.edit(ear, index, value) end }
    return box
  end
  local function head(text, width) return F.note(width, text) end
  local table_rows = { width = inner, gap = S.s,
    ui.Row { width = inner, gap = S.s, head("Hz", HZ), head("Left ear", col), head("Right ear", col) } }
  for i, hz in ipairs(model.frequencies) do
    table_rows[#table_rows + 1] = ui.Row { width = inner, gap = S.s, align = "center",
      kit.text { width = HZ, text = hz_name(hz), font_size = theme.size.normal, color = kit.ink("hi") },
      input("audiogram-left-" .. i, "left", i, col),
      input("audiogram-right-" .. i, "right", i, col) }
  end
  return P.page { id = "audiogram-scroll", width = w, height = h,
    P.section { id = "audiogram-profile", width = w, title = "Profile",
      ui.Column { width = inner, gap = S.xs, F.note(inner, "Name"), input("audiogram-label", "label", nil, inner) } },
    P.section { id = "audiogram-editor", width = w, title = "Measured thresholds",
      ui.Column(table_rows),
      F.note(inner, "In dB HL, from −10 to 120, as an audiogram you have gives them. Blank counts as 0"),
      F.note(inner, function() return model.editor_error:get() end,
        { color = function() return theme.color.error end, visible = function() return model.editor_error:get() ~= "" end }),
      P.button { id = "audiogram-save", width = inner, icon = "check", label = "Save audiogram", tone = "primary",
        on_clicked = model.save_profile },
      F.note(inner, "Back leaves without saving") },
  }
end

return M
