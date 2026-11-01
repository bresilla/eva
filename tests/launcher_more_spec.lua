-- The rest of what the launcher reaches: windows on either compositor, what the
-- network answers, and the small things.
--
--     morf test --no-dbus tests/launcher_more_spec.lua

local test = morf.test
local host = assert(load(morf.fs.read(morf.env("PWD") .. "/tests/fixtures/launcher_host.lua")))()

local function landed(name)
  return test.wait(function()
    test.advance(16)
    return host.row(name)
  end, 3000, "never listed: " .. name)
end

test.describe("windows", function()
  test.it("lists a compositor's toplevels, and acts on one", function()
    host.load { env = { EVA_TEST_WINDOWS = "toplevels" } }
    host.search("@")
    test.eq(host.names(), { "Notes", "Reader" })
    host.search("@read")
    test.eq(host.names(), { "Reader" })
    test.contains(test.ipc("act_names"), "Maximize it")
    test.ipc("do_action", "Close it")
    test.eq(test.ipc("window_calls"), { "close 2" })
    host.load { env = { EVA_TEST_WINDOWS = "toplevels" } }
    host.search("@read")
    test.ipc("activate")
    test.eq(test.ipc("window_calls"), { "activate 2" })
  end)

  test.it("finds an open window from the plain box", function()
    host.load { env = { EVA_TEST_WINDOWS = "toplevels" } }
    host.search("reader")
    test.eq(host.row("Reader").tag, "Window")
  end)

  test.it("acts on the focused window", function()
    host.load { env = { EVA_TEST_WINDOWS = "toplevels" } }
    host.search("> window ")
    test.matches(test.ipc("rows")[1].description, "Reader")
    host.search("> window max")
    test.ipc("activate")
    test.eq(test.ipc("window_calls"), { "maximize 2 true" })
  end)

  test.it("offers the window menu's buttons on Hyprland", function()
    host.load { env = { EVA_TEST_WINDOWS = "hyprland" } }
    host.search("@term")
    test.eq(host.names(), { "A terminal" })
    local names = test.ipc("act_names")
    test.contains(names, "Float or tile")
    test.contains(names, "Pin to every workspace")
    test.contains(names, "Move to workspace 3")
    test.ipc("do_action", "Move to workspace 3")
    test.truthy(host.logged("window menu (dry run): window.move on 0xabc"))
  end)

  test.it("switches to an app's open window", function()
    host.load { env = { EVA_TEST_WINDOWS = "hyprland", EVA_TEST_WINDOW_CLASS = "fixture-browser" } }
    host.search("fixture browser")
    local names = test.ipc("act_names")
    test.eq(names[1], "Switch to its window")
    test.eq(names[2], "Open another")
  end)

  test.it("says when there are none", function()
    host.load()
    host.search("@")
    test.eq(test.ipc("rows")[1].name, "No open windows")
  end)
end)

test.describe("what the network answers", function()
  test.it("translates through MyMemory where trans is not installed", function()
    host.load { path = { "unrelated" }, env = { EVA_TEST_HTTP = "1" } }
    host.search("> tr es hello", 500)
    landed("hola")
    test.matches(test.ipc("http_asked")[1], "mymemory")
    test.matches(test.ipc("http_asked")[1], "langpair=Autodetect%%7Ces")
  end)

  test.it("refuses more than MyMemory takes before anything leaves", function()
    host.load { path = { "unrelated" }, env = { EVA_TEST_HTTP = "1" } }
    host.search("> tr es " .. string.rep("hello ", 100), 500)
    landed("MyMemory takes 500 bytes at a time")
    test.eq(test.ipc("http_asked"), {})
  end)

  test.it("defines a word through the free dictionary", function()
    host.load { path = { "unrelated" }, env = { EVA_TEST_HTTP = "1" } }
    host.search("> define hello", 500)
    local row = landed("A greeting")
    test.matches(row.description, "noun")
  end)

  test.it("reads a Wikipedia summary, and opens the page", function()
    host.load { env = { EVA_TEST_HTTP = "1" } }
    host.search("> wiki linux", 500)
    landed("Linux")
    test.truthy(test.get("launcher-preview").visible, "the summary has no pane")
    test.ipc("activate")
    test.truthy(host.logged("https://en.wikipedia.org/wiki/Linux"))
  end)

  test.it("says when it cannot be reached", function()
    host.load { path = { "unrelated" }, env = { EVA_TEST_HTTP = "down" } }
    host.search("> define hello", 500)
    landed("It could not be reached")
    host.search("> tr es hi", 500)
    landed("MyMemory could not be reached")
  end)
end)

test.describe("a press", function()
  test.it("lists a row's actions on a right click", function()
    host.load()
    host.search("fixture browser")
    local row = test.get { text = "Fixture Browser", visible = true }
    test.click(row.x + row.width / 2, row.y + row.height / 2, { button = "right" })
    test.advance(200)
    test.ne(test.ipc("state").acting, "", "a right click ran it instead")
    test.truthy(host.row("New Window"))
  end)

  test.it("lists a row's actions on a long press", function()
    host.load()
    host.search("fixture browser")
    local row = test.get { text = "Fixture Browser", visible = true }
    local x, y = row.x + row.width / 2, row.y + row.height / 2
    test.touch("down", 0, x, y)
    test.advance(700)
    test.touch("up", 0, x, y)
    test.advance(200)
    test.ne(test.ipc("state").acting, "")
  end)

  test.it("runs a row on a left click", function()
    host.load()
    host.search("fixture browser")
    local row = test.get { text = "Fixture Browser", visible = true }
    test.click(row.x + row.width / 2, row.y + row.height / 2)
    test.settle(400)
    test.truthy(host.logged("launch fixture-browser"))
  end)
end)

test.describe("a keystroke's cost", function()
  test.it("reads a tile's status only for what is listed", function()
    host.load()
    test.eq(test.ipc("status_reads", "zzqq no match at all"), 0, "every tile was read for a search that listed none")
    test.truthy(test.ipc("status_reads", "wi-fi") >= 1, "the tile that was listed has no status")
  end)

  test.it("does not build a bookmark's row again for each letter", function()
    local marks = {}
    for i = 1, 3000 do marks[i] = { name = "Mark " .. i, url = "https://m.example/" .. i } end
    host.load { settings = { launcher = { bookmarks = marks } } }
    host.search("> mark ", 100)
    landed("Mark 1")
    host.search("mar", 100)
    test.note("keystroke over 3000 bookmarks: " .. tostring(test.ipc("timed_query", "mark 2")) .. " ms")
    test.truthy(test.ipc("timed_query", "mark 29") < 16, "a keystroke over 3000 bookmarks took too long")
    test.eq(#test.logs("warn"), 0)
  end)

  test.it("leaves a huge picture out of a row", function()
    local big = morf.env("XDG_CACHE_HOME") .. "/huge.png"
    host.write(big, string.rep("x", 6 * 1024 * 1024))
    host.load { path = { "fd" } }
    test.stub_run("fd", { code = 0, stdout = big .. "\n" })
    host.search("/huge", 300)
    landed("huge.png")
    test.falsy(test.find(function(n) return n.element == "Image" and n.visible and n.height == 32 end),
      "a row decodes a picture of 6 MiB")
    morf.fs.remove(big)
  end)
end)

test.describe("the small things", function()
  test.it("finds a dashboard tab from the plain box, and opens it", function()
    host.load()
    host.search("weather")
    local row = host.row("Weather")
    test.truthy(row, "no dashboard tab")
    test.eq(row.tag, "Dashboard")
    test.ipc("activate")
    test.settle(600)
    test.truthy(test.ipc("dashboard_open"))
  end)

  test.it("reads CSS sizes", function()
    host.load()
    host.search("24px in rem")
    test.eq(test.ipc("rows")[1].name, "1.5 rem")
  end)

  test.it("shows every notation of a colour, OKLCH among them", function()
    host.load()
    host.search("#ff0000")
    test.truthy(host.row("oklch(0.628 0.258 29.2)"), "no OKLCH")
    test.truthy(host.row("rgb(255, 0, 0)"))
  end)

  test.it("lists programs from the PATH after $", function()
    host.load { path = { "fixture-tool" } }
    test.stub_run("sh", "fixture-tool\nother\n")
    test.ipc("q", "$fixture-to")
    test.wait(function()
      test.advance(16)
      test.ipc("q", "$fixture-to")
      return host.row("fixture-tool")
    end, 2000, "no program")
  end)

  test.it("lists places, folders and words inside files", function()
    local home = morf.env("XDG_CACHE_HOME")
    morf.fs.mkdir(home .. "/Pictures", { parents = true })
    host.load { path = { "fd", "rg" } }
    host.search("> places ")
    test.truthy(host.row("Home"))
    test.truthy(host.row("Pictures"))
    test.stub_run("fd", { code = 0, stdout = home .. "/Pictures/\n" })
    host.search("> dir pic", 200)
    landed("Pictures")
    test.stub_run("rg", { code = 0, stdout = home .. "/words.txt\n" })
    host.search("> grep needle", 200)
    landed("words.txt")
    host.search("> grep ab")
    test.eq(test.ipc("rows")[1].name, "Type at least three letters")
  end)

  test.it("opens a file with an application of your choosing", function()
    local file = morf.env("XDG_CACHE_HOME") .. "/open-me.txt"
    host.write(file, "x")
    host.load()
    host.search("~/open-me")
    test.ipc("do_action", "Open with…")
    test.advance(200)
    test.eq(test.ipc("state").query, "> with ")
    host.search("> with fixture editor")
    test.ipc("activate")
    test.truthy(host.logged("start fixture-editor " .. file))
  end)

  test.it("opens the containing folder of a file", function()
    local file = morf.env("XDG_CACHE_HOME") .. "/reveal-me.txt"
    host.write(file, "x")
    host.load()
    host.search("~/reveal-me")
    test.contains(test.ipc("act_names"), "Open containing folder")
    test.ipc("do_action", "Open containing folder")
    test.truthy(host.logged("reveal " .. file))
  end)

  test.it("keeps the last search when told to", function()
    host.load { settings = { launcher = { keep_query = true } } }
    host.search("fixture")
    test.ipc("launcher", "close")
    test.settle(400)
    test.ipc("launcher", "open")
    test.settle(400)
    test.eq(test.ipc("state").query, "fixture")
  end)

  test.it("remembers nothing when told not to", function()
    host.load { settings = { launcher = { remember = false } } }
    host.search("fixture top")
    test.ipc("activate")
    test.settle(300)
    test.ipc("launcher", "open")
    test.settle(300)
    host.search("> history ")
    test.falsy(host.row("Fixture Top"))
  end)

  test.it("leaves the files out of a plain search when told to", function()
    host.load { path = { "fd" }, settings = { launcher = { search_files = false } } }
    host.search("anything", 400)
    for _, argv in ipairs(test.runs()) do test.ne(argv[1], "fd") end
  end)

  test.it("marks where an app came from, and what is new", function()
    host.load()
    test.eq(test.ipc("origin", "/var/lib/flatpak/exports/share/applications", "x"), "Flatpak")
    test.eq(test.ipc("origin", "/home/me/.nix-profile/share/applications", "x"), "Nix")
    test.eq(test.ipc("origin", "/usr/share/applications", "/opt/Thing.AppImage"), "AppImage")
    test.falsy(test.ipc("origin", "/usr/share/applications", "ls"))
    host.write(morf.env("XDG_DATA_HOME") .. "/applications/brand-new.desktop",
      "[Desktop Entry]\nType=Application\nName=Brand New\nExec=x\n")
    host.load()
    host.search("brand new")
    test.eq(host.row("Brand New").tag, "New")
    morf.fs.remove(morf.env("XDG_DATA_HOME") .. "/applications/brand-new.desktop")
  end)

  test.it("gives the last emoji first", function()
    host.load()
    host.search(":grinning")
    local first = test.ipc("rows")[1].name
    test.ipc("activate")
    test.settle(300)
    test.ipc("launcher", "open")
    test.settle(300)
    host.search(":")
    test.eq(test.ipc("rows")[1].name, first)
  end)

  test.it("lists a Steam library and repositories", function()
    host.load()
    test.stub_run("sh", '"appid"  "620"\n"name"  "Portal 2"\n')
    host.search("> game ", 100)
    landed("Portal 2")
    test.ipc("activate")
    test.truthy(host.logged("xdg-open steam://rungameid/620"))
  end)

  test.it("lists today's agenda from the same tasks", function()
    local today = morf.time.format("%Y%m%dT120000Z")
    local tasks = morf.json.encode {
      { uuid = "22222222-2222-2222-2222-222222222222", description = "Standup", due = today, status = "pending" } }
    host.load()
    test.stub_run("task", { code = 0, stdout = tasks })
    host.search("> task ", 100)
    landed("Standup")
    host.search("> agenda ", 100)
    landed("Standup")
  end)

  test.it("controls what is playing", function()
    host.load { env = { EVA_TEST_MEDIA = "1" } }
    host.search("> media ")
    test.eq(host.names(), { "Pause", "Next", "Previous" })
    test.matches(test.ipc("rows")[1].description, "A Song")
    test.ipc("activate")
    test.eq(test.ipc("media_calls"), { "play_pause" })
  end)

  test.it("says so when nothing plays", function()
    host.load()
    host.search("> media ")
    test.eq(test.ipc("rows")[1].name, "Nothing is playing")
  end)

  test.it("lists VPNs through the Settings page's model", function()
    host.load { env = { EVA_TEST_RADIOS = "1" } }
    host.search("> vpn ", 300)
    test.eq(test.ipc("rows")[1].name, "Work")
    test.ipc("activate")
    test.truthy(host.logged("vpn Work"))
  end)
end)
