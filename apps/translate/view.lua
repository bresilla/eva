-- eva-translate's window: the two languages, the text, what the press sends and
-- to whom, the translation. The engine is named under the button that uses it.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local L = require("themes.layouts.parts")
local controls = require("apps.common.controls")
local composites = require("themes.kit.composites")
local model = require("apps.translate.model")
local S = theme.space

local M = {}

local LANGUAGE_W = S.TARGET * 4
local ENGINE_W = S.TARGET * 6

local function area(spec)
  spec.color, spec.placeholder_color = kit.ink("hi"), kit.ink("lo")
  spec.inset = { S.s, S.s, S.s, S.s }
  local node = kit.text_field("text_area", spec)
  return node
end

-- A chooser of languages: `pick(code)`, `code()` the one chosen.
local function language(id, first, code, pick)
  local items, codes = {}, {}
  if first then
    items[1], codes[1] = first, "auto"
  end
  for _, entry in ipairs(model.LANGUAGES) do
    items[#items + 1] = entry[2]
    codes[#codes + 1] = entry[1]
  end
  local node = composites.combo_box {
    id = id, width = LANGUAGE_W, height = S.TARGET, items = items, variant = "dropdown", visible_items = 7,
    current = function()
      local now = code()
      for index, value in ipairs(codes) do
        if value == now then return index end
      end
      return 1
    end,
    on_changed = function(index) pick(codes[index]) end,
  }
  return node
end

local function engine_chooser()
  local function names()
    local out = {}
    for index, engine in ipairs(model.found:get()) do
      out[index] = engine.name .. (engine.offline and " · offline" or " · online")
    end
    return out
  end
  local node = composites.combo_box {
    id = "translate-engine", width = ENGINE_W, height = S.TARGET, items = names, variant = "dropdown",
    current = function()
      local now = model.current()
      for index, engine in ipairs(model.found:get()) do
        if now and engine.id == now.id then return index end
      end
      return 1
    end,
    on_changed = function(index)
      local engine = model.found:get()[index]
      if engine then model.set_engine(engine.id) end
    end,
  }
  return node
end

local function sending_note(w)
  local function offline()
    local engine = model.current()
    return engine ~= nil and engine.offline
  end
  return ui.Item {
    width = w, height = L.lh(theme.size.small),
    kit.icon(function() return offline() and "offline_pin" or "cloud_upload" end, S.l,
      function() return offline() and kit.ink("lo")() or kit.signal("warn")() end, { anchors = { vertical_center = true } }),
    ui.Item {
      x = S.l + S.xs, width = function() return math.max(1, w() - S.l - S.xs) end, height = L.lh(theme.size.small),
      controls.note {
        id = "translate-privacy", width = function() return math.max(1, w() - S.l - S.xs) end, text = model.privacy,
      },
    },
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  local head = S.TARGET + S.s
  local middle = P.BUTTON_H + S.TARGET + 2 * L.lh(theme.size.small) + 5 * S.s
  local function text_h() return math.max(S.TARGET * 2, math.floor((h() - head - middle) / 2)) end
  local function engine() return model.current() end
  return ui.Item {
    id = "translate-root", width = w, height = h,
    ui.Column {
      width = w, gap = S.s,
      ui.Item {
        width = w, height = S.TARGET,
        language("translate-source", "Detect", function() return model.source:get() end, model.set_source),
        L.icon_button {
          id = "translate-swap", icon = "swap_horiz", name = "Swap languages", width = S.TARGET, height = S.TARGET,
          x = function() return (w() - S.TARGET) / 2 end, on_clicked = model.swap,
        },
        ui.Item {
          width = LANGUAGE_W, height = S.TARGET, anchors = { right = true },
          language("translate-target", nil, function() return model.target:get() end, model.set_target),
        },
      },
      area {
        id = "translate-input", width = w, height = text_h, placeholder = "Text to translate", focus = true,
        text = function() return model.input:get() end,
        on_text_changed = function(value) model.input:set(value) end,
      },
      P.buttons {
        width = w,
        { id = "translate-clipboard", icon = "content_paste", label = "Paste", on_clicked = function() model.paste(false) end },
        { id = "translate-selection", icon = "select_all", label = "Selected", on_clicked = function() model.paste(true) end },
        { id = "translate-go", icon = "translate", tone = "primary",
          label = function()
            local now = engine()
            return (now and not now.offline) and "Send" or "Translate"
          end,
          enabled = function() return engine() ~= nil and not model.busy:get() end,
          on_clicked = function() model.translate() end },
      },
      sending_note(w),
      area {
        id = "translate-output", width = w, height = text_h, placeholder = "The translation", read_only = true,
        text = function() return model.output:get() end,
      },
      ui.Item {
        width = w, height = S.TARGET,
        engine_chooser(),
        ui.Item {
          width = S.TARGET * 3, height = S.TARGET, anchors = { right = true },
          P.button { id = "translate-copy", icon = "content_copy", label = "Copy", width = S.TARGET * 3,
            enabled = function() return model.output:get() ~= "" end, on_clicked = model.copy },
        },
      },
      controls.note { id = "translate-note", width = w, text = function() return model.message:get() end },
    },
  }
end

return M
