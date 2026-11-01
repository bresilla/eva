-- The smallest tool: proves the frame, the palette and the appearance.
local theme = require("theme")
local P = require("themes.layouts.page")
local frame = require("common.frame")
local C = theme.color

frame.open {
  id = "hello", title = "Hello", width = 640, height = 400,
  build = function(w, h)
    return P.page {
      id = "hello-page", width = w, height = h,
      P.section {
        id = "hello-section", width = w, title = "Appearance",
        P.row { id = "hello-theme", width = function() return P.inner(w) end, icon = "palette",
          title = theme.appearance.id, subtitle = function() return "primary " .. C.primary:hex() end },
      },
    }
  end,
}
