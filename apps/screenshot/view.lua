-- eva-screenshot's window: the targets, the delay, what happens after, the
-- readers that are installed, and the recent pictures.
local ui = require("morf.ui")
local kit = require("kit")
local theme = require("theme")
local P = require("themes.layouts.page")
local model = require("model")
local C, S = theme.color, theme.space

local M = {}

local function choices(w, signal, list)
  local spec = { width = w }
  for i, item in ipairs(list) do
    spec[i] = {
      id = "screenshot-" .. item.key, label = item.label, icon = item.icon,
      tone = function() return signal:get() == item.value and "primary" or nil end,
      on_clicked = function() signal:set(item.value) end,
    }
  end
  return P.buttons(spec)
end

local function targets(w)
  return P.section {
    id = "screenshot-targets", width = w, title = "Take",
    P.buttons {
      width = function() return P.inner(w) end,
      { id = "screenshot-region", label = "Region", icon = "crop_free", on_clicked = function() model.take("region") end },
      { id = "screenshot-window", label = "Window", icon = "web_asset", on_clicked = function() model.take("window") end },
      { id = "screenshot-screen", label = "Screen", icon = "desktop_windows", on_clicked = function() model.take("screen") end },
    },
  }
end

local function options(w)
  local inner = function() return P.inner(w) end
  local delays = {}
  for i, seconds in ipairs(model.DELAYS) do
    delays[i] = { key = "delay-" .. seconds, label = seconds == 0 and "Now" or seconds .. " s", value = seconds }
  end
  return P.section {
    id = "screenshot-options", width = w, title = "Then",
    choices(inner, model.how, {
      { key = "how-edit", label = "Edit", icon = "edit", value = "edit" },
      { key = "how-copy", label = "Copy", icon = "content_copy", value = "copy" },
      { key = "how-save", label = "Save", icon = "save", value = "save" },
    }),
    choices(inner, model.delay, delays),
  }
end

local function readers(w)
  return P.section {
    id = "screenshot-readers", width = w, title = "Read a region",
    visible = function()
      local found = model.readers:get()
      return found.ocr == true or found.qr == true
    end,
    P.buttons {
      width = function() return P.inner(w) end,
      { id = "screenshot-ocr", label = "Copy text", icon = "document_scanner",
        visible = function() return model.readers:get().ocr == true end,
        on_clicked = function() model.read("ocr") end },
      { id = "screenshot-qr", label = "Copy QR code", icon = "qr_code_scanner",
        visible = function() return model.readers:get().qr == true end,
        on_clicked = function() model.read("qr") end },
    },
  }
end

local function recent(w)
  local function width() return P.inner(w) end
  local function cell() return (width() - 2 * S.s) / 3 end
  local function at(i) return model.recent:get()[i] end
  local row = {}
  for i = 1, model.RECENT do
    row[#row + 1] = kit.action {
      id = "screenshot-recent-" .. i, cursor = "pointer", accessible_name = "Open picture",
      x = function() return (cell() + S.s) * ((i - 1) % 3) end,
      y = function() return (cell() * 0.6 + S.s) * ((i - 1) // 3) end,
      width = cell, height = function() return cell() * 0.6 end,
      visible = function() return at(i) ~= nil end,
      on_clicked = function() local item = at(i) if item then model.open(item.path) end end,
      ui.Image {
        anchors = { fill = true }, fill_mode = "preserve_aspect_crop", source_width = 320,
        source = function() local item = at(i) return item and item.path or "" end,
      },
    }
  end
  row.id = "screenshot-recent-grid"
  row.width = width
  row.height = function()
    local n = #model.recent:get()
    return math.ceil(n / 3) * (cell() * 0.6 + S.s)
  end
  return P.section {
    id = "screenshot-recent", width = w, title = "Recent",
    visible = function() return #model.recent:get() > 0 end,
    ui.Item(row),
  }
end

--- The window's content, `w` by `h` (fns).
function M.build(w, h)
  return P.page {
    id = "screenshot-page", width = w, height = h,
    targets(w), options(w), readers(w), recent(w),
    P.empty and kit.text {
      id = "screenshot-folder", width = w, color = function() return C.onSurfaceVariant end,
      font_size = theme.size.small, text = function() return model.folder() end,
    } or nil,
  }
end

return M
