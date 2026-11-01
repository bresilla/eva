-- eva-audio's window: the shell's own sound and equalizer pages in tabs, the
-- audiogram one level into the equalizer.
local morf = require("morf")
local ui = require("morf.ui")
local themes = require("themes")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("common.controls")
local model = require("model")
local S = theme.space

local M = {}

local SETTLE_MS = 120

local function get(v) if type(v) == "function" then return v() end return v end

-- The shared pages take their width when they are built: one is built again
-- at each width the window comes to rest on.
local function sized(id, w, build)
  local widths = morf.list_model({ { id = math.floor(get(w)) } })
  local wait
  morf.effect("eva.audio.width." .. id, function()
    local now = math.floor(get(w))
    if wait then wait:cancel() end
    wait = morf.time.timer(SETTLE_MS, function()
      wait = nil
      widths:replace({ { id = now } }, "id")
    end, false)
  end)
  return ui.Repeater { as = "column", model = widths, delegate = function(row) return build(row.id) end }
end

local function sound_page(id, page)
  return function(w, h)
    return sized(id, w, function(width) return themes.view("sound_page").build(page(), width, h) end)
  end
end

local function audiogram(width, h)
  local head = P.BUTTON_H + S.s
  local function body() return math.max(1, get(h) - head) end
  return ui.Item {
    id = "audio-audiogram", width = width, height = h,
    visible = function() return model.editing:get() end,
    P.header { id = "audio-audiogram-head", width = width, title = "Audiogram", back = model.equalizer.leave_editor },
    ui.Item { y = head, width = width, height = body, themes.view("equalizer_page").audiogram(model.equalizer, width, body) },
  }
end

local function equalizer_page(w, h)
  return sized("equalizer", w, function(width)
    return ui.Item {
      width = width, height = h,
      ui.Item {
        width = width, height = h, visible = function() return not model.editing:get() end,
        themes.view("equalizer_page").build(model.equalizer, width, h),
      },
      audiogram(width, h),
    }
  end)
end

--- The header's button: the sound server restarted.
function M.actions()
  return L.icon_button { id = "audio-restart", icon = "restart_alt", name = "Restart sound server",
    width = S.TARGET, height = S.TARGET, on_clicked = model.restart }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  return (controls.pages {
    id = "audio", width = w, height = h, tab = model.tab,
    tabs = {
      { key = "output", name = "Output", icon = "volume_up", build = sound_page("output", function() return model.output end) },
      { key = "input", name = "Input", icon = "mic", build = sound_page("input", function() return model.input end) },
      { key = "equalizer", name = "Equalizer", icon = "equalizer", build = equalizer_page },
    },
  })
end

return M
