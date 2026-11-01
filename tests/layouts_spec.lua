-- Saved window layouts: what is kept, which running window is which, where each
-- goes back, and what is said about those that cannot come back. The stand-in
-- compositor here; nix/tests/windows.py restores real windows on Hyprland 0.55.4.
--
--     morf test --no-dbus tests/layouts_spec.lua

local test = morf.test

local HOST = [[
  require("init")
  local lib = require("lib.services.window_layouts")
  local layouts = require("layouts_model")
  local windows = require("windows_model")
  morf.ipc.where = function(title)
    for _, c in ipairs(windows.list()) do
      if c.title == title then return { workspace = c.workspace, floating = c.floating } end
    end
  end
  morf.ipc.send_to = function(title, id)
    for _, c in ipairs(windows.list()) do
      if c.title == title then return windows.to_workspace(c.address, tonumber(id), false) end
    end
  end
  morf.ipc.close_all = function(title)
    for _, c in ipairs(windows.list()) do
      if c.title == title then windows.close(c.address) end
    end
    return true
  end
  morf.ipc.text = function() return layouts.report_text() end
  morf.ipc.pure = function(which)
    if which == "match" then
      local saved = { { class = "a", title = "one" }, { class = "a", title = "two" }, { class = "b", title = "x" } }
      local running = { { class = "a", title = "two", address = "2" }, { class = "a", title = "else", address = "1" } }
      local got, missing = lib.match(saved, running)
      local out = {}
      for _, pair in ipairs(got) do out[pair.saved.title] = pair.window.address end
      return { out = out, missing = #missing, label = lib.label(missing[1]) }
    end
    if which == "placed" then
      local saved = { workspace = 2, floating = true, x = 10, y = 10, width = 100, height = 100 }
      return { lib.placed(saved, { workspace = 2, floating = true, x = 11, y = 9, width = 100, height = 100 }),
        lib.placed(saved, { workspace = 2, floating = true, x = 40, y = 9, width = 100, height = 100 }),
        lib.placed({ workspace = 3, floating = false }, { workspace = 3, floating = false, x = 400 }),
        lib.placed({ workspace = 3, floating = false }, { workspace = 3, floating = true }) }
    end
  end
  morf.ipc.present = function(key) return require("settings_model").page_present(key) end
  morf.ipc.found = function(word)
    local out = {}
    for _, entry in ipairs(require("settings_registry").search(word)) do out[#out + 1] = entry.name end
    return out
  end
]]

local function load(name, style, size)
  local settings = morf.env("XDG_CACHE_HOME") .. "/layouts-" .. name .. ".json"
  morf.fs.remove(settings)
  test.load("../shell/init.lua", { source = HOST, size = size or { 1920, 1080 }, env = { EVA_STYLE = style or "material",
    EVA_SETTINGS = settings, EVA_DRY_RUN = "1", EVA_FAKE_WINDOWS = "1", EVA_WALLPAPER = "", EVA_FONT_FILE = "",
    HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(800)
end

test.it("the same class and title first, then the class, and what is left is missing", function()
  load("match")
  local got = test.ipc("pure", "match")
  test.eq(got.out, { two = "2", one = "1" })
  test.eq(got.missing, 1)
  test.eq(got.label, "b")
end)

test.it("a floating window must stand exactly, a tiled one on its workspace", function()
  load("placed")
  test.eq(test.ipc("pure", "placed"), { true, false, true, false })
end)

local function save(name)
  test.ipc("layouts", "save", name)
  test.settle(500)
end

test.it("a layout needs a name, and keeps every workspace's windows", function()
  load("save")
  save(" ")
  test.eq(test.ipc("layouts", "list"), {})
  save("work")
  local saved = test.ipc("layouts", "list")[1]
  test.eq(saved.name, "work")
  test.eq(#saved.windows, 7, "the scratchpad's window is not on a workspace")
end)

test.it("saving a name again replaces it", function()
  load("again")
  save("work")
  save("work")
  test.eq(#test.ipc("layouts", "list"), 1)
end)

test.it("restore moves a window back to its workspace", function()
  load("restore")
  save("work")
  test.eq(test.ipc("where", "btop").workspace, 2)
  test.ipc("send_to", "btop", 5) test.settle(100)
  test.eq(test.ipc("where", "btop").workspace, 5)
  test.eq(test.ipc("layouts", "restore", "work"), true)
  test.settle(500)
  test.eq(test.ipc("where", "btop").workspace, 2)
  test.eq(test.ipc("layouts", "report").moved, 1)
end)

test.it("what cannot be started is named, and the words say so", function()
  load("cannot")
  save("work")
  test.ipc("close_all", "btop") test.settle(100)
  test.eq(test.ipc("layouts", "restore", "work"), true)
  test.settle(500)
  local report = test.ipc("layouts", "report")
  test.truthy(#report.missing + #report.late == 1, "the closed window is accounted for")
  test.contains(test.ipc("text"), "work: 0 moved")
end)

test.it("no such layout answers no", function()
  load("none")
  test.eq(test.ipc("layouts", "restore", "nothing"), false)
end)

test.it("deleting the layout chosen for login clears the choice", function()
  load("login")
  save("work")
  test.ipc("layouts", "login", "work")
  test.ipc("layouts", "remove", "work")
  test.eq(test.ipc("layouts", "list"), {})
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the page saves, restores and says what is not restored", function()
    load("page-" .. style, style)
    save("work")
    test.ipc("utilities", "open") test.settle(600)
    test.ipc("settings", "windows") test.settle(900)
    test.truthy(test.find { id = "windows-layouts", visible = true })
    test.ipc("settings", "windows/layouts") test.settle(900)
    test.truthy(test.find { id = "layouts-row-1", visible = true })
    test.click("layouts-restore-1") test.advance(500)
    test.truthy(test.ipc("layouts", "report"))
    test.settle(300)
    test.truthy(test.find { id = "layouts-report", visible = true })
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("a phone has no layouts page: it shows one window at a time", function()
  load("phone", "material", { 412, 915 })
  test.falsy(test.ipc("present", "windows/layouts"))
end)

test.it("Settings search finds them", function()
  load("search")
  test.contains(table.concat(test.ipc("found", "layout"), ","), "Saved layouts")
  test.contains(table.concat(test.ipc("found", "after login"), ","), "Restore a layout after login")
end)
