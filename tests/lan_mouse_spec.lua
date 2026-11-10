-- The Mouse sharing page against the stand-in lan-mouse daemon
-- (lib/services/lan_mouse_fake.lua): the machines it reaches, adding,
-- placing and taking one away, allowing a machine that asks, and the daemon
-- stopped and started. The requests go out in the daemon's own JSON.
--
--     morf test --no-dbus tests/lan_mouse_spec.lua
local test = morf.test

local function load(style)
  local settings = morf.env("XDG_CACHE_HOME") .. "/lan-mouse-" .. style .. ".json"
  morf.fs.remove(settings)
  -- Tall enough that the window holds the whole page.
  test.load("../shell/init.lua", { size = { 1920, 2800 }, env = { EVA_STYLE = style, EVA_DRY_RUN = "1",
    EVA_FAKE_SYSTEM = "1", EVA_SETTINGS = settings, EVA_WALLPAPER = "", EVA_FONT_FILE = "",
    HOME = morf.env("XDG_CACHE_HOME") } })
  test.settle(1500)
  test.ipc("settings", "lan_mouse")
  test.settle(1200)
end

local function shows(text) return test.find { text = text, visible = true } ~= nil end

test.describe("the lan-mouse service", function()
  test.it("reads the daemon's events and writes its requests", function()
    test.source [[
      local mouse = require("lib.services.lan_mouse")
      mouse.apply { Enumerate = { { 4, { hostname = "surf", pos = "right", port = 4242 }, { active = true, alive = true, ips = {} } },
        { 9223372036854775807, { hostname = "incoming", pos = "left" }, { active = true } } } }
      mouse.apply { PublicKeyFingerprint = "aa:bb" }
      mouse.apply { AuthorizedUpdated = { ["cc:dd"] = "laptop" } }
      mouse.apply { ConnectionAttempt = { fingerprint = "ee:ff" } }
      mouse.apply { ConnectionAttempt = { fingerprint = "ee:ff" } }
      morf.ipc.read = function() return mouse.get() end
      morf.ipc.encode = function() return morf.json.encode { Activate = { 4, true } } end
    ]]
    local now = test.ipc("read")
    test.eq(#now.clients, 1)
    test.eq(now.clients[1].hostname, "surf")
    test.eq(now.clients[1].pos, "right")
    test.eq(now.fingerprint, "aa:bb")
    test.eq(now.allowed[1].name, "laptop")
    test.eq(#now.asking, 1)
    test.eq(test.ipc("encode"), '{"Activate":[4,true]}')
  end)
end)

for _, style in ipairs { "material", "tsugumori" } do
  test.describe(style .. " Mouse sharing", function()
    test.it("lists the machines, adds one and takes it away", function()
      load(style)
      test.truthy(shows("surf") or shows("SURF"), "surf is not listed")
      test.truthy(shows("iridium") or shows("IRIDIUM"), "iridium is not listed")
      test.truthy(shows("On the right · Connected"))
      test.click("lan-mouse-add-name")
      test.type("laptop")
      test.click("lan-mouse-add-side-top")
      test.click("lan-mouse-add-button")
      test.settle(800)
      test.truthy(shows("laptop"), "the new machine is not listed")
      test.truthy(shows("Above · Connected"), "the new machine is not placed and on")
      test.click("lan-mouse-machine-3")
      test.settle(800)
      test.click("lan-mouse-machine-3-remove")
      test.settle(800)
      test.falsy(shows("laptop"), "the machine stayed")
      test.eq(#test.logs("error"), 0)
    end)

    test.it("places a machine and turns it off", function()
      load(style)
      test.click("lan-mouse-machine-2")
      test.settle(800)
      test.click("lan-mouse-machine-2-side-bottom")
      test.settle(600)
      test.truthy(shows("Below · Off"))
      test.click("lan-mouse-machine-1-switch")
      test.settle(600)
      test.truthy(shows("On the right · Off"))
    end)

    test.it("allows a machine that asks, and forgets it", function()
      load(style)
      test.truthy(shows("A machine asks to reach this one"))
      test.click("lan-mouse-asking-1-allow")
      test.settle(800)
      test.falsy(shows("A machine asks to reach this one"), "it still asks")
      test.truthy(shows("Machine c7:21"), "it is not allowed")
      test.click("lan-mouse-allowed-1-remove")
      test.settle(800)
      test.falsy(shows("Machine c7:21"), "it is still allowed")
    end)

    test.it("stops and starts the daemon", function()
      load(style)
      test.click("lan-mouse-switch")
      test.settle(1500)
      test.wait(function() return shows("One mouse and keyboard across your machines") end, 4000,
        "it did not stop: " .. tostring(test.get("lan-mouse-on-subtitle").text))
      test.falsy(shows("iridium") or shows("IRIDIUM"), "the machines stayed with the daemon off")
      test.click("lan-mouse-switch")
      test.settle(3000)
      test.wait(function() return shows("Ready on port 4242") end, 6000, "it did not come back")
      test.eq(#test.logs("error"), 0)
    end)
  end)
end
