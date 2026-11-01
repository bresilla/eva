-- A row's note reads in full: a long one wraps, and the row grows to hold it.
--
--     morf test tests/page_row_spec.lua

local test = morf.test

local LONG = "A note far too long for one line of this row, that goes on and on until a second line is not enough"
local HOST = ([[
  local ui = require("morf.ui")
  local P = require("themes.layouts.page")
  ui.Column { width = 300,
    P.row { id = "short", width = 300, height = 44, icon = "info", title = "Short", subtitle = "Fits" },
    P.row { id = "long", width = 300, height = 44, icon = "info", title = "Long", subtitle = %q },
    ui.Item { id = "under", width = 300, height = 10 },
    P.row { id = "named", width = 300, height = 44, icon = "info", title = %q },
  }
]]):format(LONG, LONG)

local LISTED = ([[
  local ui = require("morf.ui")
  local P = require("themes.layouts.page")
  local F = require("themes.layouts.form")
  ui.Column { width = 300,
    F.list(300, "slot-", function() return 2 end, function(index, width)
      return P.row { id = "listed-" .. index, width = width, icon = "info", title = "Row", subtitle = %q }
    end, nil, 2),
    ui.Item { id = "after", width = 300, height = 10 },
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
  test.it(style .. ": a list's slot grows with its row", function()
    test.load("../shell/init.lua", { source = LISTED, size = { 400, 500 }, env = { EVA_STYLE = style } })
    test.settle(1000)
    local first, second = test.get("listed-1"), test.get("listed-2")
    test.truthy(second.y >= first.y + first.height, "the rows stand apart")
    test.truthy(test.get("after").y >= second.y + second.height, "what follows clears the list")
  end)
  test.it(style .. ": a caption's note stands in full on the card's width", function()
    test.load("../shell/init.lua", { source = CAPTION, size = { 500, 200 }, env = { EVA_STYLE = style } })
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
  test.it(style .. ": a long note wraps and pushes down what follows", function()
    test.load("../shell/init.lua", { source = HOST, size = { 400, 400 }, env = { EVA_STYLE = style } })
    test.settle(1000)
    test.eq(test.get("short").height, 44)
    local note = test.get("long-subtitle")
    test.truthy(note.height >= 2 * test.get("short-subtitle").height, "the note took a second line")
    test.truthy(test.get("long").height > 44, "the row grew")
    test.truthy(test.get("under").y >= note.y + note.height, "what follows clears the note")
    test.truthy(test.get("named-title").height >= 2 * test.get("short-title").height, "a long title wraps too")
  end)
end
