-- The grid on a phone and a tablet, quick look, and what a person adds to the
-- launcher: plugins and script commands.
--
--     morf test --no-dbus tests/launcher_grid_spec.lua

local test = morf.test
local host = assert(load(morf.fs.read(morf.env("PWD") .. "/tests/fixtures/launcher_host.lua")))()

local PHONE, TABLET = { 620, 1380 }, { 1280, 800 }
local TOUCH = morf.env("PWD") .. "/tests/fixtures/input-devices-touch"

local function phone(options)
  options = options or {}
  options.size = PHONE
  options.env = { EVA_INPUT_DEVICES = TOUCH }
  return host.load(options)
end

local function tiles()
  local count = 0
  for _, r in ipairs(test.ipc("rows")) do count = count + (r.cells or 0) end
  return count
end

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " grid", function()
    test.it("opens as a grid on a phone, and a list once something is typed", function()
      phone { style = style }
      test.eq(test.ipc("state").mode, "grid")
      test.truthy(tiles() >= 3, "no tiles")
      test.truthy(test.find { text = "Fixture Browser", visible = true }, "no app on show")
      test.truthy(test.get("launcher-chips").visible)
      test.click { id = "launcher-summon-keyboard" }
      test.advance(200)
      test.type("fix")
      test.advance(300)
      test.eq(test.ipc("state").mode, "apps")
      test.falsy(test.find { id = "launcher-chips", visible = true })
      local panel = test.get("drawer-launcher")
      test.truthy(panel.x >= 0 and panel.x + panel.width <= PHONE[1], "wider than the phone")
    end)

    test.it("opens as a grid on a tablet too", function()
      host.load { style = style, size = TABLET, env = { EVA_INPUT_DEVICES = TOUCH } }
      test.eq(test.ipc("state").mode, "grid")
      test.truthy(test.find { text = "Fixture Browser", visible = true })
    end)

    test.it("stays a list on a desk, until asked", function()
      host.load { style = style }
      test.eq(test.ipc("state").mode, "apps")
      test.key("g", "ctrl")
      test.advance(300)
      test.eq(test.ipc("state").mode, "grid")
      test.key("g", "ctrl")
      test.advance(300)
      test.eq(test.ipc("state").mode, "apps")
    end)

    test.it("opens an app with a press, and its actions with a long press", function()
      phone { style = style }
      local tile = test.get { text = "Fixture Browser", visible = true }
      test.click(tile.x + tile.width / 2, tile.y)
      test.settle(600)
      test.falsy(test.ipc("state").open)
      test.truthy(host.logged("launch fixture-browser"))
      test.ipc("launcher", "open")
      test.settle(600)
      tile = test.get { text = "Fixture Browser", visible = true }
      local x, y = tile.x + tile.width / 2, tile.y
      test.touch("down", 0, x, y)
      test.advance(700)
      test.touch("up", 0, x, y)
      test.advance(300)
      test.ne(test.ipc("state").acting, "", "a long press listed no actions")
      test.truthy(host.row("Pin to favourites"))
    end)

    test.it("lists a tile's actions on a right click", function()
      host.load { style = style, settings = { launcher = { layout = "grid" } } }
      local tile = test.get { text = "Fixture Browser", visible = true }
      test.click(tile.x + tile.width / 2, tile.y, { button = "right" })
      test.advance(300)
      test.ne(test.ipc("state").acting, "", "a right click listed no actions")
      test.truthy(host.row("New Window"))
    end)

    test.it("lists favourites first, then what is used, then every app", function()
      phone { style = style, settings = { launcher = { favourites = { "app:fixture-editor" } } } }
      local rows = test.ipc("rows")
      test.eq(rows[1].name, "Favourites")
      test.truthy(test.find { id = "launcher-section-header:Favourites", visible = true })
      local pinned = rows[2]
      test.eq(pinned.cells, 1)
      local all
      for _, r in ipairs(rows) do
        if r.name == "All apps" then all = true end
      end
      test.truthy(all, "no All apps heading")
    end)

    test.it("narrows to a category", function()
      phone { style = style }
      test.click { id = "launcher-chip-c:Internet" }
      test.advance(300)
      test.eq(test.ipc("state").category, "Internet")
      test.truthy(test.find { text = "Fixture Browser", visible = true })
      test.falsy(test.find { text = "Fixture Editor", visible = true })
      test.click { id = "launcher-chip-c:" }
      test.advance(300)
      test.eq(test.ipc("state").category, "")
    end)

    test.it("opens a folder and comes back", function()
      phone { style = style, settings = { launcher = { folders = { { name = "Work", apps = { "fixture-editor" } } } } } }
      test.truthy(test.find { text = "Work", visible = true }, "no folder tile")
      local rows = test.ipc("rows")
      local folder = test.get { text = "Work", visible = true }
      test.click(folder.x + folder.width / 2, folder.y)
      test.advance(300)
      test.eq(test.ipc("state").folder, "Work")
      test.truthy(test.find { text = "Fixture Editor", visible = true })
      test.falsy(test.find { text = "Fixture Browser", visible = true })
      test.truthy(#rows > 0)
      test.click { id = "launcher-chip-back" }
      test.advance(300)
      test.eq(test.ipc("state").folder, "")
      test.truthy(test.ipc("state").open, "Back left the folder, not the launcher")
    end)

    test.it("leaves a folder with Escape, where there is a keyboard", function()
      host.load { style = style, settings = { launcher = { layout = "grid",
        folders = { { name = "Work", apps = { "fixture-editor" } } } } } }
      local folder = test.get { text = "Work", visible = true }
      test.click(folder.x + folder.width / 2, folder.y)
      test.advance(300)
      test.eq(test.ipc("state").folder, "Work")
      test.key("Escape")
      test.advance(300)
      test.eq(test.ipc("state").folder, "")
      test.truthy(test.ipc("state").open)
    end)

    test.it("files an app in a folder from its actions", function()
      host.load { style = style, settings = { launcher = { layout = "grid" } } }
      test.key("k", "ctrl")
      test.advance(200)
      test.ipc("q", "put")
      test.advance(200)
      test.ipc("activate")
      test.advance(200)
      test.eq(test.ipc("state").query, "> appfolder ")
      host.search("> appfolder Work")
      test.ipc("activate")
      test.settle(300)
      test.eq(#test.ipc("setting", "launcher.folders"), 1)
      test.eq(test.ipc("setting", "launcher.folders")[1].name, "Work")
    end)

    test.it("walks the tiles with the arrows", function()
      host.load { style = style, size = TABLET, settings = { launcher = { layout = "grid" } } }
      local function at()
        local state = test.ipc("state")
        return { state.selected, state.cell }
      end
      local start = at()
      test.eq(start[2], 1)
      local name = test.ipc("chosen")
      test.key("Right")
      test.advance(200)
      test.ne(at(), start, "Right stayed put")
      test.ne(test.ipc("chosen"), name)
      test.key("Left")
      test.advance(200)
      test.eq(at(), start)
      test.key("Down")
      test.advance(200)
      test.ne(test.ipc("state").selected, start[1])
    end)

    test.it("keeps the on-screen keyboard down until the field is pressed", function()
      phone { style = style }
      test.falsy(test.ipc("keyboard_open"))
      test.falsy(test.get("launcher-search").focused, "a focused field brings the keyboard by itself")
      test.click { id = "launcher-summon-keyboard" }
      test.advance(400)
      test.truthy(test.ipc("keyboard_open"))
      test.truthy(test.get("launcher-search").focused)
    end)

    test.it("fits four tiles across a small phone", function()
      host.load { style = style, size = { 360, 800 }, env = { EVA_INPUT_DEVICES = TOUCH } }
      test.eq(test.ipc("columns"), 4)
      local panel = test.get("drawer-launcher")
      test.truthy(panel.x >= 0 and panel.x + panel.width <= 360, "wider than the phone")
    end)

    test.it("types straight away on a tablet with a keyboard", function()
      host.load { style = style, size = TABLET, settings = { launcher = { layout = "grid" } } }
      test.truthy(test.get("launcher-search").focused)
      test.type("fix")
      test.advance(300)
      test.eq(test.ipc("state").mode, "apps")
    end)

    test.it("scrolls under a finger and a wheel", function()
      local list = {}
      for i = 1, 30 do list[i] = "app:fixture-" .. i end
      local folder = morf.env("XDG_DATA_HOME") .. "/applications/"
      for i = 1, 40 do
        host.write(folder .. "fixture-many-" .. i .. ".desktop",
          "[Desktop Entry]\nType=Application\nName=Many " .. i .. "\nExec=many\n")
      end
      phone { style = style }
      local first = test.get { text = "Fixture Browser", visible = true }
      local y = first.y
      test.wheel(0, 200, { x = 300, y = 700 })
      test.advance(100)
      local moved = test.find { text = "Fixture Browser", visible = true }
      test.truthy(moved == nil or moved.y < y, "the wheel did not move the grid")
      test.swipe({ 300, 900 }, { 300, 1100 }, { duration = 200 })
      test.advance(800)
      local back = test.get { text = "Fixture Browser", visible = true }
      test.near(back.y, y, 2, "a drag down did not bring it back")
      for i = 1, 40 do morf.fs.remove(folder .. "fixture-many-" .. i .. ".desktop") end
    end)

    test.it("jumps to a letter", function()
      phone { style = style }
      local strip = test.get("launcher-alphabet")
      test.click(strip.x + strip.width / 2, strip.y + strip.height * 0.99)
      test.advance(200)
      test.truthy(test.ipc("state").selected >= 1)
      test.eq(#test.logs("error"), 0)
    end)
  end)

  test.describe(style .. " quick look", function()
    test.it("opens with Space once the list is walked, and shuts again", function()
      local file = morf.env("XDG_CACHE_HOME") .. "/notes.txt"
      host.write(file, "the words in the file\n")
      host.load { style = style, path = { "fd" } }
      test.stub_run("fd", { code = 0, stdout = file .. "\n" })
      test.ipc("q", "/notes")
      test.wait(function()
        test.advance(16)
        return host.row("notes.txt")
      end, 2000)
      test.key("Up")
      test.key("Down")
      test.advance(100)
      test.ipc("preview_clear")
      test.key("space")
      test.advance(400)
      test.truthy(test.ipc("state").preview, "Space did not open it")
      test.eq(test.ipc("state").query, "/notes", "Space was typed")
      test.wait(function()
        test.advance(16)
        local text = test.find("launcher-preview-text")
        return text and text.text ~= ""
      end, 2000, "the file's words never came")
      test.matches(test.get("launcher-preview-text").text, "the words in the file")
      test.key("Escape")
      test.advance(200)
      test.falsy(test.ipc("state").preview)
      test.truthy(test.ipc("state").open)
    end)

    test.it("shows a file in the pane where there is room, without being asked", function()
      local file = morf.env("XDG_CACHE_HOME") .. "/pane.txt"
      host.write(file, "beside the list\n")
      host.load { style = style, path = { "fd" } }
      test.stub_run("fd", { code = 0, stdout = file .. "\n" })
      test.ipc("q", "/pane")
      test.wait(function()
        test.advance(16)
        return test.find { id = "launcher-preview", visible = true }
      end, 2000, "no pane")
      test.settle(600)
      local panel = test.get("drawer-launcher")
      test.near(panel.width, 960, 2, "the panel did not make room")
    end)

    test.it("shows a picture", function()
      local file = morf.env("XDG_CACHE_HOME") .. "/see.png"
      host.write(file, morf.fs.read(morf.env("PWD") .. "/tests/fixtures/wallpaper.png"))
      host.load { style = style, path = { "fd" } }
      test.stub_run("fd", { code = 0, stdout = file .. "\n" })
      test.ipc("q", "/see")
      test.wait(function()
        test.advance(16)
        return test.find { id = "launcher-preview", visible = true }
      end, 2000, "no pane")
      test.wait(function()
        test.advance(16)
        local image = test.find("launcher-preview-image")
        return image and image.visible
      end, 3000, "the picture never came")
    end)

    test.it("covers the list on a phone, and gives it back", function()
      local file = morf.env("XDG_CACHE_HOME") .. "/small.txt"
      host.write(file, "on a phone\n")
      host.load { style = style, size = PHONE, path = { "fd" }, env = { EVA_INPUT_DEVICES = TOUCH } }
      test.stub_run("fd", { code = 0, stdout = file .. "\n" })
      test.ipc("q", "/small")
      test.wait(function()
        test.advance(16)
        return host.row("small.txt")
      end, 2000)
      test.falsy(test.find { id = "launcher-preview", visible = true }, "no room for a pane, so not unasked")
      test.ipc("toggle_preview")
      test.advance(400)
      test.truthy(test.get("launcher-preview").visible)
      test.falsy(test.find { id = "launcher-results", visible = true })
      test.ipc("toggle_preview")
      test.advance(400)
      test.truthy(test.get("launcher-results").visible)
    end)
  end)
end

test.describe("plugins", function()
  local function plugin(name, text)
    host.write(morf.env("XDG_CONFIG_HOME") .. "/eva/" .. name, text)
  end
  local function clear()
    morf.fs.remove(morf.env("XDG_CONFIG_HOME") .. "/eva/plugin", { recursive = true })
    morf.fs.remove(morf.env("XDG_CONFIG_HOME") .. "/eva/after", { recursive = true })
    morf.fs.remove(morf.env("XDG_CONFIG_HOME") .. "/eva/lua", { recursive = true })
    morf.fs.remove(morf.env("XDG_CONFIG_HOME") .. "/eva/pack", { recursive = true })
  end

  test.it("adds a mode from a file in the config", function()
    clear()
    plugin("plugin/weather.lua", [[
      local launcher = require("eva.launcher")
      launcher.mode { id = "shout", name = "Shout", material = "campaign", words = { "shout" },
        hint = "shout hello", search = function(term)
          return { launcher.copy("shout", term:upper(), "Louder", "campaign") }
        end }
    ]])
    host.load()
    host.search("> shout hello")
    test.eq(test.ipc("rows")[1].name, "HELLO")
    test.eq(test.ipc("state").name, "Shout")
    host.search("shout hello")
    test.eq(test.ipc("rows")[1].name, "HELLO", "a plain search did not reach the mode")
    host.search("> ")
    test.truthy(host.row("Shout"))
    host.search("> shout hi")
    test.ipc("activate")
    test.settle(300)
    test.eq(test.ipc("copied"), { "HI" })
  end)

  test.it("adds something a plain search finds, and hears what is chosen", function()
    clear()
    plugin("plugin/nas.lua", [[
      local launcher = require("eva.launcher")
      launcher.entry { id = "nas", name = "Open the storage box", material = "dns",
        run = function() return launcher.open("smb://nas") end }
      launcher.on.chosen(function(row) morf.log("info", "chose " .. tostring(row.name)) end)
      launcher.on.chosen(function() error("this one raises") end)
    ]])
    host.load()
    host.search("storage box")
    test.eq(test.ipc("chosen"), "Open the storage box")
    test.key("Return")
    test.settle(300)
    test.truthy(host.logged("start xdg-open smb://nas"))
    test.truthy(host.logged("chose Open the storage box"))
  end)

  test.it("lets a plugin that raises fail alone, and says so", function()
    clear()
    plugin("plugin/01-broken.lua", [[ error("broken on purpose") ]])
    plugin("plugin/02-good.lua", [[
      require("eva.launcher").mode { id = "good", words = { "good" }, search = function() return {} end }
    ]])
    host.load()
    host.search("> plugins ")
    test.truthy(host.row("01-broken.lua"), "a failed plugin says nothing")
    test.matches(host.row("01-broken.lua").description, "broken on purpose")
    test.eq(host.row("01-broken.lua").tag, "Failed")
    test.eq(host.row("02-good.lua").tag, "Loaded")
    test.clear_logs()
  end)

  test.it("runs after/ last, and lets a plugin keep helpers in lua/", function()
    clear()
    plugin("lua/words.lua", [[ return { greeting = "from a helper" } ]])
    plugin("plugin/a.lua", [[
      local words = require("words")
      require("eva.launcher").mode { id = "greet", words = { "greet" },
        search = function() return { { name = words.greeting, run = function() return "keep" end } } end }
    ]])
    plugin("after/plugin/z.lua", [[
      require("eva.launcher").mode { id = "greet", words = { "greet" },
        search = function() return { { name = "overridden", run = function() return "keep" end } } end }
    ]])
    host.load()
    host.search("> greet ")
    test.eq(test.ipc("rows")[1].name, "overridden")
  end)

  test.it("reads a package as a root of its own, and the path of plugin folders", function()
    clear()
    plugin("pack/mine/start/thing/plugin/p.lua", [[
      require("eva.launcher").mode { id = "packaged", words = { "packaged" },
        search = function() return { { name = "from a package", run = function() return "keep" end } } end }
    ]])
    local extra = morf.env("XDG_CACHE_HOME") .. "/more-plugins"
    host.write(extra .. "/plugin/e.lua", [[
      require("eva.launcher").mode { id = "extra", words = { "extra" },
        search = function() return { { name = "from the path", run = function() return "keep" end } } end }
    ]])
    host.load { env = { EVA_PLUGIN_PATH = extra } }
    host.search("> packaged ")
    test.eq(test.ipc("rows")[1].name, "from a package")
    host.search("> extra ")
    test.eq(test.ipc("rows")[1].name, "from the path")
  end)

  test.it("starts without them when told", function()
    clear()
    plugin("plugin/gone.lua", [[
      require("eva.launcher").mode { id = "gone", words = { "gone" }, search = function() return {} end }
    ]])
    host.load { env = { EVA_NO_PLUGINS = "1" } }
    host.search("> ")
    test.falsy(host.row("gone"))
    clear()
  end)

  test.it("asks a program without holding the search", function()
    clear()
    plugin("plugin/asks.lua", [[
      local launcher = require("eva.launcher")
      launcher.mode { id = "asks", words = { "asks" }, search = function(term)
        local answer = launcher.ask("asks", term, { "printf", "%s", "answered" }, function(stdout) return stdout end)
        return { launcher.note("asks", answer or "waiting", term) }
      end }
    ]])
    host.load()
    test.ipc("q", "> asks x")
    test.advance(10)
    test.eq(test.ipc("rows")[1].name, "waiting")
    test.wait(function()
      test.advance(16)
      return test.ipc("rows")[1].name == "answered"
    end, 2000, "the answer never landed")
    clear()
  end)
end)

test.describe("script commands", function()
  local folder = morf.env("XDG_CONFIG_HOME") .. "/eva/scripts"
  local function script(name, text)
    morf.fs.write(folder .. "/" .. name, text, { parents = true, mode = 448 })
  end
  test.it("lists an executable with its head's words, and runs it", function()
    script("restart-audio.sh", "#!/bin/sh\n# @eva.title Restart the audio\n# @eva.description Brings it back\n# @eva.icon restart_alt\nexit 0\n")
    morf.fs.write(folder .. "/not-a-script.txt", "words", { parents = true, mode = 420 })
    host.load()
    host.search("restart the audio")
    local row = host.row("Restart the audio")
    test.truthy(row, "a plain search does not find it")
    test.eq(row.tag, "Script")
    test.ipc("activate")
    test.truthy(host.logged("restart-audio.sh"))
    host.load()
    host.search("> script ")
    test.falsy(host.row("not a script"), "a file that does not run is no command")
  end)

  test.it("asks for its argument", function()
    script("say.sh", "#!/bin/sh\n# @eva.title Say\n# @eva.argument what to say\n# @eva.mode terminal\necho \"$1\"\n")
    host.load { path = { "foot" } }
    host.search("> script ")
    test.ipc("q", "> script say")
    test.advance(200)
    test.ipc("activate")
    test.advance(200)
    test.eq(test.ipc("state").query, "> script say.sh ")
    test.eq(test.ipc("rows")[1].name, "what to say")
    test.ipc("q", "> script say.sh hello")
    test.advance(200)
    test.ipc("activate")
    test.truthy(host.logged("say.sh hello"))
  end)

  test.it("finds a new script as it lands in the folder", function()
    host.load()
    script("late.sh", "#!/bin/sh\n# @eva.title Arrived late\n")
    test.wait(function()
      test.advance(16)
      host.search("arrived late", 16)
      return host.row("Arrived late")
    end, 3000, "the folder is not watched")
  end)
end)
