-- A row's long title wraps and the row grows to hold it; a caption's note stands
-- beside its title, on the card's width.
--
--     morf test tests/page_row_spec.lua

local test = morf.test

local LONG = "A title far too long for one line of this row, so it goes on to a second"
local HOST = ([[
  local ui = require("morf.ui")
  local P = require("themes.layouts.page")
  ui.Column { width = 300,
    P.row { id = "short", width = 300, height = 44, icon = "info", title = "Short", subtitle = "Fits" },
    P.row { id = "long", width = 300, height = 44, icon = "info", title = %q, subtitle = "Fits" },
    ui.Item { id = "under", width = 300, height = 10 },
  }
]]):format(LONG)

local NOTE = "Camera and commands ask for the password first"
local CAPTION = ([[
  local ui = require("morf.ui")
  local kit = require("kit")
  local P = require("themes.layouts.page")
  ui.Column { width = 408,
    P.section { id = "noted", width = 408, title = "Shortcuts", note = %q },
    P.section { id = "held", width = 200, title = "Weather", note = "A place with a very long name that goes on and on" },
    kit.label { id = "natural", text = %q },
  }
]]):format(NOTE, NOTE)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": a caption's note stands in full on the card's width", function()
    test.load("../shell/init.lua", { source = CAPTION, size = { 500, 300 }, env = { EVA_STYLE = style } })
    test.settle(1000)
    local note = test.get(function(node) return (node.text or ""):lower() == NOTE:lower() end)
    test.truthy(note.width >= test.get("natural").width, "room for all its words")
    test.truthy(note.x + note.width <= test.get("noted").x + 408 + 1, "inside the card's width")
  end)
  if style == "material" then
    test.it("material: a note too long for a narrow tile stops short of its title", function()
      test.load("../shell/init.lua", { source = CAPTION, size = { 500, 300 }, env = { EVA_STYLE = style } })
      test.settle(1000)
      local note = test.get(function(node) return (node.text or ""):find("very long name", 1, true) ~= nil end)
      test.truthy(note.width <= 124, "it keeps to the caption's right")
    end)
  end
  test.it(style .. ": a long title wraps and pushes down what follows", function()
    test.load("../shell/init.lua", { source = HOST, size = { 400, 400 }, env = { EVA_STYLE = style } })
    test.settle(1000)
    test.eq(test.get("short").height, 44)
    local title = test.get("long-title")
    test.truthy(title.height >= 2 * test.get("short-title").height, "the title took a second line")
    test.truthy(test.get("long").height > 44, "the row grew")
    test.truthy(test.get("under").y >= title.y + title.height, "what follows clears the title")
  end)
end
