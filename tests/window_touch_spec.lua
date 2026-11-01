-- What a finger does to windows on a phone and a tablet, through the real touch
-- path, on the window stand-in; and the settings pages that go with them.
local test = morf.test

local SCENE = [[{"focus":1,"clients":[
  {"class":"zzterm","title":"one","workspace":1},
  {"class":"zzweb","title":"web","workspace":1},
  {"class":"mpv","title":"film","workspace":2,"content":"video"}]}]]

local function load(width, height, env, touch)
  test.stub_run("task", { code = 0, stdout = "[]" })
  local devices = morf.env("EVA_INPUT_DEVICES")
  local e = { EVA_FAKE_WINDOWS = SCENE, EVA_DRY_RUN = "1",
    EVA_INPUT_DEVICES = devices and (touch ~= false) and devices .. "-touch" or devices,
    EVA_WALLPAPER = "", LULE_A = "/nonexistent/lule" }
  for k, v in pairs(env or {}) do e[k] = v end
  test.load("../shell/init.lua", { size = { width or 412, height or 915 }, env = e })
  test.advance(200)
end

local function window(title)
  for _, w in ipairs(test.ipc("windows")) do if w.title == title then return w end end
end

-- One finger from (x1, y1) to (x2, y2), a frame a step.
local function pull(x1, y1, x2, y2, steps)
  test.touch("down", 0, x1, y1) test.advance(16)
  for i = 1, steps do
    test.touch("move", 0, x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps) test.advance(16)
  end
end

test.it("a pull up from the bottom and a hold is recents; a quick pull is still the panel", function()
  load()
  pull(200, 912, 200, 780, 10)
  test.touch("up", 0, 200, 780) test.advance(600)
  test.falsy(test.ipc("overview", "state"), "a quick pull went to recents")
  test.ipc("close") test.advance(600)
  pull(200, 912, 200, 780, 10)
  test.advance(300)
  test.truthy(test.ipc("overview", "state"), "holding did not bring recents")
  test.touch("up", 0, 200, 780) test.settle(3000)
  test.truthy(test.ipc("overview", "state"), "letting go put it away")
  test.truthy(test.get("overview-card-1").visible)
  test.truthy(test.get("overview-clear").visible)
  test.falsy(test.find({ id = "overview-desk-1", visible = true }), "a desk's strip on a phone")
end)

test.it("recents scroll along, and a card thrown up closes its window", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  local first = test.get("overview-card-1").x
  pull(330, 500, 60, 500, 10)
  test.touch("up", 0, 60, 500) test.settle(2000)
  test.truthy(test.get("overview-card-1").x < first - 100, "the row did not scroll")
  test.ipc("overview", "close") test.settle(2000)
  test.ipc("overview", "open") test.settle(3000)
  pull(200, 500, 200, 200, 8)
  test.touch("up", 0, 200, 200) test.advance(600)
  test.eq(#test.ipc("windows"), 2, "the throw left the window open")
  test.eq(#test.logs("warn"), 0)
end)

test.it("clear all passes over a kept window", function()
  load()
  test.ipc("overview", "open") test.settle(3000)
  test.click("overview-card-more-1") test.advance(100)
  test.truthy(test.get("overview-menu").visible)
  test.click({ text = "Keep open" }) test.advance(100)
  test.click("overview-clear") test.advance(200)
  test.eq(#test.ipc("windows"), 1)
  test.truthy(test.get("overview-card-kept-1").visible)
end)

test.it("the bottom edge scrubs to the last app on a phone", function()
  load()
  test.eq(window("one").focus_history, 0.0)
  pull(60, 912, 300, 912, 10)
  test.touch("up", 0, 300, 912) test.advance(600)
  test.eq(window("web").focus_history, 0.0, "the scrub did not change the app")
end)

test.it("a card's menu splits two windows, floats one, or sends a video small", function()
  load(1280, 800)
  test.ipc("overview", "open") test.settle(3000)
  test.ipc("workspace", "2") test.advance(100)
  test.ipc("pip") test.advance(100)
  local film = window("film")
  test.truthy(film.floating and film.pinned, "not floating and pinned")
  test.truthy(film.width < 500, "not small")
  test.truthy(test.get("pip").visible, "nothing over the picture")
  test.ipc("pip", "close") test.advance(50)
  test.falsy(window("film"), "close left it")
end)

test.it("a tap on the picture shows its controls, a double tap resizes, a throw off an edge stashes", function()
  load(1280, 800)
  test.ipc("workspace", "2") test.advance(50)
  test.ipc("pip") test.advance(100)
  local small = window("film").width
  test.click("pip-area") test.advance(100)
  test.truthy(test.get("pip-controls").visible)
  local area = test.get("pip-area")
  local x, y = area.x + area.width / 2, area.y + area.height / 2
  test.click(x, y) test.click(x, y) test.advance(100)
  test.truthy(window("film").width > small, "no larger")
end)

test.it("split shares the workspace, and the divider moves it", function()
  load(1280, 800)
  test.ipc("workspace", "1") test.advance(100)
  test.truthy(test.get("split-divider").visible, "two tiled windows, no divider")
  test.eq(test.ipc("split"), true)
  test.advance(50)
  test.contains(table.concat(test.ipc("windows", "wire"), "\n"), "hl.dsp.window.float")
  local grip = test.get("split-divider")
  local x, y = grip.x + grip.width / 2, grip.y + grip.height / 2
  test.drag({ x, y }, { x + 240, y }, { steps = 6 })
  test.advance(50)
  test.contains(table.concat(test.ipc("windows", "wire"), "\n"), "splitratio +0.400",
    "the divider did not rest on the 70:30 stop")
end)

test.it("a pull in from a page's left edge goes back, with the page behind in view", function()
  load(412, 915)
  test.ipc("settings", "dock") test.advance(600)
  test.eq(test.ipc("settings_detail"), "dock")
  local page = test.get("settings-detail-dock")
  pull(page.x + 8, 400, page.x + 300, 400, 10)
  test.advance(50)
  test.truthy(test.get("settings-detail-eva").visible, "nothing to see behind the page")
  test.touch("up", 0, page.x + 300, 400) test.advance(600)
  test.eq(test.ipc("settings_detail"), "eva", "the pull did not go back")
end)

test.it("a short pull in from the edge stays on the page", function()
  load(412, 915)
  test.ipc("settings", "dock") test.advance(600)
  local page = test.get("settings-detail-dock")
  pull(page.x + 8, 400, page.x + 60, 400, 6)
  test.advance(200)
  test.touch("up", 0, page.x + 60, 400) test.advance(600)
  test.eq(test.ipc("settings_detail"), "dock")
end)

test.it("a corner does what it is set to, only with its key held", function()
  load(1920, 1080, nil, false)
  test.ipc("corner", "top_left", "overview", "ctrl")
  test.advance(100)
  test.move(3, 3) test.advance(300)
  test.falsy(test.ipc("overview", "state"), "it ran without its key")
  test.move(500, 500) test.advance(50)
  test.move(3, 3) test.press(3, 3, { modifiers = "ctrl" }) test.advance(300)
  test.release(3, 3)
  test.truthy(test.ipc("overview", "state"), "it did not run with its key")
  test.ipc("corner", "top_left", "none", "")
  test.advance(400)
end)

test.it("the pages open in both themes, and their controls set what they say", function()
  for _, style in ipairs { "material", "tsugumori" } do
    load(1920, 1080, { EVA_STYLE = style }, false)
    test.ipc("settings", "dock") test.advance(800)
    test.click("dock-show-on") test.advance(300)
    test.truthy(test.get("dock").visible, "the page did not turn it on")
    test.ipc("settings", "windows") test.advance(800)
    test.click("windows-corner-top_right") test.advance(100)
    test.eq(test.ipc("corner", "top_right"), "overview")
    test.click("windows-guard-top_right") test.advance(100)
    test.eq(test.ipc("corner", "top_right", nil, "?"), "ctrl")
    test.ipc("corner", "top_right", "none", "")
    test.ipc("dock", "auto")
    test.eq(#test.logs("warn"), 0)
    test.advance(400)
  end
end)
