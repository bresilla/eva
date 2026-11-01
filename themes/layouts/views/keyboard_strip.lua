-- The strip over the keys: a handle to drag, then what the cursor's word offers,
-- the tools, the clipboard, the cursor keys or the emoji found. Shell only: the
-- shared panel of keys never holds it, so a lock screen cannot show it.
local ui = require("morf.ui")
local theme = require("theme")
local kit = require("kit")
local L = require("themes.layouts.parts")
local S = theme.space
local C = theme.color
local V = {}

local PREFIX = "eva.keyboard."

--- A pressable word: `id`, `x`, `width`, `label()`, `run`, and a `visible()`.
local function chip(spec)
  return kit.action {
    id = spec.id, x = spec.x, width = spec.width, height = S.TARGET, cursor = "pointer", visible = spec.visible,
    accessible_name = spec.name, on_clicked = spec.run,
    kit.text {
      anchors = { center_in = true }, width = spec.width - 2 * S.xs, elide = "right", horizontal_alignment = "center",
      font_size = theme.size.normal, color = spec.color or kit.ink("hi"), text = spec.label,
    },
  }
end

local function tool(spec, size)
  if spec.label then
    return chip { id = PREFIX .. "tool-" .. spec.id, width = size, label = spec.label, run = spec.run, name = spec.name }
  end
  return L.icon_button { id = PREFIX .. "tool-" .. spec.id, name = spec.name, icon = spec.icon, width = size,
    height = S.TARGET, size = 22, on = spec.on, on_clicked = spec.run }
end

--- A row of `tools`, spread evenly across `width`.
local function tool_row(id, width, tools, visible)
  local size = math.floor(width / math.max(1, #tools))
  local row = { id = PREFIX .. id, width = width, height = S.TARGET, visible = visible }
  for i, spec in ipairs(tools) do
    local item = tool(spec, size)
    item.x = (i - 1) * size
    row[#row + 1] = item
  end
  return ui.Item(row)
end

function V.build(parts)
  local model, state = parts.model, parts.state
  local clips = require("keyboard_clips")
  local W = parts.width()
  local fixed = W - 2 * S.s
  local tray = state.tray
  local toolbox = model.tools()

  -- A copy made a moment ago goes before anything but the word being typed.
  local function fresh()
    if tray:get() ~= "words" then return nil end
    local item = clips.fresh()
    if item and state.word() == "" then return item end
  end
  local function offers()
    if fresh() then return {} end
    return state.candidates:get()
  end
  local function busy() return #offers() > 0 or fresh() ~= nil end
  local function showing(name) return function() return tray:get() == name and not state.searching:get() end end

  -- The word row: the tools' toggle, then an offer in each slot.
  local slots = require("keyboard_predict").SLOTS
  local toggle = S.TARGET
  local cell = math.floor((fixed - toggle) / slots)
  local words = { id = PREFIX .. "words", width = fixed, height = S.TARGET,
    visible = function() return showing("words")() and busy() end,
    L.icon_button { id = PREFIX .. "more", name = "Tools", icon = "chevron_right", width = toggle, height = S.TARGET,
      size = 22, on_clicked = function() tray:set("tools") end },
  }
  for i = 1, slots do
    local function offer() return offers()[i] end
    words[#words + 1] = chip {
      id = PREFIX .. "offer-" .. i, x = toggle + (i - 1) * cell, width = cell,
      visible = function() return offer() ~= nil end,
      label = function() local o = offer() return o and o.label or "" end,
      color = function()
        local o = offer()
        return o and o.kind ~= "word" and kit.signal("accent")() or kit.ink("hi")()
      end,
      run = function()
        local o = offer()
        if o then model.pick(o) end
      end,
    }
    if i < slots then
      words[#words + 1] = ui.Rect { x = toggle + i * cell, y = S.m, width = 1, height = S.TARGET - 2 * S.m,
        color = function() return C.outlineVariant end,
        visible = function() return offers()[i + 1] ~= nil end }
    end
  end
  -- A copy made a moment ago stands where there is no word to offer.
  words[#words + 1] = chip {
    id = PREFIX .. "fresh", x = toggle, width = fixed - toggle,
    visible = function() return #offers() == 0 and fresh() ~= nil end,
    label = function() local item = fresh() return item and clips.line(item) or "" end,
    run = function()
      local item = fresh()
      if item then model.paste(item.text) end
    end,
  }

  local tools = tool_row("tools", fixed, toolbox, function()
    if state.searching:get() then return false end
    return tray:get() == "tools" or (tray:get() == "words" and not busy())
  end)

  -- The clipboard: a chip for each thing held, a finger's flick along them.
  local chips = { id = PREFIX .. "clips-row", width = 1, height = S.TARGET }
  local CHIP = math.max(120, math.floor((fixed - toggle) / 2))
  for i = 1, 12 do
    local function item() return clips.items:get()[i] end
    chips[#chips + 1] = chip {
      id = PREFIX .. "clip-" .. i, x = (i - 1) * CHIP, width = CHIP - S.xs,
      visible = function() return item() ~= nil end,
      label = function() local it = item() return it and clips.line(it) or "" end,
      run = function()
        local it = item()
        if it then model.paste(it.text) end
      end,
    }
  end
  chips.width = function() return math.max(1, #clips.items:get() * CHIP) end
  local clip_scroll = kit.scroll { id = PREFIX .. "clips", x = toggle, width = fixed - toggle, height = S.TARGET,
    clip = true, ui.Item(chips) }
  local clip_row = ui.Item { id = PREFIX .. "clipboard", width = fixed, height = S.TARGET, visible = showing("clips"),
    L.icon_button { id = PREFIX .. "clips-back", name = "Back", icon = "chevron_left", width = toggle, height = S.TARGET,
      size = 22, on_clicked = function() tray:set("words") end },
    clip_scroll,
    kit.text { id = PREFIX .. "clips-empty", x = toggle + S.s, anchors = { vertical_center = true },
      font_size = theme.size.small, color = kit.ink("lo"), text = "Nothing copied yet",
      visible = function() return #clips.items:get() == 0 end },
  }

  local edit = tool_row("edit", fixed, model.editing(), showing("edit"))
  local boards = tool_row("boards", fixed, model.boards(parts.keys), showing("boards"))

  -- The emoji search: what is typed, and what it finds.
  local FOUND = 5
  local found_w = math.floor((fixed - 2 * toggle) / (FOUND + 2))
  local searching = { id = PREFIX .. "search", width = fixed, height = S.TARGET,
    visible = function() return state.searching:get() end,
    L.icon_button { id = PREFIX .. "search-back", name = "Back", icon = "chevron_left", width = toggle, height = S.TARGET,
      size = 22, on_clicked = model.end_search },
    kit.text { id = PREFIX .. "search-query", x = toggle + S.s, width = 2 * found_w - S.s, elide = "left",
      anchors = { vertical_center = true }, font_size = theme.size.normal, color = kit.ink("hi"),
      text = function()
        local query = state.query:get()
        return query ~= "" and query or "Search emoji"
      end },
  }
  for i = 1, FOUND do
    local function hit() return model.search_results(FOUND)[i] end
    searching[#searching + 1] = chip {
      id = PREFIX .. "found-" .. i, x = toggle + 2 * found_w + (i - 1) * found_w, width = found_w,
      visible = function() return hit() ~= nil end,
      label = function() local h = hit() return h and h.char or "" end,
      run = function()
        local h = hit()
        if h then model.type_emoji(h.char) end
      end,
    }
  end

  -- The handle: a finger down it shuts the keyboard, or floats it about.
  local grip = ui.Rect { anchors = { center_in = true }, width = S.xxl, height = S.xs, radius = S.xxs,
    color = function() return kit.ink("lo")():alpha(.5) end }
  local handle = ui.MouseArea {
    id = PREFIX .. "handle", x = 0, y = 0, width = W, height = parts.handle, cursor = "grab",
    on_pressed = model.handle_down, on_dragged = model.handle_move, on_released = model.handle_up,
    accessible_name = "Keyboard handle", grip,
  }

  return ui.Item { id = PREFIX .. "strip", width = W, height = parts.handle + parts.strip,
    handle,
    ui.Item { x = S.s, y = parts.handle, width = fixed, height = parts.strip, clip = true,
      ui.Item(words), tools, clip_row, edit, boards, ui.Item(searching) },
  }
end

--- The column left beside a board squeezed for one hand.
function V.side(parts)
  local model, W = parts.model, parts.W
  local function far_x()
    local hand = require("config").get("keyboard.hand")
    return hand == "left" and W - S.TARGET - S.s or S.s
  end
  local size = S.TARGET
  return ui.Item {
    id = PREFIX .. "side", x = far_x, y = parts.handle + parts.strip, width = size,
    height = parts.board_height, visible = parts.one_handed,
    ui.Column { anchors = { center_in = true }, gap = S.m,
      tool({ id = "side-swap", name = "Other hand", icon = "swap_horiz", run = model.swap_hand }, size),
      tool({ id = "side-full", name = "Full width", icon = "open_in_full", run = model.both_hands }, size),
    },
  }
end

return V
