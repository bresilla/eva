-- Installing from the grid, and the Software page, over what the machine has.
-- Every system here is a stand-in: `flatpak` and `nix` are stubbed, or held back by
-- EVA_DRY_RUN, and nothing is installed or removed.
--
--     morf test --no-dbus tests/software_spec.lua
local test = morf.test
local host = assert(load(morf.fs.read(morf.env("PWD") .. "/tests/fixtures/launcher_host.lua")))()

local PHONE = { 620, 1380 }
local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"
local FLATPAK = "org.gnome.Chess\tChess\tPlay chess\t48.0\tflathub,fedora\n"
local NIX = morf.json.encode { ["legacyPackages.x86_64-linux.ripgrep"] = { version = "14.1", description = "Searches files" } }

local function phone(style, env, settings)
  env = env or {}
  settings = settings or {}
  settings.launcher = settings.launcher or {}
  settings.launcher.layout = "grid"
  env.EVA_INPUT_DEVICES = TOUCH
  test.stub_run("flatpak", { code = 0, stdout = FLATPAK })
  test.stub_run("nix", { code = 0, stdout = NIX })
  return host.load { style = style, size = PHONE, env = env, settings = settings }
end

local function found(name)
  test.wait(function()
    test.advance(16)
    return host.row(name) ~= nil
  end, 3000, name .. " never came")
end

local function ran(word)
  for _, argv in ipairs(test.runs()) do
    local line = table.concat(argv, " ")
    if line:find(word, 1, true) then return line end
  end
end

-- Which row of `prefix` shows `name`: the machine's own entries are listed too.
local function slot(prefix, name)
  for index = 1, 24 do
    local title = test.find { id = prefix .. index .. "-title", visible = true }
    if title and title.text == name then return index end
  end
end

-- Presses `id`, the page scrolled to bring it into view first.
local function press(id)
  for _ = 1, 60 do
    local node, sheet = test.get(id), test.get("settings-detail")
    if node.y > sheet.y and node.y + node.height < sheet.y + sheet.height - 4 then
      test.settle(400)
      node = test.get(id)
      test.click(node.x + node.width / 2, node.y + node.height / 2)
      return
    end
    test.wheel(0, node.y > sheet.y + sheet.height * 0.5 and 300 or -300, { x = sheet.x + sheet.width / 2, y = sheet.y + 200 })
    test.settle(200)
  end
  error("never came into view: " .. id)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " getting an app", function()
    test.it("goes from the grid's chip to what the machine can install", function()
      phone(style, { EVA_FAKE_SYSTEM = "1" })
      test.truthy(test.find { id = "launcher-chip-get" }, "no way there from the grid")
      local chips = test.get("launcher-chips")
      test.swipe({ chips.x + chips.width - 16, chips.y + 16 }, { chips.x + 16, chips.y + 16 }, { duration = 200 })
      test.settle(400)
      test.click { id = "launcher-chip-get" } test.settle(300)
      test.eq(test.ipc("state").query, "> get ")
      test.truthy(test.ipc("keyboard_open"), "the keyboard stayed down")
      host.search("> get chess", 700)
      found("Chess")
      test.eq(host.row("Chess").tag, "Flatpak")
    end)

    test.it("asks twice, then installs from the remote it came from", function()
      phone(style, { EVA_FAKE_SYSTEM = "1" })
      host.search("> get chess", 700)
      found("Chess")
      test.ipc("do_action_row", "Chess") test.settle(300)
      test.falsy(host.logged("flatpak install"), "one press installed it")
      test.matches(host.row("Chess").description, "Press again")
      test.ipc("do_action_row", "Chess") test.settle(400)
      test.truthy(host.logged("flatpak install --noninteractive -y flathub org.gnome.Chess"), "nothing would have run")
      test.falsy(ran("flatpak install"), "a dry run reached the program")
    end)

    test.it("installs from nixpkgs into the person's profile", function()
      phone(style, { EVA_FAKE_SYSTEM = "1" })
      host.search("> get ripgrep", 800)
      found("ripgrep")
      test.eq(host.row("ripgrep").tag, "Nix")
      test.ipc("do_action_row", "ripgrep") test.settle(300)
      test.ipc("do_action_row", "ripgrep") test.settle(400)
      test.truthy(host.logged("profile install nixpkgs#ripgrep"), "nothing would have run")
    end)

    test.it("says so on a machine with nothing to install with", function()
      phone(style, { PATH = host.path {} })
      test.falsy(test.find { id = "launcher-chip-get" }, "a chip that can only fail")
      host.search("> get chess", 300)
      test.truthy(host.row("Nothing here installs apps"), "no word on why")
    end)
  end)

  test.describe(style .. " the page", function()
    test.it("says plainly what a NixOS system cannot do from here", function()
      phone(style, { EVA_FAKE_SYSTEM = "nixos", EVA_FAKE_SOFTWARE = "fixture-editor=system,fixture-browser=flatpak,fixture-top=declared" })
      test.ipc("settings", "software") test.settle(900)
      test.truthy(test.find { id = "software-nixos", visible = true }, "no word on NixOS")
      test.matches(test.get("software-nixos-subtitle").text, "cannot be removed from here")
      local browser = slot("software-app-", "Fixture Browser")
      test.truthy(browser, "what can go is not listed")
      test.truthy(test.find { id = "software-remove-" .. browser, visible = true }, "what can go has no button")
      test.falsy(slot("software-app-", "Fixture Editor"), "a button that can only fail")
      test.falsy(slot("software-app-", "Fixture Top"), "a button that can only fail")
      test.truthy(test.find { id = "software-stays", visible = true })
      local why = {}
      for index = 1, 6 do
        local line = test.find { id = "software-kind-" .. index .. "-subtitle", visible = true }
        if line then why[#why + 1] = line.text end
      end
      test.matches(table.concat(why, " "), "Take it out of the configuration")
      test.matches(table.concat(why, " "), "Home Manager")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("removes on a second press, and only then", function()
      phone(style, { EVA_FAKE_SYSTEM = "1", EVA_FAKE_SOFTWARE = "fixture-browser=flatpak,fixture-editor=package,fixture-top=package" })
      test.ipc("settings", "software") test.settle(900)
      local browser = slot("software-app-", "Fixture Browser")
      press("software-remove-" .. browser) test.settle(200)
      test.falsy(host.logged("fixture-browser (dry run)"), "one press removed it")
      press("software-remove-" .. browser) test.settle(400)
      test.truthy(host.logged("flatpak uninstall --noninteractive -y --system fixture-browser"), "nothing would have run")
    end)

    test.it("brings a hidden app back", function()
      phone(style, nil, { launcher = { hidden = { "fixture-top" } } })
      test.ipc("settings", "software") test.settle(900)
      test.matches(test.get("software-hidden-1-title").text, "Fixture Top")
      press("software-show-1") test.settle(400)
      test.eq(test.ipc("setting", "launcher.hidden"), {})
      test.falsy(test.find { id = "software-hidden", visible = true }, "the section stayed")
    end)

    test.it("is found by search", function()
      phone(style)
      local keys = {}
      for _, hit in ipairs(test.ipc("settings-search", "uninstall")) do keys[#keys + 1] = hit.key end
      test.truthy(table.concat(keys, " "):find("software", 1, true))
    end)
  end)
end

test.it("one change at a time, and a failure says why", function()
  test.stub_run("flatpak", { code = 1, stderr = "no such ref" })
  host.load { size = PHONE, env = { EVA_DRY_RUN = "0", EVA_INPUT_DEVICES = TOUCH, EVA_FAKE_SOFTWARE = "fixture-editor=flatpak",
    PATH = host.path { "flatpak", "gio" } }, settings = { appearance = { sync = false }, launcher = { layout = "grid" } }, source_extra = [==[
    morf.ipc.remove_two = function()
      local apps, software = require("apps"), require("software_model")
      local first = software.uninstall(apps.row("fixture-editor"))
      local second = software.uninstall(apps.row("fixture-editor"))
      return { first, second }
    end
    morf.ipc.toasts = function()
      local out = {}
      for _, entry in ipairs(require("notifs").history:get()) do out[#out + 1] = entry.summary end
      return out
    end
  ]==] }
  test.eq(test.ipc("remove_two"), { true, false })
  test.settle(400)
  local said = table.concat(test.ipc("toasts"), " | ")
  test.matches(said, "Could not remove Fixture Editor")
  test.matches(said, "Software is busy")
end)
