-- The panel's history: the search, the recent captures, what a chosen one can
-- do, and the text read from a shot. It stands where the panel's controls stood
-- and is built each time it opens.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local C, S = theme.color, theme.space
local V = {}

local ROW = 56
local BAR = S.TARGET + S.s

function V.build(capture, M, w, h)
  local inner = w - 2 * S.l
  local function reading() return M.reading:get() ~= false end
  local function list_h() return h() - 76 - BAR - S.xl end

  local function row(i)
    local function entry() return M.rows:get()[i] end
    local function on() return M.chosen:get() == i end
    local function ink() return on() and C.onSecondaryContainer or C.onSurface end
    local area = kit.action { id = "capture-history-row-" .. i, y = (i - 1) * (ROW + S.xs), width = inner, height = ROW,
      cursor = "pointer", visible = function() return entry() ~= nil end,
      on_clicked = function() M.press(i) end,
      kit.surface { x = S.xs, y = S.xs, width = M.SMALL_W, height = M.SMALL_H, radius = kit.round(S.s),
        color = function() return C.surfaceContainerHighest end,
        kit.icon(function()
          local one = entry()
          return one and one.kind == "recording" and "movie" or "image"
        end, 20, kit.ink("lo"), { anchors = { center_in = true } }),
        ui.Image { id = "capture-history-small-" .. i, anchors = { fill = true }, fill_mode = "preserve_aspect_crop",
          source = function()
            local one = entry()
            return one and M.small:get()[one.path] or ""
          end },
      },
      kit.text { x = M.SMALL_W + S.m, y = S.s, width = inner - M.SMALL_W - S.xl, elide = "right", font_size = 13, font_weight = 600,
        color = ink, text = function()
          local one = entry()
          return one and M.label(one) or ""
        end },
      kit.text { x = M.SMALL_W + S.m, y = S.xl + S.xs, width = inner - M.SMALL_W - S.xl, elide = "middle", font_size = 11,
        color = kit.ink("lo"), text = function()
          local one = entry()
          return one and (M.size(one.size) .. " · " .. one.name) or ""
        end },
    }
    kit.hover(area, function(hovered)
      return on() and C.secondaryContainer or C.primary:alpha(hovered and .10 or 0)
    end, 12)
    return area
  end

  local rows = {}
  for i = 1, M.LIMIT do rows[i] = row(i) end
  local list = (kit.scroll({ id = "capture-history-list", x = S.l, y = 76, width = inner, height = list_h, clip = true,
    visible = function() return not reading() end,
    ui.Item { width = inner, height = function() return #M.rows:get() * (ROW + S.xs) end, table.unpack(rows) } }))

  local nothing = kit.text { id = "capture-history-empty", x = S.l, y = 92, width = inner, font_size = 13,
    horizontal_alignment = "center", color = kit.ink("lo"),
    visible = function() return not reading() and #M.rows:get() == 0 end,
    text = function() return M.total:get() == 0 and "Nothing captured yet" or "Nothing matches" end }

  local words = (kit.scroll({ id = "capture-history-words-scroll", x = S.l, y = 76, width = inner, height = list_h, clip = true,
    visible = reading,
    kit.text { id = "capture-history-words", width = inner, wrap = true, font_size = 13, color = function() return C.onSurface end,
      text = function() return table.concat(M.lines(), "\n") end } }))

  local function action(id, label, icon, run, enabled, visible)
    local area
    local function ready() return not enabled or enabled() end
    area = kit.action { id = "capture-history-" .. id, y = 0, width = inner / 5 - S.xs, height = BAR - S.s,
      cursor = function() return ready() and "pointer" or "default" end,
      visible = visible, opacity = function() return ready() and 1 or .35 end,
      on_clicked = function() if ready() then run() end end,
      kit.icon(icon, 19, function()
        if id == "delete" and M.armed:get() then return C.error end
        return C.onSurface
      end, { anchors = { horizontal_center = true }, y = S.xs }),
      kit.label { anchors = { horizontal_center = true }, y = S.xl + S.xxs, text = label, font_size = 11, color = kit.ink("lo") },
    }
    return kit.hover(area, function(hovered) return C.primary:alpha(area.pressed and .20 or hovered and .10 or 0) end, 10)
  end

  local function chosen() return M.entry() ~= nil end
  local function a_shot() local one = M.entry() return one ~= nil and one.kind == "shot" end
  local function listing() return not reading() end

  local bar = ui.Row { id = "capture-history-bar", x = S.l, y = function() return h() - BAR - S.xs end, gap = S.xs + 1,
    action("edit", "Edit", "edit", M.edit, chosen, listing),
    action("copy", "Copy", "content_copy", M.copy, chosen, listing),
    action("text", "Text", "document_scanner", M.read, a_shot, listing),
    action("pin", "Pin", "keep", M.pin, a_shot, listing),
    action("delete", "Delete", "delete", M.delete, chosen, listing),
    action("back", "Back", "arrow_back", M.back, nil, reading),
    action("copy-text", "Copy text", "content_copy", M.copy_text, function() return M.words:get() ~= "" end, reading),
  }

  local note = kit.label { id = "capture-history-note", x = S.l, y = function() return h() - BAR - S.xl end,
    width = function() return M.unread:get() > 0 and inner - 148 or inner end, height = 16, elide = "right", font_size = 11,
    color = function() return M.armed:get() and C.error or C.onSurfaceVariant end,
    text = function()
      local said = M.note:get()
      if said ~= "" then return said end
      if M.query:get() ~= "" and not capture.editor.readers:get().ocr then return M.MISSING_SEARCH end
      return ""
    end }

  local look = ui.Item { x = w - S.l - 140, y = function() return h() - BAR - S.xl - S.xs end, width = 140, height = 24,
    visible = function() return M.unread:get() > 0 and not reading() and not M.busy:get() end,
    kit.pill { id = "capture-history-look", width = 140, height = 24, on_clicked = M.read_all,
      label = function() return "Read " .. M.unread:get() .. " more" end },
  }

  local search, handle = P.field { id = "capture-history-search", kind = "search", width = inner, placeholder = "Search by name, date or text",
    on_changed = M.search, on_escape = function()
      if reading() then M.back() else capture.history_open:set(false) end
    end }
  M.on_cleared = function() handle.text = "" end
  handle.focus = true

  return ui.Item { id = "capture-history", width = w, height = h,
    on_destroyed = function() M.close() end,
    ui.Item { x = S.l, y = 34, width = inner, height = 36, search },
    list, nothing, words, note, look, bar }
end

return V
