-- The grid under a finger, past what launcher_grid_spec covers: folders made by
-- dropping one app on another, what a folder's own actions do, hidden apps and
-- the way back, and removing an app where the machine lets it.
--
--     morf test --no-dbus tests/app_drawer_spec.lua
local test = morf.test
local host = assert(load(morf.fs.read(morf.env("PWD") .. "/tests/fixtures/launcher_host.lua")))()

local PHONE = { 620, 1380 }
local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"

local function phone(style, options)
  options = options or {}
  options.style, options.size = style, PHONE
  options.env = options.env or {}
  options.env.EVA_INPUT_DEVICES = TOUCH
  return host.load(options)
end

local function centre(name)
  local tile = test.get { text = name, visible = true }
  return tile.x + tile.width / 2, tile.y - 12
end

-- A hold on (x, y), carried to (to_x, to_y) and let go, through the touch path.
local function carry(x, y, to_x, to_y)
  test.touch("down", 0, x, y) test.advance(700)
  for i = 1, 12 do test.touch("move", 0, x + (to_x - x) * i / 12, y + (to_y - y) * i / 12) test.advance(16) end
  test.touch("up", 0, to_x, to_y) test.advance(400)
end

local function hold(name)
  local x, y = centre(name)
  test.touch("down", 0, x, y) test.advance(700)
  test.touch("up", 0, x, y) test.advance(300)
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " folders", function()
    test.it("dropping an app on another makes a folder named for its category", function()
      phone(style)
      local x, y = centre("Fixture Browser")
      local to_x, to_y = centre("Fixture Editor")
      carry(x, y, to_x, to_y)
      local folders = test.ipc("setting", "launcher.folders")
      test.eq(#folders, 1, "no folder was made")
      test.eq(folders[1].name, "Development")
      test.eq(folders[1].apps, { "fixture-editor", "fixture-browser" })
      test.settle(300)
      test.truthy(test.find { text = "Development", visible = true }, "the folder has no tile")
      test.falsy(test.find { text = "Fixture Browser", visible = true }, "the app is still loose in the grid")
      test.eq(test.ipc("state").acting, "", "a drop opened a menu")
      test.eq(test.logs("error"), {})
    end)

    test.it("dropping an app on a folder files it there", function()
      phone(style, { settings = { launcher = { folders = { { name = "Work", apps = { "fixture-editor" } } } } } })
      local x, y = centre("Fixture Browser")
      local to_x, to_y = centre("Work")
      carry(x, y, to_x, to_y)
      local folders = test.ipc("setting", "launcher.folders")
      test.eq(folders[1].apps, { "fixture-editor", "fixture-browser" })
    end)

    test.it("a drag that ends on nothing files nothing", function()
      phone(style)
      local x, y = centre("Fixture Browser")
      carry(x, y, x, PHONE[2] - 40)
      test.eq(#test.ipc("setting", "launcher.folders"), 0)
    end)

    test.it("takes an app out by dropping it on the place inside the folder", function()
      phone(style, { settings = { launcher = { folders = { { name = "Work", apps = { "fixture-editor", "fixture-browser" } } } } } })
      local x, y = centre("Work")
      test.click(x, y + 12) test.advance(300)
      test.eq(test.ipc("state").folder, "Work")
      x, y = centre("Fixture Editor")
      test.touch("down", 0, x, y) test.advance(700)
      local place = test.get("launcher-out-target")
      test.truthy(place.width > 0, "no place to take it out on")
      local to_x, to_y = place.x + place.width / 2, place.y + place.height / 2
      for i = 1, 12 do test.touch("move", 0, x + (to_x - x) * i / 12, y + (to_y - y) * i / 12) test.advance(16) end
      test.touch("up", 0, to_x, to_y) test.advance(400)
      test.eq(test.ipc("setting", "launcher.folders")[1].apps, { "fixture-browser" })
    end)

    test.it("draws a folder from its apps' icons", function()
      phone(style, { settings = { launcher = { folders = { { name = "Work", apps = { "fixture-editor", "fixture-browser" } } } } } })
      test.truthy(test.find { text = "Work", visible = true })
      test.eq(test.logs("error"), {})
    end)

    test.it("renames a folder and takes everything out of it, from a hold", function()
      phone(style, { settings = { launcher = { folders = { { name = "Work", apps = { "fixture-editor" } } } } } })
      hold("Work")
      test.ne(test.ipc("state").acting, "", "a hold on a folder listed nothing")
      test.truthy(host.row("Rename it…"))
      test.truthy(host.row("Take everything out"))
      test.ipc("do_action_row", "Rename it…")
      test.advance(300)
      test.eq(test.ipc("state").query, "> foldername ")
      host.search("> foldername Projects")
      test.ipc("activate")
      test.settle(300)
      test.eq(test.ipc("setting", "launcher.folders")[1].name, "Projects")
      test.ipc("launcher", "open") test.settle(600)
      hold("Projects")
      test.ipc("do_action_row", "Take everything out")
      test.settle(300)
      test.eq(#test.ipc("setting", "launcher.folders"), 0)
      test.truthy(test.find { text = "Fixture Editor", visible = true }, "its app did not come back to the grid")
    end)

    test.it("offers the app's own category when nothing is typed", function()
      phone(style)
      hold("Fixture Browser")
      test.ipc("do_action_row", "Put it in a folder…")
      test.advance(300)
      test.eq(test.ipc("state").query, "> appfolder ")
      test.truthy(host.row("Put it in “Internet”"), "no folder was suggested")
      test.truthy(test.ipc("keyboard_open"), "the keyboard stayed down for a question to type")
    end)
  end)

  test.describe(style .. " hidden apps", function()
    test.it("a hidden app waits under its own chip, and comes back from a hold", function()
      phone(style)
      test.falsy(test.find { id = "launcher-chip-c:Hidden", visible = true }, "a chip for nothing")
      hold("Fixture Editor")
      test.ipc("do_action_row", "Hide it")
      test.settle(400)
      test.falsy(test.find { text = "Fixture Editor", visible = true }, "it is still in the grid")
      test.ipc("close") test.settle(300)
      test.ipc("launcher", "open") test.settle(600)
      local chips = test.get("launcher-chips")
      test.swipe({ chips.x + chips.width - 16, chips.y + 16 }, { chips.x + 16, chips.y + 16 }, { duration = 240 })
      test.settle(400)
      test.click { id = "launcher-chip-c:Hidden" }
      test.advance(300)
      test.eq(test.ipc("state").category, "Hidden")
      test.truthy(test.find { text = "Fixture Editor", visible = true }, "the chip does not list it")
      hold("Fixture Editor")
      test.truthy(host.row("Show it again"), "no way back")
      test.ipc("do_action_row", "Show it again")
      test.settle(400)
      test.eq(test.ipc("setting", "launcher.hidden"), {})
    end)

    test.it("swipes on to the hidden apps like any other category", function()
      phone(style, { settings = { launcher = { hidden = { "fixture-top" } } } })
      test.truthy(test.find { id = "launcher-chip-c:Hidden", visible = true })
      test.eq(test.logs("error"), {})
    end)
  end)

  test.describe(style .. " removing an app", function()
    local function machine(kinds, extra)
      local env = { EVA_FAKE_SYSTEM = extra or "1", EVA_FAKE_SOFTWARE = kinds }
      phone(style, { env = env })
    end

    test.it("asks twice, then runs what removes it", function()
      machine("fixture-editor=flatpak")
      hold("Fixture Editor")
      local first = host.row("Uninstall it")
      test.truthy(first, "no way to remove a Flatpak")
      test.matches(first.description, "leaves its data")
      test.ipc("do_action_row", "Uninstall it")
      test.settle(200)
      test.ne(test.ipc("state").acting, "", "the first press left the panel")
      test.truthy(host.row("Press again to uninstall"), "the panel did not ask again")
      test.falsy(host.logged("flatpak uninstall"), "one press removed it")
      test.ipc("do_action_row", "Press again to uninstall")
      test.settle(400)
      test.truthy(host.logged("flatpak uninstall --noninteractive -y --system fixture-editor"), "nothing ran")
      test.falsy(test.ipc("state").open, "the launcher stayed open")
    end)

    test.it("says plainly why a system app stays, and offers no button that fails", function()
      machine("fixture-browser=system", "nixos")
      hold("Fixture Browser")
      test.falsy(host.row("Uninstall it"), "an uninstall that could only fail")
      local row = host.row("Cannot be removed here")
      test.truthy(row, "nothing said why")
      test.matches(row.description, "NixOS")
      test.matches(row.description, "configuration")
      test.ipc("do_action_row", "Cannot be removed here")
      test.settle(200)
      test.ne(test.ipc("state").acting, "", "a line of words shut the panel")
      test.falsy(host.logged("uninstall"))
    end)

    test.it("says so where a configuration declares it", function()
      machine("fixture-browser=declared", "nixos")
      hold("Fixture Browser")
      test.matches(host.row("Cannot be removed here").description, "Home Manager")
    end)

    test.it("moves the person's own entry to the trash", function()
      machine("fixture-editor=local")
      hold("Fixture Editor")
      test.matches(host.row("Uninstall it").description, "trash")
      test.ipc("do_action_row", "Uninstall it")
      test.settle(200)
      test.ipc("do_action_row", "Press again to uninstall")
      test.settle(300)
      test.truthy(host.logged("gio trash " .. morf.env("XDG_DATA_HOME") .. "/applications/fixture-editor.desktop"),
        "the entry's own file was not trashed")
    end)
  end)
end

test.describe("where an app came from", function()
  local SOURCE = [==[
    require("init")
    local software = require("lib.services.software")
    morf.ipc.source = function(row) local s = software.source_of(row) return { kind = s.kind, removable = s.removable, why = s.why, argv = s.argv } end
    morf.ipc.profile = function(text) software.read_profile(text) return true end
    morf.ipc.flatpak = function(text) return software.parse_flatpak(text) end
    morf.ipc.install = function(item) return software.install_argv(item) end
  ]==]
  local function load(env)
    env = env or {}
    env.EVA_DRY_RUN, env.EVA_FAKE_SYSTEM, env.EVA_WALLPAPER = "1", env.EVA_FAKE_SYSTEM or "nixos", ""
    env.HOME = morf.env("XDG_CACHE_HOME")
    test.stub_run("task", { code = 0, stdout = "[]" })
    test.load("../shell/init.lua", { source = SOURCE, size = { 300, 200 }, env = env })
    test.advance(100)
  end

  test.it("reads the kind from where the entry lives", function()
    load()
    local home = morf.env("XDG_CACHE_HOME")
    local cases = {
      { "/run/current-system/sw/share/applications", "system", false },
      { "/etc/profiles/per-user/ada/share/applications", "declared", false },
      { "/var/lib/flatpak/exports/share/applications", "flatpak", true },
      { home .. "/.local/share/flatpak/exports/share/applications", "flatpak", true },
      { "/usr/share/applications", "package", false },
    }
    for _, case in ipairs(cases) do
      local said = test.ipc("source", { id = "a.desktop", source = case[1], command = { "a" } })
      test.eq(said.kind, case[2], case[1])
      test.eq(said.removable, case[3], case[1])
      if not said.removable then test.truthy(said.why ~= "", "no words for " .. case[1]) end
    end
  end)

  test.it("removes a system-wide Flatpak with the system's, a person's with theirs", function()
    load()
    local home = morf.env("XDG_CACHE_HOME")
    local own = test.ipc("source", { id = "a.b.desktop", source = home .. "/.local/share/flatpak/exports/share/applications" })
    test.eq(own.argv[5], "--user")
    test.eq(own.argv[6], "a.b")
    local shared = test.ipc("source", { id = "a.b.desktop", source = "/var/lib/flatpak/exports/share/applications" })
    test.eq(shared.argv[5], "--system")
  end)

  test.it("takes a Nix profile's app out by the element's name, and nothing Home Manager keeps", function()
    load { EVA_FAKE_SOFTWARE = "a.desktop=profile" }
    test.ipc("profile", morf.json.encode { version = 3, elements = { ripgrep = { storePaths = { "/nix/store/x-ripgrep" } } } })
    local unknown = test.ipc("source", { id = "a.desktop", source = "/x/.nix-profile/share/applications" })
    test.falsy(unknown.removable, "a guess at what to remove")
    test.matches(unknown.why, "does not list it")
    local known = test.ipc("source", { id = "a.desktop", source = "/x/.nix-profile/share/applications", profile_element = "ripgrep" })
    test.truthy(known.removable)
    test.eq(known.argv[#known.argv], "ripgrep")
    test.ipc("profile", morf.json.encode { version = 3, elements = { ["home-manager-path"] = { storePaths = { "/nix/store/y-hm" } } } })
    local kept = test.ipc("source", { id = "a.desktop", source = "/x/.nix-profile/share/applications" })
    test.eq(kept.kind, "declared")
    test.falsy(kept.removable)
  end)

  test.it("reads Flatpak's catalogue, and installs from the remote it lists", function()
    load()
    local found = test.ipc("flatpak", "org.gnome.Chess\tChess\tPlay chess\t48\tflathub,fedora\nbroken line\n")
    test.eq(#found, 1)
    test.eq(found[1].remote, "flathub")
    local argv = test.ipc("install", found[1])
    test.eq(argv, { "flatpak", "install", "--noninteractive", "-y", "flathub", "org.gnome.Chess" })
    local nix = test.ipc("install", { backend = "nix", id = "ripgrep" })
    test.eq(nix[#nix], "nixpkgs#ripgrep")
    test.eq(test.ipc("install", { backend = "nothing", id = "x" }), nil)
  end)
end)

test.it("a real removal goes through the program itself, stubbed here", function()
  test.stub_run("flatpak", { code = 0 })
  local env = { EVA_DRY_RUN = "0", EVA_FAKE_SOFTWARE = "fixture-editor=flatpak", EVA_INPUT_DEVICES = TOUCH,
    PATH = host.path { "flatpak", "gio" } }
  host.load { size = PHONE, env = env, settings = { appearance = { sync = false } } }
  hold("Fixture Editor")
  test.ipc("do_action_row", "Uninstall it")
  test.settle(200)
  test.ipc("do_action_row", "Press again to uninstall")
  test.settle(400)
  local ran = false
  for _, argv in ipairs(test.runs()) do
    if argv[1] == "flatpak" and argv[2] == "uninstall" then ran = true end
  end
  test.truthy(ran, "the program was not asked")
  test.eq(test.logs("error"), {})
end)
