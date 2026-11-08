-- eva-large's page in the Tools window: the words to show, and controls that
-- show them, or the clipboard, huge across the screen. The showing itself is
-- eva-large's own program, over the whole screen.
local morf = require("morf")
local ui = require("morf.ui")
local P = require("themes.layouts.page")
local controls = require("apps.common.controls")
local overlay = require("apps.common.overlay_page")

local M = {}

-- What is typed to show.
local words = morf.signal("eva.tools.large.words", "")

local function show()
  local typed = words:get():match("^%s*(.-)%s*$")
  overlay.start("large", typed ~= "" and { typed } or { "--clipboard" })
end

--- The page, `w` by `h`.
function M.build(w, h)
  local inner = P.inner(w)
  local field = P.section { id = "large-words-section", width = w, title = "Words",
    ui.Item { width = inner, height = require("theme").space.TARGET,
      (controls.entry { id = "large-words", width = inner, value = words, placeholder = "What to show; empty, the clipboard",
        on_accepted = show }) } }
  return overlay.build({ id = "large",
    text = "Words huge across the screen, fitted to it, with a QR code beside them, until a press or Escape.",
    extra = { field },
    starts = { { id = "large-start", icon = "format_size", label = "Show them", run = show },
      { id = "large-clipboard", icon = "content_paste", label = "Show the clipboard",
        run = function() overlay.start("large", { "--clipboard" }) end } },
    keys = { { "A press, or Escape", "Ends it", "close" } } }, w, h)
end

M.verbs = {
  words = function(...) words:set(table.concat({ ... }, " ")) return true end,
  show = function() show() return true end,
}

return M
