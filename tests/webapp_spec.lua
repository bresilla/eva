-- eva-webapp: the desktop entry it writes, the browser it finds, the icon from a
-- stand-in for the web, the tile when there is none, under scratch XDG folders.
-- Nothing reaches the network, and no browser is started.
--
--     morf test --no-dbus tests/webapp_spec.lua

local test = morf.test

local ROOT = morf.fs.join(morf.env("PWD"), "")
local BIN = ROOT .. "tests/fixtures/bin"
local PICTURE = ROOT .. "tests/fixtures/site-icon.png"

local serial = 0
local function fresh()
  serial = serial + 1
  local root = morf.env("XDG_STATE_HOME") .. "/webapp-" .. serial .. "-" .. tostring(morf.time.now_ms())
  morf.fs.mkdir(root .. "/bin", { parents = true })
  morf.fs.mkdir(root .. "/data", { parents = true })
  return root
end

local function env_of(root, browser, more)
  if browser then morf.fs.write(root .. "/bin/" .. browser, "", { mode = 493 }) end
  local full = { XDG_DATA_HOME = root .. "/data", XDG_STATE_HOME = root .. "/state", EVA_FAKE_WEBAPP = "1",
    EVA_FAKE_WEBAPP_PICTURE = PICTURE, PATH = root .. "/bin", EVA_SETTINGS = "/nonexistent/eva.json",
    LULE_A = "/nonexistent/lule" }
  for key, value in pairs(more or {}) do full[key] = value end
  return full
end

local function window(style, browser, root)
  root = root or fresh()
  local appearance = root .. "/appearance.json"
  morf.fs.write(appearance, morf.json.encode { theme = style or "material", font = "" })
  test.load("../apps/webapp/app.lua", { env = env_of(root, browser or "chromium", { EVA_APPEARANCE = appearance }) })
  test.settle(400)
  return root
end

-- Picture work runs on real threads: this waits for it.
local function wait_for(check, what)
  test.wait(check, 8000, what)
end

local function job(root, args, browser, more)
  local out = root .. "/answer"
  morf.fs.remove(out)
  local env = env_of(root, browser, more)
  env.EVA_JOB_OUT = out
  test.load("../apps/webapp/app.lua", { args = args, env = env })
  wait_for(function() return morf.fs.exists(out) end, "the job answered")
  return morf.fs.read(out) or ""
end

for _, style in ipairs { "material", "tsugumori" } do
  test.it("makes an app from the form, in " .. style, function()
    local root = window(style)
    test.click("webapp-add-name")
    test.type("Notes")
    test.click("webapp-add-url")
    test.type("icon.test")
    test.key("Return")
    wait_for(function() return #test.ipc("state").rows == 1 end, "the app was made")
    test.settle(100)
    test.eq(test.get("webapp-name-1").text, "Notes")
    test.eq(test.get("webapp-url-1").text, "https://icon.test")
    test.truthy(morf.fs.exists(root .. "/data/applications/eva-webapp-notes.desktop"))
    test.eq(#test.logs("error"), 0)
  end)
end

test.it("writes the entry the brief asks for", function()
  local root = fresh()
  job(root, { "add", "Notes", "https://icon.test" }, "chromium")
  local text = morf.fs.read(root .. "/data/applications/eva-webapp-notes.desktop")
  test.contains(text, "Type=Application\n")
  test.contains(text, "Name=Notes\n")
  test.contains(text, "Exec=chromium --app=https://icon.test --class=eva-webapp-notes\n")
  test.contains(text, "StartupWMClass=eva-webapp-notes\n")
  test.contains(text, "Icon=" .. root .. "/data/icons/eva-webapp-notes.png\n")
end)

local HOST = [[
  local morf = require("morf")
  require("morf.ui").Item { width = 1, height = 1 }
  local model = require("model")
  morf.ipc.links = function(html, base) return model.icon_links(html, base) end
  morf.ipc.letter = function(name) return (model.letter(name)) end
  morf.ipc.entry = function(name, url)
    return model.entry(name, url, model.slug(name), "chromium", "/icons/a b.png")
  end
]]

test.it("escapes what the format reserves", function()
  test.load("../apps/webapp/app.lua", { source = HOST })
  local text = test.ipc("entry", "Tom & Jerry\nX\\Y", "https://icon.test/a?b=1&c=50%")
  test.contains(text, "Name=Tom & Jerry\\nX\\\\Y\n")
  test.contains(text, 'Exec=chromium "--app=https://icon.test/a?b=1&c=50%%" --class=eva-webapp-tom-jerry-x-y\n')
  test.contains(text, "Icon=/icons/a b.png\n")
  test.eq(select(2, text:gsub("\n", "\n")), 11)
end)

test.it("makes a slug of any name", function()
  local root = fresh()
  job(root, { "add", "  ~!! ", "https://plain.test" }, "chromium")
  test.truthy(morf.fs.exists(root .. "/data/applications/eva-webapp-app.desktop"))
end)

test.it("finds the browsers of the Chromium family", function()
  for _, browser in ipairs { "google-chrome-stable", "brave", "vivaldi", "microsoft-edge" } do
    local root = fresh()
    job(root, { "add", "Site", "https://plain.test" }, browser)
    test.contains(morf.fs.read(root .. "/data/applications/eva-webapp-site.desktop"), "Exec=" .. browser .. " --app=")
  end
end)

test.it("says Firefox has no app window", function()
  test.contains(job(fresh(), { "add", "Site", "https://plain.test" }, "firefox"), "1\nFirefox has no --app window")
end)

test.it("says when there is no browser at all", function()
  test.contains(job(fresh(), { "add", "Site", "https://plain.test" }), "1\nNo Chromium-family browser")
end)

test.it("refuses what is no address, and a name it has", function()
  local root = fresh()
  test.contains(job(root, { "add", "Site", "not an address" }, "chromium"), "1\nThat is no web address")
  test.contains(job(root, { "add", "Site", "ftp://x.test" }, "chromium"), "1\nThat is no web address")
  job(root, { "add", "Site", "https://plain.test" }, "chromium")
  test.contains(job(root, { "add", "Site", "https://plain.test" }, "chromium"), "1\nSite is already there")
end)

local function info(path) return morf.image.info(path) end

test.it("takes the icon the page names", function()
  local root = fresh()
  job(root, { "add", "Notes", "https://icon.test" }, "chromium")
  local path = root .. "/data/icons/eva-webapp-notes.png"
  test.truthy(morf.fs.exists(path))
  test.truthy(info(path))
  test.eq(#morf.fs.list(root .. "/data/icons"), 1)
end)

test.it("takes the PNG out of a favicon.ico", function()
  local root = fresh()
  job(root, { "add", "Mail", "https://ico.test/inbox" }, "chromium")
  test.truthy(info(root .. "/data/icons/eva-webapp-mail.png"))
end)

test.it("makes a letter tile where the site has no icon", function()
  local root = fresh()
  job(root, { "add", "Plain", "https://plain.test" }, "chromium")
  local path = root .. "/data/icons/eva-webapp-plain.png"
  local found = info(path)
  test.eq(found.width, 256)
  test.eq(found.height, 256)
end)

test.it("takes a person's own picture with --icon", function()
  local root = fresh()
  job(root, { "add", "Mine", "https://plain.test", "--icon", PICTURE }, "chromium")
  test.truthy(info(root .. "/data/icons/eva-webapp-mine.png"))
  test.contains(job(root, { "add", "Lost", "https://plain.test", "--icon", "/nonexistent.png" }, "chromium"),
    "1\nCannot read the picture")
  test.falsy(morf.fs.exists(root .. "/data/applications/eva-webapp-lost.desktop"))
end)

test.it("lists and removes, the icon too", function()
  local root = fresh()
  job(root, { "add", "Notes", "https://icon.test" }, "chromium")
  test.contains(job(root, { "list" }, "chromium"), "0\nNotes  https://icon.test")
  test.contains(job(root, { "remove", "Notes" }, "chromium"), "0\nremoved Notes")
  test.falsy(morf.fs.exists(root .. "/data/applications/eva-webapp-notes.desktop"))
  test.falsy(morf.fs.exists(root .. "/data/icons/eva-webapp-notes.png"))
  test.contains(job(root, { "list" }, "chromium"), "0\nno web apps")
  test.contains(job(root, { "remove", "Notes" }, "chromium"), "1\nnothing called Notes")
end)

test.it("writes nothing under a dry run", function()
  local root = fresh()
  job(root, { "add", "Notes", "https://icon.test" }, "chromium", { EVA_DRY_RUN = "1" })
  test.falsy(morf.fs.exists(root .. "/data/applications/eva-webapp-notes.desktop"))
end)

test.it("says why it cannot work when the window opens", function()
  window("material", "firefox")
  test.contains(test.get("webapp-message").text, "Firefox has no --app window")
end)

test.it("finds the icons a page names, largest first", function()
  test.load("../apps/webapp/app.lua", { source = HOST })
  local html = [[
    <LINK REL="shortcut icon" HREF="fav.png">
    <link rel='apple-touch-icon' href='/touch.png' sizes='180x180'>
    <link rel="mask-icon" href="/mask.svg">
    <link rel="stylesheet" href="/s.css">
    <link href=//cdn.test/big.png rel=icon sizes=512x512>
    <link rel="icon" href="data:image/png;base64,xx">
  ]]
  local links = test.ipc("links", html, "https://a.test/app/page.html?x=1")
  test.eq(links, { "https://cdn.test/big.png", "https://a.test/touch.png", "https://a.test/app/fav.png" })
  test.eq(test.ipc("letter", "notes"), "N")
  test.eq(test.ipc("letter", "<b>"), "?")
end)

local function cli(args)
  local state = morf.env("XDG_STATE_HOME")
  local log = state .. "/webapp-cli-" .. tostring(morf.time.now_ms()) .. ".log"
  morf.fs.write(log, "")
  local argv = { "env", "PATH=" .. BIN .. ":" .. morf.env("PATH"), "MORF=" .. BIN .. "/morf", "STUB_LOG=" .. log,
    "HOME=" .. state, "XDG_RUNTIME_DIR=" .. morf.env("XDG_RUNTIME_DIR"), "sh", ROOT .. "apps/webapp/cli" }
  for _, word in ipairs(args) do argv[#argv + 1] = word end
  test.load("../shell/init.lua", { source = morf.fs.read(ROOT .. "tests/fixtures/cli_host.lua") })
  test.ipc("run", table.unpack(argv))
  test.wait(function() return test.ipc("result") end, 8000, "the tool answered")
  return morf.fs.read(log) or ""
end

test.it("the command line asks the tool's own job", function()
  test.contains(cli { "add", "A b", "c.test", "--icon", "/x.png" },
    "app " .. ROOT .. "apps/webapp/app.lua -- add A b c.test --icon /x.png")
end)
