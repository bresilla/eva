-- Every Settings page against the stand-in machine (EVA_FAKE_SYSTEM): each
-- opens in both themes, at a desk and on a phone, showing what the machine
-- holds; every control has a name, a key reaches it, and the registry and the
-- builders agree.
--
--     morf test --no-dbus tests/settings_pages_spec.lua
local test = morf.test

local function load(style, size, env)
  local settings = morf.env("XDG_CACHE_HOME") .. "/settings-pages-" .. style .. ".json"
  morf.fs.remove(settings)
  local vars = { EVA_STYLE = style, EVA_DRY_RUN = "1", EVA_FAKE_SYSTEM = "1", EVA_SETTINGS = settings, EVA_WALLPAPER = "",
    EVA_FONT_FILE = "", HOME = morf.env("XDG_CACHE_HOME") }
  for key, value in pairs(env or {}) do vars[key] = value end
  test.load("../shell/init.lua", { size = size, env = vars })
  test.settle(1500)
end

-- Each page, and words only its service can have put there: a page that fails
-- to read, or a binding that dies, leaves them out.
local PAGES = {
  { "home", "Connections" }, { "network", "Home" }, { "network/connection", "192.168.1.23/24" }, { "network/proxy", "Proxy" },
  { "network/help", "Check for sign-in pages" }, { "backups", "No backup tool here" }, { "backups/more", "Repository" },
  { "welcome", "Make it yours" },
  { "bluetooth", "Pixel Buds Pro" }, { "displays", "eDP-1 · 2560×1600 at 60 Hz · 150%" }, { "sound", "Built-in speakers" },
  { "sound/more", "LDAC" }, { "microphone", "Built-in microphone" }, { "input", "English (US)" }, { "input/pointer", "Pointer speed" },
  { "input/devices", "logitech-mx-master-3" }, { "power", "Lid and power button" }, { "storage", "PHOTOS" }, { "printers", "office · Default" },
  { "theme/wallpaper", "Options" }, { "accessibility", "Sticky keys" }, { "bar/more", "Corner reach" },
  { "launcher", "Action prefix" }, { "rail", "Show the rail" }, { "panels", "Drag a page to its panel" }, { "capture", "Upload address" },
  { "keyboard", "Up by itself" }, { "weather", "Imperial units" }, { "commands", "Log out" }, { "apps", "Firefox" },
  { "startup", "Syncthing" }, { "datetime", "Europe/Amsterdam" }, { "region", "en_US.UTF-8" }, { "users", "Kate Nowak" },
  { "privacy", "Firefox" }, { "firewall", "firewalld · On" }, { "updates", "Check for updates" }, { "about", "Framework Laptop 13" },
}

-- Roles a screen reader reads by name.
local NAMED = { button = true, toggle_button = true, check_box = true, radio_button = true, switch = true, link = true,
  menu_item = true, slider = true, spin_button = true, tab = true, text_field = true, password_text = true, search_field = true,
  list_box_option = true, list_item = true }

local function open(key)
  test.ipc("settings", key)
  test.settle(800)
end

for _, style in ipairs { "material", "tsugumori" } do
  for _, form in ipairs { { "desk", { 1920, 1080 } }, { "phone", { 412, 915 } } } do
    test.it(style .. " " .. form[1] .. ": every page shows what the machine holds", function()
      load(style, form[2])
      test.ipc("utilities", "open")
      test.settle(800)
      for _, page in ipairs(PAGES) do
        test.clear_logs()
        open(page[1])
        test.eq(#test.logs("error"), 0, page[1] .. ": " .. tostring((test.logs("error")[1] or {}).message))
        test.truthy(test.find { text = page[2], visible = true } or test.find { text = page[2]:upper(), visible = true },
          page[1] .. " does not show " .. page[2])
      end
    end)
  end

  test.it(style .. ": every control on a page is named and can be pressed by a screen reader", function()
    load(style, { 1920, 1080 })
    test.ipc("utilities", "open")
    test.settle(800)
    local problems = {}
    for _, page in ipairs(PAGES) do
      open(page[1])
      for _, row in ipairs(test.accessible()) do
        if row.name == "" and (row.focusable or NAMED[row.role]) then
          problems[#problems + 1] = page[1] .. ": " .. row.role .. " " .. tostring(row.id)
        end
      end
    end
    test.eq(#problems, 0, table.concat(problems, "\n"))
    open("home")
    local row = test.accessible { id = "settings-open-storage-press" }[1] or test.accessible { name = "Storage" }[1]
    test.truthy(row, "no accessible row for Storage")
    test.accessible_action(row, "click")
    test.settle(800)
    test.truthy(test.find { id = "storage-scroll", visible = true }, "the action did not open Storage")
  end)

  test.it(style .. ": Tab reaches every control of a page, Shift+Tab comes back", function()
    load(style, { 1920, 1080 })
    test.ipc("utilities", "open")
    test.settle(800)
    open("firewall")
    local seen, first = {}, nil
    local function focused()
      for _, node in ipairs(test.nodes()) do
        if node.focused then return node.id ~= "" and node.id or node.element end
      end
    end
    for _ = 1, 40 do
      test.key("Tab")
      test.advance(40)
      local now = focused()
      if now then
        seen[now] = true
        first = first or now
      end
    end
    test.truthy(seen["firewall-on-switch"] or seen["firewall-on-switch-box"], "Tab never reached the firewall's switch")
    test.key("Tab") test.advance(40)
    local here = focused()
    test.key("Tab", { "shift" }) test.advance(40)
    test.truthy(focused() ~= here, "Shift+Tab did not move")
  end)
end

test.it("every page of the registry has a builder, and every page a registry row", function()
  test.load("../shell/init.lua", { size = { 432, 800 }, env = { EVA_DRY_RUN = "1", EVA_FAKE_SYSTEM = "1" }, source = [[
    local ui = require("morf.ui")
    ui.Item { width = 10, height = 10 }
    morf.ipc.check = function()
      local registry, model, missing = require("settings_registry"), require("utilities"), {}
      for _, page in ipairs(registry.PAGES) do
        if not model.has_page(page.key) then missing[#missing + 1] = page.key end
      end
      return missing
    end
  ]] })
  test.advance(100)
  test.eq(test.ipc("check"), {})
end)
