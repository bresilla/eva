-- The tray's Settings page on a real bar model: each item's place and order, its
-- limit, and where it is offered.
--
--     morf test --no-dbus tests/tray_page_spec.lua

local test = morf.test

local function load(style, size)
  local settings = morf.env("XDG_CACHE_HOME") .. "/tray-page-" .. style .. ".json"
  morf.fs.remove(settings)
  test.load("../shell/init.lua", { source = [[
    require("init")
    local function tray() return require("bar").model and require("bar").model.tray end
    morf.ipc.seed = function()
      require("config").set("edgebar.enabled", "on")
      require("config").set("edgebar.tray_items", { { id = "notes", title = "Notes", place = "bar" },
        { id = "chat", title = "Chat", place = "more" } })
      return true
    end
    morf.ipc.kept = function() return require("config").get("edgebar.tray_items") end
    morf.ipc.limit = function() return require("config").get("edgebar.tray_limit") end
    morf.ipc.present = function(key) return require("settings_model").page_present(key) end
    morf.ipc.found = function(word)
      local out = {}
      for _, entry in ipairs(require("settings_registry").search(word)) do out[#out + 1] = entry.name end
      return out
    end
  ]], size = size or { 1920, 1080 }, env = { EVA_STYLE = style, EVA_SETTINGS = settings, EVA_DRY_RUN = "1", EVA_FAKE_SYSTEM = "1",
    EVA_WALLPAPER = "", EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(800)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it(style .. ": the page lists the items, and sets their place and order", function()
    load(style)
    test.ipc("seed") test.settle(300)
    test.ipc("utilities", "open") test.settle(600)
    test.ipc("settings", "bar/tray") test.settle(900)
    test.truthy(test.find { id = "bar-tray-scroll", visible = true })
    test.truthy(test.find { id = "tray-row-2", visible = true })
    test.click("tray-row-1-place") test.settle(200)
    test.eq(test.ipc("kept")[1].place, "more")
    test.click("tray-row-2-up") test.settle(200)
    test.eq(test.ipc("kept")[1].id, "chat")
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("a phone has no tray, so no page", function()
  load("material", { 412, 915 })
  test.falsy(test.ipc("present", "bar/tray"))
end)

test.it("Settings search finds it", function()
  load("material")
  test.contains(table.concat(test.ipc("found", "overflow"), ","), "Tray items")
  test.contains(table.concat(test.ipc("found", "tray icon"), ","), "Hide a tray icon")
end)
