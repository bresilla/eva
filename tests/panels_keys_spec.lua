-- How the panels close and how the keyboard walks them, on every form, and
-- what the Tasks page does as the list under it changes.
local test = morf.test
local UUID = "12345678-1234-1234-1234-123456789abc"
local function list(description, project)
  return morf.json.encode { { uuid = UUID, description = description, project = project, status = "pending" } }
end
local SOURCE = [[
  require("init")
  morf.ipc.open_list = function()
    local open = {}
    for _, d in ipairs(require("drawer").all) do if d.is_open() then open[#open + 1] = d.name end end
    table.sort(open)
    return table.concat(open, " ")
  end
]]
local loads = 0
local FORMS = { phone = { 868, 1932, true }, ["touchscreen alone"] = { 1280, 800, true }, desk = { 1920, 1080, false } }
local function load(style, form, stdout)
  test.stub_run("task", { code = 0, stdout = stdout or "[]" })
  loads = loads + 1
  local f = FORMS[form or "desk"]
  local env = { EVA_STYLE = style, EVA_WALLPAPER = "", EVA_FONT_FILE = "", EVA_DRY_RUN = "1",
    LULE_A = "/nonexistent/lule", HOME = morf.env("XDG_CACHE_HOME"),
    EVA_SETTINGS = morf.env("XDG_CACHE_HOME") .. "/keys-" .. loads .. ".json" }
  if f[3] then env.EVA_INPUT_DEVICES = morf.env("PWD") .. "/tests/fixtures/input-devices-touch" end
  test.load("../shell/init.lua", { size = { f[1], f[2] }, source = SOURCE, env = env })
  test.settle(1000)
end
local function shown() return test.ipc("open_list") end

local VERBS = { { "settings" }, { "notifications" }, { "tasks" }, { "calendar" }, { "assistant" }, { "drop" } }
for _, style in ipairs { "material", "tsugumori" } do
  for _, form in ipairs { "desk", "touchscreen alone", "phone" } do
    test.it(style .. " " .. form .. ": Escape and a press outside shut every panel", function()
      load(style, form)
      local w, h = FORMS[form][1], FORMS[form][2]
      for _, verb in ipairs(VERBS) do
        test.ipc(table.unpack(verb)) test.settle(900)
        test.truthy(shown() ~= "", verb[1] .. " did not open")
        test.click(shown():find("leftbar") and w - 80 or 80, h - 120) test.settle(800)
        -- A panel may stand over that corner: then the far one.
        if shown() ~= "" then test.click(w - 80, h - 80) test.settle(800) end
        if shown() ~= "" then test.click(w / 2, h / 2) test.settle(800) end
        test.eq(shown(), "", verb[1] .. " stayed open after a press outside")
        test.ipc(table.unpack(verb)) test.settle(900)
        test.key("Escape") test.settle(800)
        test.eq(shown(), "", verb[1] .. " stayed open after Escape")
      end
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it(style .. " Tab stays on the page on show", function()
    load(style)
    test.ipc("notifications") test.settle(1400)
    for _ = 1, 16 do
      test.key("Tab") test.advance(16)
      local stray = test.find(function(n) return n.focused and (n.id or ""):match("^utilities%-") end)
      test.falsy(stray, "Tab left Notifications for the Settings page beside it")
    end
  end)
end

test.it("tabs answer the arrows, and Tab goes from the tabs into the page", function()
  load("material")
  test.ipc("tasks") test.settle(1400)
  test.key("Tab") test.advance(16)
  local tabs = test.find(function(n) return n.focused end)
  test.truthy(tabs, "Tab reached nothing in the panel")
  test.key("Right") test.settle(900)
  test.truthy(test.find { id = "planner-today", visible = true }, "the arrow did not turn to Calendar")
end)

test.it("a task's row follows what became of it", function()
  load("material", "desk", list("Plan the launch", "work"))
  test.ipc("tasks") test.settle(1400)
  test.truthy(test.find { text = "Plan the launch", visible = true })
  test.stub_run("task", { code = 0, stdout = list("Plan the launch party", "home") })
  test.click("tasks-refresh") test.settle(600)
  test.truthy(test.find { text = "Plan the launch party", visible = true }, "the row kept its old title")
  test.truthy(test.find { text = "home", visible = true }, "the row kept its old project")
end)

test.it("a list that fails after it has loaded keeps its rows and says so once", function()
  load("material", "desk", list("Plan the launch", "work"))
  test.ipc("tasks") test.settle(1400)
  test.stub_run("task", { code = 2, stderr = "Task Database Error: Cannot create directory \"/home/x/.task\"" })
  test.click("tasks-refresh") test.settle(600)
  test.truthy(test.find { text = "Plan the launch", visible = true }, "the rows went with the failure")
  test.eq(test.get("tasks-error").text, "The task list could not be opened.")
  test.falsy(test.find { text = "Task Database Error", visible = true })
end)

test.it("a search that matches nothing says so, not that there are no tasks", function()
  load("material", "desk", list("Plan the launch", "work"))
  test.ipc("tasks") test.settle(1400)
  test.click("tasks-search") test.settle(100)
  test.type("zzz") test.settle(400)
  test.truthy(test.find { text = "Nothing in this view.", visible = true })
end)
