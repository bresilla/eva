-- Connection help against the stand-in machine (EVA_FAKE_SYSTEM): each way a
-- connection can fail said in plain words, the sign-in page, the speed test.
-- Nothing here leaves the process: host_fake answers every request and keeps
-- what was asked, which `fake-net` hands back.
--     tools/test.sh tests/net_help_spec.lua
local test = morf.test

local serial = 0
local function load(style, size, scene, extra)
  serial = serial + 1
  local settings = ("%s/net-help-%d.json"):format(morf.env("XDG_CACHE_HOME"), serial)
  morf.fs.write(settings, morf.json.encode(extra or {}))
  test.load("../shell/init.lua", { size = size or { 1920, 1080 }, env = { EVA_STYLE = style or "material", EVA_DRY_RUN = "1",
    EVA_FAKE_SYSTEM = "1", EVA_FAKE_NET = scene or "ok", EVA_SETTINGS = settings, EVA_WALLPAPER = "", EVA_FONT_FILE = "",
    HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(1500)
end
local function open()
  test.ipc("settings", "network/help")
  test.settle(900)
end
local function walk()
  test.click("net-steps-run")
  test.settle(600)
end
local function asked() return test.ipc("fake-net") end
local function text(id) return test.text_of(test.get(id)) end
local function shot(name) if morf.env("EVA_THEME_SNAPSHOTS") == "1" then test.snapshot(name .. ".png") end end
local function said(id) return text(id .. "-subtitle") end
local function logged(part)
  for _, line in ipairs(test.logs("info")) do
    if tostring(line.message):find(part, 1, true) then return true end
  end
  return false
end

test.describe("connection help", function()
  for _, style in ipairs { "material", "tsugumori" } do
    test.it(style .. ": says who it asks, and walks a working connection", function()
      load(style)
      open()
      test.truthy(test.find { id = "net-help-scroll", visible = true })
      test.truthy(text("net-steps-who"):find("nmcheck.gnome.org", 1, true))
      test.truthy(text("net-speed-who"):find("speed.cloudflare.com", 1, true))
      test.falsy(test.find { id = "net-step-link", visible = true })
      test.eq(asked(), {}, "nothing goes out until a press")
      walk()
      for _, name in ipairs { "link", "address", "gateway", "dns", "internet" } do
        test.truthy(test.find { id = "net-step-" .. name, visible = true }, name)
      end
      test.truthy(said("net-step-link"):find("Home", 1, true))
      test.truthy(said("net-step-address"):find("192.168.1.23", 1, true))
      test.truthy(said("net-step-gateway"):find("192.168.1.1", 1, true))
      test.eq(text("net-steps-verdict"), "Your connection works.")
      test.eq(asked(), { "http://nmcheck.gnome.org/check_network_status.txt" })
      test.eq(#test.logs("error"), 0)
    end)
  end

  local CASES = {
    { "no-address", "address", "got no address" },
    { "self-assigned", "address", "169.254.12.3" },
    { "no-gateway", "gateway", "not answering" },
    { "no-dns", "dns", "not resolve" },
    { "no-internet", "internet", "nothing past it" },
    { "portal", "internet", "sign in" },
  }
  for _, case in ipairs(CASES) do
    test.it("names the step that failed: " .. case[1], function()
      load(nil, nil, case[1])
      open()
      walk()
      shot("help-" .. case[1])
      test.truthy(said("net-step-" .. case[2]):find(case[3], 1, true), said("net-step-" .. case[2]))
      test.truthy(text("net-steps-verdict"):find(case[3], 1, true), text("net-steps-verdict"))
      test.eq(#test.logs("error"), 0)
    end)
  end

  test.it("a router that ignores ping is no failure when the rest works", function()
    load(nil, nil, "quiet-router")
    open()
    walk()
    test.truthy(said("net-step-gateway"):find("Some routers ignore it", 1, true))
    test.eq(text("net-steps-verdict"), "Your connection works.")
  end)

  test.it("a step that failed leaves the later ones untried", function()
    load(nil, nil, "no-address")
    open()
    walk()
    test.truthy(said("net-step-dns"):find("Not tried", 1, true))
    test.eq(asked(), {}, "the Internet step never ran")
  end)

  test.it("the sign-in check asks nobody unless it is turned on", function()
    load()
    test.advance(4000)
    test.eq(asked(), {})
  end)

  test.it("turned on, it asks the chosen server once as a connection comes up", function()
    load(nil, nil, "ok", { network = { portal_probe = true, portal_server = "mozilla" } })
    test.advance(4000)
    test.eq(asked(), { "http://detectportal.firefox.com/success.txt" })
    open()
    test.falsy(test.find { id = "net-portal-row", visible = true })
  end)

  test.it("finds a sign-in page by the probe, and a press opens it", function()
    load(nil, nil, "portal", { network = { portal_probe = true } })
    test.advance(4000)
    open()
    test.truthy(test.find { id = "net-portal-row", visible = true })
    test.click("net-portal-open")
    test.advance(50)
    test.truthy(logged("xdg-open http://login.cafe.test/welcome"), "the login page opened")
  end)

  test.it("NetworkManager's own word is enough, with nothing sent", function()
    load(nil, nil, "portal")
    test.advance(100)
    test.truthy(test.find { text = "Sign in to Home", visible = true }, "the notice")
    test.eq(asked(), {}, "no request of eva's own")
    test.ipc("notifications", "invoke", "", "open")
    test.advance(50)
    test.truthy(logged("xdg-open http://nmcheck.gnome.org/"), "a press opens a page the network redirects")
    test.ipc("settings", "network") test.settle(900)
    test.truthy(test.find { text = "Connected · Needs you to sign in", visible = true }, "the network's own row says so")
    open()
    test.truthy(test.find { id = "net-portal-row", visible = true })
    test.ipc("fake-net", "ok")
    test.advance(1000)
    test.falsy(test.find { id = "net-portal-row", visible = true }, "signed in, the row goes")
  end)

  test.it("the speed test waits for a press, and reports", function()
    load()
    open()
    test.eq(asked(), {})
    test.click("net-speed-run")
    test.settle(900)
    test.truthy(text("net-speed-latency-subtitle"):find("ms", 1, true))
    test.truthy(text("net-speed-down-subtitle"):find("Mbit/s", 1, true))
    test.truthy(text("net-speed-up-subtitle"):find("Mbit/s", 1, true))
    shot("help-speed")
    for _, url in ipairs(asked()) do
      test.truthy(url:find("^https://speed%.cloudflare%.com/"), url)
    end
  end)

  test.it("says when the speed test cannot reach its server", function()
    load(nil, nil, "no-internet")
    open()
    test.click("net-speed-run")
    test.settle(600)
    test.truthy(text("net-speed-said"):find("no route", 1, true))
  end)

  test.it("is reached from the Network page, and found by search", function()
    load()
    test.ipc("settings", "network") test.settle(900)
    test.truthy(test.find { id = "network-help-open", visible = true } or test.find { id = "network-help-open-press", visible = true })
    test.ipc("settings", "home") test.settle(900)
    test.type("speed test") test.settle(300)
    test.truthy(test.find { text = "Speed test", visible = true })
  end)

  test.it("fits a phone", function()
    load("tsugumori", { 412, 915 }, "no-dns")
    open()
    walk()
    shot("help-phone")
    local box = test.get("net-help-scroll")
    test.truthy(box.x >= 0 and box.x + box.width <= 412)
    test.eq(#test.logs("error"), 0)
  end)
end)
