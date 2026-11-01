-- Which panel holds which page: every verb, shortcut and launcher row lands a
-- page in the panel that holds it on this form; on a phone or a tablet that is
-- the sheet, and the desk's left and bottom panels are not built at all.
local test = morf.test
local SOURCE = [[
  require("init")
  local pages = require("pages")
  morf.ipc.where = function()
    local drawer = require("drawer")
    local open = {}
    for _, d in ipairs(drawer.all) do if d.is_open() then open[#open + 1] = d.name end end
    table.sort(open)
    return { open = table.concat(open, " "), left = drawer.leftbar ~= nil, bottom = drawer.bottom ~= nil,
      showing = (function()
        for key in pairs(pages.all) do if pages.on_show(key) then return key end end
        return ""
      end)(),
      keyboard = morf.surface.keyboard_focus, form = require("responsive").form() }
  end
  morf.ipc.panel_of = function(key) return pages.panel_name(key) or "" end
  morf.ipc.keys = function(edge) return pages.keys(edge) end
  morf.ipc.set_panels = function(edge, json) require("config").set("panels." .. edge, morf.json.decode(json)) end
  morf.ipc.rows = function()
    local out = {}
    for _, row in ipairs(require("providers").system and require("providers").system("") or {}) do out[#out + 1] = row.id end
    return out
  end
  morf.ipc.sheet_h = function() return require("drawer").sidebar.panel.height end
  morf.ipc.run_key = function(name, how, tab) return morf.ipc[name](how, tab) end
]]
local loads = 0
local FORMS = {
  phone = { 868, 1932, true }, ["tablet upright"] = { 800, 1280, true }, ["tablet wide"] = { 1280, 800, true },
  desk = { 1920, 1080, false },
}
local function load(style, form, panels)
  test.stub_run("task", { code = 0, stdout = "[]" })
  loads = loads + 1
  local settings = morf.env("XDG_CACHE_HOME") .. "/pages-" .. loads .. ".json"
  if panels then morf.fs.write(settings, morf.json.encode { panels = panels }) end
  local f = FORMS[form or "desk"]
  local env = { EVA_STYLE = style, EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1",
    LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"), EVA_SETTINGS = settings }
  if f[3] then env.EVA_INPUT_DEVICES = morf.env("PWD") .. "/tests/fixtures/input-devices-touch" end
  test.load("../shell/init.lua", { size = { f[1], f[2] }, source = SOURCE, env = env })
  test.settle(1200)
end
local function where() return test.ipc("where") end
local function shut() test.ipc("close") test.settle(700) end

local SHEETED = { "phone", "tablet upright", "tablet wide" }
for _, style in ipairs { "material", "tsugumori" } do
  for _, form in ipairs(SHEETED) do
    test.it(style .. " " .. form .. " has no desk panels, and every verb lands on the sheet", function()
      load(style, form)
      test.falsy(where().left, "a left drawer was built")
      test.falsy(where().bottom, "a bottom drawer was built")
      for _, case in ipairs {
        { { "leftbar", "open" }, "tasks" }, { { "leftbar", "open", "calendar" }, "calendar" },
        { { "tasks" }, "tasks" }, { { "calendar" }, "calendar" },
        { { "bottom", "open" }, "assistant" }, { { "bottom", "open", "drop" }, "drop" },
        { { "assistant" }, "assistant" }, { { "drop" }, "drop" }, { { "notifications" }, "notifications" },
        { { "sidebar", "open", "tasks" }, "tasks" },
      } do
        test.ipc(table.unpack(case[1])) test.settle(500)
        test.eq(where().open, "sidebar", table.concat(case[1], " "))
        test.eq(where().showing, case[2], table.concat(case[1], " "))
        shut()
      end
      test.eq(#test.logs("error"), 0)
    end)
  end
end

test.it("the desk names reach the sheet through `drawers` too", function()
  load("material", "phone")
  test.ipc("drawers", "open", "leftbar") test.settle(500)
  test.eq(where().open, "sidebar")
end)

test.it("a phone's task field takes the keyboard from the sheet", function()
  load("material", "phone")
  test.eq(where().keyboard, "none")
  test.ipc("tasks") test.settle(500)
  test.eq(where().keyboard, "on_demand")
end)

test.it("the sheet reads the tasks: it polls while one of their pages is on show", function()
  load("material", "phone")
  test.ipc("calendar") test.advance(600)
  local polled = false
  for _, argv in ipairs(test.runs()) do if argv[1] == "task" then polled = true end end
  test.truthy(polled, "opening Calendar on the sheet never asked Taskwarrior")
end)

test.it("a toggle turns to its page, and shuts only that page", function()
  load("material", "phone")
  test.ipc("calendar") test.settle(500)
  test.ipc("tasks", "toggle") test.settle(500)
  test.eq(where().showing, "tasks", "it shut the sheet instead of turning to Tasks")
  test.ipc("tasks", "toggle") test.settle(700)
  test.eq(where().open, "")
end)

test.it("a closing verb leaves another page of the sheet alone", function()
  load("material", "phone")
  test.ipc("calendar") test.settle(500)
  test.eq(test.ipc("tasks", "close"), false)
  test.eq(where().open, "sidebar")
  test.eq(test.ipc("tasks", "state"), false)
  test.eq(test.ipc("calendar", "state"), true)
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " on a desk a moved page lands in the panel that holds it", function()
    load(style, "desk", { right = { "settings" }, left = { "tasks", "notifications" }, bottom = { "calendar", "assistant" } })
    test.eq(test.ipc("panel_of", "notifications"), "leftbar")
    test.ipc("notifications") test.settle(1200)
    test.eq(where().open, "leftbar")
    test.eq(where().showing, "notifications")
    shut()
    test.ipc("sidebar", "open", "calendar") test.settle(1200)
    test.eq(where().open, "bottom", "a verb on the old panel should follow the page")
    test.eq(where().showing, "calendar")
    test.truthy(test.get("bottom-tab-calendar"))
    test.falsy(test.find { id = "bottom-tab-drop" }, "`panels.bottom` did not decide the tabs")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("a page no panel holds has nowhere to land, and no launcher row", function()
  load("material", "desk", { right = { "settings" }, left = { "tasks" }, bottom = { "assistant" } })
  test.eq(test.ipc("panel_of", "drop"), "")
  test.eq(test.ipc("drop"), false)
  test.eq(where().open, "")
  test.eq(#test.logs("error"), 0)
end)

test.it("Settings cannot be lost, and a page named twice stays in the first", function()
  load("material", "desk", { right = { "notifications", "tasks" }, left = { "tasks", "nonsense" }, bottom = {} })
  test.eq(test.ipc("keys", "right"), { "settings", "notifications", "tasks" })
  test.eq(test.ipc("keys", "left"), {})
  test.eq(test.ipc("panel_of", "settings"), "sidebar")
end)

test.it("a panel left with no pages does not open", function()
  load("material", "desk", { right = { "settings", "tasks", "calendar", "notifications", "assistant", "drop" }, left = {}, bottom = {} })
  test.ipc("leftbar", "open") test.settle(500)
  test.ipc("bottom", "open") test.settle(500)
  test.eq(where().open, "")
  test.eq(#test.logs("error"), 0)
end)

test.it("Settings pages reach whichever panel holds Settings", function()
  load("material", "desk", { right = { "notifications" }, left = { "settings", "tasks" }, bottom = { "assistant" } })
  test.ipc("settings", "theme") test.settle(1200)
  test.eq(where().open, "leftbar")
  test.eq(where().showing, "settings")
  shut()
  test.ipc("quick", "edit") test.settle(1200)
  test.eq(where().keyboard, "on_demand")
  test.eq(where().open, "leftbar")
end)

for _, form in ipairs { "phone", "tablet upright" } do
  test.it(form .. " sheet fits what each page holds", function()
    load("material", form)
    local most = form == "phone" and 1400 or 1100
    for _, verb in ipairs { "drop", "assistant", "notifications" } do
      test.ipc(verb) test.settle(1500)
      test.truthy(test.ipc("sheet_h") < most, verb .. " left the sheet tall: " .. test.ipc("sheet_h"))
      shut()
    end
    test.ipc("settings", "panels") test.settle(1500)
    test.truthy(test.ipc("sheet_h") < most, "a Settings page took the whole sheet: " .. test.ipc("sheet_h"))
  end)
end
