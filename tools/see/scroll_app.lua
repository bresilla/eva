-- A real window that scrolls, for the sealed session: numbered lines under a
-- header and over a footer that stand still, at a fixed size in whatever the
-- compositor gives it. Page Down scrolls it a page.
--
--     morf app tools/see/scroll_app.lua
local morf = require("morf")
local ui = require("morf.ui")
local app = require("lib.kit.app")

local LINES, LINE, HEADER, BODY, FOOTER, WIDTH = 120, 40, 56, 560, 40, 840
local PAGE_DOWN = 65366
local offset = morf.signal("see.scroll.offset", 0)

morf.surface.blend = "srgb"
morf.surface.namespace = "eva-see-scroll"

app.application {
  title = "Scroll", app_id = "see.scroll", width = WIDTH, height = HEADER + BODY + FOOTER,
  build = function()
    local rows = {}
    for i = 1, LINES do
      rows[i] = ui.Rect { y = (i - 1) * LINE, width = WIDTH, height = LINE, color = i % 2 == 0 and "#20303c" or "#263a48",
        ui.Text { x = 24, anchors = { vertical_center = true }, color = "#ffffff", font_size = 22,
          text = ("Line %03d of the long page"):format(i) },
        ui.Text { x = 520, anchors = { vertical_center = true }, color = "#ffcc66", font_size = 18,
          text = ("%08x"):format(i * 2654435761 % 4294967296) } }
    end
    return ui.MouseArea { anchors = { fill = true }, focus = true,
      on_key_pressed = function(key)
        if key == PAGE_DOWN then offset:set(math.min(LINES * LINE - BODY, offset:get() + BODY - LINE)) end
      end,
      ui.Rect { anchors = { fill = true }, color = "#101820" },
      ui.Item { y = HEADER, width = WIDTH, height = BODY, clip = true,
        ui.Item { y = function() return -offset:get() end, width = WIDTH, height = LINES * LINE, table.unpack(rows) } },
      ui.Rect { width = WIDTH, height = HEADER, color = "#0d3b66",
        ui.Text { x = 24, anchors = { vertical_center = true }, color = "#ffffff", font_size = 26, text = "Sticky header" } },
      ui.Rect { y = HEADER + BODY, width = WIDTH, height = FOOTER, color = "#5c2a2a",
        ui.Text { x = 24, anchors = { vertical_center = true }, color = "#ffffff", font_size = 20, text = "Sticky footer" } },
    }
  end,
}
