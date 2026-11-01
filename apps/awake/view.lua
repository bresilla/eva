-- eva-awake's window: a dial of the time left, the presets, and a line that
-- takes what you say.
local morf = require("morf")
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("common.controls")
local alarm = require("lib.services.alarm")
local model = require("model")
local S = theme.space

local M = {}

local DIAL = 200
local ADD = 120

local function running() return model.up:get() end

local function title()
  if not running() then return "The shell is not running" end
  if not model.on:get() then return "Off" end
  if model.stop:get() <= 0 then return "On" end
  morf.time.clock:get()
  return alarm.running(model.left())
end

local function subtitle()
  if not running() then return "Keep awake lives in the shell. Start it, and this window follows." end
  if not model.on:get() then return "The session sleeps as usual" end
  if model.stop:get() <= 0 then return "Until told otherwise" end
  return "Until " .. morf.time.format("%H:%M", model.stop:get())
end

local function now_section(w)
  local inner = function() return P.inner(w) end
  return P.section {
    id = "awake-now", width = w,
    ui.Column {
      width = inner, gap = S.s, align = "center",
      ui.Item { width = DIAL, height = DIAL, kit.dial { id = "awake-dial", size = DIAL, value = model.fraction } },
      kit.text {
        id = "awake-left", width = inner, horizontal_alignment = "center", elide = "right",
        font_size = theme.size.extra, font_weight = 300, color = kit.ink("hi"), text = title,
      },
      kit.text {
        id = "awake-until", width = inner, horizontal_alignment = "center", wrap = true,
        font_size = theme.size.small, color = kit.ink("lo"), text = subtitle,
      },
    },
  }
end

local function time_section(w)
  local inner = function() return P.inner(w) end
  local presets = { width = inner }
  for index, preset in ipairs(model.PRESETS) do
    presets[index] = {
      id = "awake-preset-" .. preset.minutes, label = preset.label, enabled = running,
      on_clicked = function() model.keep(preset.minutes) end,
    }
  end
  return P.section {
    id = "awake-time", width = w, title = "For how long",
    P.buttons(presets),
    ui.Row {
      gap = S.s, align = "center",
      controls.entry {
        id = "awake-words", width = function() return math.max(1, P.inner(w) - ADD - S.s) end, value = model.draft,
        placeholder = "45 min, 2 hours, until 18:30", on_accepted = function(value) model.say(value) end,
      },
      P.button {
        id = "awake-words-go", label = "Keep", tone = "primary", width = ADD, enabled = running,
        on_clicked = function() model.say(model.draft:get()) end,
      },
    },
    controls.note { id = "awake-hint", width = inner, text = function() return model.hint() or model.message:get() end },
    P.buttons {
      width = inner,
      { id = "awake-forever", label = "Indefinitely", icon = "all_inclusive", enabled = running,
        on_clicked = function() model.forever() end },
      { id = "awake-off", label = "Turn off", icon = "bedtime", enabled = function() return running() and model.on:get() end,
        on_clicked = function() model.off() end },
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  return P.page { id = "awake-page", width = w, height = h, now_section(w), time_section(w) }
end

return M
