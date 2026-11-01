-- Alt+Tab on the window stand-in.
local test = morf.test

local SCENE = [[{"focus":1,"clients":[
  {"class":"kitty","title":"one","workspace":1},
  {"class":"firefox","title":"web","workspace":1},
  {"class":"kitty","title":"two","workspace":2},
  {"class":"code","title":"edit","workspace":2}]}]]

local function load(extra)
  test.stub_run("task", { code = 0, stdout = "[]" })
  local env = { EVA_FAKE_WINDOWS = SCENE, EVA_DRY_RUN = "1" }
  for k, v in pairs(extra or {}) do env[k] = v end
  test.load("../shell/init.lua", { size = { 1920, 1080 }, env = env })
  test.advance(200)
end

local function active()
  for _, w in ipairs(test.ipc("windows")) do if w.focus_history == 0 then return w.title end end
end

test.it("a quick tap flips to the last window and draws nothing", function()
  load()
  test.eq(test.ipc("switcher", "next"), true)
  test.falsy(test.ipc("switcher", "state").shown, "drawn at once")
  test.eq(test.ipc("switcher", "state").title, "web")
  test.key("Alt_L", { phase = "up" })
  test.advance(16)
  test.falsy(test.ipc("switcher", "state").open)
  test.eq(active(), "web")
end)

test.it("a quick tap goes to the last window even when it is the same application's", function()
  load { EVA_FAKE_WINDOWS = [[{"focus":1,"clients":[
    {"class":"zzterm","title":"a","workspace":1},
    {"class":"zzterm","title":"b","workspace":1},
    {"class":"zzweb","title":"c","workspace":1}]}]] }
  test.ipc("switcher", "next")
  test.ipc("switcher", "commit")
  test.advance(16)
  test.eq(active(), "b", "it went to the next application, not the last window")
end)

test.it("a release that overtakes its key still flips to the last window", function()
  load()
  test.eq(test.ipc("switcher", "commit"), false)
  test.ipc("switcher", "next")
  test.advance(16)
  test.falsy(test.ipc("switcher", "state").open, "it stayed open with Alt already up")
  test.eq(active(), "web")
  test.advance(400)
  test.ipc("switcher", "next")
  test.truthy(test.ipc("switcher", "state").open, "a later press was taken for a quick tap")
end)

test.it("held, it shows one card per application, with the windows counted", function()
  load()
  test.ipc("switcher", "next")
  test.advance(300)
  test.truthy(test.ipc("switcher", "state").shown)
  test.truthy(test.get("switcher-card-1").visible)
  test.truthy(test.find("switcher-card-3"), "kitty's second window took a card of its own")
  test.falsy(test.find("switcher-card-4"), "one card too many")
  test.eq(test.text_of(test.get("switcher-count-1")), "2")
  test.ipc("switcher", "next")
  test.eq(test.ipc("switcher", "state").title, "edit")
  test.ipc("switcher", "prev")
  test.eq(test.ipc("switcher", "state").title, "web")
  test.key("Tab") test.eq(test.ipc("switcher", "state").title, "edit")
  test.key("Tab", "shift") test.eq(test.ipc("switcher", "state").title, "web")
  test.ipc("switcher", "commit")
  test.advance(16)
  test.eq(active(), "web")
end)

test.it("alt and the backtick walk one application's windows", function()
  load()
  test.ipc("switcher", "same")
  test.eq(test.ipc("switcher", "state").title, "two")
  test.ipc("switcher", "commit")
  test.advance(16)
  test.eq(active(), "two")
end)

test.it("escape goes nowhere, and a click chooses", function()
  load()
  test.ipc("switcher", "next", "free")
  test.advance(300)
  test.key("Escape")
  test.advance(16)
  test.falsy(test.ipc("switcher", "state").open)
  test.eq(active(), "one")
  test.ipc("switcher", "next", "free")
  test.advance(300)
  test.click("switcher-card-area-3")
  test.advance(16)
  test.eq(active(), "edit")
end)

test.it("its reach follows the scope setting", function()
  load()
  test.ipc("switcher_scope", "workspace")
  test.ipc("switcher", "next") test.advance(300)
  test.falsy(test.find("switcher-card-3"), "a window from another workspace")
end)
