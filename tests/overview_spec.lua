-- The overview on the window stand-in: it runs the real shell, and everything
-- sent to the compositor is read back from the stand-in's list.
local test = morf.test

local function load(style, size, scene)
  test.stub_run("task", { code = 0, stdout = "[]" })
  test.load("../shell/init.lua", { size = size or { 1920, 1080 },
    env = { EVA_STYLE = style or "material", EVA_FAKE_WINDOWS = scene or "1", EVA_DRY_RUN = "1" } })
  test.advance(200)
end

local function by_title(title)
  for _, w in ipairs(test.ipc("windows")) do if w.title == title then return w end end
end

test.it("cards keep their shape, fit the area and stay apart", function()
  test.load("../shell/init.lua", { source = [[
    local m = require("overview_model")
    morf.ipc.calc = function()
      local area = { x = 0, y = 0, width = 1000, height = 600 }
      return { four = m.arrange({ { width = 800, height = 600 }, { width = 800, height = 600 },
          { width = 400, height = 600 }, { width = 400, height = 600 } }, area, 16),
        one = m.arrange({ { width = 200, height = 100 } }, area, 16),
        none = m.arrange({}, area, 16),
        strip = m.strip(4, { x = 0, y = 0, width = 400, height = 100 }, 16 / 9, 8),
        hit = m.hit({ a = { x = 0, y = 0, width = 10, height = 10 } }, 5, 5),
        miss = m.hit({ a = { x = 0, y = 0, width = 10, height = 10 } }, 50, 5) or "none",
        right = m.step({ a = { x = 0, y = 0, width = 10, height = 10 }, b = { x = 100, y = 0, width = 10, height = 10 },
          c = { x = 0, y = 100, width = 10, height = 10 } }, "a", 1, 0) }
    end
    return require("morf.ui").Item { width = 10, height = 10 }
  ]] })
  local r = test.ipc("calc")
  test.eq(#r.four, 4)
  for i, box in ipairs(r.four) do
    test.truthy(box.x >= 0 and box.y >= 0 and box.x + box.width <= 1000.01 and box.y + box.height <= 600.01, "card " .. i .. " left the area")
    for j, other in ipairs(r.four) do
      if i < j then
        local apart = box.x + box.width + 15 < other.x or other.x + other.width + 15 < box.x
          or box.y + box.height + 15 < other.y or other.y + other.height + 15 < box.y
        test.truthy(apart, "cards " .. i .. " and " .. j .. " touch")
      end
    end
  end
  test.near(r.four[1].width / r.four[1].height, 800 / 600, .01, "a card changed shape")
  test.eq({ r.one[1].width, r.one[1].height }, { 200, 100 }, "a small window was blown up")
  test.eq(r.none, {})
  test.truthy(r.strip[4].x + r.strip[4].width <= 400.01, "the strip left its area")
  test.eq({ r.hit, r.miss, r.right }, { "a", "none", "b" })
end)

test.it("typing finds windows on every workspace, and Return goes there", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  test.type("mailx") test.key("BackSpace") test.advance(100)
  test.truthy(test.find(function(n) return n.id == "overview-card-title-1" and not n.exiting and n.visible end)
    or test.find({ text = "Mail", visible = true }), "no card")
  test.eq(test.get("overview-search").text, "mail", "the field does not show what was typed")
  test.falsy(test.find({ text = "btop", visible = true }), "the filter left others")
  test.key("Return") test.advance(100)
  test.eq(test.ipc("overview", "state"), false)
  test.eq(test.ipc("windows")[1].title, "Mail", "Return did not go to the window")
end)

test.it("nothing matching says so", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  test.type("zzzz") test.advance(100)
  test.truthy(test.get("overview-empty").visible)
end)

test.it("the arrows walk the cards, a press goes there, and the close button closes", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  test.truthy(test.get("overview-card-focus-1").visible)
  test.key("Right") test.advance(50)
  test.falsy(test.find({ id = "overview-card-focus-1", visible = true }), "the keys did not move")
  test.truthy(test.get("overview-card-focus-2").visible or test.get("overview-card-focus-3").visible, "the keys went nowhere")
  test.key("Delete") test.advance(100)
  test.eq(#test.ipc("windows"), 7, "Delete did not close the card")
  test.click("overview-card-area-1") test.advance(100)
  test.eq(test.ipc("overview", "state"), false, "a press did not go there")
end)

test.it("the middle button closes a card, and the right one offers the rest", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  local card = test.get("overview-card-area-1")
  local x, y = card.x + card.width / 2, card.y + card.height / 2
  test.click(x, y, { button = "right" }) test.advance(100)
  test.truthy(test.get("overview-menu").visible, "no menu")
  test.key("Escape") test.advance(100)
  test.click(x, y, { button = "middle" }) test.advance(100)
  test.eq(#test.ipc("windows"), 7)
end)

test.it("the strip walks the workspaces", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  test.click("overview-desk-area-2") test.advance(100)
  test.eq(test.get("overview-card-title-1") ~= nil, true)
  test.contains(test.text_of(test.get("overview-track")), "btop")
  test.key("Page_Down") test.advance(100)
  test.contains(test.text_of(test.get("overview-track")), "Pictures")
  test.ipc("overview", "app") test.advance(100)
end)

test.it("one application's windows, wherever they are", function()
  load()
  test.ipc("overview", "app") test.settle(3000)
  test.truthy(test.find("overview-card-2"), "kitty's second window is missing")
  test.falsy(test.find("overview-card-3"))
end)

test.it("a second monitor's workspaces, with sparse ids, join the strip", function()
  load("material", nil, '{"second_monitor":true,"clients":[{"class":"kitty","title":"one","workspace":1}]}')
  test.eq(test.ipc("overview", "open"), true)
  test.settle(3000)
  test.truthy(test.get("overview-desk-1").visible)
  test.truthy(test.get("overview-desk-11").visible, "the second monitor's workspace is missing")
  test.eq(#test.logs("warn"), 0)
end)

test.it("it opens and shuts, each card flying from its window to a slot", function()
  load()
  test.eq(test.ipc("overview", "open"), true)
  test.advance(16)
  local card = test.get("overview-card-1")
  test.settle(3000)
  card = test.get("overview-card-1")
  test.truthy(card.visible, "no card")
  test.truthy(card.y > 200, "the card did not land under the strip")
  test.truthy(test.get("overview-desk-1").visible, "no strip")
  test.eq(test.ipc("overview", "state"), true)
  test.key("Escape")
  test.settle(3000)
  test.eq(test.ipc("overview", "state"), false)
  test.falsy(test.find({ id = "overview", visible = true }), "it stayed on the screen")
end)
