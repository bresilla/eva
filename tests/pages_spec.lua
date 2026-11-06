-- Which panel holds which page: every verb, shortcut and launcher row lands a
-- page in the panel that holds it on this form; on a phone that is the sheet,
-- and the desk's left and bottom panels are not built at all.
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
  morf.ipc.sheet_h = function() return require("drawer").sidebar.panel.height end
]]
local loads = 0
local FORMS = {
  phone = { 868, 1932, true }, desk = { 1920, 1080, false },
  ["touchscreen alone"] = { 1280, 800, true },
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

local SHEETED = { "phone" }
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

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " a touchscreen alone has a desk's panels, and each verb lands in its own", function()
    load(style, "touchscreen alone")
    test.eq(where().form, "desk")
    test.truthy(where().left, "no left drawer")
    test.truthy(where().bottom, "no bottom drawer")
    for _, case in ipairs { { "tasks", "leftbar" }, { "calendar", "leftbar" }, { "assistant", "bottom" },
      { "drop", "bottom" }, { "notifications", "sidebar" } } do
      test.ipc(case[1]) test.settle(900)
      test.eq(where().open, case[2], case[1])
      test.eq(where().showing, case[1])
      shut()
    end
    test.eq(#test.logs("error"), 0)
  end)
end

-- The launcher's rows for the shell's own pages: `!NAME`, and Return runs the first.
local function launch(query)
  test.ipc("launcher", "query", query) test.settle(1200)
end

for _, form in ipairs(SHEETED) do
  test.it(form .. " launcher rows land on the sheet", function()
    load("material", form)
    for _, key in ipairs { "tasks", "calendar", "assistant", "drop", "notifications", "settings" } do
      local name = key:sub(1, 1):upper() .. key:sub(2)
      launch("!" .. key)
      test.truthy(test.find { text = name, visible = true }, "no row for " .. key)
      test.key("Return") test.settle(900)
      test.eq(where().open, "sidebar", key)
      test.eq(where().showing, key)
      shut()
    end
    test.eq(#test.logs("error"), 0)
  end)

  test.it(form .. " shortcuts land on the sheet", function()
    load("material", form)
    test.ipc("sidebar", "open", "settings") test.settle(700)
    for _, case in ipairs { { "t", "ctrl", "tasks" }, { "c", "ctrl+shift", "calendar" }, { "n", "ctrl", "notifications" } } do
      test.key(case[1], case[2]) test.settle(700)
      test.eq(where().open, "sidebar", case[3])
      test.eq(where().showing, case[3], "a shortcut shut the sheet instead of turning to its page")
    end
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("on a desk launcher rows and shortcuts land where the page is held", function()
  load("material", "desk", { right = { "settings", "calendar" }, left = { "notifications" }, bottom = { "tasks" } })
  launch("!calendar")
  test.key("Return") test.settle(1000)
  test.eq(where().open, "sidebar")
  test.eq(where().showing, "calendar")
  test.key("t", "ctrl") test.settle(1000)
  test.eq(where().showing, "tasks")
  test.truthy(where().open:find("bottom", 1, true), "Ctrl+T did not reach the panel holding Tasks")
end)

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
  launch("!tasks")
  test.truthy(test.find { text = "Tasks", visible = true }, "the rows were not listed at all")
  test.ipc("close") test.settle(600)
  launch("!drop")
  test.falsy(test.find { text = "Drop", visible = true }, "a row for a page with nowhere to land")
  test.eq(#test.logs("error"), 0)
end)

test.it("Settings cannot be lost, and a page named twice stays in the first", function()
  load("material", "desk", { right = { "notifications", "tasks" }, left = { "tasks", "nonsense" }, bottom = {} })
  test.eq(test.ipc("keys", "right"), { "settings", "notifications", "tasks" })
  test.eq(test.ipc("keys", "left"), {})
  test.eq(test.ipc("panel_of", "settings"), "sidebar")
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. " a panel left with no pages builds quietly and does not open", function()
    load(style, "desk", { right = { "settings", "tasks", "calendar", "notifications", "assistant", "drop" }, left = {}, bottom = {} })
    test.ipc("leftbar", "open") test.settle(500)
    test.ipc("bottom", "open") test.settle(500)
    test.eq(where().open, "")
    test.eq(#test.logs("error"), 0)
    test.eq(#test.logs("warn"), 0)
  end)
end

test.it("the quick controls reach whichever panel holds Settings, and its pages the window", function()
  load("material", "desk", { right = { "notifications" }, left = { "settings", "tasks" }, bottom = { "assistant" } })
  test.ipc("settings") test.settle(1200)
  test.eq(where().open, "leftbar")
  test.eq(where().showing, "settings")
  test.ipc("settings", "theme") test.settle(1200)
  test.eq(where().open, "", "the panel stayed open under the Settings window")
  test.eq(test.ipc("settings", "state").page, "theme")
  shut()
  test.ipc("quick", "edit") test.settle(1200)
  test.eq(where().keyboard, "on_demand")
  test.eq(where().open, "leftbar")
end)

test.it("phone sheet fits what each page holds", function()
  load("material", "phone")
  local most = 1400
  for _, verb in ipairs { "drop", "assistant", "notifications" } do
    test.ipc(verb) test.settle(1500)
    test.truthy(test.ipc("sheet_h") < most, verb .. " left the sheet tall: " .. test.ipc("sheet_h"))
    shut()
  end
  test.ipc("settings", "panels") test.settle(1500)
  test.truthy(test.ipc("sheet_h") < most, "a Settings page took the whole sheet: " .. test.ipc("sheet_h"))
end)
